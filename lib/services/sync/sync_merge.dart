import '../../models/library_entry.dart';
import '../../models/review.dart';

/// Формат снимка для синхронизации и ЧИСТЫЕ функции слияния двух снимков.
/// Отдельный файл без Flutter — легко покрыть юнит-тестами
/// (см. test/sync_merge_test.dart).
///
/// Модель слияния — ОБЪЕДИНЕНИЕ (union) по ключам: фильмы по `uuid`, сериалы по
/// `tvShowId`, списки по имени. Данные Kadr в основном АДДИТИВНЫ (просмотры,
/// серии, списки лишь добавляются), поэтому объединение НИЧЕГО не теряет из
/// добавленного на любом устройстве:
///   * просмотры фильма и серии — объединение по id просмотра, у общего
///     побеждает более поздняя правка;
///   * серии сериала — объединение по (сезон,номер);
///   * избранное — ИЛИ; списки — объединение; эмоции — объединение по id;
///   * статус — «сильнейший» (есть просмотры → просмотрено).
/// Цена простоты и безопасности: удаление отдельного просмотра/серии на одном
/// устройстве не распространяется (запись вернётся с другого устройства).
/// Настройки (тема/язык) в снимок НЕ входят — это device-local.

const String kSyncKind = 'kadr-sync';

/// Версия 2: оценка фильма лежит в просмотре, у просмотра есть id. Версии
/// приложения до 0.29 такой снимок портят (задваивают просмотры), поэтому он
/// пишется в отдельный файл, см. `WebdavService`.
const int kSyncVersion = 2;

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

/// Объединяет просмотры двух сторон. Запись узнаётся по id, а если id разные
/// (одна сторона писалась старой версией) — по точной дате: так правка
/// оценки или даты не плодит второй просмотр. Что остаётся от общей записи,
/// решает [_mergeViewing]. Порядок — по дате, без даты первыми.
List<Viewing> _mergeViewings(List<Viewing> a, List<Viewing> b) {
  final out = [for (final v in a) Viewing.fromAny(v.toJson())];
  for (final v in b) {
    var at = out.indexWhere((x) => x.id == v.id);
    if (at < 0 && v.date != null) at = out.indexWhere((x) => x.date == v.date);
    if (at < 0) {
      out.add(Viewing.fromAny(v.toJson()));
    } else {
      out[at] = _mergeViewing(out[at], v);
    }
  }
  return orderViewings(out);
}

/// Один и тот же просмотр с двух сторон. Id остаётся локальный.
///
/// Правка ставит просмотру момент [Viewing.editedAt]. Побеждает сторона с
/// более поздней правкой, причём целиком: если оценку убрали, пустое место
/// не заполняется старой оценкой с другого устройства. Запись без момента
/// уступает любой правленой. Так оба устройства приходят к одному и тому же.
///
/// Если запись не правили нигде, остаётся локальная, а пустые поля
/// заполняются с удалённой стороны.
Viewing _mergeViewing(Viewing a, Viewing b) {
  final at = a.editedAt, bt = b.editedAt;
  if (at == null && bt == null) {
    return a
      ..date ??= b.date
      ..score ??= b.score
      ..diary ??= b.diary;
  }
  final remoteWins = at == null || (bt != null && bt.isAfter(at));
  if (!remoteWins) return a;
  return Viewing.fromAny(b.toJson())..id = a.id;
}

