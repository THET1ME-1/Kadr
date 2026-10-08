import '../l10n/strings.dart';
import '../models/library_entry.dart';

/// Свод рецензий на сезоны (см. [LibrarySeries.seasonReviewsAverage]).
double? reviewsAverage(LibrarySeries s) => s.seasonReviewsAverage;

/// Средняя по оценкам серий одного сезона, до 0.1. null, если оценок нет.
double? seasonEpisodeAverage(LibrarySeries s, int season) {
  final scores = [
    for (final e in s.episodes)
      if (e.season == season && e.score != null) e.score!,
  ];
  if (scores.isEmpty) return null;
  return (scores.reduce((a, b) => a + b) / scores.length * 10).round() / 10;
}

/// Рецензия на сезоны, которая идёт в свод: не черновик и с оценками.
bool _counts(SeasonReview p) =>
    p.reviewMeta?.average != null && !(p.reviewMeta?.draft ?? false);

/// Строка сравнения: сезон, средняя по сериям и средняя рецензии на него.
class SeasonCompare {
  final int season;
  final double? episodes;
  final double? review;
  const SeasonCompare(this.season, this.episodes, this.review);
}

/// Сезоны, у которых есть оценки серий или рецензия из свода, по порядку.
List<SeasonCompare> compareSeasons(LibrarySeries s) {
  final seasons = <int>{
    for (final e in s.episodes)
      if ((e.season ?? 0) >= 1 && e.score != null) e.season!,
    for (final p in s.seasonReviews)
      if (_counts(p)) for (var n = p.from; n <= p.to; n++) n,
  }.toList()..sort();
  return [
    for (final n in seasons)
      SeasonCompare(
        n,
        seasonEpisodeAverage(s, n),
        s.seasonReviews
            .where((p) => _counts(p) && p.covers(n))
            .firstOrNull
            ?.reviewMeta
            ?.average,
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

/// Рецензия на сезоны, в которую уже входит [season], кроме [exceptId].
SeasonReview? takenBy(LibrarySeries s, int season, {String? exceptId}) =>
    s.seasonReviews
        .where((p) => p.id != exceptId && p.covers(season))
        .firstOrNull;

/// Можно ли взять сезоны [from]..[to]: ни один не занят другой рецензией.
bool canCover(LibrarySeries s, int from, int to, {String? exceptId}) {
  for (var n = from; n <= to; n++) {
    if (takenBy(s, n, exceptId: exceptId) != null) return false;
  }
  return true;
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
