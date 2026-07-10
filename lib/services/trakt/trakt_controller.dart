import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/library_entry.dart';
import '../movie_repository.dart';
import '../store.dart';
import '../tmdb_service.dart';
import 'trakt_service.dart';

enum TraktState { idle, waitingForUser, connected, syncing }

/// Управление интеграцией с Trakt: вход (device flow), синхронизация фильмов
/// (Kadr — источник правды: только добавляем/заполняем, ничего не удаляем и не
/// перезаписываем оценки) и отключение.
class TraktController extends ChangeNotifier {
  TraktController._();
  static final TraktController instance = TraktController._();

  TraktToken? _token;
  TraktDeviceCode? deviceCode; // активный код входа (показывается в UI)
  TraktState state = TraktState.idle;

  /// Ключ строки статуса (для локализованного сообщения в UI) или null.
  String? statusKey;
  int lastPushed = 0;
  int lastPulled = 0;

  /// Синхронизировать оценки (Kadr → Trakt, и заполнять пустые из Trakt).
  bool syncRatings = true;

  bool get connected => _token != null;
  bool get busy => state == TraktState.syncing;

  Future<void> load() async {
    final raw = await Store.instance.getString('trakt.token');
    if (raw != null && raw.isNotEmpty) {
      try {
        _token = TraktToken.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        state = TraktState.connected;
      } catch (_) {}
    }
    syncRatings = await Store.instance.getBool('trakt.syncRatings', def: true);
  }

  Future<void> _saveToken(TraktToken? t) async {
    _token = t;
    await Store.instance
        .setString('trakt.token', t == null ? '' : jsonEncode(t.toJson()));
  }

  /// Валидный access-токен (обновляет через воркер при необходимости).
  Future<String?> _access() async {
    var t = _token;
    if (t == null) return null;
    if (t.needsRefresh) {
      final nt = await TraktService.refresh(t.refreshToken);
      if (nt != null) {
        await _saveToken(nt);
        t = nt;
      }
    }
    return t.accessToken;
  }

  // -------------------------------- вход --------------------------------

  bool _cancelLogin = false;

  /// Запускает device-вход: получает код (для показа), крутит опрос токена.
  Future<void> connect() async {
    _cancelLogin = false;
    statusKey = null;
    final code = await TraktService.deviceCode();
    if (code == null) {
      statusKey = 'trakt_error';
      notifyListeners();
      return;
    }
    deviceCode = code;
    state = TraktState.waitingForUser;
    notifyListeners();

    var interval = code.interval;
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
    while (!_cancelLogin && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(Duration(seconds: interval));
      if (_cancelLogin) break;
      final res = await TraktService.pollToken(code.deviceCode);
      switch (res.status) {
        case TraktPollStatus.ok:
          await _saveToken(res.token);
          deviceCode = null;
          state = TraktState.connected;
          statusKey = null;
          notifyListeners();
          return;
        case TraktPollStatus.pending:
          break;
        case TraktPollStatus.slowDown:
          interval += 1;
          break;
        case TraktPollStatus.expired:
        case TraktPollStatus.denied:
        case TraktPollStatus.error:
          deviceCode = null;
          state = TraktState.idle;
          statusKey = 'trakt_login_failed';
          notifyListeners();
          return;
      }
    }
    deviceCode = null;
    state = connected ? TraktState.connected : TraktState.idle;
    notifyListeners();
  }

  void cancelLogin() {
    _cancelLogin = true;
    deviceCode = null;
    state = connected ? TraktState.connected : TraktState.idle;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _saveToken(null);
    state = TraktState.idle;
    statusKey = null;
    notifyListeners();
  }

  Future<void> setSyncRatings(bool v) async {
    syncRatings = v;
    await Store.instance.setBool('trakt.syncRatings', v);
    notifyListeners();
  }

  // ------------------------- отправка (Kadr → Trakt) -------------------------

  Future<void> pushToTrakt() async {
    final token = await _access();
    if (token == null) return;
    state = TraktState.syncing;
    statusKey = 'trakt_pushing';
    notifyListeners();
    final repo = MovieRepository.instance;

    final watched = [
      for (final m in repo.watched)
        if (m.tmdbId != null) (tmdb: m.tmdbId!, at: m.lastViewing)
    ];
    if (watched.isNotEmpty) await TraktService.addHistory(token, watched);

    final wl = [
      for (final m in repo.watchlist)
        if (m.tmdbId != null) m.tmdbId!
    ];
    if (wl.isNotEmpty) await TraktService.addWatchlist(token, wl);

    if (syncRatings) {
      final ratings = [
        for (final m in repo.watched)
          if (m.tmdbId != null && m.currentScore != null)
            (tmdb: m.tmdbId!, rating: m.currentScore!.round().clamp(1, 10))
      ];
      if (ratings.isNotEmpty) await TraktService.addRatings(token, ratings);
    }

    lastPushed = watched.length + wl.length;
    state = TraktState.connected;
    statusKey = 'trakt_done';
    notifyListeners();
  }

  // ------------------------- загрузка (Trakt → Kadr) -------------------------

  Future<void> pullFromTrakt() async {
    final token = await _access();
    if (token == null) return;
    state = TraktState.syncing;
    statusKey = 'trakt_pulling';
    notifyListeners();
    final repo = MovieRepository.instance;
    var added = 0;

    // Просмотренные: добавляем те, что в Kadr ещё не помечены просмотренными.
    for (final tm in await TraktService.watchedMovies(token)) {
      final existing = repo.movieByTmdb(tm.tmdb);
      if (existing != null && existing.status == LibraryStatus.watched) {
        continue;
      }
      final m = repo.ensureFromTmdb(
          TmdbMovie(id: tm.tmdb, title: tm.title, year: tm.year));
      await repo.addViewing(m.uuid, tm.at);
      added++;
    }

    // «Буду смотреть»: только для фильмов, которых в библиотеке ещё нет.
    for (final tm in await TraktService.watchlistMovies(token)) {
      if (repo.movieByTmdb(tm.tmdb) != null) continue;
      final m = repo.ensureFromTmdb(
          TmdbMovie(id: tm.tmdb, title: tm.title, year: tm.year));
      await repo.toggleWatchlist(m.uuid);
      added++;
    }

    // Оценки: только ЗАПОЛНЯЕМ пустые, никогда не перезаписываем твою.
    if (syncRatings) {
      final rated = await TraktService.ratedMovies(token);
      for (final e in rated.entries) {
        final m = repo.movieByTmdb(e.key);
        if (m != null && m.currentScore == null) {
          await repo.setScore(m.uuid, e.value.toDouble());
        }
      }
    }

    lastPulled = added;
    state = TraktState.connected;
    statusKey = 'trakt_done';
    notifyListeners();
    repo.startEnrichSweep(); // подтянуть постеры/детали новым фильмам
  }
}
