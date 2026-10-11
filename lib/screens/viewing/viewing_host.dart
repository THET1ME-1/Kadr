import '../../models/library_entry.dart';
import '../../services/app_prefs.dart';
import '../../services/movie_repository.dart';
import '../review/review_target.dart';

/// Возвращает удалённый просмотр на место (плашка «Вернуть»).
typedef ViewingUndo = Future<void> Function();

/// Просмотры фильма или серии для общих окон: блок «Просмотры» и окно
/// просмотра работают с ними одинаково и не знают, чьи они.
///
/// Просмотр всегда ищется по id: первый просмотр серии отдаётся копией, а
/// «Вернуть» подменяет объекты в библиотеке, поэтому ссылка на [Viewing]
/// между вызовами не живёт.
abstract class ViewingHost {
  MovieRepository get repo;

  /// Серия, а не фильм: у неё нет рецензии на просмотр.
  bool get isEpisode;

  /// Просмотры по порядку: без даты первыми, дальше по дате. Пусто, если
  /// фильм или серия больше не отмечены.
  List<Viewing> get ordered;

  /// Имя файла для фото дневника этого просмотра.
  String photoKey(Viewing v);

  Future<void> setScore(Viewing v, double? score);
  Future<void> setDate(Viewing v, DateTime? date);
  Future<void> setDiary(Viewing v, DiaryEntry? diary);

  /// Ещё один просмотр без даты с оценкой [score]: «видел раньше».
  Future<void> addUndated(double? score);

  /// Удаляет просмотр. null — удалять было нечего.
  Future<ViewingUndo?> remove(Viewing v);

  /// Сколько ещё серий уйдёт вместе с просмотром [v]. Больше нуля только у
  /// серии при настройке «Снимать серии по порядку», когда этот просмотр у
  /// неё единственный и после неё есть отмеченные.
  int cascadeOf(Viewing v) => 0;

  /// Рецензия на просмотр [v]; у серии её нет.
  ReviewTarget? reviewTarget(Viewing v);

  Viewing? byId(String? id) {
    if (id == null) return null;
    for (final v in ordered) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// Номер просмотра с единицы; 0, если такого уже нет.
  int ordinalOf(Viewing v) => ordered.indexWhere((x) => x.id == v.id) + 1;

  /// Оценка ближайшего оценённого просмотра перед [v] и его номер.
  ({double score, int ordinal})? previousRated(Viewing v) {
    final list = ordered;
    final at = list.indexWhere((x) => x.id == v.id);
    for (var i = at - 1; i >= 0; i--) {
      final s = list[i].score;
      if (s != null) return (score: s, ordinal: i + 1);
    }
    return null;
  }

  /// Написана ли на просмотр рецензия (черновик тоже считается).
  bool hasReview(Viewing v) => reviewTarget(v)?.item.hasReview ?? false;
}

/// Просмотры фильма.
class MovieViewingHost extends ViewingHost {
  final String uuid;
  @override
  final MovieRepository repo;

  MovieViewingHost(this.uuid, {MovieRepository? repo})
      : repo = repo ?? MovieRepository.instance;

  LibraryMovie? get movie => repo.byUuid(uuid);

  @override
  bool get isEpisode => false;

  @override
  List<Viewing> get ordered => movie?.orderedViewings ?? const [];

  @override
  String photoKey(Viewing v) => '$uuid-${v.id}';

  @override
  Future<void> setScore(Viewing v, double? score) async {
    final live = byId(v.id);
    if (live != null) await repo.setViewingScore(uuid, live, score);
  }

  @override
  Future<void> setDate(Viewing v, DateTime? date) async {
    final live = byId(v.id);
    if (live != null) await repo.setViewingDate(uuid, live, date);
  }

  @override
  Future<void> setDiary(Viewing v, DiaryEntry? diary) async {
    final live = byId(v.id);
    if (live != null) await repo.setViewingDiary(uuid, live, diary);
  }

  @override
  Future<void> addUndated(double? score) =>
      repo.addViewing(uuid, null, score: score);

  @override
  Future<ViewingUndo?> remove(Viewing v) async {
    final live = byId(v.id);
    if (live == null) return null;
    final removed = await repo.removeViewing(uuid, live);
    if (removed == null) return null;
    return () => repo.restoreViewing(uuid, removed);
  }

  @override
  ReviewTarget? reviewTarget(Viewing v) {
    final m = movie;
    return m == null ? null : ReviewTarget.movie(m, repo: repo, viewId: v.id);
  }
}

/// Просмотры одной серии.
class EpisodeViewingHost extends ViewingHost {
  final String seriesId;
  final int season;
  final int number;

  /// Длительность серии из TMDB: нужна, когда просмотр добавляют заново.
  final int? runtimeMin;
  @override
  final MovieRepository repo;

  EpisodeViewingHost(
    this.seriesId,
    this.season,
    this.number, {
    this.runtimeMin,
    MovieRepository? repo,
  }) : repo = repo ?? MovieRepository.instance;

  Episode? get episode =>
      repo.seriesById(seriesId)?.watchedEpisode(season, number);

  @override
  bool get isEpisode => true;

  @override
  List<Viewing> get ordered => episode?.orderedViews ?? const [];

  @override
  String photoKey(Viewing v) => 'ep-$seriesId-$season-$number-${v.id}';

  @override
  Future<void> setScore(Viewing v, double? score) =>
      repo.setEpisodeViewScoreById(seriesId, season, number, v.id, score);

  @override
  Future<void> setDate(Viewing v, DateTime? date) =>
      repo.setEpisodeViewDateById(seriesId, season, number, v.id, date);

  @override
  Future<void> setDiary(Viewing v, DiaryEntry? diary) =>
      repo.setEpisodeViewDiaryById(seriesId, season, number, v.id, diary);

  @override
  Future<void> addUndated(double? score) => repo.addEpisodeView(
        seriesId,
        season,
        number,
        score: score,
        runtimeMin: runtimeMin,
      );

  @override
  int cascadeOf(Viewing v) {
    if (!AppPrefs.instance.sequentialUnmark) return 0;
    final views = ordered;
    if (views.length != 1 || views.single.id != v.id) return 0;
    return repo.watchedAfter(seriesId, season, number);
  }

  @override
  Future<ViewingUndo?> remove(Viewing v) async {
    // Снятие по порядку трогает много серий разом: возвращаем сериал
    // снимком, как после снятия сезона.
    if (cascadeOf(v) > 0) {
      final snap = await repo.unmarkFrom(seriesId, season, number);
      if (snap == null) return null;
      return () => repo.restoreFromSnapshot(const [], [snap]);
    }
    final removed =
        await repo.removeEpisodeViewById(seriesId, season, number, v.id);
    if (removed == null) return null;
    return () => repo.restoreEpisodeView(seriesId, season, number, removed);
  }

  @override
  ReviewTarget? reviewTarget(Viewing v) => null;
}
