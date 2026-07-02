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
        add(s.lastWatch, WatchedEntry.series(s));
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

  int get seriesCount => _series.length;

  // ------------------------------ мутации ------------------------------

  LibrarySeries? seriesById(String id) {
    for (final s in _series) {
      if (s.tvShowId == id) return s;
    }
    return null;
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
