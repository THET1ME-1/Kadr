import '../../models/library_entry.dart';
import '../../models/review.dart';
import '../../services/movie_repository.dart';

/// Фильм или сериал, о котором рецензия. Редактор и экран чтения работают с
/// ним одинаково: название, постер, оценка, текст и разбор. Запись идёт
/// только в свою библиотеку; у рецензии друга [repo] — его read-only копия.
class ReviewTarget {
  final LibraryMovie? movie;
  final LibrarySeries? series;
  final MovieRepository repo;

  /// [mine] переопределяет, чья рецензия; по умолчанию своя — та, что лежит
  /// не в read-only копии чужой библиотеки.
  ReviewTarget.movie(LibraryMovie this.movie,
      {MovieRepository? repo, bool? mine})
      : series = null,
        repo = repo ?? MovieRepository.instance,
        _mine = mine;

  ReviewTarget.series(LibrarySeries this.series,
      {MovieRepository? repo, bool? mine})
      : movie = null,
        repo = repo ?? MovieRepository.instance,
        _mine = mine;

  final bool? _mine;

  bool get isSeries => series != null;
  bool get isMine => _mine ?? !repo.isDetached;

  HasReview get item => movie ?? series!;
  String? get text => item.review;
  ReviewMeta? get meta => item.reviewMeta;

  // Поля фильма могут быть null сами по себе, поэтому ветвимся по типу,
  // а не через `movie?.x ?? series!.x` — та падает на фильме без года.
  String get title => isSeries ? series!.displayTitle : movie!.displayTitle;
  int? get year => isSeries ? series!.year : movie!.year;
  String? get poster => isSeries ? series!.displayPoster : movie!.displayPoster;
  int? get tmdbId => isSeries ? series!.tmdbId : movie!.tmdbId;

  /// Ключ для поиска той же картины в другой библиотеке (моей или друга).
  String get matchKey => '${isSeries ? 's' : 'm'}:${tmdbId ?? '$title|$year'}';

  double? get score =>
      isSeries ? series!.displayScore : movie!.currentScore;

  /// Оценку сериала с оценёнными сериями считает среднее, руками её не задать.
  bool get scoreLocked => series?.episodeScoreAvg != null;

  /// Фильм оценивают после просмотра, как в карточке.
  bool get canRate {
    final m = movie;
    if (m == null) return true;
    return m.currentViewing != null || m.status == LibraryStatus.watched;
  }

  Future<void> setScore(double? v) => movie != null
      ? repo.setCurrentScore(movie!.uuid, v)
      : repo.setSeriesScore(series!.tvShowId, v);

  Future<void> save(String? text, ReviewMeta meta) => movie != null
      ? repo.saveMovieReview(movie!.uuid, text: text, meta: meta)
      : repo.saveSeriesReview(series!.tvShowId, text: text, meta: meta);

  Future<void> delete() => movie != null
      ? repo.deleteMovieReview(movie!.uuid)
      : repo.deleteSeriesReview(series!.tvShowId);

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
    return found == null ? null : ReviewTarget.series(found, repo: me);
  }

  /// Опубликованные рецензии библиотеки, свежие сверху. Для друга это всё,
  /// что пришло в его проекции: туда попадают только открытые друзьям.
  static List<ReviewTarget> publicReviews(MovieRepository repo) {
    final out = <ReviewTarget>[
      for (final m in repo.movies)
        if (m.reviewIsPublic) ReviewTarget.movie(m, repo: repo),
      for (final s in repo.series)
        if (s.reviewIsPublic) ReviewTarget.series(s, repo: repo),
    ];
    DateTime at(ReviewTarget t) => t.meta?.shownDate ?? DateTime(1970);
    out.sort((a, b) => at(b).compareTo(at(a)));
    return out;
  }
}
