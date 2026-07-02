import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';
import 'series_screen.dart';

/// Экран «Сейчас смотрю»: сериалы с просмотренными сериями, по свежести.
/// Тап → полный список серий, где можно отмечать новые серии просмотренными.
class NowWatchingScreen extends StatelessWidget {
  const NowWatchingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final series = repo.currentlyWatching;
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
