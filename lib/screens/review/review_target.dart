import '../../models/library_entry.dart';
import '../../models/review.dart';
import '../../services/movie_repository.dart';
import '../../utils/season_reviews.dart';

/// Фильм или сериал, о котором рецензия. Редактор и экран чтения работают с
/// ним одинаково: название, постер, оценка, текст и разбор. Запись идёт
/// только в свою библиотеку; у рецензии друга [repo] — его read-only копия.
///
/// У сериала рецензия берёт весь сериал ([from] и [to] пустые, текст в
/// полях сериала) или сезоны [from]..[to] ([SeasonReview], id в [partId]).
/// Охват меняется на ходу через [setScope], поэтому поля изменяемые.
class ReviewTarget {
  final LibraryMovie? movie;
  final LibrarySeries? series;
  final MovieRepository repo;

  /// Рецензия на сезоны, уже записанная в библиотеку. null у фильма, у
  /// рецензии на весь сериал и у новой рецензии на сезоны до первой записи.
  String? partId;
  int? from;
  int? to;

  /// [mine] переопределяет, чья рецензия; по умолчанию своя — та, что лежит
  /// не в read-only копии чужой библиотеки.
  ReviewTarget.movie(LibraryMovie this.movie,
      {MovieRepository? repo, bool? mine})
      : series = null,
        repo = repo ?? MovieRepository.instance,
        _mine = mine;

  ReviewTarget.series(LibrarySeries this.series,
      {MovieRepository? repo, bool? mine, SeasonReview? part, int? from, int? to})
      : movie = null,
        repo = repo ?? MovieRepository.instance,
        partId = part?.id,
        from = part?.from ?? from,
        to = part?.to ?? to,
        _mine = mine;

  final bool? _mine;

  bool get isSeries => series != null;
  bool get isMine => _mine ?? !repo.isDetached;

  /// Рецензия на сезоны, а не на весь сериал.
  bool get isPart => from != null && to != null;

  /// Записанная рецензия на сезоны (свежая ссылка из библиотеки).
  SeasonReview? get part => partId == null
      ? null
      : series?.seasonReviews.where((p) => p.id == partId).firstOrNull;

  /// Пустая заготовка, пока новую рецензию на сезоны ещё не записали.
  late final SeasonReview _blankPart =
      SeasonReview(id: '', from: from ?? 1, to: to ?? 1);

  HasReview get item =>
      movie ?? (isPart ? (part ?? _blankPart) : series!);

  /// «S2–S3» / «Весь сериал»; у фильма пусто.
  String? get scopeShortLabel => isSeries ? scopeShort(from, to) : null;

  /// «Сезоны 2–3» / «Весь сериал»; у фильма пусто.
  String? get scopeLongLabel => isSeries ? scopeLong(from, to) : null;
  String? get text => item.review;
  ReviewMeta? get meta => item.reviewMeta;

  // Поля фильма могут быть null сами по себе, поэтому ветвимся по типу,
  // а не через `movie?.x ?? series!.x` — та падает на фильме без года.
  String get title => isSeries ? series!.displayTitle : movie!.displayTitle;
  int? get year => isSeries ? series!.year : movie!.year;
  String? get poster => isSeries ? series!.displayPoster : movie!.displayPoster;
  int? get tmdbId => isSeries ? series!.tmdbId : movie!.tmdbId;

  /// Ключ для поиска той же картины в другой библиотеке (моей или друга).
  /// У рецензии на сезоны к нему добавлен охват.
  String get matchKey => '${isSeries ? 's' : 'm'}:${tmdbId ?? '$title|$year'}'
      '${isPart ? ':$from-$to' : ''}';

  /// Оценка рецензии. У сериала это средняя по пунктам; у старой рецензии на
  /// весь сериал без пунктов — оценка сериала.
  double? get score {
    if (!isSeries) return movie!.currentScore;
    final avg = meta?.average;
    if (isPart) return avg;
    return avg ?? series!.displayScore;
  }

  /// У сериала общая оценка рецензии — средняя по пунктам, руками не задаётся.
  bool get scoreLocked => isSeries;

