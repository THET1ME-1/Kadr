import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';
import 'series_screen.dart';

/// Экран «Сейчас смотрю»: только НЕЗАВЕРШЁННЫЕ сериалы, по свежести.
/// Тап → полный список серий, где можно отмечать новые серии просмотренными.
class NowWatchingScreen extends StatefulWidget {
  const NowWatchingScreen({super.key});

  @override
  State<NowWatchingScreen> createState() => _NowWatchingScreenState();
}

class _NowWatchingScreenState extends State<NowWatchingScreen> {
  @override
  void initState() {
    super.initState();
    _backfillTotals();
  }

  /// Дозагружает общее число серий для сериалов, у которых оно ещё не известно,
  /// чтобы уже завершённые исчезли из списка (реактивно). TMDB-выборка сезонов
  /// кэшируется; идём порциями, чтобы не грузить сеть разом.
  Future<void> _backfillTotals() async {
    final repo = MovieRepository.instance;
    final pending = repo.currentlyWatching
        .where((s) => s.totalEpisodes == null && s.tmdbId != null)
        .take(40)
        .toList();
    for (final s in pending) {
      if (!mounted) return;
      final seasons = await TmdbService.seasons(s.tmdbId!);
      if (seasons.isNotEmpty) {
        await repo.setSeriesTotal(
            s.tvShowId, seasons.fold<int>(0, (a, b) => a + b.episodeCount));
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final series = repo.nowWatching;
        return Scaffold(
          appBar: AppBar(title: Text(tr('now_watching'))),
          body: series.isEmpty
              ? EmptyState(
                  icon: Icons.live_tv_rounded,
                  title: tr('now_watching'),
                  subtitle: tr('now_watching_empty'))
              : LayoutBuilder(builder: (context, c) {
                  const spacing = 12.0;
                  final cols = (c.maxWidth ~/ 130).clamp(2, 5);
                  final w = (c.maxWidth - 32 - spacing * (cols - 1)) / cols;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: Wrap(
                      spacing: spacing,
                      runSpacing: 18,
                      children: [
                        for (var i = 0; i < series.length; i++)
                          Reveal(
                            delay: Duration(milliseconds: (i % cols) * 40),
                            child: _card(context, series[i], w),
                          ),
                      ],
                    ),
                  );
                }),
        );
      },
    );
  }

  Widget _card(BuildContext context, LibrarySeries s, double w) {
    final scheme = Theme.of(context).colorScheme;
    final last = s.lastWatch;
    return SizedBox(
      width: w,
      child: Pressable(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Poster(title: s.displayTitle, url: s.posterUrl, width: w, radius: 16),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: scheme.tertiary, shape: BoxShape.circle),
                    child: Icon(Icons.live_tv_rounded,
                        size: 13, color: scheme.onTertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(s.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.1,
                    color: scheme.onSurface)),
            const SizedBox(height: 2),
            Text(
                '${trf('episodes_n', {'n': s.episodesSeen})}${last != null ? ' · ${numericDate(last)}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
