import '../../models/library_entry.dart';
import '../../models/review.dart';
import '../../services/movie_repository.dart';
import '../../utils/movie_reviews.dart';
import '../../utils/season_reviews.dart';

/// Фильм или сериал, о котором рецензия. Редактор и экран чтения работают с
/// ним одинаково: название, постер, оценка, текст и разбор. Запись идёт
/// только в свою библиотеку; у рецензии друга [repo] — его read-only копия.
///
/// У фильма рецензия привязана к просмотру ([viewId]): на один просмотр
/// одна рецензия. У сериала рецензия берёт весь сериал ([from] и [to]
/// пустые, текст в полях сериала) или сезоны [from]..[to] на их просмотр
/// [pass] ([SeasonReview], id в [partId]). Охват и просмотр меняются на ходу
/// через [setScope] и [setViewing], поэтому поля изменяемые.
class ReviewTarget {
  final LibraryMovie? movie;
  final LibrarySeries? series;
  final MovieRepository repo;

  /// Просмотр фильма, о котором рецензия. null у сериала, у фильма без
  /// просмотров и у старой рецензии, которой не досталось просмотра.
  String? viewId;

  /// Id рецензии из `moreReviews`, если цель — именно она. Нужен рецензии
  /// без просмотра: иначе её не отличить от первой, что лежит в полях фильма.
  final String? extraId;

  /// Рецензия на сезоны, уже записанная в библиотеку. null у фильма, у
  /// рецензии на весь сериал и у новой рецензии на сезоны до первой записи.
  String? partId;
  int? from;
  int? to;

  /// Какой по счёту просмотр сезонов описывает рецензия.
  int pass;

  /// [mine] переопределяет, чья рецензия; по умолчанию своя — та, что лежит
  /// не в read-only копии чужой библиотеки. [unbound] — рецензия в старых
  /// полях фильма как есть, без подбора просмотра.
  ReviewTarget.movie(LibraryMovie this.movie,
      {MovieRepository? repo,
      bool? mine,
      String? viewId,
      bool unbound = false,
      this.extraId})
      : series = null,
        repo = repo ?? MovieRepository.instance,
        viewId = unbound ? null : (viewId ?? _defaultViewId(movie)),
        pass = 1,
        _mine = mine;

  /// Цель для строки списка рецензий фильма.
  ReviewTarget.ofRef(LibraryMovie movie, MovieReviewRef ref,
      {MovieRepository? repo, bool? mine})
      : this.movie(movie,
            repo: repo,
            mine: mine,
            viewId: ref.viewing?.id,
            unbound: ref.viewing == null,
            extraId: ref.viewing == null ? ref.extraId : null);

  ReviewTarget.series(LibrarySeries this.series,
      {MovieRepository? repo,
      bool? mine,
      SeasonReview? part,
      int? from,
      int? to,
      int pass = 1})
      : movie = null,
        extraId = null,
        repo = repo ?? MovieRepository.instance,
        partId = part?.id,
        from = part?.from ?? from,
        to = part?.to ?? to,
        pass = part?.pass ?? pass,
        _mine = mine;

  final bool? _mine;

  /// Просмотр по умолчанию: тот, на который написана последняя рецензия,
  /// а без рецензий — последний просмотр фильма.
  static String? _defaultViewId(LibraryMovie m) {
    final bound = [
      for (final r in movieReviews(m))
        if (r.viewing != null) r.viewing!.id,
    ];
    return bound.isNotEmpty ? bound.last : m.currentViewing?.id;
  }

  bool get isSeries => series != null;
  bool get isMine => _mine ?? !repo.isDetached;

  /// Рецензия на сезоны, а не на весь сериал.
  bool get isPart => from != null && to != null;

  /// Записанная рецензия на сезоны (свежая ссылка из библиотеки).
  SeasonReview? get part => partId == null
      ? null
      : series?.seasonReviews.where((p) => p.id == partId).firstOrNull;

  /// Пустые заготовки, пока новую рецензию ещё не записали.
  late final SeasonReview _blankPart =
      SeasonReview(id: '', from: from ?? 1, to: to ?? 1, pass: pass);
  late final ExtraReview _blankMovie = ExtraReview(id: '');

  HasReview get item {
    final m = movie;
    if (m != null) {
      final HasReview? found;
      if (extraId != null && viewId == null) {
        found = m.moreReviews.where((r) => r.id == extraId).firstOrNull;
      } else {
        found = viewId == null
            ? (m.hasReview ? m : null)
            : reviewOfViewing(m, viewId);
      }
      return found ?? _blankMovie;
    }
    return isPart ? (part ?? _blankPart) : series!;
  }

  /// Как хранилище находит рецензию фильма: по [extraId], пока она без
  /// просмотра, иначе по просмотру.
  String? get _looseId => viewId == null ? extraId : null;

  /// Просмотр фильма, о котором рецензия.
  Viewing? get viewing => movie?.viewingById(viewId);

  /// Номер просмотра: у фильма по порядку просмотров, у рецензии на сезоны
  /// её [pass]. 0, когда просмотра нет.
  int get ordinal {
    final m = movie;
    if (m == null) return isPart ? pass : 0;
    final v = viewing;
    return v == null ? 0 : m.ordinalOf(v);
  }

