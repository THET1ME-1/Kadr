import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/poster.dart';
import '../widgets/reveal.dart';
import 'movie_sheet.dart';

/// Экран статистики (Material 3 Expressive): крупные плитки, графики по годам,
/// распределение оценок, топ по оценке, эмоции, сериалы.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final s = _Stats.compute(repo);
        return Scaffold(
          appBar: AppBar(title: Text(tr('drawer_stats'))),
          body: s.totalViewings == 0
              ? Center(
                  child: Text(tr('stat_empty'),
                      style: const TextStyle(fontFamily: AppTheme.bodyFont)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _tiles(context, s),
                    const SizedBox(height: 20),
                    _byYear(context, s),
                    const SizedBox(height: 20),
                    _scoreDist(context, s),
                    if (s.emotions.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _emotions(context, s),
                    ],
                    if (s.topRated.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _section(context, tr('stat_top')),
                      const SizedBox(height: 8),
                      ...s.topRated.map((m) => _topRow(context, m)),
                    ],
                  ],
                ),
        );
      },
    );
  }

  // ------------------------------- плитки -------------------------------
  Widget _tiles(BuildContext context, _Stats s) {
    return Column(
      children: [
        Row(children: [
          _tile(context, Icons.check_circle_rounded, '${s.watchedMovies}',
              tr('stat_watched'), 0),
          const SizedBox(width: 12),
          _tile(context, Icons.schedule_rounded, '${s.hours}',
              tr('stat_hours'), 1),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _tile(context, Icons.star_rounded,
              s.avgScore == 0 ? '—' : s.avgScore.toStringAsFixed(1),
              tr('stat_avg'), 2),
          const SizedBox(width: 12),
          _tile(context, Icons.repeat_rounded, '${s.totalViewings}',
              tr('stat_viewings'), 3),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _tile(context, Icons.live_tv_rounded, '${s.seriesCount}',
              tr('stat_series'), 4),
          const SizedBox(width: 12),
          _tile(context, Icons.favorite_rounded, '${s.favorites}',
              tr('stat_favorites'), 5),
        ]),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String value, String label,
      int i) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ];
    final onColors = [
      scheme.onPrimaryContainer,
      scheme.onSecondaryContainer,
      scheme.onTertiaryContainer,
    ];
    final bg = colors[i % 3];
    final fg = onColors[i % 3];
    return Expanded(
      child: Reveal(
        delay: Duration(milliseconds: i * 50),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: fg, size: 24),
              const SizedBox(height: 10),
              Text(value,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 32,
                      height: 1,
                      color: fg)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: fg.withValues(alpha: 0.85))),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------ по годам ------------------------------
  Widget _byYear(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    final years = s.byYear.keys.toList()..sort();
    final maxV = s.byYear.values.fold(0, (a, b) => a > b ? a : b);
    return _card(context, tr('stat_by_year'), SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final y in years)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${s.byYear[y]}',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                        begin: 0, end: maxV == 0 ? 0 : s.byYear[y]! / maxV),
                    duration: const Duration(milliseconds: 700),
                    curve: AppTheme.emphasized,
                    builder: (_, v, _) => Container(
                      height: 96 * v + 4,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('$y',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    ));
  }

  // ------------------------- распределение оценок -------------------------
  Widget _scoreDist(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = s.scoreDist.fold(0, (a, b) => a > b ? a : b);
    Color barColor(int i) {
      // 1 → красный, 10 → зелёный
      final t = i / 9;
      return Color.lerp(const Color(0xFFD0433B), const Color(0xFF2E9B57), t)!;
    }

    return _card(context, tr('stat_scores'), SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 10; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (s.scoreDist[i] > 0)
                    Text('${s.scoreDist[i]}',
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 10,
                            color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 3),
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                        begin: 0,
                        end: maxV == 0 ? 0 : s.scoreDist[i] / maxV),
                    duration: Duration(milliseconds: 500 + i * 40),
                    curve: AppTheme.emphasized,
                    builder: (_, v, _) => Container(
                      height: 96 * v + 3,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: barColor(i),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text('${i + 1}',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    ));
  }

  // ------------------------------ эмоции ------------------------------
  Widget _emotions(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    final top = s.emotions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _card(context, tr('stat_emotions'), Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in top.take(8))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20)),
            child: Text('${e.key} ${e.value}',
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
          ),
      ],
    ));
  }

  Widget _topRow(BuildContext context, LibraryMovie m) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showMovieSheet(context, m),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Poster(title: m.displayTitle, url: m.posterUrl, width: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(m.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: scheme.onSurface)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(m.currentScore!.toStringAsFixed(1),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: scheme.onPrimaryContainer)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, String title, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: scheme.onSurface)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Text(title,
      style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: Theme.of(context).colorScheme.onSurface));
}

/// Посчитанная статистика библиотеки.
class _Stats {
  final int watchedMovies;
  final int totalViewings;
  final int hours;
  final double avgScore;
  final int seriesCount;
  final int favorites;
  final Map<int, int> byYear;
  final List<int> scoreDist; // 10 бакетов (1..10)
  final List<LibraryMovie> topRated;
  final Map<String, int> emotions;

  _Stats({
    required this.watchedMovies,
    required this.totalViewings,
    required this.hours,
    required this.avgScore,
    required this.seriesCount,
    required this.favorites,
    required this.byYear,
    required this.scoreDist,
    required this.topRated,
    required this.emotions,
  });

  static _Stats compute(MovieRepository repo) {
    final watched = repo.watched;
    var totalViewings = 0;
    var minutes = 0;
    final byYear = <int, int>{};
    final scoreDist = List<int>.filled(10, 0);
    final emotions = <String, int>{};
    var scoreSum = 0.0;
    var scoreN = 0;

    for (final m in watched) {
      for (final v in m.viewings) {
        totalViewings++;
        if (m.runtimeMin != null) minutes += m.runtimeMin!;
        final d = v.date;
        if (d != null) byYear[d.year] = (byYear[d.year] ?? 0) + 1;
      }
      final sc = m.currentScore;
      if (sc != null) {
        scoreSum += sc;
        scoreN++;
        final b = (sc.round()).clamp(1, 10) - 1;
        scoreDist[b]++;
      }
      for (final e in m.emotions) {
        emotions[e.emoji] = (emotions[e.emoji] ?? 0) + 1;
      }
    }

    final top = watched.where((m) => m.currentScore != null).toList()
      ..sort((a, b) => b.currentScore!.compareTo(a.currentScore!));

    return _Stats(
      watchedMovies: watched.length,
      totalViewings: totalViewings,
      hours: minutes ~/ 60,
      avgScore: scoreN == 0 ? 0 : scoreSum / scoreN,
      seriesCount: repo.seriesCount,
      favorites: repo.favorites.length,
      byYear: byYear,
      scoreDist: scoreDist,
      topRated: top.take(10).toList(),
      emotions: emotions,
    );
  }
}
