import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/score.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster.dart';
import 'movie_sheet.dart';
import 'series_screen.dart';

/// Официальный список «Брошено» — фильмы и сериалы, просмотр которых прекращён.
/// Открывается из меню. Помечены мягко-красным во всех лентах.
class DroppedScreen extends StatelessWidget {
  const DroppedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('drawer_dropped'))),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final movies = repo.droppedMovies;
          final series = repo.droppedSeries;
          if (movies.isEmpty && series.isEmpty) {
            return EmptyState(
                icon: Icons.heart_broken_rounded,
                title: tr('drawer_dropped'),
                subtitle: tr('dropped_empty'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Text(
                  trf('dropped_count', {'n': movies.length + series.length}),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              if (movies.isNotEmpty) ...[
                _sectionTitle(context, tr('dropped_movies')),
                for (final m in movies) _MovieDroppedRow(movie: m),
              ],
              if (series.isNotEmpty) ...[
                _sectionTitle(context, tr('dropped_series')),
                for (final s in series) _SeriesDroppedRow(series: s),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Text(title,
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurface)),
      );
}

class _MovieDroppedRow extends StatelessWidget {
  final LibraryMovie movie;
  const _MovieDroppedRow({required this.movie});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _row(
      context,
      title: movie.displayTitle,
      subtitle: movie.year != null ? '${movie.year}' : '',
      posterUrl: movie.displayPoster,
      scheme: scheme,
      onTap: () => showMovieSheet(context, movie),
    );
  }
}

class _SeriesDroppedRow extends StatelessWidget {
  final LibrarySeries series;
  const _SeriesDroppedRow({required this.series});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _row(
      context,
      title: series.displayTitle,
      subtitle: trf('episodes_n', {'n': series.episodes.length}),
      posterUrl: series.displayPoster,
      scheme: scheme,
      seriesIcon: true,
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: series))),
    );
  }
}

Widget _row(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String? posterUrl,
  required ColorScheme scheme,
  required VoidCallback onTap,
  bool seriesIcon = false,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
    child: Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Poster(title: title, url: posterUrl, width: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.1,
                            color: scheme.onSurface)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (seriesIcon) ...[
                          Icon(Icons.live_tv_rounded,
                              size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 5),
                        ],
                        if (subtitle.isNotEmpty)
                          Text(subtitle,
                              style: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: kDroppedColor, shape: BoxShape.circle),
                child: const Icon(Icons.heart_broken_rounded,
                    size: 20, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
