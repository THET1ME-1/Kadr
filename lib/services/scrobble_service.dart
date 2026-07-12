import '../config/api_config.dart';
import 'movie_repository.dart';
import 'social/social_api.dart';
import 'social/social_controller.dart';
import 'store.dart';

/// Скробблинг Plex/Jellyfin. Плеер шлёт вебхук на воркер (по персональному
/// токену) → события копятся в очереди на сервере → приложение забирает их и
/// отмечает просмотр в ЛОКАЛЬНОЙ библиотеке (local-first). Требует аккаунта
/// соц-слоя (очередь привязана к пользователю).
class ScrobbleService {
  ScrobbleService._();
  static final ScrobbleService instance = ScrobbleService._();

  static const _kEnabled = 'scrobbleEnabled';
  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> load() async {
    _enabled = await Store.instance.getBool(_kEnabled);
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await Store.instance.setBool(_kEnabled, v);
    if (v) unawaitedDrain();
  }

  /// Полный URL вебхука для настройки в Plex/Jellyfin (null — если не вошёл).
  Future<String?> webhookUrl() async {
    final token = SocialController.instance.token;
    if (token == null) return null;
    final scr = await SocialApi.instance.scrobbleToken(token);
    if (scr.isEmpty) return null;
    return '${ApiConfig.socialBase}/scrobble/$scr';
  }

  /// Забрать очередь и отметить локально. Возвращает число применённых событий.
  Future<int> drain() async {
    final token = SocialController.instance.token;
    if (token == null) return 0;
    final pending = await SocialApi.instance.pendingScrobbles(token);
    if (pending.isEmpty) return 0;
    final repo = MovieRepository.instance;
    final done = <String>[];
    for (final s in pending) {
      final id = s['id']?.toString();
      if (id == null) continue;
      final title = (s['title'] as String?)?.trim() ?? '';
      if (title.isEmpty) {
        done.add(id); // мусорное событие — просто подтверждаем
        continue;
      }
      final createdAt = (s['created_at'] as num?)?.toInt();
      final date = createdAt != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : null;
      final year = (s['year'] as num?)?.toInt();
      try {
        if (s['kind'] == 'episode') {
          final season = (s['season'] as num?)?.toInt();
          final episode = (s['episode'] as num?)?.toInt();
          if (season != null && episode != null) {
            await repo.ingestCoWatchSeries(
              title: title,
              year: year,
              episodes: [
                [season, episode]
              ],
              date: date,
            );
          }
        } else {
          await repo.ingestCoWatchMovie(title: title, year: year, date: date);
        }
        done.add(id);
      } catch (_) {
        // Не подтверждаем — попробуем в следующий заход.
      }
    }
    if (done.isNotEmpty) {
      try {
        await SocialApi.instance.ackScrobbles(token, done);
      } catch (_) {}
    }
    return done.length;
  }

  /// Тихий фоновый забор (при возврате в приложение). Ничего не бросает.
  Future<void> drainSilently() async {
    if (!_enabled || !SocialController.instance.isLoggedIn) return;
    try {
      await drain();
    } catch (_) {}
  }

  void unawaitedDrain() {
    drainSilently();
  }
}
