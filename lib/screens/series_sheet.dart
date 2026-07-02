import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/poster.dart';

/// Карточка сериала — нижняя панель: постер, число серий, оценка (слайдер),
/// избранное, история просмотров эпизодов.
Future<void> showSeriesSheet(BuildContext context, LibrarySeries series) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _SeriesSheet(series: series),
  );
}

class _SeriesSheet extends StatefulWidget {
  final LibrarySeries series;
  const _SeriesSheet({required this.series});

  @override
  State<_SeriesSheet> createState() => _SeriesSheetState();
}

class _SeriesSheetState extends State<_SeriesSheet> {
  final _repo = MovieRepository.instance;
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final s = _repo.seriesById(widget.series.tvShowId) ?? widget.series;
        final scheme = Theme.of(context).colorScheme;
        final val = _dragging ?? s.score ?? 7.0;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Poster(
                      title: s.displayTitle,
                      url: s.posterUrl,
                      width: 100,
                      radius: 18),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.displayTitle,
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                                height: 1.1,
                                color: scheme.onSurface)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _chip(scheme, Icons.live_tv_rounded,
                                trf('episodes_n', {'n': s.episodesSeen})),
                            if (s.lastWatch != null)
                              _chip(scheme, Icons.event_rounded,
                                  numericDate(s.lastWatch!)),
                            if (s.kpRating != null)
                              _chip(scheme, Icons.star_rounded,
                                  s.kpRating!.toStringAsFixed(1)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _scoreCard(scheme, s, val),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => _repo.toggleSeriesFavorite(s.tvShowId),
                  icon: Icon(s.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded),
                  label: Text(tr('act_favorite')),
                ),
              ),
              ..._episodesSection(scheme, s),
              if (s.review != null && s.review!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(s.review!,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 14,
                          height: 1.4,
                          color: scheme.onSurface)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---- список серий по сезонам, у каждой своя оценка ----
  List<Widget> _episodesSection(ColorScheme scheme, LibrarySeries s) {
    if (s.episodes.isEmpty) return [];
    final bySeason = <int?, List<Episode>>{};
    for (final ep in s.episodes) {
      bySeason.putIfAbsent(ep.season, () => []).add(ep);
    }
    final keys = bySeason.keys.toList()
      ..sort((a, b) => (a ?? 9999).compareTo(b ?? 9999));
    final out = <Widget>[
      const SizedBox(height: 20),
      Text('${tr('episodes_section')} · ${s.episodes.length}',
          style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: scheme.primary)),
    ];
    for (final k in keys) {
      final eps = bySeason[k]!
        ..sort((a, b) {
          final an = a.number ?? 0, bn = b.number ?? 0;
          if (an != bn) return an.compareTo(bn);
          final ad = a.watchedAt, bd = b.watchedAt;
          if (ad == null || bd == null) return 0;
          return ad.compareTo(bd);
        });
      if (k != null) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
          child: Text(trf('season_n', {'n': k}),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: scheme.onSurfaceVariant)),
        ));
      } else {
        out.add(const SizedBox(height: 8));
      }
      out.addAll(eps.map((ep) => _episodeRow(scheme, s, ep)));
    }
    return out;
  }

  Widget _episodeRow(ColorScheme scheme, LibrarySeries s, Episode ep) {
    final sc = ep.score;
    final label = ep.number != null
        ? 'E${ep.number}'
        : (ep.watchedAt != null ? numericDate(ep.watchedAt!) : tr('when_unknown'));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _rateEpisode(s, ep),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline_rounded,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            SizedBox(
                width: 46,
                child: Text(label,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: scheme.onSurface))),
            if (ep.watchedAt != null)
              Text('${numericDate(ep.watchedAt!)} ${hhmm(ep.watchedAt!)}',
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: sc != null
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sc != null ? Icons.star_rounded : Icons.star_border_rounded,
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

  void _rateEpisode(LibrarySeries s, Episode ep) {
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
                Row(
                  children: [
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
                          _repo.setEpisodeScore(
                              s.tvShowId, ep, rated ? val : null);
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

  Widget _scoreCard(ColorScheme scheme, LibrarySeries s, double val) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Icon(Icons.star_rounded, color: scheme.onPrimaryContainer, size: 32),
              const SizedBox(width: 6),
              Text(val.toStringAsFixed(1),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 48,
                      height: 1,
                      color: scheme.onPrimaryContainer)),
              Text(' / 10',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
            ],
          ),
          Slider(
            value: val,
            min: 1,
            max: 10,
            divisions: 90,
            label: val.toStringAsFixed(1),
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              _repo.setSeriesScore(s.tvShowId, v);
              setState(() => _dragging = null);
            },
          ),
          Text(s.score != null ? tr('your_rating') : tr('rate_it'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme scheme, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      );
}
