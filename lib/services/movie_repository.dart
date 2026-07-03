import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../models/library_entry.dart';
import 'kinopoisk_service.dart';
import 'movie_source.dart';
import 'store.dart';
import 'tmdb_service.dart';

/// Единое хранилище библиотеки фильмов/сериалов Kadr.
///
/// При первом запуске подгружает импортированную базу из ассета
/// `assets/seed/library.json` (экспорт TV Time) и сохраняет её в файл документов.
/// Дальше — источник истины файл `library.json` в каталоге приложения.
/// Мутации персистятся и оповещают слушателей (экраны обновляются на лету).
class MovieRepository extends ChangeNotifier {
  MovieRepository._();
  static final MovieRepository instance = MovieRepository._();

  final List<LibraryMovie> _movies = [];
  final List<LibrarySeries> _series = [];
  final List<MovieList> _lists = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<LibraryMovie> get movies => List.unmodifiable(_movies);
  List<LibrarySeries> get series => List.unmodifiable(_series);
  List<MovieList> get lists => List.unmodifiable(_lists);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/library.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final f = await _file();
      final exists = await f.exists();
      final seed = jsonDecode(
          await rootBundle.loadString('assets/seed/library.json'))
          as Map<String, dynamic>;
      final seedVersion =
          ((seed['meta'] as Map?)?['seedVersion'] as num?)?.toInt() ?? 1;

