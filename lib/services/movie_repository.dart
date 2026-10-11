import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../l10n/locale_controller.dart';
import '../models/library_entry.dart';
import '../models/review.dart';
import '../utils/movie_reviews.dart';
import '../utils/season_pass.dart';
import '../utils/season_reviews.dart';
import '../utils/series_finale.dart';
import 'kinopoisk_service.dart';
import 'movie_source.dart';
import 'poster_store.dart';
import 'store.dart';
import 'sync/sync_merge.dart';
import 'tmdb_service.dart';
import 'tvdb_service.dart';

/// Удалённый просмотр: всё, чтобы «Вернуть» поставило на место его одного.
///
/// Раньше «Вернуть» подменяло фильм или сериал целиком снимком, снятым до
/// удаления, и стирало всё, что человек успел сделать после.
class RemovedView {
  /// Копия просмотра с его id, датой, оценкой и дневником.
  final Viewing view;

  /// Где он стоял в списке, чтобы вернуться на то же место.
  final int index;

  /// Рецензия фильма на этот просмотр, если была.
  final ExtraReview? review;

  /// Статус фильма до удаления.
  final LibraryStatus? status;

  /// Это был первый просмотр серии, см. [Episode.vid].
  final bool wasFirst;

  /// Длительность и id серии: нужны, когда вместе с единственным просмотром
  /// ушла сама серия.
  final int? runtimeMin;
  final String? epId;

  const RemovedView({
    required this.view,
    this.index = 0,
    this.review,
    this.status,
    this.wasFirst = false,
    this.runtimeMin,
    this.epId,
  });
}

/// Единое хранилище библиотеки фильмов/сериалов Kadr.
///
/// При первом запуске подгружает импортированную базу из ассета
/// `assets/seed/library.json` (экспорт TV Time) и сохраняет её в файл документов.
/// Дальше — источник истины файл `library.json` в каталоге приложения.
/// Мутации персистятся и оповещают слушателей (экраны обновляются на лету).
class MovieRepository extends ChangeNotifier {
  MovieRepository._();
  static final MovieRepository instance = MovieRepository._();

  /// Detached-экземпляр ТОЛЬКО для просмотра чужой (публичной) библиотеки друга:
  /// наполняется его проекцией, НЕ читает и НЕ пишет диск, не обогащает и не
  /// синкается. Позволяет отрисовать ленту «Просмотрено»/«Буду смотреть» и
  /// статистику друга теми же экранами, что и свою (read-only).
  factory MovieRepository.detached(Map<String, dynamic> data) {
    final r = MovieRepository._();
    r._detached = true;
    r._ingest(data);
    r._loaded = true;
    return r;
  }

  /// true — это read-only копия чужой библиотеки: любые записи на диск заглушены.
  bool _detached = false;
  bool get isDetached => _detached;

  final List<LibraryMovie> _movies = [];
  final List<LibrarySeries> _series = [];
  final List<MovieList> _lists = [];
  bool _loaded = false;

  /// Кэш ленты «Просмотрено» (по комбинации фильмы/сериалы). Пересборка ленты
  /// (сессии всех сериалов + помесячная сортировка) тяжёлая на большой базе —
  /// считаем один раз и переиспользуем, пока данные не изменились. Сбрасывается
  /// в [notifyListeners] при любой мутации. Так переключение вида/вкладок и
  /// открытие меню (не меняют данные) больше не пересчитывают ленту → без фризов.
  final Map<String, List<MapEntry<DateTime, List<WatchedEntry>>>>
      _watchedCache = {};

  /// Версия данных: растёт при любой мутации. Экраны мемоизируют тяжёлые
  /// вычисления по ней — пересчитывают только когда данные реально изменились,
  /// а не на каждый rebuild (переключение вида/вкладок/меню).
  int _revision = 0;
  int get revision => _revision;

  @override
  void notifyListeners() {
    _watchedCache.clear();
    _revision++;
    super.notifyListeners();
  }

  bool get isLoaded => _loaded;
  List<LibraryMovie> get movies => List.unmodifiable(_movies);

  /// Есть ли что бэкапить/показывать (не пустая ли библиотека).
  bool get hasData =>
      _movies.isNotEmpty || _series.isNotEmpty || _lists.isNotEmpty;
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
      // Чистим задвоенные серии (наследие старого бага bulk-операций): сливаем
      // эпизоды с одинаковыми (сезон,номер), сохраняя оценку/дату. Оценки на
      // экране сериала были, а в списке «Просмотрено» дубли шли пустыми.
      // Заодно выкидываем спецвыпуски (сезон/серия 0), которые импорт TV Time
      // сохранил как «Серия 0» — они мусорят список серий и счётчики.
      var deduped = 0;
      for (final s in _series) {
        deduped += _dropSpecials(s);
        deduped += _dedupeEpisodes(s);
      }
      if (deduped > 0) await _persist();