// --------------------------- слияние фильма ---------------------------
LibraryMovie _mergeMovie(LibraryMovie a, LibraryMovie b) {
  final viewings = _mergeViewings(a.viewings, b.viewings);

  // В старых полях остаётся более свежая рецензия. Если проигравшая была про
  // другой просмотр (на двух устройствах написали по рецензии), она не
  // пропадает, а уходит в дополнительные. Рецензия, которую на одном
  // устройстве перенесли на другой просмотр, второй рецензией не считается.
  final main = _pickReview(a, b);
  final other = identical(main, a) ? b : a;
  final more = _mergeExtraReviews(a.moreReviews, b.moreReviews);
  final mainView = main.reviewMeta?.viewId, otherView = other.reviewMeta?.viewId;
  if (other.hasReview &&
      main.hasReview &&
      !_sameReview(main, other) &&
      otherView != null &&
      mainView != null &&
      otherView != mainView &&
      !more.any((r) => r.reviewMeta?.viewId == otherView)) {
    more.add(ExtraReview(
      id: 'mr-$otherView',
      review: other.review,
      reviewMeta: other.reviewMeta?.copy(),
    ));
  }

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
    titleLang: a.ruTitle != null ? a.titleLang : b.titleLang,
    kpRating: a.kpRating ?? b.kpRating,
    enrichTried: a.enrichTried || b.enrichTried,
    tmdbId: a.tmdbId ?? b.tmdbId,
    year: a.year ?? b.year,
    runtimeMin: a.runtimeMin ?? b.runtimeMin,
    status: status,
    addedAt: earliest(a.addedAt, b.addedAt),
    viewings: viewings,
    score: a.score ?? b.score,
    emotions: emo.values.toList(),
    favorite: a.favorite || b.favorite,
    lists: lists,
    review: main.review,
    reviewMeta: main.reviewMeta?.copy(),
    moreReviews: more,
    kinopoiskId: a.kinopoiskId ?? b.kinopoiskId,
    tvdbId: a.tvdbId ?? b.tvdbId,
    imdbId: a.imdbId ?? b.imdbId,
    posterUrl: a.posterUrl ?? b.posterUrl,
    posterFile: a.posterFile ?? b.posterFile,
    genres: genres,
    countries: countries,
    detailsTried: a.detailsTried || b.detailsTried,
  );
}

/// Рецензии на другие просмотры обеих сторон по id; у общей побеждает свежая
/// правка.
List<ExtraReview> _mergeExtraReviews(List<ExtraReview> a, List<ExtraReview> b) {
  final byId = <String, ExtraReview>{for (final r in a) r.id: r};
  for (final r in b) {
    final mine = byId[r.id];
    byId[r.id] = mine == null ? r : _pickReview(mine, r) as ExtraReview;
  }
  return [for (final r in byId.values) ExtraReview.fromJson(r.toJson())];
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
    } else if (prev.vid != e.vid) {
      // Первые просмотры у сторон разные: на одной первый удалили, и его
      // место занял повтор со своим id. Складываем все просмотры обеих
      // сторон по id и заново выбираем первый, иначе повтор оказался бы в
      // серии дважды под одним id.
      final all = _mergeViewings(prev.views, e.views);
      final first = all.first;
      emap[k] = Episode(
        season: prev.season ?? e.season,
        number: prev.number ?? e.number,
        watchedAt: first.date,
        runtimeMin: prev.runtimeMin ?? e.runtimeMin,
        score: first.score,
        epId: prev.epId ?? e.epId,
        vid: first.id,
        rewatchViews: all.skip(1).toList(),
        diary: first.diary,
        editedAt: first.editedAt,
      );
    } else {
      // Общая серия. Первый просмотр сливается как любой другой: побеждает
      // более поздняя правка. Пока его не правили нигде, действует прежнее
      // правило: ранняя дата, непустая оценка и дневник.
      final Viewing first;
      if (prev.editedAt == null && e.editedAt == null) {
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
        first = Viewing(
          id: prev.vid,
          date: at,
          score: prev.score ?? e.score,
          diary: prev.diary ?? e.diary,
        );
      } else {
        first = _mergeViewing(prev.views.first, e.views.first);
      }
      // Повторы объединяются по id (без него — по точной дате), поэтому один и
      // тот же просмотр не задваивается, а сделанный на другом устройстве
      // добавляется. Раньше бралась только более длинная сторона, и повтор
      // с короткой пропадал вместе с дневником.
      emap[k] = Episode(
        season: prev.season ?? e.season,
        number: prev.number ?? e.number,
        watchedAt: first.date,
        runtimeMin: prev.runtimeMin ?? e.runtimeMin,
        score: first.score,
        epId: prev.epId ?? e.epId,
        vid: prev.vid,
        rewatchViews: _mergeViewings(prev.rewatchViews, e.rewatchViews),
        diary: first.diary,
        editedAt: first.editedAt,
      );
    }
  }
  final episodes = emap.values.toList()
    ..sort((x, y) {
      final s = (x.season ?? 0).compareTo(y.season ?? 0);
      return s != 0 ? s : (x.number ?? 0).compareTo(y.number ?? 0);
    });

  // Дата добавления — ранняя из двух: тогда сериал и попал в библиотеку.
  DateTime? added;
  if (a.addedAt == null) {
    added = b.addedAt;
  } else if (b.addedAt == null) {
    added = a.addedAt;
  } else {
    added = a.addedAt!.isBefore(b.addedAt!) ? a.addedAt : b.addedAt;
  }

  return LibrarySeries(
    tvShowId: a.tvShowId,
    title: a.title.isNotEmpty ? a.title : b.title,
    ruTitle: a.ruTitle ?? b.ruTitle,
    titleLang: a.ruTitle != null ? a.titleLang : b.titleLang,
    episodes: episodes,
    addedAt: added,
    favorite: a.favorite || b.favorite,
    // Отметки пользователя объединяем. Раньше «Буду смотреть» и «Досмотрен»
    // не переносились вовсе — сериал выпадал из списка после синхронизации.
    watchlist: a.watchlist || b.watchlist,
    dropped: a.dropped || b.dropped,
    finished: a.finished || b.finished,
    totalEpisodes: a.totalEpisodes ?? b.totalEpisodes,
    year: a.year ?? b.year,
    air: _newerAir(a.air, b.air),
    seasonReviews: _mergeSeasonReviews(a.seasonReviews, b.seasonReviews),
    scoreSource: _newerSource(a, b).scoreSource,
    scoreSourceAt: _newerSource(a, b).scoreSourceAt,
    caughtUpAt: {...a.caughtUpAt, ...b.caughtUpAt}.toList()..sort(),
    score: a.score ?? b.score,
    review: _pickReview(a, b).review,
    reviewMeta: _pickReview(a, b).reviewMeta?.copy(),
    kinopoiskId: a.kinopoiskId ?? b.kinopoiskId,
    tmdbId: a.tmdbId ?? b.tmdbId,
    tvdbId: a.tvdbId ?? b.tvdbId,
    imdbId: a.imdbId ?? b.imdbId,
    kpRating: a.kpRating ?? b.kpRating,
    enrichTried: a.enrichTried || b.enrichTried,
    posterUrl: a.posterUrl ?? b.posterUrl,
    posterFile: a.posterFile ?? b.posterFile,
  );
}

