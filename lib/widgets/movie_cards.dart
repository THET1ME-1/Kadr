import 'package:flutter/material.dart';

import '../models/library_entry.dart';
import '../screens/movie_sheet.dart';
import '../screens/series_screen.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/score.dart';
import 'poster.dart';
import 'pressable.dart';

/// Бейдж «Брошено» — мягко-красный кружок с надломленным сердцем.
Widget droppedBadge() => Container(
      padding: const EdgeInsets.all(5),
      decoration:
          const BoxDecoration(color: kDroppedColor, shape: BoxShape.circle),
      child: const Icon(Icons.heart_broken_rounded, size: 14, color: Colors.white),
    );

/// Бейджи статуса поверх постера в лентах: сердечко (если в избранном) — левее,
/// затем галочка+оценка (просмотрено) или закладка (в списке).
Widget statusBadges(ColorScheme scheme, LibraryMovie? lib) {
  if (lib == null) return const SizedBox.shrink();
  final badges = <Widget>[];
  if (lib.favorite) {
    badges.add(Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Icon(Icons.favorite_rounded, size: 14, color: scheme.onPrimary),
    ));
  }
  if (lib.status == LibraryStatus.dropped) {
    badges.add(droppedBadge());
  } else if (lib.status == LibraryStatus.watched) {
    final sc = lib.currentScore;
    badges.add(Container(
      padding: EdgeInsets.symmetric(horizontal: sc != null ? 8 : 5, vertical: 4),
      decoration: BoxDecoration(
          color: scheme.primary, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary),
          if (sc != null) ...[
            const SizedBox(width: 3),
            Text(sc.toStringAsFixed(1),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: scheme.onPrimary)),
          ],
        ],
      ),
    ));
  } else if (lib.status == LibraryStatus.watchlist) {
    badges.add(Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: scheme.secondaryContainer, shape: BoxShape.circle),
      child: Icon(Icons.bookmark_rounded,
          size: 14, color: scheme.onSecondaryContainer),
    ));
  }
  if (badges.isEmpty) return const SizedBox.shrink();
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < badges.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        badges[i],
      ],
    ],
  );
}

/// Карточка-постер фильма для лент (Обзор/В кино/жанр). Тап → карточка фильма.
class DiscoverMovieCard extends StatelessWidget {
  final TmdbMovie movie;
  final double width;
  const DiscoverMovieCard({super.key, required this.movie, required this.width});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lib = MovieRepository.instance.findMovieForTmdb(movie);
    return SizedBox(
      width: width,
      child: Pressable(
        onTap: () => showMovieSheet(
            context, MovieRepository.instance.ensureFromTmdb(movie)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Poster(
                    title: movie.title,
                    url: movie.posterUrl,
                    width: width,
                    radius: 16),
                Positioned(top: 6, right: 6, child: statusBadges(scheme, lib)),
              ],
            ),
            const SizedBox(height: 6),
            Text(movie.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.1,
                    color: scheme.onSurface)),
            const SizedBox(height: 2),
            Row(
              children: [
                if (movie.rating != null && movie.rating! > 0) ...[
                  Icon(Icons.star_rounded, size: 13, color: scheme.primary),
                  const SizedBox(width: 2),
                  Text(movie.rating!.toStringAsFixed(1),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                ],
                if (movie.year != null)
                  Text('${movie.year}',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка-постер сериала для ленты «Сериалы». Тап → экран серий.
class DiscoverSeriesCard extends StatelessWidget {
  final TmdbSeries series;
  final double width;
  const DiscoverSeriesCard(
      {super.key, required this.series, required this.width});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lib = MovieRepository.instance.seriesByTmdb(series.id);
    final seen = lib?.episodes.length ?? 0;
    return SizedBox(
      width: width,
      child: Pressable(
        onTap: () {
          final s = MovieRepository.instance.ensureSeriesFromTmdb(series);
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s)));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Poster(
                    title: series.title,
                    url: series.posterUrl,
                    width: width,
                    radius: 16),
                if (lib != null && (lib.favorite || lib.dropped))
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (lib.favorite)
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                                color: scheme.primary, shape: BoxShape.circle),
                            child: Icon(Icons.favorite_rounded,
                                size: 14, color: scheme.onPrimary),
                          ),
                        if (lib.favorite && lib.dropped)
                          const SizedBox(width: 4),
                        if (lib.dropped) droppedBadge(),
                      ],
                    ),
                  ),
                if (seen > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                          color: scheme.tertiary,
                          borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.live_tv_rounded,
                              size: 13, color: scheme.onTertiary),
                          const SizedBox(width: 3),
                          Text('$seen',
                              style: TextStyle(
                                  fontFamily: AppTheme.displayFont,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: scheme.onTertiary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(series.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.1,
                    color: scheme.onSurface)),
            const SizedBox(height: 2),
            Row(
              children: [
                if (series.rating != null && series.rating! > 0) ...[
                  Icon(Icons.star_rounded, size: 13, color: scheme.primary),
                  const SizedBox(width: 2),
                  Text(series.rating!.toStringAsFixed(1),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                ],
                if (series.year != null)
                  Text('${series.year}',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка фильма для списков (фильмография персоны): постер + название + быстрая
/// кнопка «Буду смотреть»/«Просмотрено». Тап по строке → карточка фильма.
class TmdbMovieRow extends StatelessWidget {
  final TmdbMovie movie;
  const TmdbMovieRow({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = MovieRepository.instance;
    final lib = repo.findMovieForTmdb(movie);
    final watched = lib?.status == LibraryStatus.watched;
    final inWatchlist = lib?.status == LibraryStatus.watchlist;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showMovieSheet(context, repo.ensureFromTmdb(movie)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Poster(title: movie.title, url: movie.posterUrl, width: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(movie.title,
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
                          if (lib != null && lib.favorite)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(Icons.favorite_rounded,
                                  size: 14, color: scheme.primary),
                            ),
                          if (movie.rating != null && movie.rating! > 0) ...[
                            Icon(Icons.star_rounded,
                                size: 13, color: scheme.primary),
                            const SizedBox(width: 2),
                            Text(movie.rating!.toStringAsFixed(1),
                                style: TextStyle(
                                    fontFamily: AppTheme.bodyFont,
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant)),
                            const SizedBox(width: 8),
                          ],
                          if (movie.year != null)
                            Text('${movie.year}',
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
                // Быстрое действие: отмечено — галочка; иначе тап = «Буду смотреть».
                if (watched)
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: scheme.primary, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded,
                        size: 22, color: scheme.onPrimary),
                  )
                else
                  IconButton(
                    onPressed: () {
                      final m = repo.ensureFromTmdb(movie);
                      repo.toggleWatchlist(m.uuid);
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: inWatchlist
                          ? scheme.secondaryContainer
                          : scheme.surfaceContainerHighest,
                      foregroundColor: inWatchlist
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    icon: Icon(inWatchlist
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_add_outlined),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
