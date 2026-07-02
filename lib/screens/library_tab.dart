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
import 'series_sheet.dart';

enum LibraryMode { watched, watchlist }

enum _WatchedFilter { all, movies, series }

/// Вкладка библиотеки: «Просмотрено» (карточка на каждый просмотр + сериалы, по
/// месяцам) или «Буду смотреть» (по дате добавления).
class LibraryTab extends StatefulWidget {
  final LibraryMode mode;
  final String query;
  const LibraryTab({super.key, required this.mode, this.query = ''});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  _WatchedFilter _filter = _WatchedFilter.all;

  String get _q => widget.query.toLowerCase().trim();
  bool _matchMovie(LibraryMovie m) =>
      _q.isEmpty ||
      m.displayTitle.toLowerCase().contains(_q) ||
      m.title.toLowerCase().contains(_q);
  bool _matchSeries(LibrarySeries s) =>
      _q.isEmpty ||
      s.displayTitle.toLowerCase().contains(_q) ||
      s.title.toLowerCase().contains(_q);
  bool _matchEntry(WatchedEntry e) =>
      e.isSeries ? _matchSeries(e.series!) : _matchMovie(e.movie!);

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        if (widget.mode == LibraryMode.watchlist) return _watchlist(repo);
        return _watched(repo);
      },
    );
  }

  Widget _watchlist(MovieRepository repo) {
    final items = repo.watchlist.where(_matchMovie).toList();
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
        if (i == 0) return _watchlistHeader(context, repo, items.length);
        return _MovieRow(movie: items[i - 1]);
      },
    );
  }

  Widget _watched(MovieRepository repo) {
    final groups = [
      for (final g in repo.watchedEntriesByMonth(
        movies: _filter != _WatchedFilter.series,
        series: _filter != _WatchedFilter.movies,
      ))
        if (g.value.any(_matchEntry))
          MapEntry(g.key, g.value.where(_matchEntry).toList()),
    ];
    final total = groups.fold<int>(0, (s, g) => s + g.value.length);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _filterBar(repo)),
        if (groups.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
                icon: Icons.check_circle_rounded,
                title: tr('nav_watched'),
                subtitle: tr('lib_empty_watched')),
          )
        else ...[
          SliverToBoxAdapter(child: _countHeader(context, total)),
          for (final g in groups) ...[
            SliverToBoxAdapter(child: _monthHeader(context, g.key)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _entryRow(g.value[i]),
                childCount: g.value.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ],
    );
  }

  Widget _entryRow(WatchedEntry e) {
    if (e.isSeries) return _SeriesRow(series: e.series!);
    final movie = e.movie!;
    final viewing = e.viewing!;
    final ordinal = movie.sortedViewings.indexOf(viewing) + 1;
    final rewatchNum =
        (movie.viewings.length > 1 && ordinal > 1) ? ordinal : null;
    return _MovieRow(
        movie: movie, viewing: viewing, rewatchNumber: rewatchNum);
  }

  Widget _filterBar(MovieRepository repo) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SegmentedButton<_WatchedFilter>(
          segments: [
            ButtonSegment(
                value: _WatchedFilter.all, label: Text(tr('filter_all'))),
            ButtonSegment(
                value: _WatchedFilter.movies, label: Text(tr('filter_movies'))),
            ButtonSegment(
                value: _WatchedFilter.series,
                label: Text('${tr('filter_series')} (${repo.seriesCount})')),
          ],
          selected: {_filter},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _filter = s.first),
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll(TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
          ),
        ),
      );

  Widget _watchlistHeader(
          BuildContext context, MovieRepository repo, int n) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 2),
        child: Row(
          children: [
            Text(
              trf('lib_count', {'n': n}),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: repo.toggleWatchlistOrder,
              icon: Icon(
                  repo.watchlistNewestFirst
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 18),
              label: Text(tr(
                  repo.watchlistNewestFirst ? 'sort_newest' : 'sort_oldest')),
            ),
          ],
        ),
      );

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

/// Строка сериала во вкладке «Просмотрено».
class _SeriesRow extends StatelessWidget {
  final LibrarySeries series;
  const _SeriesRow({required this.series});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = series.lastWatch;
    return Reveal(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showSeriesSheet(context, series),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Stack(
                    children: [
                      Poster(
                          title: series.displayTitle,
                          url: series.posterUrl,
                          width: 58),
                      Positioned(
                        left: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                              color: scheme.tertiary,
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.live_tv_rounded,
                              size: 12, color: scheme.onTertiary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(series.displayTitle,
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
                            if (series.favorite)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(Icons.favorite_rounded,
                                    size: 15, color: scheme.primary),
                              ),
                            Text(trf('episodes_n', {'n': series.episodesSeen}),
                                style: TextStyle(
                                    fontFamily: AppTheme.bodyFont,
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                        if (date != null) ...[
                          const SizedBox(height: 3),
                          Text(dateExactWithTime(date),
                              style: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.85))),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _scoreBadge(scheme, series.score),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Бейдж оценки. Если оценки нет: в «Буду смотреть» ([addMode]) — «+»
/// (добавить просмотр), в «Просмотрено» — звезда (поставить оценку).
Widget _scoreBadge(ColorScheme scheme, double? score, {bool addMode = false}) {
  if (score == null) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
      child: Icon(addMode ? Icons.add_rounded : Icons.star_border_rounded,
          color: scheme.onSurfaceVariant, size: 24),
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

class _MovieRow extends StatelessWidget {
  final LibraryMovie movie;

  /// Конкретный просмотр (для вкладки «Просмотрено»). null во «Буду смотреть».
  final Viewing? viewing;

  /// Номер повторного просмотра (2, 3, …); null — если это первый просмотр.
  final int? rewatchNumber;

  const _MovieRow({required this.movie, this.viewing, this.rewatchNumber});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (movie.year != null) '${movie.year}',
      if (movie.runtimeMin != null)
        humanDuration(Duration(minutes: movie.runtimeMin!)),
    ].join(' · ');
    final date = viewing?.date;
    final score =
        viewing != null ? movie.scoreOf(viewing!) : movie.currentScore;

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
                        if (date != null || rewatchNumber != null) ...[
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
                              if (rewatchNumber != null) ...[
                                if (date != null) const SizedBox(width: 8),
                                _rewatchChip(scheme, rewatchNumber!),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _scoreBadge(scheme, score, addMode: viewing == null),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Бейдж повтора: «↻ N» — номер по счёту (2-й, 3-й… просмотр).
  Widget _rewatchChip(ColorScheme scheme, int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat_rounded,
                size: 13, color: scheme.onTertiaryContainer),
            const SizedBox(width: 3),
            Text('$n',
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: scheme.onTertiaryContainer)),
          ],
        ),
      );
}
