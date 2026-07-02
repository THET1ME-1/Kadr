import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../widgets/poster.dart';
import '../widgets/reveal.dart';

/// Экран сериала: все серии из TMDB с отметкой просмотра (галочка) и оценкой
/// каждой серии. Позволяет отмечать серии, которых ещё нет в библиотеке.
class SeriesScreen extends StatefulWidget {
  final LibrarySeries series;
  const SeriesScreen({super.key, required this.series});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  final _repo = MovieRepository.instance;
  int? _tmdbId;
  List<TmdbSeason> _seasons = [];
  int? _season;
  List<TmdbEpisode>? _eps;
  bool _loading = true;
  bool _error = false;

  LibrarySeries get s =>
      _repo.seriesById(widget.series.tvShowId) ?? widget.series;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    var id = widget.series.tmdbId;
    if (id == null) {
      final m = await TmdbService.searchTv(widget.series.title);
      id = m?.tmdbId;
      if (id != null) {
        widget.series.tmdbId = id;
        await _repo.enrichSeries(widget.series); // подхватит постер/имя заодно
      }
    }
    _tmdbId = id;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    _seasons = await TmdbService.seasons(id);
    if (_seasons.isEmpty) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    _season = _initialSeason();
    await _loadSeason(_season!);
    if (mounted) setState(() => _loading = false);
  }

  int _initialSeason() {
    // Сезон последней просмотренной серии, иначе первый.
    int? best;
    DateTime? bestAt;
    for (final e in s.episodes) {
      if (e.season == null || e.watchedAt == null) continue;
      if (bestAt == null || e.watchedAt!.isAfter(bestAt)) {
        bestAt = e.watchedAt;
        best = e.season;
      }
    }
    if (best != null && _seasons.any((x) => x.number == best)) return best;
    return _seasons.first.number;
  }

  Future<void> _loadSeason(int n) async {
    setState(() => _eps = null);
    final eps = await TmdbService.episodesOf(_tmdbId!, n);
    if (mounted) setState(() => _eps = eps);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(s.displayTitle)),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              if (_error)
                SliverToBoxAdapter(child: _errorCard(context))
              else ...[
                if (_seasons.length > 1)
                  SliverToBoxAdapter(child: _seasonBar(context)),
                if (_eps == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Reveal(
                        delay: Duration(milliseconds: (i % 6) * 30),
                        child: _episodeTile(context, _eps![i]),
                      ),
                      childCount: _eps!.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _seasons.fold<int>(0, (a, b) => a + b.episodeCount);
    final seen = s.episodes.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Poster(title: s.displayTitle, url: s.posterUrl, width: 90, radius: 16),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.displayTitle,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            height: 1.1,
                            color: scheme.onSurface)),
                    const SizedBox(height: 8),
                    Text(
                        total > 0
                            ? trf('seen_of', {'n': seen, 'm': total})
                            : trf('episodes_n', {'n': seen}),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    if (total > 0)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (seen / total).clamp(0, 1),
                          minHeight: 7,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _iconBtn(
                          scheme,
                          s.favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          () => _repo.toggleSeriesFavorite(s.tvShowId),
                          on: s.favorite,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(ColorScheme scheme, IconData icon, VoidCallback onTap,
          {bool on = false}) =>
      Material(
        color: on ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon,
                size: 22,
                color: on ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
          ),
        ),
      );

  Widget _seasonBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final se in _seasons)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(trf('season_n', {'n': se.number})),
                selected: _season == se.number,
                onSelected: (_) {
                  setState(() => _season = se.number);
                  _loadSeason(se.number);
                },
                labelStyle: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    color: _season == se.number
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant),
                selectedColor: scheme.secondaryContainer,
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }

  Widget _episodeTile(BuildContext context, TmdbEpisode ep) {
    final scheme = Theme.of(context).colorScheme;
    final watchedEp = s.watchedEpisode(ep.season, ep.number);
    final watched = watchedEp != null;
    final sc = watchedEp?.score;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Кадр серии
            SizedBox(
              width: 116,
              height: 76,
              child: ep.stillUrl != null
                  ? CachedNetworkImage(
                      imageUrl: ep.stillUrl!,
                      fit: BoxFit.cover,
                      placeholder: (c, _) =>
                          Container(color: scheme.surfaceContainerHighest),
                      errorWidget: (c, u, e) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(Icons.tv_rounded,
                              color: scheme.onSurfaceVariant)),
                    )
                  : Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.tv_rounded,
                          color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('S${ep.season}·E${ep.number}',
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: scheme.primary)),
                  const SizedBox(height: 2),
                  Text(ep.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          height: 1.15,
                          color: scheme.onSurface)),
                  if (watched && sc != null) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _rate(watchedEp),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.star_rounded, size: 14, color: scheme.primary),
                        const SizedBox(width: 2),
                        Text(sc.toStringAsFixed(1),
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: scheme.primary)),
                      ]),
                    ),
                  ] else if (watched) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _rate(watchedEp),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.star_border_rounded,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(tr('not_rated'),
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            // Галочка «просмотрено» — тап переключает.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: GestureDetector(
                onTap: () {
                  if (watched) {
                    _repo.unmarkEpisode(s.tvShowId, ep.season, ep.number);
                  } else {
                    _repo.markEpisodeWatched(s.tvShowId, ep.season, ep.number,
                        runtimeMin: ep.runtime);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: watched ? scheme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: watched ? scheme.primary : scheme.outline,
                        width: 2),
                  ),
                  child: Icon(Icons.check_rounded,
                      size: 22,
                      color: watched ? scheme.onPrimary : scheme.outline),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 52, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(tr('no_episodes'),
              style: const TextStyle(fontFamily: AppTheme.bodyFont)),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _init, child: Text(tr('retry'))),
        ],
      ),
    );
  }

  void _rate(Episode ep) {
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
                Text('S${ep.season}·E${ep.number}',
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
                        color: rated ? scheme.primary : scheme.onSurfaceVariant)),
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
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        _repo.setEpisodeScore(s.tvShowId, ep, null);
                        Navigator.pop(sheetCtx);
                      },
                      child: Text(tr('remove_score')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        _repo.setEpisodeScore(s.tvShowId, ep, rated ? val : null);
                        Navigator.pop(sheetCtx);
                      },
                      child: Text(tr('done')),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
