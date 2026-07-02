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
