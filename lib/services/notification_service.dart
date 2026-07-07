import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/strings.dart';
import 'movie_repository.dart';
import 'store.dart';
import 'tmdb_service.dart';

/// Одна «новая серия» для показа: и системным уведомлением, и внутри приложения.
class NewEpisode {
  final String tvShowId;
  final String title;
  final String label; // «S2·E5»
  const NewEpisode(
      {required this.tvShowId, required this.title, required this.label});

  String get key => '$tvShowId·$label';
}

/// Уведомления о выходе новых серий для сериалов, которые пользователь сейчас
/// смотрит (кроме брошенных). Проверка — при запуске приложения. Каждая серия
/// уведомляется один раз (ключи в Store). Найденные серии складываются в
/// [inbox] для красивого показа внутри приложения (баннер с закрытием).
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  bool _enabled = true;

  bool get enabled => _enabled;

  /// Непоказанные внутри приложения новые серии (для баннера). Свежие — в начале.
  final List<NewEpisode> inbox = [];

  static const _channelId = 'new_episodes';
  static const _prefEnabled = 'notifyNewEpisodes';
  static const _prefNotified = 'notifiedEpisodeKeys';

  Future<void> init() async {
    if (_inited) return;
    _enabled = await Store.instance.getBool(_prefEnabled, def: true);
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    try {
      await _plugin.initialize(settings: settings);
      _inited = true;
    } catch (e) {
      debugPrint('notif init error: $e');
    }
  }

  /// Запрашивает разрешение на уведомления (Android 13+).
  Future<void> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('notif permission error: $e');
    }
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await Store.instance.setBool(_prefEnabled, v);
    if (v) {
      await requestPermission();
    } else {
      inbox.clear();
      notifyListeners();
    }
  }

  /// Закрыть один баннер (пользователь нажал «×»).
  void dismiss(NewEpisode e) {
    inbox.removeWhere((x) => x.key == e.key);
    notifyListeners();
  }

  /// Закрыть все баннеры.
  void dismissAll() {
    inbox.clear();
    notifyListeners();
  }

  /// Показать соц-уведомление (заявка в друзья и т.п.). Фиксированный id —
  /// новое заменяет предыдущее, а не копит стопку.
  Future<void> showSocial(String title, String body) async {
    await init();
    await _showSystem(9200, title, body);
  }

  Future<void> _showSystem(int id, String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Новые серии',
        channelDescription: 'Уведомления о выходе новых серий',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    try {
      await _plugin.show(
          id: id, title: title, body: body, notificationDetails: details);
    } catch (e) {
      debugPrint('notif show error: $e');
    }
  }

  /// Проверяет сериалы «в процессе» (не брошенные) на недавно вышедшие серии,
  /// которые пользователь ещё не отметил, и уведомляет о них (один раз).
  Future<void> checkNewEpisodes(
      {DateTime? nowOverride, int maxPerRun = 8}) async {
    if (!_enabled) return;
    await init();
    final now = nowOverride ?? DateTime.now();
    final repo = MovieRepository.instance;
    final notified = (await Store.instance.getStringList(_prefNotified)).toSet();
    var found = 0;

    final series = repo.currentlyWatching
        .where((s) => !s.dropped && s.tmdbId != null)
        .take(25)
        .toList();

    for (final s in series) {
      if (found >= maxPerRun) break;
      try {
        final seasons = await TmdbService.seasons(s.tmdbId!);
        if (seasons.isEmpty) continue;
        final last = seasons.last; // новые серии выходят в последнем сезоне
        final eps = await TmdbService.episodesOf(s.tmdbId!, last.number);
        for (final ep in eps) {
          if (found >= maxPerRun) break;
          if (s.isEpisodeWatched(ep.season, ep.number)) continue;
          final air = DateTime.tryParse(ep.airDate ?? '');
          if (air == null || air.isAfter(now)) continue; // ещё не вышла
          if (now.difference(air).inDays > 30) continue; // не новинка
          final storeKey = '${s.tmdbId}-${ep.season}-${ep.number}';
          if (notified.contains(storeKey)) continue;
          notified.add(storeKey);
          final label = 'S${ep.season}·E${ep.number}';
          inbox.insert(
              0,
              NewEpisode(
                  tvShowId: s.tvShowId, title: s.displayTitle, label: label));
          await _showSystem(
            storeKey.hashCode & 0x7fffffff,
            tr('notif_new_ep_title'),
            trf('notif_new_ep_body', {'title': s.displayTitle, 'ep': label}),
          );
          found++;
        }
      } catch (e) {
        debugPrint('checkNewEpisodes ${s.title}: $e');
      }
    }
    await Store.instance.setStringList(_prefNotified, notified.toList());
    if (found > 0) notifyListeners();
  }

  /// Тест из настроек: кладёт демонстрационную «новую серию» в баннер и шлёт
  /// системное уведомление (проверка канала/разрешения и вида баннера).
  Future<void> showTest() async {
    await init();
    final list = MovieRepository.instance.currentlyWatching
        .where((x) => !x.dropped)
        .toList();
    final title = list.isNotEmpty ? list.first.displayTitle : tr('app_name');
    final tvId = list.isNotEmpty ? list.first.tvShowId : '';
    inbox.insert(
        0, NewEpisode(tvShowId: tvId, title: title, label: 'S1·E1'));
    notifyListeners();
    await _showSystem(999001, tr('notif_new_ep_title'),
        trf('notif_new_ep_body', {'title': title, 'ep': 'S1·E1'}));
  }
}