/// Рецензии на сезоны обеих сторон по id. У общей побеждает свежая правка,
/// охват едет вместе с ней.
List<SeasonReview> _mergeSeasonReviews(
    List<SeasonReview> a, List<SeasonReview> b) {
  final byId = <String, SeasonReview>{for (final p in a) p.id: p};
  for (final p in b) {
    final mine = byId[p.id];
    byId[p.id] = mine == null ? p : _pickReview(mine, p) as SeasonReview;
  }
  return [
    for (final p in byId.values)
      SeasonReview.fromJson(p.toJson()),
  ]..sort((x, y) => x.from.compareTo(y.from));
}

/// Сериал, у которого источник оценки выбран позже.
LibrarySeries _newerSource(LibrarySeries a, LibrarySeries b) {
  final at = a.scoreSourceAt, bt = b.scoreSourceAt;
  if (at == null) return bt == null ? a : b;
  if (bt == null) return a;
  return bt.isAfter(at) ? b : a;
}

/// Сведения о выходе с более поздней проверкой TMDB.
SeriesAir? _newerAir(SeriesAir? a, SeriesAir? b) {
  if (a == null || b == null) return a ?? b;
  final at = a.checkedAt, bt = b.checkedAt;
  if (at == null) return b;
  if (bt == null) return a;
  return bt.isAfter(at) ? b : a;
}

/// Одна ли это рецензия на двух устройствах. Её узнают по моменту создания:
/// его ставит первая запись, и дальше он не меняется. У рецензий старых
/// версий момента нет, а была такая у фильма одна. Совпавший текст тоже
/// значит ту же рецензию.
bool _sameReview(HasReview a, HasReview b) =>
    a.reviewMeta?.createdAt == b.reviewMeta?.createdAt ||
    (a.hasReviewText && a.review == b.review);

/// Чья рецензия остаётся после слияния. Текст и разбор едут парой, иначе
/// заголовок одной версии встанет над текстом другой. Побеждает более свежая
/// правка; рецензия со старой версии приложения (без разбора и без даты)
/// уступает любой датированной. Если разбора нет ни у кого — прежнее правило:
/// непустой текст побеждает.
HasReview _pickReview(HasReview a, HasReview b) {
  final am = a.reviewMeta, bm = b.reviewMeta;
  if (am == null && bm == null) return a.hasReviewText ? a : b;
  if (!b.hasReview) return a;
  if (!a.hasReview) return b;
  final at = am?.updatedAt, bt = bm?.updatedAt;
  if (at == null && bt == null) return a;
  if (at == null) return b;
  if (bt == null) return a;
  return bt.isAfter(at) ? b : a;
}
