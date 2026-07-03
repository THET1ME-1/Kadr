import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../movie_repository.dart';
import '../store.dart';
import 'sync_merge.dart';

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
  static const _file = '/Kadr/sync.json';

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
  }

  Future<void> forget() async {
    for (final k in [_kUrl, _kUser, _kPass]) {
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
    Map<String, dynamic> remote = {};
    try {
      final bytes = await c.read(_file);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic> && decoded['kind'] == kSyncKind) {
        remote = decoded;
      }
    } catch (_) {
      // Файла ещё нет — первый синк, remote пустой.
    }
    final stats = await MovieRepository.instance.mergeSyncSnapshot(remote);
    final merged = MovieRepository.instance.buildSyncSnapshot();
    final data = Uint8List.fromList(utf8.encode(jsonEncode(merged)));
    await c.write(_file, data);
    await Store.instance
        .setInt(_kLastAt, DateTime.now().millisecondsSinceEpoch);
    return stats;
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
