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
import 'series_screen.dart';

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
  bool _matchEntry(WatchedEntry e) => e.isSeries
      ? _matchSeries(e.session!.series)
      : _matchMovie(e.movie!);

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
    if (e.isSeries) return _SeriesSessionCard(session: e.session!);
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

/// Блок сессии сериала во вкладке «Просмотрено»: серии, просмотренные подряд,
/// одной карточкой (как фильм) + список серий внутри, у каждой своя оценка.
class _SeriesSessionCard extends StatelessWidget {
  final EpisodeSession session;
  const _SeriesSessionCard({required this.session});

  LibrarySeries get s => session.series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = session.start;
    return Reveal(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s))),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Poster(
                              title: s.displayTitle,
                              url: s.posterUrl,
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
                            Text(s.displayTitle,
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
                                if (s.favorite)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(Icons.favorite_rounded,
                                        size: 15, color: scheme.primary),
                                  ),
                                Flexible(
                                  child: Text(
                                      '${session.rangeLabel} · ${session.count} сер.',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontFamily: AppTheme.bodyFont,
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant)),
                                ),
                              ],
                            ),
                            if (start != null) ...[
                              const SizedBox(height: 3),
                              Text(dateExactWithTime(start),
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
                      _scoreBadge(scheme, session.avgScore),
                    ],
                  ),
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: scheme.surfaceContainerHighest),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 10, 8),
                child: Column(
                  children: [
                    for (final ep in session.episodes.take(12))
                      _EpisodeRow(seriesId: s.tvShowId, ep: ep),
                    if (session.episodes.length > 12)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 4),
                          child: Row(
                            children: [
                              Icon(Icons.expand_more_rounded,
                                  size: 18, color: scheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                  trf('more_episodes',
                                      {'n': session.episodes.length - 12}),
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: scheme.primary)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка одного эпизода в блоке сессии — с оценкой (тап → поставить).
class _EpisodeRow extends StatelessWidget {
  final String seriesId;
  final Episode ep;
  const _EpisodeRow({required this.seriesId, required this.ep});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sc = ep.score;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _rate(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline_rounded,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: Text(ep.label,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: scheme.onSurface)),
            ),
            if (ep.watchedAt != null)
              Text(hhmm(ep.watchedAt!),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sc != null
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      sc != null
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 14,
                      color: sc != null
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(sc != null ? sc.toStringAsFixed(1) : '—',
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: sc != null
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _rate(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    double val = ep.score ?? 7.0;
    bool rated = ep.score != null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 14),
                Text(ep.label,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: scheme.onSurface)),
                const SizedBox(height: 6),
                Text(rated ? val.toStringAsFixed(1) : '—',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 44,
                        color:
                            rated ? scheme.primary : scheme.onSurfaceVariant)),
                Slider(
                  value: val,
                  min: 1,
                  max: 10,
                  divisions: 90,
                  label: val.toStringAsFixed(1),
                  onChanged: (x) => setSheet(() {
                    val = x;
                    rated = true;
                  }),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          MovieRepository.instance
                              .setEpisodeScore(seriesId, ep, null);
                          Navigator.pop(sheetCtx);
                        },
                        child: Text(tr('remove_score')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          MovieRepository.instance
                              .setEpisodeScore(seriesId, ep, rated ? val : null);
                          Navigator.pop(sheetCtx);
                        },
                        child: Text(tr('done')),
                      ),
                    ),
                  ],
                ),
              ],
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
