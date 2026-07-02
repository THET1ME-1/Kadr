import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/poster.dart';

/// Карточка фильма — выезжающая снизу панель (M3). Показывает постер, мета,
/// личную оценку 1.0–10.0 (редактируется слайдером с шагом 0.1), эмоции,
/// избранное и историю просмотров.
Future<void> showMovieSheet(BuildContext context, LibraryMovie movie) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _MovieSheet(movie: movie),
  );
}

class _MovieSheet extends StatefulWidget {
  final LibraryMovie movie;
  const _MovieSheet({required this.movie});

  @override
  State<_MovieSheet> createState() => _MovieSheetState();
}

class _MovieSheetState extends State<_MovieSheet> {
  final _repo = MovieRepository.instance;
  late double _score = widget.movie.score ?? 7.0;

  LibraryMovie get m => widget.movie;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (m.year != null) '${m.year}',
      if (m.runtimeMin != null) humanDuration(Duration(minutes: m.runtimeMin!)),
    ].join(' · ');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.5,
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
              Poster(title: m.displayTitle, url: m.posterUrl, width: 96, radius: 18),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.displayTitle,
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          height: 1.1,
                          color: scheme.onSurface,
                        )),
                    const SizedBox(height: 6),
                    if (meta.isNotEmpty)
                      Text(meta,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 14,
                              color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in m.emotions)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${e.emoji} ${e.label}'),
                            backgroundColor: scheme.secondaryContainer,
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _scoreCard(scheme),
          const SizedBox(height: 18),
          _actionsRow(scheme),
          if (m.viewings.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(trf('viewings_n', {'n': m.viewings.length}),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: scheme.primary)),
            const SizedBox(height: 8),
            for (final d in m.viewings.reversed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded, size: 20),
                title: Text(longDate(d)),
              ),
          ],
          if (m.review != null && m.review!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(m.review!,
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
  }

  Widget _scoreCard(ColorScheme scheme) {
    final rated = m.score != null;
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
              Icon(Icons.star_rounded,
                  color: scheme.onPrimaryContainer, size: 32),
              const SizedBox(width: 6),
              Text(
                _score.toStringAsFixed(1),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 48,
                  height: 1,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              Text(' / 10',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
            ],
          ),
          Slider(
            value: _score,
            min: 1,
            max: 10,
            divisions: 90,
            label: _score.toStringAsFixed(1),
            onChanged: (v) => setState(() => _score = v),
            onChangeEnd: (v) => _repo.setScore(m.uuid, v),
          ),
          Text(
            rated ? tr('your_rating') : tr('rate_it'),
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _actionsRow(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => setState(() => _repo.toggleFavorite(m.uuid)),
            icon: Icon(m.favorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded),
            label: Text(tr('act_favorite')),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check_rounded),
            label: Text(tr('done')),
          ),
        ),
      ],
    );
  }
}