      _watchlistNewestFirst =
          await Store.instance.getBool('watchlistNewestFirst', def: true);
    } catch (e) {
      debugPrint('MovieRepository.load error: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Убирает спецвыпуски сериала — серии, у которых сезон или номер ≤ 0
  /// (импорт TV Time сохранял такие как «Серия 0»). Возвращает число убранных.
  /// Безномерные серии (season/number == null) НЕ трогаем — их разложит
  /// [reconcileSeriesEpisodes] по порядку.
  int _dropSpecials(LibrarySeries s) {
    final before = s.episodes.length;
    s.episodes.removeWhere((e) =>
        (e.season != null && e.season! <= 0) ||
        (e.number != null && e.number! <= 0));
    return before - s.episodes.length;
  }

  /// Сливает задвоенные серии сериала (одинаковые сезон+номер) в одну, сохраняя
  /// оценку, раннюю дату и больший счётчик повторов. Возвращает число убранных.
  int _dedupeEpisodes(LibrarySeries s) {
    final byKey = <String, Episode>{};
    final kept = <Episode>[];
    final unnumbered = <Episode>[];
    var removed = 0;
    for (final e in s.episodes) {
      if (e.season == null || e.number == null) {
        unnumbered.add(e);
        continue;
      }
      final key = '${e.season}-${e.number}';
      final prev = byKey[key];
      if (prev == null) {
        byKey[key] = e;
        kept.add(e);
      } else {
        prev.score ??= e.score;
        if (prev.watchedAt == null) {
          prev.watchedAt = e.watchedAt;
        } else if (e.watchedAt != null &&
            e.watchedAt!.isBefore(prev.watchedAt!)) {
          prev.watchedAt = e.watchedAt;
        }
        // Повторы дублей: берём БОЛЕЕ ПОЛНЫЙ список (без склейки — дубли обычно
        // повторяют одни и те же просмотры, склейка бы задвоила ×N).
        if (e.rewatchViews.length > prev.rewatchViews.length) {
          prev.rewatchViews = e.rewatchViews;
        }
        prev.diary ??= e.diary;
        prev.runtimeMin ??= e.runtimeMin;
        prev.epId ??= e.epId;
        removed++;
      }
    }
    if (removed > 0) s.episodes = [...kept, ...unnumbered];
    return removed;
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
    _stampWatchlistDates();
    _movies.forEach(bindLooseReviews);
  }

  /// Сериалы из импорта TV Time и версий до 0.20 лежат в «Буду смотреть» без
  /// даты добавления. Сортировка «новые сверху» уводила их под все фильмы
  /// списка — проставляем дату один раз, дальше её ведёт сам пользователь.
  void _stampWatchlistDates() {
    final now = DateTime.now();
    for (final s in _series) {
      if (s.watchlist && s.addedAt == null) s.addedAt = now;
    }
  }

  Map<String, dynamic> toJson() => {
        'movies': [for (final m in _movies) m.toJson()],
        'series': [for (final s in _series) s.toJson()],
        'lists': [for (final l in _lists) l.toJson()],
      };

  /// Разрешает записать ПУСТУЮ библиотеку (только для явной очистки clearAll).
  bool _allowEmptyPersist = false;

  Future<void> _persist() async {
    if (_detached) return; // read-only копия чужой библиотеки — не пишем диск
    _persistDebounce?.cancel(); // объединяем с отложенной записью
    try {
      final f = await _file();
      // ЗАЩИТА ОТ ПОТЕРИ ДАННЫХ: никогда не затираем непустую базу на диске
      // пустой в памяти (кроме явной очистки clearAll). Ловит любые сбои, где
      // _movies случайно опустел — гонка, исключение в load(), фон-sweep до
      // загрузки и т.п. Раньше такой сценарий мог перезаписать всю библиотеку
      // пустым файлом безвозвратно.
      if (!_allowEmptyPersist &&
          _movies.isEmpty &&
          _series.isEmpty &&
          _lists.isEmpty &&
          await f.exists()) {
        debugPrint('Kadr: пропускаю запись пустой базы поверх существующей');
        return;
      }
      // Пишем во временный файл и атомарно подменяем: если приложение убьют
      // посреди записи, library.json не побьётся — останется прошлая версия.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(toJson()), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('MovieRepository.persist error: $e');
    }
  }

  /// Немедленно сбрасывает на диск отложенную (debounce) запись — вызывать при
  /// уходе приложения в фон, чтобы не потерять последние изменения.
  Future<void> flush() async {
    if (_persistDebounce?.isActive ?? false) await _persist();
  }

  /// Восстанавливает фильмы/сериалы из JSON-снимка, снятого перед массовым
  /// удалением (кнопка «Отмена» в снекбаре). Запись с тем же uuid/tvShowId
  /// заменяется снимком; если её уже нет — добавляется заново.
  Future<void> restoreFromSnapshot(
    List<Map<String, dynamic>> movies,
    List<Map<String, dynamic>> series,
  ) async {
    for (final j in movies) {
      final m = LibraryMovie.fromJson(j);
      final i = _movies.indexWhere((x) => x.uuid == m.uuid);
      if (i >= 0) {
        _movies[i] = m;
      } else {
        _movies.add(m);
      }
    }
    for (final j in series) {
      final s = LibrarySeries.fromJson(j);
      final i = _series.indexWhere((x) => x.tvShowId == s.tvShowId);
      if (i >= 0) {
        _series[i] = s;
      } else {
        _series.add(s);
      }
    }
    notifyListeners();
    await _persist();
  }

  /// Полностью удаляет сериал из базы (для мусорных/ненаходимых записей).
  /// Возвращает JSON-снимок для «Отмены» (restoreFromSnapshot) или null.
  Future<Map<String, dynamic>?> deleteSeries(String id) async {
    final s = seriesById(id);
    if (s == null) return null;
    final snap = s.toJson();
    _series.remove(s);
    notifyListeners();
    await _persist();
    return snap;
  }

  /// Полностью удаляет фильм из базы. Возвращает JSON-снимок для «Отмены».
  Future<Map<String, dynamic>?> deleteMovie(String uuid) async {
    final m = byUuid(uuid);
    if (m == null) return null;
    final snap = m.toJson();
    _movies.remove(m);
    notifyListeners();
    await _persist();
    return snap;
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
    // Явная очистка — единственный случай, когда разрешено записать пустую базу.
    _allowEmptyPersist = true;
    await _persist();
    _allowEmptyPersist = false;
    notifyListeners();
  }

  /// Полная резервная копия (JSON-строка) — для переноса на другое устройство.
  String exportJson() => const JsonEncoder.withIndent(' ').convert({
        'app': 'kadr',
        'version': 1,
        ...toJson(),
      });

  /// Снимок для синхронизации (без device-local настроек).
  Map<String, dynamic> buildSyncSnapshot() => {
        'kind': kSyncKind,
        'version': kSyncVersion,
        ...toJson(),
      };

  /// Публичная проекция библиотеки для друзей: полный снимок просмотров и
  /// желаний (чтобы друг видел ленту «Просмотрено»/«Буду смотреть» и статистику
  /// теми же экранами), но БЕЗ приватного — личных списков, черновиков и
  /// рецензий, закрытых от друзей. В облако
  /// уезжает только это; настройки и device-local данные не входят.
  ///
  /// [hideRatings] — не делиться оценками; [hideDates] — скрыть точные даты
  /// (огрубляются до начала месяца, чтобы лента друга оставалась заполненной).
  Map<String, dynamic> buildPublicProfile(
      {bool hideRatings = false, bool hideDates = false}) {
    String? coarse(dynamic iso) {
      if (iso == null) return null;
      final d = DateTime.tryParse('$iso');
      return d == null ? null : DateTime(d.year, d.month).toIso8601String();
    }

    // Id просмотра выводится из его даты или из момента отметки, id рецензии
    // — из момента создания: при скрытых датах по ним читалось бы точное
    // время. Наружу уходят порядковые номера, рецензии переезжают на них же.
    // Момент правки просмотра нужен только синхронизации.
    Map<String, String> renumber(List views) {
      final ids = <String, String>{};
      for (final v in views) {
        final id = 'p${ids.length + 1}';
        ids['${(v as Map)['id']}'] = id;
        v
          ..['id'] = id
          ..remove('edited');
      }
      return ids;
    }

    void relink(Map? review, Map<String, String> ids) {
      final meta = review?['reviewMeta'] as Map?;
      if (meta == null) return;
      final id = ids[meta['viewId']];
      if (id == null) {
        meta.remove('viewId');
      } else {
        meta['viewId'] = id;
      }
    }

    // Дневник просмотра личный: настроение, с кем, где, фото и заметка не
    // уезжают ни при каких настройках.
    void stripMovie(Map m) {
      final ids = renumber(m['viewings'] as List? ?? []);
      relink(m, ids);
      final more = (m['moreReviews'] as List? ?? []);
      for (var i = 0; i < more.length; i++) {
        (more[i] as Map)['id'] = 'r${i + 1}';
        relink(more[i] as Map, ids);
      }
      for (final v in (m['viewings'] as List? ?? [])) {
        (v as Map).remove('diary');
      }
      if (hideRatings) {
        m['score'] = null;
        for (final v in (m['viewings'] as List? ?? [])) {
          (v as Map)['score'] = null;
        }
      }
      if (hideDates) {
        m['addedAt'] = coarse(m['addedAt']);
        for (final v in (m['viewings'] as List? ?? [])) {
          (v as Map)['date'] = coarse(v['date']);
        }
      }
    }

    void stripSeries(Map s) {
      if (hideRatings) s['score'] = null;
      // Когда выбрали источник оценки, нужно только синхронизации.
      s.remove('scoreSourceAt');
      final parts = (s['seasonReviews'] as List? ?? []);
      for (var i = 0; i < parts.length; i++) {
        (parts[i] as Map)['id'] = 'r${i + 1}';
      }
      if (hideDates) {
        s['addedAt'] = coarse(s['addedAt']);
        // «Догнал» записан моментом просмотра последней серии.
        if (s['caughtUpAt'] is List) {
          s['caughtUpAt'] = [for (final d in s['caughtUpAt'] as List) coarse(d)];
        }
      }
      for (final e in (s['episodes'] as List? ?? [])) {
        final em = e as Map;
        em
          ..remove('diary')
          ..remove('vid')
          ..remove('vEdited');
        renumber(em['rewatchViews'] as List? ?? []);
        for (final v in (em['rewatchViews'] as List? ?? [])) {
          (v as Map).remove('diary');
        }
        if (hideRatings) {
          em['score'] = null;
          for (final v in (em['rewatchViews'] as List? ?? [])) {
            (v as Map)['score'] = null;
          }
        }
        if (hideDates) {
          em['watchedAt'] = coarse(em['watchedAt']);
          for (final v in (em['rewatchViews'] as List? ?? [])) {
            (v as Map)['date'] = coarse(v['date']);
          }
        }
      }
    }

    // Рецензия уезжает, только если опубликована и открыта друзьям.
    // Черновики и старые приватные рецензии режутся вместе с разбором.
    // Рецензии на сезоны и на другие просмотры фильма проходят то же сито
    // по одной.
    Map<String, dynamic> withReview(HasReview item, Map<String, dynamic> j) {
      if (!item.reviewIsPublic) {
        j.remove('review');
        j.remove('reviewMeta');
      } else {
        final meta = j['reviewMeta'] as Map?;
        if (hideRatings) meta?.remove('criteria');
        if (hideDates && meta != null) {
          for (final k in ['createdAt', 'updatedAt', 'publishedAt']) {
            if (meta[k] != null) meta[k] = coarse(meta[k]);
          }
        }
      }
      if (item is LibraryMovie) {
        final more = [
          for (final r in item.moreReviews)
            if (r.reviewIsPublic) withReview(r, r.toJson()),
        ];
        if (more.isEmpty) {
          j.remove('moreReviews');
        } else {
          j['moreReviews'] = more;
        }
      }
      if (item is LibrarySeries) {
        final parts = [
          for (final p in item.seasonReviews)
            if (p.reviewIsPublic) withReview(p, p.toJson()),
        ];
        if (parts.isEmpty) {
          j.remove('seasonReviews');
        } else {
          j['seasonReviews'] = parts;
        }
      }
      return j;
    }

    final movies = [
      for (final m in _movies)
        if (m.status == LibraryStatus.watched ||
            m.status == LibraryStatus.watchlist ||
            m.status == LibraryStatus.dropped ||
            m.favorite)
          withReview(m, m.toJson()),
    ];
    final series = [
      for (final s in _series)
        if (s.episodes.isNotEmpty || s.watchlist || s.favorite || s.dropped)
          withReview(s, s.toJson()),
    ];
    for (final m in movies) {
      stripMovie(m);
    }
    for (final s in series) {
      stripSeries(s);
    }
    return {'app': 'kadr', 'v': 1, 'movies': movies, 'series': series};
  }

  /// Сливает удалённый снимок с локальным (объединение), применяет результат и
  /// сохраняет. Возвращает статистику изменений (для сообщения пользователю).
  Future<SyncStats> mergeSyncSnapshot(Map<String, dynamic> remote) async {
    final stats = SyncStats();
    final merged = mergeSnapshots(buildSyncSnapshot(), remote, stats);
    _ingest(merged);
    await _persist();
    notifyListeners();
    return stats;
  }

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

  /// Импорт фильмов из другого трекера (Letterboxd/IMDb/…): добавляет новые
  /// (дедуп по названию+году), у существующих дозаполняет просмотры/оценку/
  /// статус. НЕ дублирует просмотры с той же датой. Возвращает (добавлено,
  /// обновлено). Постеры/детали подтянет фоновая дозагрузка.
  Future<(int, int)> importMovies(List<LibraryMovie> incoming) async {
    String norm(String s) => s.toLowerCase().trim();
    final index = <String, LibraryMovie>{};
    for (final m in _movies) {
      index['${norm(m.title)}|${m.year ?? 0}'] = m;
      if (m.ruTitle != null) index['${norm(m.ruTitle!)}|${m.year ?? 0}'] = m;
    }
    var added = 0, updated = 0;
    for (final inc in incoming) {
      final key = '${norm(inc.title)}|${inc.year ?? 0}';
      final existing = index[key];
      if (existing != null) {
        if (inc.status == LibraryStatus.watched) {
          existing.status = LibraryStatus.watched;
        } else if (inc.status == LibraryStatus.watchlist &&
            existing.status == LibraryStatus.library) {
          existing.status = LibraryStatus.watchlist;
        }
        // Просмотр с той же датой второй раз не добавляется, но оценку из
        // файла забирает: у импортируемого фильма она уже лежит в просмотре.
        for (final v in inc.viewings) {
          final same =
              existing.viewings.where((x) => x.date == v.date).firstOrNull;
          if (same == null) {
            existing.viewings.add(v);
          } else {
            same.score ??= v.score;
          }
        }
        existing.score ??= inc.score;
        existing.adoptHeadlineScore();
        existing.addedAt ??= inc.addedAt;
        updated++;
      } else {
        bindLooseReviews(inc);
        _movies.add(inc);
        index[key] = inc;
        added++;
      }
    }
    if (added > 0 || updated > 0) {
      notifyListeners();
      await _persist();
      startEnrichSweep(); // подтянуть постеры/названия в фоне
    }
    return (added, updated);
  }

  /// Импорт сериалов (TV Time и др.). Дедуп по tmdbId, иначе по названию —
  /// эпизоды сливаются по (сезон, номер): первый просмотр в watchedAt, повторы
  /// в rewatchViews (даты не дублируются). Постеры дотягиваются в фоне.
  Future<(int, int)> importSeries(List<LibrarySeries> incoming) async {
    String norm(String s) => s.toLowerCase().trim();
    final byTitle = <String, LibrarySeries>{};
    final byTmdb = <int, LibrarySeries>{};
    for (final s in _series) {
      byTitle[norm(s.title)] = s;
      if (s.ruTitle != null) byTitle[norm(s.ruTitle!)] = s;
      if (s.tmdbId != null) byTmdb[s.tmdbId!] = s;
    }
    var added = 0, updated = 0;
    for (final inc in incoming) {
      LibrarySeries? existing;
      if (inc.tmdbId != null) existing = byTmdb[inc.tmdbId];
      existing ??= byTitle[norm(inc.title)];
      if (existing != null) {
        _mergeEpisodes(existing, inc.episodes);
        existing.favorite = existing.favorite || inc.favorite;
        existing.review ??= inc.review;
        existing.year ??= inc.year;
        updated++;
      } else {
        _series.add(inc);
        byTitle[norm(inc.title)] = inc;
        added++;
      }
    }
    if (added > 0 || updated > 0) {
      notifyListeners();
      await _persist();
      startEnrichSweep();
    }
    return (added, updated);
  }

  /// Слить входящие эпизоды в существующий сериал: совпавшие по (сезон, номер)
  /// добавляют недостающие даты как повторы, новые — добавляются целиком.
  void _mergeEpisodes(LibrarySeries s, List<Episode> incoming) {
    for (final ep in incoming) {
      final existing = s.watchedEpisode(ep.season, ep.number);
      if (existing == null) {
        s.episodes.add(ep);
        continue;
      }
      final have = <DateTime?>{
        existing.watchedAt,
        for (final v in existing.rewatchViews) v.date,
      };
      for (final v in [
        Viewing(date: ep.watchedAt, score: ep.score),
        ...ep.rewatchViews,
      ]) {
        if (!have.contains(v.date)) {
          existing.rewatchViews.add(v);
          have.add(v.date);
        }
      }
      existing.runtimeMin ??= ep.runtimeMin;
    }
  }

  /// Импорт пользовательских списков (TV Time). По имени: новый добавляется,
  /// существующий пополняется недостающими uuid. Возвращает число новых списков.
  Future<int> importLists(List<MovieList> incoming) async {
    var n = 0;
    for (final inc in incoming) {
      if (inc.name.trim().isEmpty) continue;
      MovieList? existing;
      for (final l in _lists) {
        if (l.name == inc.name) {
          existing = l;
          break;
        }
      }
      if (existing == null) {
        _lists.add(MovieList(
            name: inc.name,
            movieUuids: [...inc.movieUuids],
            public: inc.public));
        n++;
      } else {
        for (final u in inc.movieUuids) {
          if (!existing.movieUuids.contains(u)) existing.movieUuids.add(u);
        }
      }
    }
    if (n > 0) {
      notifyListeners();
      await _persist();
    }
    return n;
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

  /// Избранные сериалы (для списка «Избранное» рядом с фильмами).
  List<LibrarySeries> get favoriteSeries =>
      _series.where((s) => s.favorite).toList();

  /// Просмотренные сериалы — с хотя бы одной просмотренной серией, по свежести
  /// (для системного списка «Просмотренные сериалы»).
  List<LibrarySeries> get watchedSeries {
    final list = _series.where((s) => s.episodes.isNotEmpty).toList()
      ..sort((a, b) =>
          (b.lastWatch ?? DateTime(0)).compareTo(a.lastWatch ?? DateTime(0)));
    return list;
  }

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
    final cacheKey = '$movies-$series';
    final cached = _watchedCache[cacheKey];
    if (cached != null) return cached;
    final map = <String, List<WatchedEntry>>{};
    final months = <String, DateTime>{};
    void add(DateTime? d, WatchedEntry e) {
      final key = d == null
          ? 'unknown'
          : '${d.year}-${d.month.toString().padLeft(2, '0')}';
      months[key] = d == null ? DateTime(1) : DateTime(d.year, d.month);
      map.putIfAbsent(key, () => []).add(e);
    }

    // Просмотры/сессии без даты («Неизвестно») в ленту НЕ попадают — они живут
    // только в карточке фильма/сериала (по просьбе: не засорять «Просмотрено»).
    if (movies) {
      for (final m in _movies) {
        if (m.status != LibraryStatus.watched) continue;
        for (final v in m.viewings) {
          if (v.date == null) continue;
          add(v.date, WatchedEntry.movie(m, v));
        }
      }
    }
    if (series) {
      for (final s in _series) {
        for (final sess in s.sessions()) {
          if (sess.start == null) continue;
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
    _watchedCache[cacheKey] = result;
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
    if (existing != null) {
      if (existing.year == null && t.year != null) existing.year = t.year;
      return existing;
    }
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
        s.year ??= t.year;
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
      year: t.year,
      enrichTried: true,
      addedAt: DateTime.now(),
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
    s.air = null; // сведения о выходе были про чужое шоу
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

  /// «Буду смотреть» для сериала (добавить/убрать). Снимаем «Брошено», если было.
  Future<void> toggleSeriesWatchlist(String id) async {
    final s = seriesById(id);
    if (s == null) return;
    s.watchlist = !s.watchlist;
    if (s.watchlist) {
      s.dropped = false;
      // Дата нужна сортировке «новые сверху»: без неё сериал уезжает в самый
      // низ списка, за все фильмы.
      s.addedAt ??= DateTime.now();
    }
    notifyListeners();
    await _persist();
  }

  /// Сериалы в «Буду смотреть»: те, что пользователь пометил сам.
  ///
  /// Начатые не отсеиваем. Раньше условие `episodes.isEmpty` выбрасывало из
  /// списка любой сериал с отмеченной серией — на экране сериала кнопка горела
  /// «В списке», а вкладка оставалась пустой (в базе из импорта TV Time серии
  /// есть почти у всех).
  List<LibrarySeries> get watchlistSeries =>
      _series.where((s) => s.watchlist && !s.dropped).toList();

  /// Отмечает серию просмотренной с НЕИЗВЕСТНОЙ датой (или снимает дату у уже
  /// отмеченной). Такая серия не попадает в ленту «Просмотрено», но остаётся
  /// отмеченной галочкой и в карточке сериала.
  Future<void> markEpisodeUnknown(String seriesId, int season, int number,
      {int? runtimeMin}) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final ep = s.watchedEpisode(season, number);
    if (ep == null) {
      s.episodes.add(Episode(
          season: season, number: number, watchedAt: null, runtimeMin: runtimeMin));
    } else {
      ep
        ..watchedAt = null
        ..editedAt = DateTime.now();
    }
    notifyListeners();
    await _persist();
  }

  /// Отмечает серию просмотренной (добавляет эпизод), если ещё не отмечена.
  /// [at] — когда посмотрели (по умолчанию сейчас); [undated] — «не помню
  /// когда»: серия отмечена, но в ленту не попадает.
  Future<void> markEpisodeWatched(String seriesId, int season, int number,
      {int? runtimeMin, DateTime? at, bool undated = false}) async {
    final s = seriesById(seriesId);
    if (s == null || s.isEpisodeWatched(season, number)) return;
    s.episodes.add(Episode(
        season: season,
        number: number,
        watchedAt: undated ? null : at ?? DateTime.now(),
        runtimeMin: runtimeMin));
    // Отметили новую серию → сериал снова «смотрю» (напр. вышел новый сезон).
    s.finished = false;
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
  /// [numbers] — номера серий сезона; [runtimes] — их длительности (опц.);
  /// [date] — когда посмотрели (null = «неизвестная дата», watchedAt пустой).
  /// Небольшой сдвиг по секундам держит серии одной сессией по порядку.
  Future<void> markSeason(String seriesId, int season, List<int> numbers,
      {Map<int, int?> runtimes = const {}, DateTime? date}) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    var added = 0;
    for (final n in numbers) {
      if (!s.isEpisodeWatched(season, n)) {
        s.episodes.add(Episode(
            season: season,
            number: n,
            watchedAt: date?.add(Duration(seconds: added)),
            runtimeMin: runtimes[n]));
        added++;
      }
    }
    notifyListeners();
    await _persist();
  }

  /// Ставит ОДНУ оценку всем УЖЕ ПРОСМОТРЕННЫМ сериям сезона: каждой — в её
  /// последний просмотр, чтобы оценка серии стала именно такой. НЕ отмечает
  /// новые серии просмотренными (и не трогает невышедшие). Возвращает число
  /// оценённых серий.
  Future<int> setSeasonScore(String seriesId, int season, double? score) async {
    final s = seriesById(seriesId);
    if (s == null) return 0;
    var n = 0;
    for (final e in s.episodes) {
      if (e.season == season) {
        _setViewScore(e, e.orderedViews.last.id, score);
        n++;
      }
    }
    if (n > 0) {
      notifyListeners();
      await _persist();
    }
    return n;
  }

  /// Доводит просмотр сезона до конца: серии из [numbers], у которых
  /// просмотров меньше, чем нужно для следующего целого просмотра сезона,
  /// получают ещё один. Серию, которую смотрели чаще остальных, не трогает.
  /// [date] — когда пересмотрели (null — «не помню»: в ленту не попадёт).
  /// Небольшой сдвиг по секундам держит серии одной сессией по порядку.
  /// Возвращает число затронутых серий; 0, если сезон ещё не досмотрен в
  /// первый раз.
  Future<int> completeSeasonPass(
      String seriesId, int season, List<int> numbers, DateTime? date) async {
    final s = seriesById(seriesId);
    if (s == null) return 0;
    final state = seasonPass(s, season, numbers);
    if (state.completed == 0) return 0;
    final eps = [
      for (final n in numbers.toList()..sort()) s.watchedEpisode(season, n)!,
    ];
    var added = 0;
    for (final e in eps) {
      if (e.watchCount >= state.current) continue;
      e.rewatchViews.add(Viewing(date: date?.add(Duration(seconds: added))));
      added++;
    }
    if (added > 0) {
      notifyListeners();
      await _persist();
    }
    return added;
  }

  /// Массово ставит дату/время просмотра всем просмотренным сериям сезона.
  /// Небольшой сдвиг по секундам сохраняет порядок серий. Возвращает число.
  Future<int> setSeasonWatchedAt(
      String seriesId, int season, DateTime? at) async {
    final s = seriesById(seriesId);
    if (s == null) return 0;
    final eps = s.episodes.where((e) => e.season == season).toList()
      ..sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0));
    final now = DateTime.now();
    var i = 0;
    for (final e in eps) {
      e
        ..watchedAt = at?.add(Duration(seconds: i))
        ..editedAt = now;
      i++;
    }
    if (eps.isNotEmpty) {
      notifyListeners();
      await _persist();
    }
    return eps.length;
  }

  /// Массово отмечает просмотренными переданные серии (последовательный режим:
  /// «отметил серию 10 → серии 1–10»). [eps] — список [сезон, номер]. Все
  /// получают одну дату [at] (по умолчанию сейчас) со сдвигом по секундам,
  /// чтобы остаться одной сессией по порядку; с [undated] дата не ставится.
  Future<void> markEpisodesBulk(String seriesId, List<List<int>> eps,
      {DateTime? at, bool undated = false}) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final base = at ?? DateTime.now();
    var added = 0;
    for (final e in eps) {
      if (!s.isEpisodeWatched(e[0], e[1])) {
        s.episodes.add(Episode(
            season: e[0],
            number: e[1],
            watchedAt: undated ? null : base.add(Duration(seconds: added))));
        added++;
      }
    }
    if (added > 0) {
      notifyListeners();
      await _persist();
    }
  }

  /// Удаляет из ленты выбранные записи-сессии. В ленте эпизоды — копии-СОБЫТИЯ
  /// (первый просмотр или конкретный повтор), поэтому удаляем именно тот
  /// просмотр, что стоит за событием ([Episode.eventViewId]). Серия без
  /// номера (старый импорт) находится по ссылке и снимается целиком.
  Future<void> removeEpisodes(String seriesId, List<Episode> eps) async {
    final s = seriesById(seriesId);
    if (s == null || eps.isEmpty) return;
    var changed = false;
    for (final ev in eps) {
      final stored = s.episodes.contains(ev)
          ? ev
          : (ev.season != null && ev.number != null
              ? s.watchedEpisode(ev.season, ev.number)
              : null);
      if (stored == null) continue;
      final viewId = ev.eventViewId;
      changed = (viewId == null
              ? s.episodes.remove(stored)
              : _removeView(s, stored, viewId)) ||
          changed;
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  /// Ставит оценку просмотру [viewId] серии; первый просмотр лежит в полях
  /// самой серии. false, если такого просмотра нет.
  bool _setViewScore(Episode ep, String viewId, double? score) {
    final now = DateTime.now();
    if (viewId == ep.vid) {
      ep
        ..score = score
        ..editedAt = now;
      return true;
    }
    final v = ep.rewatchViews.where((v) => v.id == viewId).firstOrNull;
    if (v == null) return false;
    v
      ..score = score
      ..editedAt = now;
    return true;
  }

  /// Убирает просмотр [viewId] серии. Если это был первый, а повторы есть, на
  /// его место встаёт следующий со своей датой, оценкой и дневником.
  /// Единственный просмотр снимает серию целиком.
  bool _removeView(LibrarySeries s, Episode ep, String viewId) {
    if (viewId != ep.vid) {
      final before = ep.rewatchViews.length;
      ep.rewatchViews.removeWhere((v) => v.id == viewId);
      return ep.rewatchViews.length != before;
    }
    if (ep.rewatchViews.isEmpty) return s.episodes.remove(ep);
    final next = ep.rewatchViews.removeAt(0);
    ep
      ..vid = next.id
      ..watchedAt = next.date
      ..score = next.score
      ..diary = next.diary
      ..editedAt = next.editedAt;
    return true;
  }

  /// Удаляет из сериала серии ВНЕ реальной структуры TMDB: сезон не из [sizes]
  /// или номер больше числа серий сезона. Так чистятся «хвосты» от неточного
  /// импорта/матча (напр. мультсериал, привязанный к 8-серийному ремейку —
  /// лишние S1·E9…E21, целые сезоны, которых у шоу нет). Безномерные серии
  /// (season/number == null) не трогаем — их разложит [reconcileSeriesEpisodes].
  /// Вызывать только когда [sizes] получены из TMDB. Возвращает число удалённых.
  Future<int> pruneToStructure(String seriesId, Map<int, int> sizes) async {
    final s = seriesById(seriesId);
    if (s == null || sizes.isEmpty) return 0;
    final before = s.episodes.length;
    s.episodes.removeWhere((e) {
      final se = e.season, num = e.number;
      if (se == null || num == null) return false;
      if (num < 1) return true; // спецвыпуск
      final cap = sizes[se];
      return cap == null || num > cap; // сезона нет / номер за пределами
    });
    final removed = before - s.episodes.length;
    if (removed > 0) {
      notifyListeners();
      await _persist();
    }
    return removed;
  }

  /// Разовый фоновый обход: у всех сериалов с tmdbId чистит серии вне реальной
  /// структуры TMDB (лишние «хвосты» от неточного импорта/матча — напр. серии
  /// сверх числа серий сезона или целые сезоны, которых у шоу нет). Идёт
  /// порциями, чтобы не грузить сеть; выполняется один раз (флаг в Store).
  Future<void> pruneStructureSweep() async {
    if (await Store.instance.getBool('prunedStructureV1', def: false)) return;
    final targets =
        _series.where((s) => s.tmdbId != null && s.episodes.isNotEmpty).toList();
    for (final s in targets) {
      try {
        final seasons = await TmdbService.seasons(s.tmdbId!);
        if (seasons.isNotEmpty) {
          final sizes = {for (final se in seasons) se.number: se.episodeCount};
          await pruneToStructure(s.tvShowId, sizes);
        }
      } catch (e) {
        debugPrint('pruneStructureSweep ${s.title}: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    await Store.instance.setBool('prunedStructureV1', true);
  }

  /// Снимает отметки со всех серий сезона.
  Future<void> unmarkSeason(String seriesId, int season) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    s.episodes.removeWhere((e) => e.season == season);
    notifyListeners();
    await _persist();
  }

  /// Оценка просмотра [viewId] серии. Первый просмотр и повторы находятся
  /// одинаково, по id (см. [Episode.vid]).
  Future<void> setEpisodeViewScoreById(String seriesId, int? season,
      int? number, String viewId, double? score) async {
    final ep = seriesById(seriesId)?.watchedEpisode(season, number);
    if (ep == null || !_setViewScore(ep, viewId, score)) return;
    notifyListeners();
    await _persist();
  }

  /// Дата просмотра [viewId] серии (null — «не помню когда»).
  Future<void> setEpisodeViewDateById(String seriesId, int? season,
      int? number, String viewId, DateTime? date) async {
    final ep = seriesById(seriesId)?.watchedEpisode(season, number);
    if (ep == null) return;
    final now = DateTime.now();
    if (viewId == ep.vid) {
      ep
        ..watchedAt = date
        ..editedAt = now;
    } else {
      final v = ep.rewatchViews.where((v) => v.id == viewId).firstOrNull;
      if (v == null) return;
      v
        ..date = date
        ..editedAt = now;
    }
    notifyListeners();
    await _persist();
  }

  /// Дневник просмотра [viewId] серии; пустая запись убирает дневник.
  Future<void> setEpisodeViewDiaryById(String seriesId, int? season,
      int? number, String viewId, DiaryEntry? diary) async {
    final ep = seriesById(seriesId)?.watchedEpisode(season, number);
    if (ep == null) return;
    final value = diary == null || diary.isEmpty ? null : diary;
    final now = DateTime.now();
    if (viewId == ep.vid) {
      ep
        ..diary = value
        ..editedAt = now;
    } else {
      final v = ep.rewatchViews.where((v) => v.id == viewId).firstOrNull;
      if (v == null) return;
      v
        ..diary = value
        ..editedAt = now;
    }
    notifyListeners();
    await _persist();
  }

  /// Добавляет ещё один просмотр серии (дата+оценка) — «смотрел ещё раз».
  /// У ещё не отмеченной серии это первый просмотр.
  Future<void> addEpisodeView(String seriesId, int season, int number,
      {DateTime? date, double? score, int? runtimeMin}) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final ep = s.watchedEpisode(season, number);
    if (ep == null) {
      s.episodes.add(Episode(
          season: season,
          number: number,
          watchedAt: date,
          score: score,
          runtimeMin: runtimeMin));
      s.finished = false;
    } else {
      ep.rewatchViews.add(Viewing(date: date, score: score));
    }
    notifyListeners();
    await _persist();
  }

  /// Удаляет просмотр [viewId] серии и возвращает его для «Вернуть»
  /// ([restoreEpisodeView]). Единственный просмотр снимает серию.
  Future<RemovedView?> removeEpisodeViewById(
      String seriesId, int? season, int? number, String viewId) async {
    final s = seriesById(seriesId);
    final ep = s?.watchedEpisode(season, number);
    if (s == null || ep == null) return null;
    final view = ep.views.where((v) => v.id == viewId).firstOrNull;
    if (view == null) return null;
    final removed = RemovedView(
      view: Viewing.fromAny(view.toJson()),
      index: ep.rewatchViews.indexWhere((v) => v.id == viewId),
      wasFirst: viewId == ep.vid,
      runtimeMin: ep.runtimeMin,
      epId: ep.epId,
    );
    if (!_removeView(s, ep, viewId)) return null;
    notifyListeners();
    await _persist();
    return removed;
  }

  /// Возвращает просмотр серии, убранный [removeEpisodeViewById]. Остальное в
  /// сериале не трогает: серии, отмеченные после удаления, остаются.
  Future<void> restoreEpisodeView(
      String seriesId, int? season, int? number, RemovedView removed) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    final v = Viewing.fromAny(removed.view.toJson());
    final ep = s.watchedEpisode(season, number);
    if (ep == null) {
      s.episodes.add(Episode(
        season: season,
        number: number,
        watchedAt: v.date,
        score: v.score,
        diary: v.diary,
        vid: v.id,
        editedAt: v.editedAt,
        runtimeMin: removed.runtimeMin,
        epId: removed.epId,
      ));
    } else if (ep.views.any((x) => x.id == v.id)) {
      return;
    } else if (removed.wasFirst) {
      // Первый просмотр встаёт на своё место, а тот, что его заменил, снова
      // становится повтором: так [_removeView] их и переставил.
      ep.rewatchViews.insert(0, ep.views.first);
      ep
        ..vid = v.id
        ..watchedAt = v.date
        ..score = v.score
        ..diary = v.diary
        ..editedAt = v.editedAt;
    } else {
      ep.rewatchViews.insert(removed.index.clamp(0, ep.rewatchViews.length), v);
    }
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
      .where(
        (s) =>
            !s.dropped &&
            !s.finished &&
            !s.isCompleted &&
            seriesRun(s) == SeriesRun.watching,
      )
      .toList();

  /// Сведения TMDB о выходе сериала. Если сериал был догнан, а теперь вышли
  /// новые серии, момент «Догнал» уходит в историю, чтобы плашка осталась в
  /// ленте.
  Future<void> setSeriesAir(String id, SeriesAir air) async {
    final s = seriesById(id);
    if (s == null) return;
    _applyAir(s, air);
    notifyListeners();
    await _persist();
  }

  void _applyAir(LibrarySeries s, SeriesAir air) {
    final wasCaughtUp = seriesRun(s) == SeriesRun.caughtUp;
    final at = completedAt(s);
    s.air = air;
    if (wasCaughtUp &&
        at != null &&
        seriesRun(s) != SeriesRun.caughtUp &&
        !s.caughtUpAt.contains(at)) {
      s.caughtUpAt.add(at);
    }
  }

  bool _airSweeping = false;

  /// Обход на старте: сведения о выходе для начатых сериалов. Закрытые
  /// сериалы больше не проверяются, идущие — раз в три дня, чтобы «Догнал»
  /// вовремя сменялся на «Смотрю», когда выходит новая серия.
  Future<void> refreshAirSweep({int budget = 120}) async {
    if (_airSweeping) return;
    _airSweeping = true;
    try {
      final now = DateTime.now();
      final todo = currentlyWatching.where((s) {
        if (s.tmdbId == null || s.dropped) return false;
        final air = s.air;
        if (air == null || air.checkedAt == null) return true;
        return !air.ended && now.difference(air.checkedAt!).inDays >= 3;
      }).take(budget).toList();
      var used = 0;
      for (final s in todo) {
        final air = await TmdbService.airOf(s.tmdbId!);
        used++;
        if (air != null) _applyAir(s, air);
        _persistSoon();
        if (used % 30 == 0) notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      _airSweeping = false;
      notifyListeners();
    }
  }

  /// Пометить сериал досмотренным / вернуть в «Сейчас смотрю».
  Future<void> setSeriesFinished(String id, bool finished) async {
    final s = seriesById(id);
    if (s == null || s.finished == finished) return;
    s.finished = finished;
    notifyListeners();
    await _persist();
  }

  /// Запоминает общее число серий сериала (из TMDB) — чтобы отличать
  /// завершённые от незавершённых в «Сейчас смотрю».
  Future<void> setSeriesTotal(String id, int total) async {
    final s = seriesById(id);
    if (s == null || total <= 0 || s.totalEpisodes == total) return;
    s.totalEpisodes = total;
    notifyListeners();
    await _persist();
  }

  /// Год выхода сериала (из TMDB) — для статистики. Ставим только если ещё нет.
  Future<void> setSeriesYear(String id, int? year) async {
    final s = seriesById(id);
    if (s == null || year == null || s.year != null) return;
    s.year = year;
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

  /// Сохраняет рецензию на просмотр [viewId] фильма: текст (Markdown) и разбор
  /// критика. Пустой текст убирает поле, разбор остаётся. Даты правки и первой
  /// публикации ставятся здесь, чтобы синхронизация выбирала свежую версию.
  ///
  /// На один просмотр одна рецензия: повторная запись обновляет её. Первая
  /// рецензия фильма ложится в старые поля, остальные — в `moreReviews`. Без
  /// [viewId] пишется рецензия в старых полях (у фильма без просмотров другой
  /// и не бывает). [extraId] называет рецензию из `moreReviews` напрямую: так
  /// находится та, которой не досталось просмотра.
  Future<void> saveMovieReview(String uuid,
      {String? viewId,
      String? extraId,
      String? text,
      required ReviewMeta meta}) async {
    final m = byUuid(uuid);
    if (m == null) return;
    final cleaned = _cleanReviewText(text);
    final stamped = _stampReview(meta)..viewId = viewId ?? meta.viewId;
    final existing = _movieReviewAt(m, viewId, extraId: extraId);
    if (existing is ExtraReview) {
      existing
        ..review = cleaned
        ..reviewMeta = stamped;
    } else if (existing != null || !m.hasReview) {
      m.review = cleaned;
      m.reviewMeta = stamped;
    } else {
      m.moreReviews.add(ExtraReview(
        id: 'mr-${DateTime.now().microsecondsSinceEpoch}',
        review: cleaned,
        reviewMeta: stamped,
      ));
    }
    notifyListeners();
    await _persist();
  }

  /// Переносит рецензию с просмотра [from] на просмотр [to]. false, если на
  /// [to] рецензия уже есть или переносить нечего. Старая рецензия без
  /// разбора получает его закрытым от друзей, как и была. Дата правки
  /// обновляется: по ней синхронизация поймёт, что перенос свежее.
  Future<bool> moveMovieReview(String uuid,
      {required String? from, String? extraId, required String to}) async {
    final m = byUuid(uuid);
    if (m == null || m.viewingById(to) == null) return false;
    final item = _movieReviewAt(m, from, extraId: extraId);
    if (item == null || reviewOfViewing(m, to) != null) return false;
    final meta = item is ExtraReview
        ? (item.reviewMeta ??= ReviewMeta(shared: false))
        : (m.reviewMeta ??= ReviewMeta(shared: false));
    meta
      ..viewId = to
      ..updatedAt = DateTime.now();
    notifyListeners();
    await _persist();
    return true;
  }

  /// То же для сериала.
  Future<void> saveSeriesReview(String seriesId,
      {String? text, required ReviewMeta meta}) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    s.review = _cleanReviewText(text);
    s.reviewMeta = _stampReview(meta);
    notifyListeners();
    await _persist();
  }

  /// Удаляет рецензию на просмотр [viewId]; без него — рецензию в старых
  /// полях фильма. [extraId] называет рецензию из `moreReviews` напрямую.
  Future<void> deleteMovieReview(String uuid,
      {String? viewId, String? extraId}) async {
    final m = byUuid(uuid);
    if (m == null || !_dropMovieReview(m, viewId, extraId: extraId)) return;
    notifyListeners();
    await _persist();
  }

  /// Рецензия на просмотр [viewId]; без него — та, что в старых полях.
  /// [extraId] важнее обоих: это рецензия из `moreReviews` с таким id.
  HasReview? _movieReviewAt(LibraryMovie m, String? viewId,
      {String? extraId}) {
    if (extraId != null) {
      return m.moreReviews.where((r) => r.id == extraId).firstOrNull;
    }
    return viewId == null
        ? (m.hasReview ? m : null)
        : reviewOfViewing(m, viewId);
  }

  bool _dropMovieReview(LibraryMovie m, String? viewId, {String? extraId}) {
    final item = _movieReviewAt(m, viewId, extraId: extraId);
    if (item == null) return false;
    if (item is ExtraReview) {
      m.moreReviews.remove(item);
    } else {
      m.review = null;
      m.reviewMeta = null;
    }
    return true;
  }

  Future<void> deleteSeriesReview(String seriesId) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    s.review = null;
    s.reviewMeta = null;
    notifyListeners();
    await _persist();
  }

  /// Рецензия на просмотр [pass] сезонов [from]..[to]. Без [id] создаёт новую.
  /// Возвращает id или null, если на этот просмотр сезоны уже заняты другой
  /// рецензией.
  Future<String?> saveSeasonReview(String seriesId,
      {String? id,
      required int from,
      required int to,
      int pass = 1,
      String? text,
      required ReviewMeta meta}) async {
    final s = seriesById(seriesId);
    if (s == null || !canCover(s, from, to, exceptId: id, pass: pass)) {
      return null;
    }
    var part = id == null
        ? null
        : s.seasonReviews.where((p) => p.id == id).firstOrNull;
    if (part == null) {
      part = SeasonReview(
        id: id ?? 'sr-${DateTime.now().microsecondsSinceEpoch}',
        from: from,
        to: to,
      );
      s.seasonReviews.add(part);
    }
    part
      ..from = from
      ..to = to
      ..pass = pass
      ..review = _cleanReviewText(text)
      ..reviewMeta = _stampReview(meta);
    _sortSeasonReviews(s);
    notifyListeners();
    await _persist();
    return part.id;
  }

  /// Рецензии на сезоны по порядку сезонов, внутри сезона по просмотрам.
  void _sortSeasonReviews(LibrarySeries s) => s.seasonReviews.sort((a, b) {
        final bySeason = a.from.compareTo(b.from);
        return bySeason != 0 ? bySeason : a.pass.compareTo(b.pass);
      });

  Future<void> deleteSeasonReview(String seriesId, String id) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    s.seasonReviews.removeWhere((p) => p.id == id);
    notifyListeners();
    await _persist();
  }

  /// Меняет охват рецензии. [partId] — какая рецензия на сезоны, null — на
  /// весь сериал. [from]/[to] — новый охват, null — весь сериал; [pass] —
  /// какой просмотр этих сезонов. Текст и разбор переезжают вместе. Отказ,
  /// если сезоны на этот просмотр заняты или рецензия на весь сериал уже
  /// есть.
  Future<({bool ok, String? partId})> moveReview(String seriesId,
      {String? partId, int? from, int? to, int pass = 1}) async {
    const fail = (ok: false, partId: null);
    final s = seriesById(seriesId);
    if (s == null) return fail;
    final part = partId == null
        ? null
        : s.seasonReviews.where((p) => p.id == partId).firstOrNull;
    if (partId != null && part == null) return fail;
    final toWhole = from == null || to == null;
    if (toWhole) {
      if (part == null) return (ok: true, partId: null);
      if (s.hasReview) return fail;
      s.review = part.review;
      s.reviewMeta = part.reviewMeta;
      s.seasonReviews.remove(part);
      notifyListeners();
      await _persist();
      return (ok: true, partId: null);
    }
    if (from > to || !canCover(s, from, to, exceptId: partId, pass: pass)) {
      return fail;
    }
    if (part != null) {
      part
        ..from = from
        ..to = to
        ..pass = pass;
    } else {
      final moved = SeasonReview(
        id: 'sr-${DateTime.now().microsecondsSinceEpoch}',
        from: from,
        to: to,
        pass: pass,
        review: s.review,
        reviewMeta: s.reviewMeta,
      );
      s.seasonReviews.add(moved);
      s.review = null;
      s.reviewMeta = null;
      partId = moved.id;
    }
    _sortSeasonReviews(s);
    notifyListeners();
    await _persist();
    return (ok: true, partId: partId);
  }

  /// Откуда брать оценку сериала: кнопка «Выставить сериалу» и «Вернуть».
  Future<void> setSeriesScoreSource(
      String seriesId, SeriesScoreSource source) async {
    final s = seriesById(seriesId);
    if (s == null) return;
    s.scoreSource = source;
    s.scoreSourceAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  static String? _cleanReviewText(String? text) {
    final t = text?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static ReviewMeta _stampReview(ReviewMeta meta) {
    final now = DateTime.now();
    meta.createdAt ??= now;
    meta.updatedAt = now;
    if (!meta.draft) meta.publishedAt ??= now;
    return meta;
  }

  /// Оценка фильма «как в карточке»: в текущий просмотр, а если просмотров
  /// нет — в общую.
  Future<void> setCurrentScore(String uuid, double? score) async {
    final m = byUuid(uuid);
    if (m == null) return;
    final cv = m.currentViewing;
    if (cv != null) {
      cv
        ..score = score
        ..editedAt = DateTime.now();
    } else {
      m.score = score;
    }
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
    m.status = LibraryStatus.watched;
    // Оценка, поставленная до первого просмотра, становится его оценкой.
    final first = m.viewings.isEmpty;
    m.viewings.add(Viewing(date: date, score: score ?? (first ? m.score : null)));
    if (first) m.score = null;
    notifyListeners();
    await _persist();
    return wasWatched;
  }

  /// Приём совместного просмотра ФИЛЬМА от друга: находит/создаёт фильм и
  /// добавляет просмотр с датой ([date] = null → «неизвестная дата»).
  Future<void> ingestCoWatchMovie({
    required String title,
    String? origTitle,
    int? year,
    int? tmdbId,
    String? posterUrl,
    DateTime? date,
  }) async {
    LibraryMovie m;
    if (tmdbId != null) {
      m = ensureFromTmdb(TmdbMovie(
          id: tmdbId,
          title: title,
          originalTitle: origTitle,
          year: year,
          posterUrl: posterUrl));
    } else {
      final key = (origTitle ?? title).toLowerCase().trim();
      LibraryMovie? found;
      for (final x in _movies) {
        final names = {
          x.title.toLowerCase().trim(),
          (x.ruTitle ?? '').toLowerCase().trim(),
        };
        if (names.contains(key) &&
            (year == null || x.year == null || x.year == year)) {
          found = x;
          break;
        }
      }
      if (found == null) {
        found = LibraryMovie(
          uuid: 'cw-${key.hashCode}-${year ?? 0}',
          title: origTitle ?? title,
          ruTitle: title,
          year: year,
          posterUrl: posterUrl,
        );
        _movies.add(found);
      }
      m = found;
    }
    await addViewing(m.uuid, date);
  }

  /// Приём совместного просмотра СЕРИАЛА от друга: находит/создаёт сериал и
  /// отмечает переданные серии ([episodes] = список [сезон, номер]).
  Future<void> ingestCoWatchSeries({
    required String title,
    String? origTitle,
    int? year,
    int? tmdbId,
    String? posterUrl,
    required List<List<int>> episodes,
    DateTime? date,
  }) async {
    LibrarySeries s;
    if (tmdbId != null) {
      s = ensureSeriesFromTmdb(TmdbSeries(
          id: tmdbId,
          title: title,
          originalTitle: origTitle,
          year: year,
          posterUrl: posterUrl));
    } else {
      final key = (origTitle ?? title).toLowerCase().trim();
      LibrarySeries? found;
      for (final x in _series) {
        final names = {
          x.title.toLowerCase().trim(),
          (x.ruTitle ?? '').toLowerCase().trim(),
        };
        if (names.contains(key)) {
          found = x;
          break;
        }
      }
      if (found == null) {
        found = LibrarySeries(
          tvShowId: 'cw-tv-${key.hashCode}',
          title: origTitle ?? title,
          ruTitle: title,
          year: year,
          posterUrl: posterUrl,
        );
        _series.add(found);
      }
      s = found;
    }
    var i = 0;
    for (final ep in episodes) {
      if (ep.length < 2) continue;
      if (!s.isEpisodeWatched(ep[0], ep[1])) {
        // Небольшой сдвиг по секундам держит серии одной сессией по порядку.
        s.episodes.add(Episode(
            season: ep[0],
            number: ep[1],
            watchedAt: date?.add(Duration(seconds: i))));
        i++;
      }
    }
    s.finished = false;
    notifyListeners();
    await _persist();
  }

  /// Просмотр фильма в библиотеке по id того, что передал экран. Сам объект
  /// экрана мог устареть: синхронизация и «Вернуть» пересоздают библиотеку.
  Viewing? _liveViewing(String uuid, Viewing v) =>
      byUuid(uuid)?.viewingById(v.id);

  /// Устанавливает оценку конкретного просмотра.
  Future<void> setViewingScore(String uuid, Viewing v, double? score) async {
    final live = _liveViewing(uuid, v);
    if (live == null) return;
    live
      ..score = score
      ..editedAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  /// Меняет дату/время конкретного просмотра ([date] = null → неизвестная дата).
  Future<void> setViewingDate(String uuid, Viewing v, DateTime? date) async {
    final live = _liveViewing(uuid, v);
    if (live == null) return;
    live
      ..date = date
      ..editedAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  /// Дневник просмотра (настроение, с кем, где, фото, заметка); пустая запись
  /// убирает дневник.
  Future<void> setViewingDiary(
      String uuid, Viewing v, DiaryEntry? diary) async {
    final live = _liveViewing(uuid, v);
    if (live == null) return;
    live
      ..diary = diary == null || diary.isEmpty ? null : diary
      ..editedAt = DateTime.now();
    notifyListeners();
    await _persist();
  }

  /// Отменяет последний просмотр фильма (широкая кнопка в карточке).
  /// Если это был единственный просмотр — фильм возвращается из «Просмотрено».
  /// Возвращает true, если после этого фильм больше не просмотрен.
  Future<bool> undoLastViewing(String uuid) async {
    final m = byUuid(uuid);
    if (m == null) return true;
    final v = m.currentViewing;
    if (v == null) {
      m.status = LibraryStatus.library;
      notifyListeners();
      await _persist();
      return true;
    }
    await removeViewing(uuid, v);
    return m.viewings.isEmpty;
  }

  /// Удаляет просмотр вместе с его рецензией и возвращает их для «Вернуть»
  /// ([restoreViewing]); null, если удалять было нечего. Без просмотров фильм
  /// уходит из «Просмотрено».
  Future<RemovedView?> removeViewing(String uuid, Viewing given) async {
    final m = byUuid(uuid);
    final v = m?.viewingById(given.id);
    if (m == null || v == null) return null;
    final review = reviewOfViewing(m, v.id);
    final removed = RemovedView(
      view: Viewing.fromAny(v.toJson()),
      index: m.viewings.indexOf(v),
      review: review == null
          ? null
          : ExtraReview(
              id: review is ExtraReview ? review.id : '',
              review: review.review,
              reviewMeta: review.reviewMeta?.copy(),
            ),
      status: m.status,
    );
    // Сначала рецензия: пока просмотр на месте, она находится по нему.
    _dropMovieReview(m, v.id);
    m.viewings.remove(v);
    if (m.viewings.isEmpty) m.status = LibraryStatus.library;
    notifyListeners();
    await _persist();
    return removed;
  }

  /// Возвращает просмотр, убранный [removeViewing], вместе с его рецензией.
  /// Остальное в фильме не трогает: сделанное после удаления остаётся.
  Future<void> restoreViewing(String uuid, RemovedView removed) async {
    final m = byUuid(uuid);
    if (m == null || m.viewingById(removed.view.id) != null) return;
    final at = removed.index.clamp(0, m.viewings.length);
    m.viewings.insert(at, Viewing.fromAny(removed.view.toJson()));
    if (m.status == LibraryStatus.library) {
      m.status = removed.status ?? LibraryStatus.watched;
    }
    final review = removed.review;
    if (review != null) {
      if (!m.hasReview) {
        m.review = review.review;
        m.reviewMeta = review.reviewMeta?.copy();
      } else {
        m.moreReviews.add(ExtraReview(
          id: review.id.isNotEmpty
              ? review.id
              : 'mr-${DateTime.now().microsecondsSinceEpoch}',
          review: review.review,
          reviewMeta: review.reviewMeta?.copy(),
        ));
      }
    }
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

  /// Ищет фильм библиотеки под TMDB-карточку БЕЗ создания/мутации: сперва по
  /// tmdbId, затем по названию+году (как [ensureFromTmdb], но только поиск).
  /// Нужно, чтобы части франшизы сразу показывали статус (просмотрено/в списке)
  /// даже у импортированных фильмов, которым tmdbId ещё не проставлен.
  LibraryMovie? findMovieForTmdb(TmdbMovie t) {
    final byId = movieByTmdb(t.id);
    if (byId != null) return byId;
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
      if (names.contains(tl) || (ol.isNotEmpty && names.contains(ol))) return m;
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
    if (_detached) return; // read-only копия чужой библиотеки — не пишем диск
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 3), _persist);
  }

  /// Обогащает один фильм (русское название + постер + рейтинг КП).
  /// Возвращает false, если пора остановиться (лимит API).
  Future<bool> enrich(LibraryMovie m, {bool persist = true}) async {
    if (m.posterUrl != null || m.enrichTried) return true;
    try {
      final source = SourceController.instance.source;
      final match = switch (source) {
        MovieSource.tmdb => await TmdbService.search(m.title, year: m.year),
        MovieSource.kinopoisk =>
          await KinopoiskService.search(m.title, year: m.year),
        MovieSource.tvdb => await TvdbService.search(m.title, year: m.year),
      };
      m.enrichTried = true;
      if (match != null) {
        m.kinopoiskId ??= match.kinopoiskId;
        m.tmdbId ??= match.tmdbId;
        m.tvdbId ??= match.tvdbId;
        m.imdbId ??= match.imdbId;
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

  /// Сохраняет подробности TMDB (жанры/страны/длительность) в фильм. Реальной
  /// длительностью из TMDB ЗАМЕНЯЕТ пустую или битую (мусор из импорта >600 мин).
  Future<void> applyDetails(String uuid,
      {List<String> genres = const [],
      List<String> countries = const [],
      int? runtimeMin}) async {
    final m = byUuid(uuid);
    if (m == null) return;
    var changed = false;
    if (genres.isNotEmpty && m.genres.isEmpty) {
      m.genres = genres;
      changed = true;
    }
    if (countries.isNotEmpty && m.countries.isEmpty) {
      m.countries = countries;
      changed = true;
    }
    final cur = m.runtimeMin;
    if (runtimeMin != null &&
        runtimeMin > 0 &&
        runtimeMin <= 600 &&
        (cur == null || cur <= 0 || cur > 600)) {
      m.runtimeMin = runtimeMin;
      changed = true;
    }
    if (!m.detailsTried) {
      m.detailsTried = true;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      _persistSoon();
    }
  }

  bool _genreSweeping = false;

  /// Фоновая дозагрузка жанров/стран/длительности из TMDB для просмотренных
  /// фильмов, у которых их ещё нет (TMDB без суточного лимита). Порциями.
  Future<void> backfillDetailsSweep({int budget = 120}) async {
    if (_genreSweeping) return;
    _genreSweeping = true;
    try {
      final todo = <LibraryMovie>[
        ...watched,
        ...watchlist,
      ].where((m) => m.tmdbId != null && !m.detailsTried && m.genres.isEmpty).toList();
      var used = 0;
      for (final m in todo) {
        if (used >= budget) break;
        final d = await TmdbService.details(m.tmdbId!);
        used++;
        m.detailsTried = true;
        if (d != null) {
          // IMDb id — универсальный ключ между источниками (миграция без потерь).
          if (m.imdbId == null && d.imdbId != null) m.imdbId = d.imdbId;
          if (m.genres.isEmpty) m.genres = d.genres.map((g) => g.name).toList();
          if (m.countries.isEmpty) m.countries = d.countries;
          final cur = m.runtimeMin;
          if (d.runtime != null &&
              d.runtime! > 0 &&
              d.runtime! <= 600 &&
              (cur == null || cur <= 0 || cur > 600)) {
            m.runtimeMin = d.runtime;
          }
        }
        _persistSoon();
        // UI обновляем ПАЧКАМИ, а не на каждый фильм — иначе счётчики статистики
        // тикают каждые 150 мс и «прыгают».
        if (used % 30 == 0) notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      _genreSweeping = false;
      notifyListeners();
    }
  }

  bool _titleSweeping = false;

  /// Фоновая ЛОКАЛИЗАЦИЯ названий (`ruTitle`) под текущий язык интерфейса — для
  /// фильмов И сериалов. Берёт записи, где локализованного имени нет ИЛИ оно в
  /// другом языке (`titleLang != текущий`), и тянет название из TMDB (по tmdbId —
  /// точно; иначе поиском по названию+году). У TMDB нет суточного лимита. Порциями;
  /// тихо выходит, если TMDB недоступен (нет ключа/лимит). Запускается на старте и
  /// при смене языка — прогресс сохраняется по записям (сеттер `ruTitle` проставляет
  /// `titleLang`), поэтому при прерывании продолжается, а не начинается заново.
  Future<void> relocalizeTitlesSweep({int budget = 500}) async {
    if (_titleSweeping) return;
    _titleSweeping = true;
    try {
      final lang = LocaleController.instance.code;
      bool needs(String? rt, String? tl) =>
          rt == null || rt.trim().isEmpty || (tl ?? 'ru') != lang;

      // Приоритет показа: просмотрено → буду смотреть → остальные фильмы; дедуп.
      final seen = <String>{};
      final movies = <LibraryMovie>[...watched, ...watchlist, ..._movies]
          .where((m) => seen.add(m.uuid) && needs(m.ruTitle, m.titleLang))
          .toList();
      final series =
          _series.where((s) => needs(s.ruTitle, s.titleLang)).toList();

      var used = 0;
      var dirty = 0;
      Future<void> bump() async {
        dirty++;
        _persistSoon();
        if (dirty % 20 == 0) notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      for (final m in movies) {
        if (used >= budget) break;
        try {
          String? name;
          if (m.tmdbId != null) {
            name = await TmdbService.localizedTitle(m.tmdbId!, isTv: false);
          } else {
            final match = await TmdbService.search(m.title, year: m.year);
            m.tmdbId ??= match?.tmdbId;
            name = match?.ruName;
          }
          used++;
          if (name != null && name.trim().isNotEmpty) {
            m.ruTitle = name.trim(); // сеттер проставит titleLang = текущий язык
            await bump();
          }
        } on SourceLimitException {
          break; // нет TMDB-ключа / лимит — прекращаем проход
        } catch (_) {/* сетевая ошибка — пропускаем */}
      }
      for (final s in series) {
        if (used >= budget) break;
        try {
          String? name;
          if (s.tmdbId != null) {
            name = await TmdbService.localizedTitle(s.tmdbId!, isTv: true);
          } else {
            final match = await TmdbService.searchTv(s.title, year: s.year);
            s.tmdbId ??= match?.tmdbId;
            name = match?.ruName;
          }
          used++;
          if (name != null && name.trim().isNotEmpty) {
            s.ruTitle = name.trim();
            await bump();
          }
        } on SourceLimitException {
          break;
        } catch (_) {}
      }
    } finally {
      _titleSweeping = false;
      notifyListeners();
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

  /// Обновляет постер сериала (из TMDB tv-деталей) — фикс «чужого постера».
  Future<void> setSeriesPoster(String id, String posterUrl) async {
    final s = seriesById(id);
    if (s == null || s.posterUrl == posterUrl) return;
    s.posterUrl = posterUrl;
    notifyListeners();
    await _persist();
  }

  // ------------------ локальные пользовательские постеры -------------------
  // Замена постера своим изображением. Хранится локально (имя файла в модели),
  // при показе приоритетнее сетевого; на сервер/друзьям не уходит. Меняется в
  // одном месте (модель) → отображается везде, где показывается постер.

  /// Ставит локальный постер фильму. Возвращает true при успехе.
  Future<bool> setMoviePosterLocal(String uuid, Uint8List bytes) async {
    final m = byUuid(uuid);
    if (m == null) return false;
    final name = await PosterStore.instance.save(uuid, bytes, old: m.posterFile);
    if (name == null) return false;
    m.posterFile = name;
    notifyListeners();
    await _persist();
    return true;
  }

  /// Сбрасывает локальный постер фильма — снова показывается сетевой.
  Future<void> clearMoviePosterLocal(String uuid) async {
    final m = byUuid(uuid);
    if (m == null || m.posterFile == null) return;
    await PosterStore.instance.delete(m.posterFile);
    m.posterFile = null;
    notifyListeners();
    await _persist();
  }

  /// Ставит локальный постер сериалу. Возвращает true при успехе.
  Future<bool> setSeriesPosterLocal(String id, Uint8List bytes) async {
    final s = seriesById(id);
    if (s == null) return false;
    final name = await PosterStore.instance.save(id, bytes, old: s.posterFile);
    if (name == null) return false;
    s.posterFile = name;
    notifyListeners();
    await _persist();
    return true;
  }

  /// Сбрасывает локальный постер сериала.
  Future<void> clearSeriesPosterLocal(String id) async {
    final s = seriesById(id);
    if (s == null || s.posterFile == null) return;
    await PosterStore.instance.delete(s.posterFile);
    s.posterFile = null;
    notifyListeners();
    await _persist();
  }

  /// Ставит фильму постер из сетевого URL (официальный постер TMDB): скачивает
  /// картинку и сохраняет её как локальный постер — устойчиво к обновлению
  /// сетевого `posterUrl` при следующем обогащении. Возвращает true при успехе.
  Future<bool> setMoviePosterFromUrl(String uuid, String url) async {
    final bytes = await _downloadImage(url);
    if (bytes == null) return false;
    return setMoviePosterLocal(uuid, bytes);
  }

  /// Ставит сериалу постер из сетевого URL (см. [setMoviePosterFromUrl]).
  Future<bool> setSeriesPosterFromUrl(String id, String url) async {
    final bytes = await _downloadImage(url);
    if (bytes == null) return false;
    return setSeriesPosterLocal(id, bytes);
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    } catch (_) {/* нет сети/битый URL — вернём null, экран покажет ошибку */}
    return null;
  }
}
