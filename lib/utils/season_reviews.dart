import '../l10n/strings.dart';
import '../models/library_entry.dart';
import 'season_pass.dart';

/// Свод рецензий на сезоны (см. [LibrarySeries.seasonReviewsAverage]).
double? reviewsAverage(LibrarySeries s) => s.seasonReviewsAverage;

/// Средняя по оценкам серий одного сезона, до 0.1. null, если оценок нет.
/// У пересмотренной серии берётся её последняя оценка.
double? seasonEpisodeAverage(LibrarySeries s, int season) {
  final scores = [
    for (final e in s.episodes)
      if (e.season == season && e.currentScore != null) e.currentScore!,
  ];
  if (scores.isEmpty) return null;
  return (scores.reduce((a, b) => a + b) / scores.length * 10).round() / 10;
}

/// Строка сравнения: сезон, средняя по сериям и средняя рецензии на него.
class SeasonCompare {
  final int season;
  final double? episodes;
  final double? review;
  const SeasonCompare(this.season, this.episodes, this.review);
}

/// Сезоны, у которых есть оценки серий или рецензия из свода, по порядку.
/// Рецензия берётся та, что идёт в свод: на последний просмотр сезона.
List<SeasonCompare> compareSeasons(LibrarySeries s) {
  final seasons = <int>{
    for (final e in s.episodes)
      if ((e.season ?? 0) >= 1 && e.currentScore != null) e.season!,
    for (final p in s.seasonReviews)
      if (p.countsInSummary) for (var n = p.from; n <= p.to; n++) n,
  }.toList()..sort();
  return [
    for (final n in seasons)
      SeasonCompare(
        n,
        seasonEpisodeAverage(s, n),
        s.summaryReviewOf(n)?.reviewMeta?.average,
      ),
  ];
}

/// Вывод под двумя средними: строже рецензии или мягче и где разошлись
/// сильнее всего. null, если сравнивать не с чем.
String? reviewsDeltaLine(LibrarySeries s) {
  final rv = reviewsAverage(s), ep = s.episodeScoreAvg;
  if (rv == null || ep == null) return null;
  final d = ((rv - ep) * 10).round() / 10;
  final head = d == 0
      ? tr('rvs_same')
      : trf(d < 0 ? 'rvs_stricter' : 'rvs_softer',
          {'d': d.abs().toStringAsFixed(1)});
  SeasonCompare? worst;
  var gap = 0.0;
  for (final r in compareSeasons(s)) {
    if (r.episodes == null || r.review == null) continue;
    final g = (r.review! - r.episodes!).abs();
    if (g > gap) {
      gap = g;
      worst = r;
    }
  }
  if (worst == null || gap < 0.3) return head;
  return '$head ${trf('rvs_most', {'season': trf('season_ord', {'n': worst.season})})}';
}

/// Рецензия на просмотр [pass], в которую уже входит [season], кроме
/// [exceptId]. На один просмотр сезона одна рецензия.
SeasonReview? takenBy(LibrarySeries s, int season,
        {String? exceptId, int pass = 1}) =>
    s.seasonReviews
        .where((p) => p.id != exceptId && p.pass == pass && p.covers(season))
        .firstOrNull;

/// Можно ли взять сезоны [from]..[to] на просмотр [pass]: ни один не занят
/// другой рецензией на тот же просмотр.
bool canCover(LibrarySeries s, int from, int to,
    {String? exceptId, int pass = 1}) {
  for (var n = from; n <= to; n++) {
    if (takenBy(s, n, exceptId: exceptId, pass: pass) != null) return false;
  }
  return true;
}

/// Клетка таблицы «сезоны × просмотры».
class PassCell {
  /// Средняя рецензии на этот просмотр сезона.
  final double? value;

  /// Сезон на этом просмотре смотрели, а рецензии нет.
  final bool missing;

  /// Эта рецензия идёт в свод: она на последний просмотр сезона.
  final bool inSummary;
  const PassCell({this.value, this.missing = false, this.inSummary = false});

  /// Такого просмотра у сезона не было.
  bool get none => value == null && !missing;
}

/// Строка таблицы: сезон и его рецензии по просмотрам.
class PassRow {
  final int season;
  final List<PassCell> cells;
  const PassRow(this.season, this.cells);

  /// Разница между последней и первой рецензией сезона; null, если она одна.
  double? get delta {
    final values = [
      for (final c in cells)
        if (c.value != null) c.value!,
    ];
    if (values.length < 2) return null;
    return ((values.last - values.first) * 10).round() / 10;
  }
}

/// Рецензии по сезонам и просмотрам для вкладки «Пересмотры».
class PassTable {
  /// Число столбцов: самый поздний просмотр с рецензией.
  final int passes;
  final List<PassRow> rows;

  /// Средняя первых рецензий сезонов и средняя последних (она же свод).
  final double first;
  final double last;
  const PassTable({
    required this.passes,
    required this.rows,
    required this.first,
    required this.last,
  });

  /// Насколько последние рецензии выше первых.
  double get delta => ((last - first) * 10).round() / 10;

  /// Сезон, у которого рецензии разошлись сильнее всего (от 0.1).
  int? get strongest {
    int? best;
    var gap = 0.05;
    for (final r in rows) {
      final d = r.delta?.abs() ?? 0;
      if (d > gap) {
        gap = d;
        best = r.season;
      }
    }
    return best;
  }
}

/// Таблица для вкладки «Пересмотры»; null, пока ни у одного сезона нет
/// рецензий на два разных просмотра.
PassTable? passTable(LibrarySeries s) {
  final counted = [
    for (final p in s.seasonReviews)
      if (p.countsInSummary) p,
  ];
  final seasons = <int>{
    for (final p in counted) for (var n = p.from; n <= p.to; n++) n,
  }.toList()..sort();
  var passes = 0;
  for (final p in counted) {
    if (p.pass > passes) passes = p.pass;
  }
  final rows = <PassRow>[];
  var firstSum = 0.0;
  for (final n in seasons) {
    final viewed = seasonViewsMax(s, n);
    final summary = s.summaryReviewOf(n);
    double? first;
    final cells = <PassCell>[];
    for (var pass = 1; pass <= passes; pass++) {
      final p = counted
          .where((p) => p.pass == pass && p.covers(n))
          .firstOrNull;
      final v = p?.reviewMeta?.average;
      first ??= v;
      cells.add(PassCell(
        value: v,
        missing: v == null && pass <= viewed,
        inSummary: p != null && identical(p, summary),
      ));
    }
    firstSum += first ?? 0;
    rows.add(PassRow(n, cells));
  }
  if (!rows.any((r) => r.delta != null)) return null;
  return PassTable(
    passes: passes,
    rows: rows,
    first: (firstSum / rows.length * 10).round() / 10,
    last: s.seasonReviewsAverage!,
  );
}

/// «S1», «S2–S3», «Весь сериал». null охват — весь сериал.
String scopeShort(int? from, int? to) {
  if (from == null || to == null) return tr('scope_whole');
  return from == to ? 'S$from' : 'S$from–S$to';
}

/// «Сезон 1», «Сезоны 2–3», «Весь сериал».
String scopeLong(int? from, int? to) {
  if (from == null || to == null) return tr('scope_whole');
  return from == to
      ? trf('scope_season', {'n': from})
      : trf('scope_seasons', {'a': from, 'b': to});
}
