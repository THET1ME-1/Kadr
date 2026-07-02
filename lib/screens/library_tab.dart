import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster.dart';
import '../widgets/reveal.dart';
import 'movie_sheet.dart';

enum LibraryMode { watched, watchlist }

/// Вкладка библиотеки: «Просмотрено» (карточка на КАЖДЫЙ просмотр, по месяцам —
/// как в референсе; повторные просмотры помечаются) или «Буду смотреть».
class LibraryTab extends StatelessWidget {
  final LibraryMode mode;
  const LibraryTab({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        if (mode == LibraryMode.watchlist) {
          final items = repo.watchlist;
          if (items.isEmpty) {
            return EmptyState(
                icon: Icons.bookmark_rounded,
                title: tr('nav_watchlist'),
                subtitle: tr('lib_empty_watchlist'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: items.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) return _countHeader(context, items.length);
              return _MovieRow(movie: items[i - 1]);
            },
          );
        }

        final groups = repo.watchedViewingsByMonth;
        if (groups.isEmpty) {
          return EmptyState(
              icon: Icons.check_circle_rounded,
              title: tr('nav_watched'),
              subtitle: tr('lib_empty_watched'));
        }
        final total = groups.fold<int>(0, (s, g) => s + g.value.length);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _countHeader(context, total)),
            for (final g in groups) ...[
              SliverToBoxAdapter(child: _monthHeader(context, g.key)),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final (movie, viewing) = g.value[i];
                    final first = movie.sortedViewings.isNotEmpty
                        ? movie.sortedViewings.first
                        : null;
                    final isRe = movie.viewings.length > 1 &&
                        !identical(viewing, first);
                    return _MovieRow(
                        movie: movie,
                        viewing: viewing,
                        isRewatchViewing: isRe);
                  },
                  childCount: g.value.length,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        );
      },
    );
  }

  Widget _countHeader(BuildContext context, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          trf('lib_count', {'n': n}),
          style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  Widget _monthHeader(BuildContext context, DateTime month) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text(
          month.year <= 1
              ? tr('when_unknown')
              : trf('watched_month',
                  {'month': monthName(month.month), 'year': month.year}),
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: 21,
            letterSpacing: -0.4,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
}

class _MovieRow extends StatelessWidget {
  final LibraryMovie movie;

  /// Конкретный просмотр (для вкладки «Просмотрено»). null во «Буду смотреть».
  final Viewing? viewing;
  final bool isRewatchViewing;

  const _MovieRow(
      {required this.movie, this.viewing, this.isRewatchViewing = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (movie.year != null) '${movie.year}',
      if (movie.runtimeMin != null)
        humanDuration(Duration(minutes: movie.runtimeMin!)),
    ].join(' · ');
    final date = viewing?.date;
    final score = viewing != null ? movie.scoreOf(viewing!) : movie.score;

    return Reveal(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showMovieSheet(context, movie),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Poster(title: movie.displayTitle, url: movie.posterUrl, width: 58),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(movie.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                height: 1.1,
                                color: scheme.onSurface)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (movie.emotions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(movie.emotions.first.emoji,
                                    style: const TextStyle(fontSize: 15)),
                              ),
                            if (movie.favorite)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(Icons.favorite_rounded,
                                    size: 15, color: scheme.primary),
                              ),
                            Flexible(
                              child: Text(meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant)),
                            ),
                          ],
                        ),
                        if (date != null || isRewatchViewing) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (date != null)
                                Text(
                                  dateExactWithTime(date),
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.85)),
                                ),
                              if (isRewatchViewing) ...[
                                if (date != null) const SizedBox(width: 8),
                                _rewatchChip(scheme),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _scoreBadge(scheme, score),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _rewatchChip(ColorScheme scheme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat_rounded,
                size: 12, color: scheme.onTertiaryContainer),
            const SizedBox(width: 3),
            Text(tr('rewatch'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: scheme.onTertiaryContainer)),
          ],
        ),
      );

  Widget _scoreBadge(ColorScheme scheme, double? score) {
    if (score == null) {
      return Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
        child: Icon(Icons.add_rounded, color: scheme.onSurfaceVariant),
      );
    }
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      child: Text(
        score.toStringAsFixed(1),
        style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