      if (!exists) {
        _ingest(seed);
        await Store.instance.setInt('seedVersion', seedVersion);
        await _persist(); // первый запуск — сохранить сид
      } else {
        _ingest(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        final applied = await Store.instance.getInt('seedVersion') ?? 0;
        if (seedVersion > applied) {
          // Обновился сид (напр. добавились русские названия/постеры из дампа) —
          // добавляем обогащение к уже установленным данным, не трогая оценки.
          _mergeSeed(seed);
          await Store.instance.setInt('seedVersion', seedVersion);
          await _persist();
        }
      }
      // Разовый сброс флага «пробовали» для необогащённых фильмов — чтобы
      // источник по умолчанию (TMDB) дотянул те, что не нашлись раньше.
      final ev = await Store.instance.getInt('enrichVersion') ?? 0;
      if (ev < 2) {
        for (final m in _movies) {
          if (m.posterUrl == null) m.enrichTried = false;
        }
        await Store.instance.setInt('enrichVersion', 2);
        await _persist();
      }
      _watchlistNewestFirst =
          await Store.instance.getBool('watchlistNewestFirst', def: true);
    } catch (e) {
      debugPrint('MovieRepository.load error: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Дозаполняет обогащение (kinopoiskId/постер/рус. название) из свежего сида,
  /// не затрагивая пользовательские оценки/просмотры/избранное.
  void _mergeSeed(Map<String, dynamic> seed) {
    final byId = {for (final m in _movies) m.uuid: m};
    for (final j in (seed['movies'] as List? ?? [])) {
      final sj = j as Map<String, dynamic>;
      final cur = byId['${sj['uuid']}'];
      if (cur == null) continue;
      // Дата добавления — дозаполняем всегда (для сортировки «Буду смотреть»).
      if (cur.addedAt == null && sj['addedAt'] != null) {
        cur.addedAt = DateTime.tryParse('${sj['addedAt']}');
      }
      // Обогащение — только если фильм ещё не обогащён никаким источником.
      if (cur.kinopoiskId == null &&
          cur.tmdbId == null &&
          sj['kinopoiskId'] != null) {
        cur.kinopoiskId = (sj['kinopoiskId'] as num).toInt();
        cur.posterUrl ??= sj['posterUrl'] as String?;
        cur.ruTitle ??= sj['ruTitle'] as String?;
        if (sj['kpRating'] != null) {
          cur.kpRating ??= (sj['kpRating'] as num).toDouble();
        }
        if (sj['enrichTried'] == true) cur.enrichTried = true;
      }
    }

    // Сериалы: если эпизоды без структуры (старый формат дат) — берём полные
    // эпизоды с сезонами/номерами из сида; обогащение и оценки сохраняем.
    final bySeries = {for (final s in _series) s.tvShowId: s};
    for (final j in (seed['series'] as List? ?? [])) {
      final sj = j as Map<String, dynamic>;
      final cur = bySeries['${sj['tvShowId']}'];
      if (cur == null) continue;
      final structured = cur.episodes.any((e) => e.season != null);
      if (!structured && sj['episodes'] != null) {
        cur.episodes = (sj['episodes'] as List)
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
  }

  void _ingest(Map<String, dynamic> data) {
    _movies
      ..clear()
      ..addAll((data['movies'] as List? ?? [])
          .map((e) => LibraryMovie.fromJson(e as Map<String, dynamic>)));
    _series
      ..clear()
      ..addAll((data['series'] as List? ?? [])
          .map((e) => LibrarySeries.fromJson(e as Map<String, dynamic>)));
    _lists
      ..clear()
      ..addAll((data['lists'] as List? ?? [])
          .map((e) => MovieList.fromJson(e as Map<String, dynamic>)));
  }

  Map<String, dynamic> toJson() => {
        'movies': [for (final m in _movies) m.toJson()],
        'series': [for (final s in _series) s.toJson()],
        'lists': [for (final l in _lists) l.toJson()],
      };

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(toJson()));
    } catch (e) {
      debugPrint('MovieRepository.persist error: $e');
    }
  }

  /// Полностью очищает личную библиотеку (просмотры, списки, оценки, избранное,
  /// сериалы). Остаются только ленты Обзор/В кино (они из TMDB, не хранятся).
  /// Как чистая установка. Необратимо (пусть пользователь сделает бэкап заранее).
  Future<void> clearAll() async {
    _movies.clear();
    _series.clear();
    _lists.clear();
    _limitHit = false;
    // Сбрасываем запомненные уведомления о новых сериях.
    await Store.instance.setStringList('notifiedEpisodeKeys', const []);
    await _persist();
    notifyListeners();
  }

  /// Полная резервная копия (JSON-строка) — для переноса на другое устройство.
  String exportJson() => const JsonEncoder.withIndent(' ').convert({
        'app': 'kadr',
        'version': 1,
        ...toJson(),
      });

  /// Восстанавливает библиотеку из резервной копии (заменяет текущую).
  Future<bool> importJson(String raw) async {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['movies'] == null && data['series'] == null) return false;
      _ingest(data);
      await _persist();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('MovieRepository.import error: $e');
      return false;
    }
  }

  // ------------------------------ выборки ------------------------------

  /// Просмотренные — по убыванию последнего просмотра.
  List<LibraryMovie> get watched {
    final list = _movies
        .where((m) => m.status == LibraryStatus.watched)
        .toList()
      ..sort((a, b) => (b.lastViewing ?? DateTime(0))
          .compareTo(a.lastViewing ?? DateTime(0)));
    return list;
  }

  bool _watchlistNewestFirst = true;
  bool get watchlistNewestFirst => _watchlistNewestFirst;

  Future<void> toggleWatchlistOrder() async {
    _watchlistNewestFirst = !_watchlistNewestFirst;
    notifyListeners();
    await Store.instance.setBool('watchlistNewestFirst', _watchlistNewestFirst);
  }

  /// «Буду смотреть» — по дате добавления (новые сверху; порядок разворачивается).
  List<LibraryMovie> get watchlist {
    final list =
        _movies.where((m) => m.status == LibraryStatus.watchlist).toList();
    list.sort((a, b) {
      final da = a.addedAt, db = b.addedAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1; // без даты — в конец
      if (db == null) return -1;
      return db.compareTo(da); // новые сверху
    });
    return _watchlistNewestFirst ? list : list.reversed.toList();
  }

  List<LibraryMovie> get favorites =>
      _movies.where((m) => m.favorite).toList();

  /// Группировка просмотренного по месяцам: «2023-10» → фильмы (свежие сверху).
  /// Просмотры без даты попадают в группу с ключом-заглушкой `DateTime(1)`.
  List<MapEntry<DateTime, List<LibraryMovie>>> get watchedByMonth {
    final map = <String, List<LibraryMovie>>{};
    final months = <String, DateTime>{};
    for (final m in watched) {
      final d = m.lastViewing;
      final key = d == null
          ? 'unknown'
          : '${d.year}-${d.month.toString().padLeft(2, '0')}';
      final month = d == null ? DateTime(1) : DateTime(d.year, d.month);
      map.putIfAbsent(key, () => []).add(m);
      months[key] = month;
    }
    final keys = months.keys.toList()
      ..sort((a, b) => months[b]!.compareTo(months[a]!));
    return [for (final k in keys) MapEntry(months[k]!, map[k]!)];
  }

  /// Лента «Просмотрено» с фильмами И сериалами (фильтруется), по месяцам.
  List<MapEntry<DateTime, List<WatchedEntry>>> watchedEntriesByMonth(
      {bool movies = true, bool series = true}) {
    final map = <String, List<WatchedEntry>>{};
    final months = <String, DateTime>{};
    void add(DateTime? d, WatchedEntry e) {
      final key = d == null
          ? 'unknown'
          : '${d.year}-${d.month.toString().padLeft(2, '0')}';
      months[key] = d == null ? DateTime(1) : DateTime(d.year, d.month);
      map.putIfAbsent(key, () => []).add(e);
    }

    if (movies) {
      for (final m in _movies) {
        if (m.status != LibraryStatus.watched) continue;
        for (final v in m.viewings) {
          add(v.date, WatchedEntry.movie(m, v));
        }
      }
    }
    if (series) {
      for (final s in _series) {
        for (final sess in s.sessions()) {
          add(sess.start, WatchedEntry.session(sess));
        }
      }
    }
    final keys = months.keys.toList()
      ..sort((a, b) => months[b]!.compareTo(months[a]!));
    final result = <MapEntry<DateTime, List<WatchedEntry>>>[];
    for (final k in keys) {
      final list = map[k]!
        ..sort((a, b) {
          final da = a.date, db = b.date;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      result.add(MapEntry(months[k]!, list));
    }
    return result;
  }

  /// Сериалы с хотя бы одной просмотренной серией (пустые заготовки не в счёт).
  int get seriesCount => _series.where((s) => s.episodes.isNotEmpty).length;

  // ------------------------------ мутации ------------------------------

  LibrarySeries? seriesById(String id) {
    for (final s in _series) {
      if (s.tvShowId == id) return s;
    }
    return null;
  }

  LibrarySeries? seriesByTmdb(int id) {
    for (final s in _series) {
      if (s.tmdbId == id) return s;
    }
    return null;
  }

  /// Возвращает сериал библиотеки для TMDB-карточки, добавляя заготовку, если
  /// его ещё нет (чтобы открыть экран серий из ленты «Сериалы»). Отметки серий
  /// наполняют его дальше. Сериалы из импорта TV Time могут ещё не иметь
  /// tmdbId — сопоставляем по названию, чтобы не плодить дубликаты.
  LibrarySeries ensureSeriesFromTmdb(TmdbSeries t) {
    final existing = seriesByTmdb(t.id);
    if (existing != null) return existing;
    final tl = t.title.toLowerCase().trim();
    final ol = (t.originalTitle ?? '').toLowerCase().trim();
    for (final s in _series) {
      if (s.tmdbId != null) continue;
      final names = {
        s.title.toLowerCase().trim(),
        (s.ruTitle ?? '').toLowerCase().trim(),
      }..remove('');
      if (names.contains(tl) || (ol.isNotEmpty && names.contains(ol))) {
        s.tmdbId = t.id;
        s.posterUrl ??= t.posterUrl;
        s.ruTitle ??= t.title;
        s.kpRating ??= t.rating;
        s.enrichTried = true;
        notifyListeners();
        _persistSoon();
        return s;
      }
    }
    final s = LibrarySeries(
      tvShowId: 'tmdb-tv-${t.id}',
      title: t.originalTitle ?? t.title,
      ruTitle: t.title,
      tmdbId: t.id,
      posterUrl: t.posterUrl,
      kpRating: t.rating,
      enrichTried: true,
    );
    _series.add(s);
    notifyListeners();
    _persistSoon();
    return s;
  }

  /// Ручная привязка сериала к записи TMDB (когда автопоиск не сматчил —
  /// напр. импортное имя латиницей vs. кириллица). Просмотренные серии остаются.
  Future<void> linkSeriesTmdb(String id, TmdbSeries t) async {
    final s = seriesById(id);
    if (s == null) return;
    s.tmdbId = t.id;
    s.posterUrl = t.posterUrl ?? s.posterUrl;
    s.ruTitle = t.title;
    s.kpRating ??= t.rating;
    s.enrichTried = true;
    s.totalEpisodes = null; // пересчитается при загрузке сезонов
    notifyListeners();
    await _persist();
  }

  Future<void> setSeriesScore(String id, double? score) async {
    final s = seriesById(id);
    if (s == null) return;
    s.score = score;
    notifyListeners();
    await _persist();
  }

  Future<void> toggleSeriesFavorite(String id) async {
    final s = seriesById(id);
    if (s == null) return;
    s.favorite = !s.favorite;
    notifyListeners();
    await _persist();
  }

  /// Оценка конкретного эпизода сериала.
  Future<void> setEpisodeScore(
      String seriesId, Episode ep, double? score) async {
    final s = seriesById(seriesId);
    if (s == null || !s.episodes.contains(ep)) return;
    ep.score = score;
    notifyListeners();
    await _persist();
  }

  /// Задаёт дату и время просмотра серии (для ручной правки, как у фильмов).
  Future<void> setEpisodeWatchedAt(
      String seriesId, Episode ep, DateTime? at) async {
    final s = seriesById(seriesId);
    if (s == null || !s.episodes.contains(ep)) return;
    ep.watchedAt = at;
    notifyListeners();
    await _persist();
  }

  /// Отмечает серию просмотренной (добавляет эпизод), если ещё не отмечена.
  Future<void> markEpisodeWatched(String seriesId, int season, int number,
      {int? runtimeMin, DateTime? at}) async {
    final s = seriesById(seriesId);
    if (s == null || s.isEpisodeWatched(season, number)) return;
    s.episodes.add(Episode(
        season: season,
        number: number,
        watchedAt: at ?? DateTime.now(),
        runtimeMin: runtimeMin));
    notifyListeners();
    await _persist();
  }

  /// Снимает отметку просмотра серии.
  Future<void> unmarkEpisode(String seriesId, int season, int number) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    s.episodes.removeWhere((e) => e.season == season && e.number == number);
    notifyListeners();
    await _persist();
  }

  /// Отмечает все серии сезона до [uptoNumber] включительно.
  Future<void> markUpTo(String seriesId, int season, int uptoNumber,
      {Map<int, int?> runtimes = const {}}) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    for (var n = 1; n <= uptoNumber; n++) {
      if (!s.isEpisodeWatched(season, n)) {
        s.episodes.add(Episode(
            season: season,
            number: n,
            watchedAt: DateTime.now(),
            runtimeMin: runtimes[n]));
      }
    }
    notifyListeners();
    await _persist();
  }

  /// Сопоставляет безномерные просмотренные серии (импорт TV Time хранил только
  /// даты, без сезона/номера) с сериями TMDB ПО ПОРЯДКУ: N просмотренных →
  /// первые N серий (по сезонам). Даты сохраняются (ранний просмотр → серия 1).
  /// [ordered] — все (сезон, номер) сериала по порядку. Без сети — номера берутся
  /// из уже загруженного списка сезонов. Идемпотентно (безномерных не осталось —
  /// ничего не делает).
  Future<void> reconcileSeriesEpisodes(
      String seriesId, List<List<int>> ordered) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final unnumbered = s.episodes
        .where((e) => e.season == null || e.number == null)
        .toList()
      ..sort((a, b) => (a.watchedAt ?? DateTime(0))
          .compareTo(b.watchedAt ?? DateTime(0)));
    if (unnumbered.isEmpty) return;
    // Слоты, уже занятые сериями с номерами (не назначаем поверх).
    final taken = <String>{
      for (final e in s.episodes)
        if (e.season != null && e.number != null) '${e.season}-${e.number}'
    };
    var idx = 0;
    for (final slot in ordered) {
      if (idx >= unnumbered.length) break;
      final key = '${slot[0]}-${slot[1]}';
      if (taken.contains(key)) continue;
      final ep = unnumbered[idx++];
      ep.season = slot[0];
      ep.number = slot[1];
    }
    notifyListeners();
    await _persist();
  }

  /// Отмечает просмотренными сразу все переданные серии сезона (по одному тапу).
  /// [numbers] — номера серий сезона; [runtimes] — их длительности (опц.).
  Future<void> markSeason(String seriesId, int season, List<int> numbers,
      {Map<int, int?> runtimes = const {}}) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final now = DateTime.now();
    var added = 0;
    for (final n in numbers) {
      if (!s.isEpisodeWatched(season, n)) {
        s.episodes.add(Episode(
            season: season,
            number: n,
            // Небольшой сдвиг, чтобы серии сезона легли в один блок по порядку.
            watchedAt: now.add(Duration(seconds: added)),
            runtimeMin: runtimes[n]));
        added++;
      }
    }
    notifyListeners();
    await _persist();
  }

  /// Массово отмечает просмотренными переданные серии (последовательный режим:
  /// «отметил серию 10 → серии 1–10»). [eps] — список [сезон, номер].
  Future<void> markEpisodesBulk(String seriesId, List<List<int>> eps) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final now = DateTime.now();
    var added = 0;
    for (final e in eps) {
      if (!s.isEpisodeWatched(e[0], e[1])) {
        s.episodes.add(Episode(
            season: e[0],
            number: e[1],
            watchedAt: now.add(Duration(seconds: added))));
        added++;
      }
    }
    if (added > 0) {
      notifyListeners();
      await _persist();
    }
  }

  /// Массово снимает отметки с переданных серий (последовательный режим:
  /// «снял серию → все после неё»). [eps] — список [сезон, номер].
  Future<void> unmarkEpisodesBulk(String seriesId, List<List<int>> eps) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final keys = {for (final e in eps) '${e[0]}-${e[1]}'};
    final before = s.episodes.length;
    s.episodes.removeWhere((e) => keys.contains('${e.season}-${e.number}'));
    if (s.episodes.length != before) {
      notifyListeners();
      await _persist();
    }
  }

  /// Снимает отметки с конкретных объектов-серий (по ссылке) — для удаления
  /// целой сессии из «Просмотрено». Надёжнее ключей сезон-номер: работает и с
  /// импортированными сериями, где season/number ещё не заполнены.
  Future<void> removeEpisodes(String seriesId, List<Episode> eps) async {
    final s = seriesById(seriesId);
    if (s == null || eps.isEmpty) return;
    final before = s.episodes.length;
    s.episodes.removeWhere((e) => eps.contains(e));
    if (s.episodes.length != before) {
      notifyListeners();
      await _persist();
    }
  }

  /// Снимает отметки со всех серий сезона.
  Future<void> unmarkSeason(String seriesId, int season) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    s.episodes.removeWhere((e) => e.season == season);
    notifyListeners();
    await _persist();
  }

  /// Добавляет повторный просмотр серии (серию можно смотреть несколько раз).
  Future<void> addEpisodeRewatch(String seriesId, int season, int number,
      {int? runtimeMin}) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final ep = s.watchedEpisode(season, number);
    if (ep == null) {
      // Ещё не отмечена — первый просмотр.
      await markEpisodeWatched(seriesId, season, number, runtimeMin: runtimeMin);
      return;
    }
    ep.rewatchCount += 1;
    ep.watchedAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  /// Убирает один повторный просмотр серии (не снимая саму отметку просмотра).
  Future<void> removeEpisodeRewatch(
      String seriesId, int season, int number) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final ep = s.watchedEpisode(season, number);
    if (ep == null || ep.rewatchCount <= 0) return;
    ep.rewatchCount -= 1;
    notifyListeners();
    await _persist();
  }

  /// «Вернуть один просмотр» — сбрасывает все повторы, оставляя ровно один
  /// просмотр серии (серия остаётся отмеченной, ×N исчезает).
  Future<void> resetEpisodeToSingle(
      String seriesId, int season, int number) async {
    final s = seriesById(seriesId);
    final ep = s?.watchedEpisode(season, number);
    if (ep == null || ep.rewatchCount == 0) return;
    ep.rewatchCount = 0;
    notifyListeners();
    await _persist();
  }

  /// Сериалы «сейчас смотрю» — с просмотренными сериями, по свежести.
  List<LibrarySeries> get currentlyWatching {
    final list = _series.where((s) => s.episodes.isNotEmpty).toList()
      ..sort((a, b) => (b.lastWatch ?? DateTime(0))
          .compareTo(a.lastWatch ?? DateTime(0)));
    return list;
  }

  /// Только НЕЗАВЕРШЁННЫЕ сериалы (для экрана «Сейчас смотрю»): есть
  /// просмотренные серии, не брошен и просмотрены не все серии.
  List<LibrarySeries> get nowWatching => currentlyWatching
      .where((s) => !s.dropped && !s.isCompleted)
      .toList();

  /// Запоминает общее число серий сериала (из TMDB) — чтобы отличать
  /// завершённые от незавершённых в «Сейчас смотрю».
  Future<void> setSeriesTotal(String id, int total) async {
    final s = seriesById(id);
    if (s == null || total <= 0 || s.totalEpisodes == total) return;
    s.totalEpisodes = total;
    notifyListeners();
    await _persist();
  }

  LibraryMovie? byUuid(String uuid) {
    for (final m in _movies) {
      if (m.uuid == uuid) return m;
    }
    return null;
  }

  // ------------------------------ списки ------------------------------

  List<String> listsForMovie(String uuid) => _lists
      .where((l) => l.movieUuids.contains(uuid))
      .map((l) => l.name)
      .toList();

  Future<void> toggleInList(String listName, String uuid) async {
    MovieList? l;
    for (final x in _lists) {
      if (x.name == listName) {
        l = x;
        break;
      }
    }
    if (l == null) return;
    if (l.movieUuids.contains(uuid)) {
      l.movieUuids.remove(uuid);
    } else {
      l.movieUuids.add(uuid);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> deleteList(String name) async {
    _lists.removeWhere((l) => l.name == name);
    notifyListeners();
    await _persist();
  }

  Future<void> createList(String name, {String? withMovieUuid}) async {
    final n = name.trim();
    if (n.isEmpty || _lists.any((l) => l.name == n)) {
      if (withMovieUuid != null && _lists.any((l) => l.name == n)) {
        await toggleInList(n, withMovieUuid);
      }
      return;
    }
    _lists.add(MovieList(
        name: n, movieUuids: withMovieUuid != null ? [withMovieUuid] : []));
    notifyListeners();
    await _persist();
  }

  Future<void> setScore(String uuid, double? score) async {
    final m = byUuid(uuid);
    if (m == null) return;
    m.score = score;
    notifyListeners();
    await _persist();
  }

  Future<void> toggleFavorite(String uuid) async {
    final m = byUuid(uuid);
    if (m == null) return;
    m.favorite = !m.favorite;
    notifyListeners();
    await _persist();
  }

  // ------------------------------ брошено ------------------------------

  /// Брошенные фильмы (просмотр прекращён) — для официального списка «Брошено».
  List<LibraryMovie> get droppedMovies =>
      _movies.where((m) => m.status == LibraryStatus.dropped).toList();

  /// Брошенные сериалы.
  List<LibrarySeries> get droppedSeries =>
      _series.where((s) => s.dropped).toList();

  /// Помечает фильм брошенным / снимает пометку (возврат в библиотеку).
  Future<void> toggleDropped(String uuid) async {
    final m = byUuid(uuid);
    if (m == null) return;
    m.status = m.status == LibraryStatus.dropped
        ? LibraryStatus.library
        : LibraryStatus.dropped;
    notifyListeners();
    await _persist();
  }

  /// Помечает сериал брошенным / снимает пометку (просмотренные серии не
  /// стираются — брошено лишь исключает из уведомлений о новых сериях).
  Future<void> toggleSeriesDropped(String id) async {
    final s = seriesById(id);
    if (s == null) return;
    s.dropped = !s.dropped;
    notifyListeners();
    await _persist();
  }

  /// Отмечает просмотр (со своей оценкой). Если фильм уже смотрели — это
  /// повторный просмотр. [date] = null → «неизвестная дата».
  /// Возвращает true, если это был повтор.
  Future<bool> addViewing(String uuid, DateTime? date, {double? score}) async {
    final m = byUuid(uuid);
    if (m == null) return false;
    final wasWatched =
        m.status == LibraryStatus.watched || m.viewings.isNotEmpty;
    if (wasWatched) m.rewatchCount += 1;
    m.status = LibraryStatus.watched;
    m.viewings.add(Viewing(date: date, score: score));
    notifyListeners();
    await _persist();
    return wasWatched;
  }

  /// Устанавливает оценку конкретного просмотра.
  Future<void> setViewingScore(String uuid, Viewing v, double? score) async {
    final m = byUuid(uuid);
    if (m == null || !m.viewings.contains(v)) return;
    v.score = score;
    notifyListeners();
    await _persist();
  }

  /// Меняет дату/время конкретного просмотра ([date] = null → неизвестная дата).
  Future<void> setViewingDate(String uuid, Viewing v, DateTime? date) async {
    final m = byUuid(uuid);
    if (m == null || !m.viewings.contains(v)) return;
    v.date = date;
    notifyListeners();
    await _persist();
  }

  /// Отменяет последний просмотр фильма (удобная широкая кнопка в карточке).
  /// Если это был единственный просмотр — фильм возвращается из «Просмотрено».
  /// Возвращает true, если после этого фильм больше не просмотрен.
  Future<bool> undoLastViewing(String uuid) async {
    final m = byUuid(uuid);
    if (m == null) return true;
    if (m.viewings.isNotEmpty) {
      // Убираем самый поздний по дате просмотр (неизвестные даты — последними).
      final v = m.currentViewing ?? m.viewings.last;
      m.viewings.remove(v);
    }
    if (m.rewatchCount > 0) m.rewatchCount -= 1;
    final nowUnwatched = m.viewings.isEmpty;
    if (nowUnwatched) {
      m.status = LibraryStatus.library;
      m.rewatchCount = 0;
    }
    notifyListeners();
    await _persist();
    return nowUnwatched;
  }

  /// Удаляет просмотр.
  Future<void> removeViewing(String uuid, Viewing v) async {
    final m = byUuid(uuid);
    if (m == null) return;
    m.viewings.remove(v);
    if (m.rewatchCount > 0) m.rewatchCount -= 1;
    if (m.viewings.isEmpty) m.status = LibraryStatus.library;
    notifyListeners();
    await _persist();
  }

  /// Просмотренное по месяцам — КАРТОЧКА НА КАЖДЫЙ ПРОСМОТР (как в референсе):
  /// один фильм может встречаться несколько раз (повторные просмотры).
  List<MapEntry<DateTime, List<(LibraryMovie, Viewing)>>>
      get watchedViewingsByMonth {
    final map = <String, List<(LibraryMovie, Viewing)>>{};
    final months = <String, DateTime>{};
    for (final m in _movies) {
      if (m.status != LibraryStatus.watched) continue;
      for (final v in m.viewings) {
        final d = v.date;
        final key = d == null
            ? 'unknown'
            : '${d.year}-${d.month.toString().padLeft(2, '0')}';
        months[key] = d == null ? DateTime(1) : DateTime(d.year, d.month);
        map.putIfAbsent(key, () => []).add((m, v));
      }
    }
    final keys = months.keys.toList()
      ..sort((a, b) => months[b]!.compareTo(months[a]!));
    final result = <MapEntry<DateTime, List<(LibraryMovie, Viewing)>>>[];
    for (final k in keys) {
      final list = map[k]!
        ..sort((a, b) {
          final da = a.$2.date, db = b.$2.date;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      result.add(MapEntry(months[k]!, list));
    }
    return result;
  }

  /// Добавляет фильм из TMDB-ленты в библиотеку (или обновляет статус).
  Future<void> addFromTmdb(TmdbMovie t, LibraryStatus status) async {
    LibraryMovie? existing;
    for (final m in _movies) {
      if (m.tmdbId == t.id) {
        existing = m;
        break;
      }
    }
    final now = DateTime.now();
    if (existing != null) {
      existing.status = status;
      existing.addedAt ??= now;
      if (status == LibraryStatus.watched) {
        existing.viewings.add(Viewing(date: now));
      }
    } else {
      _movies.add(LibraryMovie(
        uuid: 'tmdb-${t.id}',
        title: t.originalTitle ?? t.title,
        ruTitle: t.title,
        year: t.year,
        posterUrl: t.posterUrl,
        tmdbId: t.id,
        kpRating: t.rating,
        enrichTried: true,
        status: status,
        addedAt: now,
        viewings: status == LibraryStatus.watched ? [Viewing(date: now)] : [],
      ));
    }
    notifyListeners();
    await _persist();
  }

  /// Возвращает фильм библиотеки для TMDB-карточки, добавляя его (статус
  /// «в библиотеке», не в списках) если его ещё нет — чтобы открыть ПОЛНУЮ
  /// карточку из ленты «Обзор»/«В кино». Действия в карточке меняют статус.
  LibraryMovie ensureFromTmdb(TmdbMovie t) {
    final existing = movieByTmdb(t.id);
    if (existing != null) return existing;
    // Импортированный фильм мог ещё не получить tmdbId (enrich не дошёл) —
    // сопоставляем по названию и году, иначе появится дубликат.
    final tl = t.title.toLowerCase().trim();
    final ol = (t.originalTitle ?? '').toLowerCase().trim();
    for (final m in _movies) {
      if (m.tmdbId != null) continue;
      if (t.year != null && m.year != null && (m.year! - t.year!).abs() > 1) {
        continue;
      }
      final names = {
        m.title.toLowerCase().trim(),
        (m.ruTitle ?? '').toLowerCase().trim(),
      }..remove('');
      if (names.contains(tl) || (ol.isNotEmpty && names.contains(ol))) {
        m.tmdbId = t.id;
        m.posterUrl ??= t.posterUrl;
        m.ruTitle ??= t.title;
        m.kpRating ??= t.rating;
        m.enrichTried = true;
        notifyListeners();
        _persistSoon();
        return m;
      }
    }
    final m = LibraryMovie(
      uuid: 'tmdb-${t.id}',
      title: t.originalTitle ?? t.title,
      ruTitle: t.title,
      year: t.year,
      posterUrl: t.posterUrl,
      tmdbId: t.id,
      kpRating: t.rating,
      enrichTried: true,
      status: LibraryStatus.library,
    );
    _movies.add(m);
    notifyListeners();
    _persistSoon();
    return m;
  }

  /// Статус фильма в библиотеке по tmdbId (null — если ещё не добавлен).
  LibraryStatus? statusOfTmdb(int id) => movieByTmdb(id)?.status;

  /// Фильм библиотеки по tmdbId (null — если ещё не добавлен).
  LibraryMovie? movieByTmdb(int id) {
    for (final m in _movies) {
      if (m.tmdbId == id) return m;
    }
    return null;
  }

  /// Переключает «Буду смотреть» (только для непросмотренных).
  Future<void> toggleWatchlist(String uuid) async {
    final m = byUuid(uuid);
    if (m == null || m.status == LibraryStatus.watched) return;
    m.status = m.status == LibraryStatus.watchlist
        ? LibraryStatus.library
        : LibraryStatus.watchlist;
    if (m.status == LibraryStatus.watchlist) m.addedAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  // ------------------------ обогащение kinopoisk.dev ------------------------

  bool _sweeping = false;
  bool _limitHit = false;
  Timer? _persistDebounce;

  /// Достигнут ли суточный лимит API (для показа подсказки в UI).
  bool get limitHit => _limitHit;

  /// Сколько фильмов ещё не обогащено (нет постера и не пробовали).
  int get pendingEnrich =>
      _movies.where((m) => m.posterUrl == null && !m.enrichTried).length;

  void _persistSoon() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 3), _persist);
  }

  /// Обогащает один фильм (русское название + постер + рейтинг КП).
  /// Возвращает false, если пора остановиться (лимит API).
  Future<bool> enrich(LibraryMovie m, {bool persist = true}) async {
    if (m.posterUrl != null || m.enrichTried) return true;
    try {
      final source = SourceController.instance.source;
      final match = source == MovieSource.tmdb
          ? await TmdbService.search(m.title, year: m.year)
          : await KinopoiskService.search(m.title, year: m.year);
      m.enrichTried = true;
      if (match != null) {
        m.kinopoiskId ??= match.kinopoiskId;
        m.tmdbId ??= match.tmdbId;
        m.posterUrl = match.posterUrl;
        m.kpRating ??= match.rating;
        if (match.ruName != null && match.ruName!.isNotEmpty) {
          m.ruTitle = match.ruName;
        }
      }
      notifyListeners();
      if (persist) _persistSoon();
      return true;
    } on SourceLimitException {
      _limitHit = true;
      m.enrichTried = false; // не помечаем — повторим позже
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('enrich error for ${m.title}: $e');
      return true; // сетевая ошибка — пропускаем, попробуем позже
    }
  }

  /// Обогащает сериал (русское название + постер из TMDB).
  Future<bool> enrichSeries(LibrarySeries s) async {
    if (s.posterUrl != null || s.enrichTried) return true;
    try {
      final match = await TmdbService.searchTv(s.title);
      s.enrichTried = true;
      if (match != null) {
        s.tmdbId = match.tmdbId;
        s.posterUrl = match.posterUrl;
        s.kpRating = match.rating;
        if (match.ruName != null && match.ruName!.isNotEmpty) {
          s.ruTitle = match.ruName;
        }
      }
      notifyListeners();
      _persistSoon();
      return true;
    } on SourceLimitException {
      _limitHit = true;
      s.enrichTried = false;
      return false;
    } catch (e) {
      debugPrint('enrichSeries error ${s.title}: $e');
      return true;
    }
  }

  /// Повторить обогащение для необогащённых (напр. после смены источника).
  Future<void> retryUnmatched() async {
    _limitHit = false;
    for (final m in _movies) {
      if (m.posterUrl == null) m.enrichTried = false;
    }
    for (final s in _series) {
      if (s.posterUrl == null) s.enrichTried = false;
    }
    await _persist();
    await startEnrichSweep();
  }

  /// Фоновая дозагрузка: обогащает фильмы порциями, начиная с того, что
  /// пользователь видит первым (свежие просмотры → список → остальное).
  /// Останавливается на суточном лимите. [budget] — максимум запросов за проход.
  Future<void> startEnrichSweep({int budget = 450, int seriesBudget = 250}) async {
    if (_sweeping || _limitHit) return;
    _sweeping = true;
    try {
      final queue = <LibraryMovie>[
        ...watched,
        ...watchlist,
        ..._movies.where((m) => m.status == LibraryStatus.library),
      ].where((m) => m.posterUrl == null && !m.enrichTried).toList();

      var used = 0;
      for (final m in queue) {
        if (used >= budget) break;
        final ok = await enrich(m, persist: false);
        used++;
        if (!ok) break; // лимит
        _persistSoon();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      // Сериалы — отдельный бюджет (не голодают за фильмами).
      if (!_limitHit) {
        var sUsed = 0;
        final sQueue = _series
            .where((s) => s.posterUrl == null && !s.enrichTried)
            .toList();
        for (final s in sQueue) {
          if (sUsed >= seriesBudget) break;
          final ok = await enrichSeries(s);
          sUsed++;
          if (!ok) break;
          _persistSoon();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    } finally {
      await _persist();
      _sweeping = false;
    }
  }

  Future<void> setTmdbId(String uuid, int id) async {
    final m = byUuid(uuid);
    if (m == null || m.tmdbId == id) return;
    m.tmdbId = id;
    await _persist();
  }

  Future<void> setPoster(String uuid, {int? kinopoiskId, String? posterUrl}) async {
    final m = byUuid(uuid);
    if (m == null) return;
    if (kinopoiskId != null) m.kinopoiskId = kinopoiskId;
    if (posterUrl != null) m.posterUrl = posterUrl;
    notifyListeners();
    await _persist();
  }
}
