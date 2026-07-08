import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'movie_repository.dart';
import 'store.dart';

/// Как часто делать локальный автобекап.
enum AutoBackupMode {
  /// При изменениях (с задержкой и минимальным интервалом между копиями).
  onChange,

  /// Раз в сутки (проверяется при запуске/возврате в приложение).
  daily,
}

/// Локальные автоматические резервные копии библиотеки в выбранную пользователем
/// папку. Пишет `kadr_auto_<дата>.json`, хранит последние [keep] копий.
/// На Android нужен доступ ко всем файлам (MANAGE_EXTERNAL_STORAGE), т.к.
/// targetSdk высокий (scoped storage) и папку выбирает пользователь.
class AutoBackupService extends ChangeNotifier {
  AutoBackupService._();
  static final AutoBackupService instance = AutoBackupService._();

  bool _enabled = false;
  String? _folder;
  AutoBackupMode _mode = AutoBackupMode.onChange;
  int _lastBackup = 0;
  final int _keep = 20;
  String? _lastError;

  Timer? _debounce;
  bool _busy = false;

  bool get enabled => _enabled;
  String? get folder => _folder;
  AutoBackupMode get mode => _mode;
  String? get lastError => _lastError;
  DateTime? get lastBackup =>
      _lastBackup > 0 ? DateTime.fromMillisecondsSinceEpoch(_lastBackup) : null;

  /// Минимальный интервал между авто-копиями в режиме «при изменениях».
  static const _minGap = Duration(minutes: 10);

  Future<void> load() async {
    _enabled = await Store.instance.getBool('ab.enabled');
    _folder = await Store.instance.getString('ab.folder');
    _lastBackup = await Store.instance.getInt('ab.last') ?? 0;
    final m = await Store.instance.getString('ab.mode');
    _mode = AutoBackupMode.values.firstWhere((e) => e.name == m,
        orElse: () => AutoBackupMode.onChange);
    MovieRepository.instance.addListener(_onRepoChange);
    notifyListeners();
  }

  /// Запрашивает доступ ко всем файлам (Android). Возвращает true, если выдан.
  Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return true;
    var st = await Permission.manageExternalStorage.status;
    if (!st.isGranted) st = await Permission.manageExternalStorage.request();
    return st.isGranted;
  }

  /// Открывает системный выбор папки. Возвращает путь или null.
  Future<String?> chooseFolder() async {
    if (!await ensurePermission()) {
      _lastError = 'no_permission';
      notifyListeners();
      return null;
    }
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return null;
    // Проверяем, что реально можем писать (иначе content-URI/недоступно).
    try {
      final probe = File('$path/.kadr_write_test');
      await probe.writeAsString('ok');
      await probe.delete();
    } catch (_) {
      _lastError = 'not_writable';
      notifyListeners();
      return null;
    }
    _folder = path;
    _lastError = null;
    await Store.instance.setString('ab.folder', path);
    notifyListeners();
    return path;
  }

  Future<bool> setEnabled(bool v) async {
    if (v) {
      if (_folder == null) {
        final f = await chooseFolder();
        if (f == null) return false;
      } else if (!await ensurePermission()) {
        return false;
      }
    }
    _enabled = v;
    await Store.instance.setBool('ab.enabled', v);
    notifyListeners();
    if (v) await backupNow();
    return true;
  }

  Future<void> setMode(AutoBackupMode m) async {
    _mode = m;
    await Store.instance.setString('ab.mode', m.name);
    notifyListeners();
  }

  void _onRepoChange() {
    if (!_enabled || _mode != AutoBackupMode.onChange) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 30), () {
      final since = DateTime.now().millisecondsSinceEpoch - _lastBackup;
      if (since >= _minGap.inMilliseconds) backupNow();
    });
  }

  /// Периодическая проверка — вызывать при запуске и возврате в приложение.
  Future<void> maybePeriodic() async {
    if (!_enabled || _mode != AutoBackupMode.daily) return;
    final since = DateTime.now().millisecondsSinceEpoch - _lastBackup;
    if (since >= const Duration(hours: 22).inMilliseconds) await backupNow();
  }

  /// Делает копию прямо сейчас (кнопка «Создать сейчас» игнорирует интервалы).
  Future<bool> backupNow() async {
    if (_busy || _folder == null) return false;
    _busy = true;
    try {
      if (!await ensurePermission()) {
        _lastError = 'no_permission';
        return false;
      }
      final dir = Directory(_folder!);
      if (!await dir.exists()) {
        _lastError = 'folder_missing';
        return false;
      }
      final json = MovieRepository.instance.exportJson();
      final f = File('${dir.path}/kadr_auto_${_stamp()}.json');
      await f.writeAsString(json);
      _lastBackup = DateTime.now().millisecondsSinceEpoch;
      _lastError = null;
      await Store.instance.setInt('ab.last', _lastBackup);
      await _rotate(dir);
      return true;
    } catch (e) {
      _lastError = 'write_failed';
      debugPrint('AutoBackup error: $e');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Список автобекапов в текущей папке (самые свежие — сверху). Пусто, если
  /// папка не выбрана/недоступна.
  Future<List<BackupFile>> listBackups() async {
    final folder = _folder;
    if (folder == null) return const [];
    try {
      final dir = Directory(folder);
      if (!await dir.exists()) return const [];
      final out = <BackupFile>[];
      for (final e in await dir.list().toList()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith('kadr_auto_') || !name.endsWith('.json')) continue;
        final st = await e.stat();
        out.add(BackupFile(e, _parseStamp(name) ?? st.modified, st.size));
      }
      out.sort((a, b) => b.date.compareTo(a.date));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Восстанавливает библиотеку из файла копии (мерж в текущую библиотеку —
  /// на свежей установке это просто загрузка всех данных).
  Future<bool> restore(File f) async {
    try {
      final raw = await f.readAsString();
      return MovieRepository.instance.importJson(raw);
    } catch (e) {
      debugPrint('AutoBackup restore error: $e');
      return false;
    }
  }

  /// Разбирает дату из имени `kadr_auto_YYYYMMDD_HHMMSS.json`.
  static DateTime? _parseStamp(String name) {
    final m = RegExp(r'kadr_auto_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})')
        .firstMatch(name);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!),
        int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
  }

  Future<void> _rotate(Directory dir) async {
    try {
      final files = (await dir.list().toList())
          .whereType<File>()
          .where((f) =>
              f.uri.pathSegments.last.startsWith('kadr_auto_') &&
              f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      while (files.length > _keep) {
        await files.removeAt(0).delete();
      }
    } catch (_) {/* не критично */}
  }

  static String _stamp() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }
}

/// Найденный файл автобекапа: путь, дата (из имени/времени) и размер.
class BackupFile {
  final File file;
  final DateTime date;
  final int size;
  const BackupFile(this.file, this.date, this.size);
}
