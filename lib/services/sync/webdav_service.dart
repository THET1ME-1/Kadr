import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../movie_repository.dart';
import '../store.dart';
import 'sync_merge.dart';

/// Файлы на сервере синхронизации. Вынесено из [WebdavService], чтобы цикл
/// синка проверялся тестом без сети.
abstract class SyncRemote {
  /// Содержимое файла; null, если файла нет.
  Future<List<int>?> read(String path);

  /// Отпечаток файла, который меняется вместе с содержимым. null — файла
  /// нет; пустая строка — файл может быть, но сервер отпечаток не отдал.
  Future<String?> signature(String path);

  Future<void> write(String path, List<int> data);
}

/// Двусторонняя синхронизация через WebDAV (Nextcloud, ownCloud, Яндекс.Диск и
/// любой WebDAV-сервер). Данные — на СЕРВЕРЕ пользователя, секретов в коде нет.
///
/// Один цикл: скачать удалённый снимок → слить с локальным (объединение) →
/// залить объединённый обратно. Настройки подключения — device-local, в снимок
/// и бэкап НЕ входят.
class WebdavService {
  WebdavService._();
  static final WebdavService instance = WebdavService._();

  static const _kUrl = 'webdavUrl';
  static const _kUser = 'webdavUser';
  static const _kPass = 'webdavPass';
  static const _kAuto = 'webdavAuto';
  static const _kLastAt = 'webdavLastAt';
  static const _dir = '/Kadr';

  /// Снимок нынешнего формата (оценка в просмотре, у просмотра id).
  @visibleForTesting
  static const file = '/Kadr/sync2.json';

  /// Файл версий до 0.29. Они склеивают просмотры по паре «дата и оценка» и,
  /// получив снимок нынешнего формата, задвоили бы просмотр у каждого
  /// оценённого фильма. Поэтому сюда мы не пишем, а только читаем: отметки со
  /// старого устройства доезжают, пока его не обновили. В обратную сторону
  /// они пойдут после обновления.
  @visibleForTesting
  static const legacyFile = '/Kadr/sync.json';

  /// Отпечаток [legacyFile], который уже влит: тот же файл второй раз не
  /// скачивается.
  @visibleForTesting
  static const legacySignatureKey = 'webdavLegacySig';

  Future<String?> url() => Store.instance.getString(_kUrl);
  Future<String?> user() => Store.instance.getString(_kUser);
  Future<String?> password() => Store.instance.getString(_kPass);
  Future<bool> isConfigured() async => ((await url()) ?? '').isNotEmpty;

  Future<bool> autoEnabled() => Store.instance.getBool(_kAuto, def: true);
  Future<void> setAutoEnabled(bool value) =>
      Store.instance.setBool(_kAuto, value);