  /// Фильм оценивают после просмотра, как в карточке.
  bool get canRate {
    final m = movie;
    if (m == null) return true;
    return m.currentViewing != null || m.status == LibraryStatus.watched;
  }

  Future<void> setScore(double? v) => movie != null
      ? repo.setCurrentScore(movie!.uuid, v)
      : repo.setSeriesScore(series!.tvShowId, v);

  Future<void> save(String? text, ReviewMeta meta) async {
    if (movie != null) {
      return repo.saveMovieReview(movie!.uuid, text: text, meta: meta);
    }
    if (!isPart) {
      return repo.saveSeriesReview(series!.tvShowId, text: text, meta: meta);
    }
    final id = await repo.saveSeasonReview(series!.tvShowId,
        id: partId, from: from!, to: to!, text: text, meta: meta);
    if (id != null) partId = id;
  }

  Future<void> delete() async {
    if (movie != null) return repo.deleteMovieReview(movie!.uuid);
    if (!isPart) return repo.deleteSeriesReview(series!.tvShowId);
    if (partId != null) {
      await repo.deleteSeasonReview(series!.tvShowId, partId!);
    }
  }

  /// Записанная ли уже рецензия: у новой охват меняется без переезда.
  bool get _stored => isPart ? partId != null : series!.hasReview;

  /// Новый охват: [newFrom]/[newTo] — сезоны, оба null — весь сериал.
  /// Записанная рецензия переезжает вместе с текстом. false, если сезоны
  /// заняты или рецензия на весь сериал уже есть.
  Future<bool> setScope(int? newFrom, int? newTo) async {
    final s = series!;
    final whole = newFrom == null || newTo == null;
    if (!_stored) {
      if (whole ? s.hasReview : !canCover(s, newFrom, newTo)) return false;
      from = whole ? null : newFrom;
      to = whole ? null : newTo;
      return true;
    }
    final res = await repo.moveReview(s.tvShowId,
        partId: partId, from: newFrom, to: newTo);
    if (!res.ok) return false;
    partId = res.partId;
    from = whole ? null : newFrom;
    to = whole ? null : newTo;
    return true;
  }

  /// Та же картина в моей библиотеке — для сравнения оценок с другом и
  /// ответной рецензии. null, если у меня её нет.
  ReviewTarget? mineCounterpart({MovieRepository? mine}) {
    final me = mine ?? MovieRepository.instance;
    if (movie != null) {
      final m = movie!;
      LibraryMovie? found =
          m.tmdbId != null ? me.movieByTmdb(m.tmdbId!) : null;
      found ??= me.movies.where((x) =>
          x.title.toLowerCase() == m.title.toLowerCase() &&
          x.year == m.year).firstOrNull;
      return found == null ? null : ReviewTarget.movie(found, repo: me);
    }
    final s = series!;
    LibrarySeries? found =
        s.tmdbId != null ? me.seriesByTmdb(s.tmdbId!) : null;
    found ??= me.series
        .where((x) => x.title.toLowerCase() == s.title.toLowerCase())
        .firstOrNull;
    if (found == null) return null;
    if (!isPart) return ReviewTarget.series(found, repo: me);
    // Своя рецензия на те же сезоны, иначе новая с тем же охватом.
    final same = found.seasonReviews
        .where((p) => p.from == from && p.to == to)
        .firstOrNull;
    return ReviewTarget.series(found,
        repo: me, part: same, from: from, to: to);
  }

  /// Опубликованные рецензии библиотеки, свежие сверху. Для друга это всё,
  /// что пришло в его проекции: туда попадают только открытые друзьям.
  static List<ReviewTarget> publicReviews(MovieRepository repo) {
    final out = <ReviewTarget>[
      for (final m in repo.movies)
        if (m.reviewIsPublic) ReviewTarget.movie(m, repo: repo),
      for (final s in repo.series) ...[
        if (s.reviewIsPublic) ReviewTarget.series(s, repo: repo),
        for (final p in s.seasonReviews)
          if (p.reviewIsPublic) ReviewTarget.series(s, repo: repo, part: p),
      ],
    ];
    DateTime at(ReviewTarget t) => t.meta?.shownDate ?? DateTime(1970);
    out.sort((a, b) => at(b).compareTo(at(a)));
    return out;
  }
}
