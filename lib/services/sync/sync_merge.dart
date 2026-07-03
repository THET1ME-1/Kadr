import '../../models/library_entry.dart';

/// Формат снимка для синхронизации и ЧИСТЫЕ функции слияния двух снимков.
/// Отдельный файл без Flutter — легко покрыть юнит-тестами
/// (см. test/sync_merge_test.dart).
///
/// Модель слияния — ОБЪЕДИНЕНИЕ (union) по ключам: фильмы по `uuid`, сериалы по
/// `tvShowId`, списки по имени. Данные Kadr в основном АДДИТИВНЫ (просмотры,
/// серии, списки лишь добавляются), поэтому объединение НИЧЕГО не теряет из
/// добавленного на любом устройстве:
///   * просмотры фильма — объединение (дедуп по дате+оценке);
///   * серии сериала — объединение по (сезон,номер), у общей берём раннюю дату,
///     непустую оценку, больший счётчик повторов;
///   * избранное — ИЛИ; списки — объединение; эмоции — объединение по id;
///   * статус — «сильнейший» (есть просмотры → просмотрено).
/// Цена простоты и безопасности: удаление отдельного просмотра/серии на одном
/// устройстве не распространяется (запись вернётся с другого устройства).
/// Настройки (тема/язык) в снимок НЕ входят — это device-local.

const String kSyncKind = 'kadr-sync';
const int kSyncVersion = 1;

/// Что изменилось в результате слияния (для сообщения пользователю).
class SyncStats {
  int addedMovies = 0;
  int mergedMovies = 0;
  int addedSeries = 0;
  int mergedSeries = 0;
  int addedLists = 0;

  bool get changed =>
      addedMovies + addedSeries + addedLists + mergedMovies + mergedSeries > 0;

  @override
  String toString() => 'SyncStats(movies +$addedMovies ~$mergedMovies, '
      'series +$addedSeries ~$mergedSeries, lists +$addedLists)';
}

List<Map<String, dynamic>> _mapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : const [];

/// Сливает локальный и удалённый снимки → новый снимок-результат (им заменяем
/// локальное состояние). Статистику пишет в [stats].
Map<String, dynamic> mergeSnapshots(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
  SyncStats stats,
) {
  // ------------------------------ Фильмы ------------------------------
  final lm = {
    for (final j in _mapList(local['movies'])) '${j['uuid']}': j
  };
  final rm = {
    for (final j in _mapList(remote['movies'])) '${j['uuid']}': j
  };
  final movies = <Map<String, dynamic>>[];
  for (final k in {...lm.keys, ...rm.keys}) {
    final a = lm[k], b = rm[k];
    if (a != null && b != null) {
      movies.add(_mergeMovie(
              LibraryMovie.fromJson(a), LibraryMovie.fromJson(b))
          .toJson());
      stats.mergedMovies++;
    } else if (a != null) {
      movies.add(a);
    } else {
      movies.add(b!);
      stats.addedMovies++;
    }
  }

  // ------------------------------ Сериалы ------------------------------
  final ls = {
    for (final j in _mapList(local['series'])) '${j['tvShowId']}': j
  };
  final rs = {
    for (final j in _mapList(remote['series'])) '${j['tvShowId']}': j
  };
  final series = <Map<String, dynamic>>[];
  for (final k in {...ls.keys, ...rs.keys}) {
    final a = ls[k], b = rs[k];
    if (a != null && b != null) {
      series.add(_mergeSeries(
              LibrarySeries.fromJson(a), LibrarySeries.fromJson(b))
          .toJson());
      stats.mergedSeries++;
    } else if (a != null) {
      series.add(a);
    } else {
      series.add(b!);
      stats.addedSeries++;
    }
  }

  // ------------------------------ Списки ------------------------------
  final ll = {
    for (final j in _mapList(local['lists'])) '${j['name']}': j
  };
  final rl = {
    for (final j in _mapList(remote['lists'])) '${j['name']}': j
  };
  final lists = <Map<String, dynamic>>[];
  for (final k in {...ll.keys, ...rl.keys}) {
    final a = ll[k], b = rl[k];
    if (a != null && b != null) {
      final uuids = <String>{
        ...(a['movieUuids'] as List? ?? []).map((e) => '$e'),
        ...(b['movieUuids'] as List? ?? []).map((e) => '$e'),
      }.toList();
      lists.add({...a, 'movieUuids': uuids});
    } else if (a != null) {
      lists.add(a);
    } else {
      lists.add(b!);
      stats.addedLists++;
    }
  }

  return {
    'kind': kSyncKind,
    'version': kSyncVersion,
    'movies': movies,
    'series': series,
    'lists': lists,
  };
}