  /// Рецензия на тот же фильм или те же сезоны, написанная на прошлый
  /// просмотр: с ней сравнивают «тогда и сейчас». Черновики не в счёт.
  ReviewTarget? get previous {
    final m = movie;
    if (m != null) {
      final at = ordinal;
      if (at == 0) return null;
      MovieReviewRef? best;
      for (final r in movieReviews(m)) {
        if (r.ordinal == 0 || r.ordinal >= at) continue;
        if (r.meta?.draft ?? false) continue;
        if (best == null || r.ordinal > best.ordinal) best = r;
      }
      return best == null
          ? null
          : ReviewTarget.movie(m,
              repo: repo, mine: _mine, viewId: best.viewing!.id);
    }
    if (!isPart) return null;
    SeasonReview? best;
    for (final p in series!.seasonReviews) {
      if (p.pass >= pass || !p.hasReview) continue;
      if (p.reviewMeta?.draft ?? false) continue;
      if (!p.covers(from!)) continue;
      if (best == null || p.pass > best.pass) best = p;
    }
    return best == null
        ? null
        : ReviewTarget.series(series!, repo: repo, mine: _mine, part: best);
  }

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

  /// Оценка рецензии. У фильма это оценка просмотра, о котором она
  /// написана. У сериала — средняя по пунктам; у старой рецензии на весь
  /// сериал без пунктов — оценка сериала.
  double? get score {
    final m = movie;
    if (m != null) return viewId == null ? m.currentScore : viewing?.score;
    final avg = meta?.average;
    if (isPart) return avg;
    return avg ?? series!.displayScore;
  }

  /// Оценка для показа: у фильма без оценки просмотра — средняя по пунктам.
  double? get displayScore => score ?? meta?.average;

  /// У сериала общая оценка рецензии — средняя по пунктам, руками не задаётся.
  bool get scoreLocked => isSeries;

  /// Фильм оценивают после просмотра, как в карточке.
  bool get canRate {
    final m = movie;
    if (m == null) return true;
    return viewing != null || m.status == LibraryStatus.watched;
  }

  Future<void> setScore(double? v) {
    final m = movie;
    if (m == null) return repo.setSeriesScore(series!.tvShowId, v);
    final view = viewing;
    return view != null
        ? repo.setViewingScore(m.uuid, view, v)
        : repo.setCurrentScore(m.uuid, v);
  }

  Future<void> save(String? text, ReviewMeta meta) async {
    if (movie != null) {
      return repo.saveMovieReview(movie!.uuid,
          viewId: viewId, extraId: _looseId, text: text, meta: meta);
    }
    if (!isPart) {
      return repo.saveSeriesReview(series!.tvShowId, text: text, meta: meta);
    }
    final id = await repo.saveSeasonReview(series!.tvShowId,
        id: partId, from: from!, to: to!, pass: pass, text: text, meta: meta);
    if (id != null) partId = id;
  }

  Future<void> delete() async {
    if (movie != null) {
      return repo.deleteMovieReview(movie!.uuid,
          viewId: viewId, extraId: _looseId);
    }
    if (!isPart) return repo.deleteSeriesReview(series!.tvShowId);
    if (partId != null) {
      await repo.deleteSeasonReview(series!.tvShowId, partId!);
    }
  }

  /// Записанная ли уже рецензия: у новой охват меняется без переезда.
  bool get _stored => movie != null
      ? item.hasReview
      : (isPart ? partId != null : series!.hasReview);

  /// Новый охват: [newFrom]/[newTo] — сезоны, оба null — весь сериал;
  /// [newPass] — какой их просмотр. Записанная рецензия переезжает вместе с
  /// текстом. false, если сезоны на этот просмотр заняты или рецензия на
  /// весь сериал уже есть.
  Future<bool> setScope(int? newFrom, int? newTo, {int newPass = 1}) async {
    final s = series!;
    final whole = newFrom == null || newTo == null;
    if (!_stored) {
      if (whole
          ? s.hasReview
          : !canCover(s, newFrom, newTo, pass: newPass)) {
        return false;
      }
      from = whole ? null : newFrom;
      to = whole ? null : newTo;
      pass = whole ? 1 : newPass;
      return true;
    }
    final res = await repo.moveReview(s.tvShowId,
        partId: partId, from: newFrom, to: newTo, pass: newPass);
    if (!res.ok) return false;
    partId = res.partId;
    from = whole ? null : newFrom;
    to = whole ? null : newTo;
    pass = whole ? 1 : newPass;
    return true;
  }

  /// Переносит рецензию фильма на просмотр [newViewId]. false, если на него
  /// рецензия уже есть.
  Future<bool> setViewing(String newViewId) async {
    final m = movie!;
    if (newViewId == viewId) return true;
    if (m.viewingById(newViewId) == null) return false;
    if (!_stored) {
      if (reviewOfViewing(m, newViewId) != null) return false;
      viewId = newViewId;
      return true;
    }
    final ok = await repo.moveMovieReview(m.uuid,
        from: viewId, extraId: _looseId, to: newViewId);
    if (ok) viewId = newViewId;
    return ok;
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
    // Своя рецензия на те же сезоны (лучше на тот же просмотр, иначе
    // последняя), а без неё новая с тем же охватом.
    final same = found.seasonReviews
        .where((p) => p.from == from && p.to == to)
        .toList();
    final exact = same.where((p) => p.pass == pass).firstOrNull;
    return ReviewTarget.series(found,
        repo: me,
        part: exact ?? (same.isEmpty ? null : same.last),
        from: from,
        to: to);
  }

  /// Опубликованные рецензии библиотеки, свежие сверху. Для друга это всё,
  /// что пришло в его проекции: туда попадают только открытые друзьям.
  static List<ReviewTarget> publicReviews(MovieRepository repo) {
    final out = <ReviewTarget>[
      for (final m in repo.movies)
        for (final r in movieReviews(m))
          if (r.item.reviewIsPublic) ReviewTarget.ofRef(m, r, repo: repo),
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
