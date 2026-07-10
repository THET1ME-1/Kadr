import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

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
///
/// Папка выбирается через системный Storage Access Framework (SAF): приложение
/// получает постоянный доступ к её `content://`-URI и пишет через SAF, а не
/// напрямую в файловую систему. Поэтому НЕ нужен `MANAGE_EXTERNAL_STORAGE`
/// (Google Play такое разрешение для трекера бы не пропустил), а папка может
/// быть любой — в т.ч. синхронизируемой (Syncthing/Nextcloud) — и переживает
/// переустановку приложения.
class AutoBackupService extends ChangeNotifier {
  AutoBackupService._();
  static final AutoBackupService instance = AutoBackupService._();

  final SafUtil _saf = SafUtil();
  final SafStream _safStream = SafStream();

  bool _enabled = false;
  String? _uri; // content:// URI выбранной папки (SAF tree)
  String? _folderName; // человекочитаемое имя папки для UI
  AutoBackupMode _mode = AutoBackupMode.onChange;
  int _lastBackup = 0;
  final int _keep = 20;
  String? _lastError;

  Timer? _debounce;
  bool _busy = false;

  bool get enabled => _enabled;
  String? get folder => _folderName ?? _uri;
  AutoBackupMode get mode => _mode;
  String? get lastError => _lastError;
  DateTime? get lastBackup =>
      _lastBackup > 0 ? DateTime.fromMillisecondsSinceEpoch(_lastBackup) : null;

  /// Минимальный интервал между авто-копиями в режиме «при изменениях».
  static const _minGap = Duration(minutes: 10);

  Future<void> load() async {
    _enabled = await Store.instance.getBool('ab.enabled');
    _uri = await Store.instance.getString('ab.uri');
    _folderName = await Store.instance.getString('ab.name');
    _lastBackup = await Store.instance.getInt('ab.last') ?? 0;
    final m = await Store.instance.getString('ab.mode');
    _mode = AutoBackupMode.values.firstWhere((e) => e.name == m,
        orElse: () => AutoBackupMode.onChange);
    // Если доступ к папке отозвали (или это не Android) — забываем её, чтобы UI
    // не показывал недоступную папку и не пытался в неё писать.
    if (_uri != null && !await _hasPermission()) {
      _uri = null;
      _folderName = null;
    }
    MovieRepository.instance.addListener(_onRepoChange);
    notifyListeners();
  }

  /// Есть ли постоянный доступ (чтение+запись) к выбранной папке.
  Future<bool> _hasPermission() async {
    final uri = _uri;
    if (uri == null || !Platform.isAndroid) return false;
    try {
      return await _saf.hasPersistedPermission(uri,
          checkRead: true, checkWrite: true);
    } catch (_) {
      return false;
    }
  }

  /// Открывает системный выбор папки (SAF) и запоминает постоянный доступ.
  /// Возвращает имя папки или null (отмена/нет доступа на запись).
  Future<String?> chooseFolder() async {
    if (!Platform.isAndroid) {
      _lastError = 'unsupported';
      notifyListeners();
      return null;
    }
    final dir = await _saf.pickDirectory(
        writePermission: true, persistablePermission: true);
    if (dir == null) return null; // пользователь отменил выбор
    // Убеждаемся, что реально дали доступ на запись.
    final ok = await _saf.hasPersistedPermission(dir.uri,
        checkRead: true, checkWrite: true);
    if (!ok) {
      _lastError = 'not_writable';
      notifyListeners();
      return null;
    }
    _uri = dir.uri;
    _folderName = dir.name;
    _lastError = null;
    await Store.instance.setString('ab.uri', dir.uri);
    await Store.instance.setString('ab.name', dir.name);
    notifyListeners();
    return dir.name;
  }

  Future<bool> setEnabled(bool v) async {
    if (v) {
      if (_uri == null) {
        final f = await chooseFolder();
        if (f == null) return false;
      } else if (!await _hasPermission()) {
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
    if (_busy || _uri == null) return false;
    _busy = true;
    try {
      if (!await _hasPermission()) {
        _lastError = 'no_permission';
        return false;
      }
      // НЕ пишем ПУСТУЮ копию: иначе на свежей установке она станет «последней»
      // и восстановление вернёт пустоту (а ротация со временем сотрёт реальные).
      if (!MovieRepository.instance.hasData) {
        _lastError = 'empty';
        return false;
      }
      final json = MovieRepository.instance.exportJson();
      final bytes = Uint8List.fromList(utf8.encode(json));
      await _safStream.writeFileBytes(
          _uri!, 'kadr_auto_${_stamp()}.json', 'application/json', bytes);
      _lastBackup = DateTime.now().millisecondsSinceEpoch;
      _lastError = null;
      await Store.instance.setInt('ab.last', _lastBackup);
      await _rotate();
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
    final uri = _uri;
    if (uri == null || !Platform.isAndroid) return const [];
    try {
      if (!await _saf.hasPersistedPermission(uri, checkRead: true)) {
        return const [];
      }
      final out = <BackupFile>[];
      for (final f in await _saf.list(uri)) {
        if (f.isDir) continue;
        if (!f.name.startsWith('kadr_auto_') || !f.name.endsWith('.json')) {
          continue;
        }
        // Пропускаем ПУСТЫЕ копии (пустой экспорт ~75 байт) — они бесполезны и
        // раньше могли попасть в «восстановить последнюю».
        if (f.length < 120) continue;
        final date = _parseStamp(f.name) ??
            DateTime.fromMillisecondsSinceEpoch(f.lastModified);
        out.add(BackupFile(f.uri, date, f.length));
      }
      out.sort((a, b) => b.date.compareTo(a.date));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Восстанавливает библиотеку из файла копии (мерж в текущую библиотеку —
  /// на свежей установке это просто загрузка всех данных).
  Future<bool> restore(BackupFile b) async {
    try {
      final bytes = await _safStream.readFileBytes(b.uri);
      return MovieRepository.instance.importJson(utf8.decode(bytes));
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

  Future<void> _rotate() async {
    final uri = _uri;
    if (uri == null) return;
    try {
      final files = (await _saf.list(uri))
          .where((f) =>
              !f.isDir &&
              f.name.startsWith('kadr_auto_') &&
              f.name.endsWith('.json'))
          .toList()
        // Имя содержит сортируемую метку времени kadr_auto_YYYYMMDD_HHMMSS.
        ..sort((a, b) => a.name.compareTo(b.name));
      while (files.length > _keep) {
        await _saf.delete(files.removeAt(0).uri, false);
      }
    } catch (_) {/* не критично */}
  }

  static String _stamp() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }
}

/// Найденный файл автобекапа: SAF-URI, дата (из имени/времени) и размер.
class BackupFile {
  final String uri;
  final DateTime date;
  final int size;
  const BackupFile(this.uri, this.date, this.size);
}