// --------------------------- слияние фильма ---------------------------
LibraryMovie _mergeMovie(LibraryMovie a, LibraryMovie b) {
  // Просмотры — объединение с дедупом по (дата, оценка).
  String vk(Viewing v) => '${v.date?.toIso8601String() ?? ''}|${v.score ?? ''}';
  final vmap = <String, Viewing>{};
  for (final v in [...a.viewings, ...b.viewings]) {
    vmap.putIfAbsent(vk(v), () => v);
  }
  final viewings = vmap.values.toList()
    ..sort((x, y) => (x.date ?? DateTime(0)).compareTo(y.date ?? DateTime(0)));

  // Эмоции — объединение по id.
  final emo = <String, MovieEmotion>{};
  for (final e in [...a.emotions, ...b.emotions]) {
    emo.putIfAbsent(e.id, () => e);
  }

  final lists = <String>{...a.lists, ...b.lists}.toList();
  final genres = a.genres.isNotEmpty ? a.genres : b.genres;
  final countries = a.countries.isNotEmpty ? a.countries : b.countries;

  // Статус — сильнейший: просмотрено > буду смотреть > брошено > библиотека.
  LibraryStatus status;
  if (viewings.isNotEmpty ||
      a.status == LibraryStatus.watched ||
      b.status == LibraryStatus.watched) {
    status = LibraryStatus.watched;
  } else if (a.status == LibraryStatus.watchlist ||
      b.status == LibraryStatus.watchlist) {
    status = LibraryStatus.watchlist;
  } else if (a.status == LibraryStatus.dropped ||
      b.status == LibraryStatus.dropped) {
    status = LibraryStatus.dropped;
  } else {
    status = LibraryStatus.library;
  }

  DateTime? earliest(DateTime? x, DateTime? y) {
    if (x == null) return y;
    if (y == null) return x;
    return x.isBefore(y) ? x : y;
  }

  return LibraryMovie(
    uuid: a.uuid,
    title: a.title.isNotEmpty ? a.title : b.title,
    ruTitle: a.ruTitle ?? b.ruTitle,
    kpRating: a.kpRating ?? b.kpRating,
    enrichTried: a.enrichTried || b.enrichTried,
    tmdbId: a.tmdbId ?? b.tmdbId,
    year: a.year ?? b.year,
    runtimeMin: a.runtimeMin ?? b.runtimeMin,
    status: status,
    addedAt: earliest(a.addedAt, b.addedAt),
    viewings: viewings,
    rewatchCount:
        a.rewatchCount > b.rewatchCount ? a.rewatchCount : b.rewatchCount,
    score: a.score ?? b.score,
    emotions: emo.values.toList(),
    favorite: a.favorite || b.favorite,
    lists: lists,
    review: (a.review != null && a.review!.trim().isNotEmpty)
        ? a.review
        : b.review,
    kinopoiskId: a.kinopoiskId ?? b.kinopoiskId,
    posterUrl: a.posterUrl ?? b.posterUrl,
    genres: genres,
    countries: countries,
    detailsTried: a.detailsTried || b.detailsTried,
  );
}

// --------------------------- слияние сериала ---------------------------
LibrarySeries _mergeSeries(LibrarySeries a, LibrarySeries b) {
  String ek(Episode e) => '${e.season}-${e.number}';
  final emap = <String, Episode>{};
  for (final e in a.episodes) {
    emap[ek(e)] = e;
  }
  for (final e in b.episodes) {
    final k = ek(e);
    final prev = emap[k];
    if (prev == null) {
      emap[k] = e;
    } else {
      // Общая серия: ранняя дата, непустая оценка, больший счётчик повторов.
      DateTime? at;
      if (prev.watchedAt == null) {
        at = e.watchedAt;
      } else if (e.watchedAt == null) {
        at = prev.watchedAt;
      } else {
        at = prev.watchedAt!.isBefore(e.watchedAt!)
            ? prev.watchedAt
            : e.watchedAt;
      }
      emap[k] = Episode(
        season: prev.season ?? e.season,
        number: prev.number ?? e.number,
        watchedAt: at,
        runtimeMin: prev.runtimeMin ?? e.runtimeMin,
        score: prev.score ?? e.score,
        epId: prev.epId ?? e.epId,
        rewatchCount: prev.rewatchCount > e.rewatchCount
            ? prev.rewatchCount
            : e.rewatchCount,
      );
    }
  }
  final episodes = emap.values.toList()
    ..sort((x, y) {
      final s = (x.season ?? 0).compareTo(y.season ?? 0);
      return s != 0 ? s : (x.number ?? 0).compareTo(y.number ?? 0);
    });

  return LibrarySeries(
    tvShowId: a.tvShowId,
    title: a.title.isNotEmpty ? a.title : b.title,
    ruTitle: a.ruTitle ?? b.ruTitle,
    episodes: episodes,
    favorite: a.favorite || b.favorite,
    dropped: a.dropped || b.dropped,
    totalEpisodes: a.totalEpisodes ?? b.totalEpisodes,
    score: a.score ?? b.score,
    review: (a.review != null && a.review!.trim().isNotEmpty)
        ? a.review
        : b.review,
    kinopoiskId: a.kinopoiskId ?? b.kinopoiskId,
    tmdbId: a.tmdbId ?? b.tmdbId,
    kpRating: a.kpRating ?? b.kpRating,
    enrichTried: a.enrichTried || b.enrichTried,
    posterUrl: a.posterUrl ?? b.posterUrl,
  );
}