  Future<DateTime?> lastSyncAt() async {
    final ms = await Store.instance.getInt(_kLastAt);
    return (ms == null || ms == 0)
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> saveConfig({
    required String url,
    required String user,
    required String password,
  }) async {
    await Store.instance.setString(_kUrl, url.trim());
    await Store.instance.setString(_kUser, user.trim());
    await Store.instance.setString(_kPass, password);
    // Сервер мог смениться: файл прежних версий читаем заново.
    await Store.instance.remove(legacySignatureKey);
  }

  Future<void> forget() async {
    for (final k in [_kUrl, _kUser, _kPass, legacySignatureKey]) {
      await Store.instance.remove(k);
    }
    await Store.instance.setInt(_kLastAt, 0);
  }

  Future<webdav.Client> _client() async {
    final c = webdav.newClient(
      (await url()) ?? '',
      user: (await user()) ?? '',
      password: (await password()) ?? '',
    );
    c.setConnectTimeout(15000);
    c.setSendTimeout(30000);
    c.setReceiveTimeout(30000);
    return c;
  }

  /// Проверка соединения (кнопка «Подключить»). Бросает при ошибке.
  Future<void> testConnection() async {
    final c = await _client();
    await c.ping();
  }

  /// Полный цикл синка: скачать → слить → залить. Возвращает статистику.
  Future<SyncStats> sync() async {
    final c = await _client();
    try {
      await c.mkdirAll(_dir);
    } catch (_) {}
    return syncWith(_WebdavRemote(c));
  }

  /// Цикл синка поверх [remote]. [repo] подменяется в тестах.
  @visibleForTesting
  Future<SyncStats> syncWith(SyncRemote remote,
      {MovieRepository? repo}) async {
    final library = repo ?? MovieRepository.instance;
    final current = await _readSnapshot(remote, file, strict: true);

    // Без отпечатка (сервер его не отдал) файл читается каждый раз: иначе
    // отметки со старого устройства перестали бы доезжать молча.
    Map<String, dynamic>? legacy;
    final signature = await remote.signature(legacyFile);
    final merged = await Store.instance.getString(legacySignatureKey);
    if (signature != null && (signature.isEmpty || signature != merged)) {
      legacy = await _readSnapshot(remote, legacyFile);
    }

    // Сначала сводим оба удалённых снимка: при споре нынешний формат важнее.
    final incoming = legacy == null
        ? current ?? const <String, dynamic>{}
        : mergeSnapshots(
            current ?? const <String, dynamic>{}, legacy, SyncStats());
    final stats = await library.mergeSyncSnapshot(incoming);
    final data = utf8.encode(jsonEncode(library.buildSyncSnapshot()));
    await remote.write(file, data);
    // Отпечаток запоминаем после записи: если она сорвалась, файл прежних
    // версий в следующий раз прочитается снова.
    if (legacy != null && signature != null && signature.isNotEmpty) {
      await Store.instance.setString(legacySignatureKey, signature);
    }
    await Store.instance
        .setInt(_kLastAt, DateTime.now().millisecondsSinceEpoch);
    return stats;
  }

  /// Снимок из файла; null, если файла нет.
  ///
  /// Файл есть, но в нём не снимок Kadr (недокачан, чужой): со [strict] это
  /// ошибка, и синк обрывается. Писать поверх такого файла нельзя: в нём
  /// может лежать единственная копия библиотеки. Без [strict] он пропускается.
  static Future<Map<String, dynamic>?> _readSnapshot(
      SyncRemote remote, String path,
      {bool strict = false}) async {
    final bytes = await remote.read(path);
    if (bytes == null) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic> && decoded['kind'] == kSyncKind) {
        return decoded;
      }
    } on FormatException {
      // Разбор не удался: ниже общий ответ для всего, что не снимок.
    }
    if (strict) throw FormatException('В $path лежит не снимок Kadr');
    return null;
  }

  /// Тихий авто-синк (старт/сворачивание): не бросает, null при ошибке/выкл.
  Future<SyncStats?> syncSilently() async {
    try {
      if (!await isConfigured() || !await autoEnabled()) return null;
      return await sync();
    } catch (e) {
      debugPrint('Kadr: WebDAV авто-синк не удался: $e');
      return null;
    }
  }
}

/// Файлы на WebDAV-сервере.
class _WebdavRemote implements SyncRemote {
  final webdav.Client _c;
  _WebdavRemote(this._c);

  /// Сервер ответил, что файла нет: первый синк или сервер, где старых
  /// версий не было. Ошибку бросает dio, которого нет в наших зависимостях,
  /// поэтому код ответа читаем без его типов.
  static bool _missing(Object e) {
    try {
      return (e as dynamic).response?.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  /// Любой другой сбой чтения летит наружу и обрывает синк. Раньше он
  /// считался «файла ещё нет», и свой снимок записывался поверх чужого:
  /// на новом телефоне обрыв связи стирал библиотеку на сервере.
  @override
  Future<List<int>?> read(String path) async {
    try {
      return await _c.read(path);
    } catch (e) {
      if (_missing(e)) return null;
      rethrow;
    }
  }

  @override
  Future<String?> signature(String path) async {
    try {
      final f = await _c.readProps(path);
      return '${f.eTag}|${f.mTime?.millisecondsSinceEpoch}|${f.size}';
    } catch (e) {
      return _missing(e) ? null : '';
    }
  }

  @override
  Future<void> write(String path, List<int> data) =>
      _c.write(path, Uint8List.fromList(data));
}
