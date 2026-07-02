import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/poster.dart';
import 'when_watched_sheet.dart';

/// Карточка фильма — выезжающая снизу панель (M3). Постер, мета, рейтинг КП,
/// личная оценка 1.0–10.0 (слайдер, шаг 0.1), отметка просмотра (+ повтор),
/// избранное, история просмотров. Обновляется на лету.
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final m = _repo.byUuid(widget.movie.uuid) ?? widget.movie;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: _content(context, m),
          ),
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, LibraryMovie m) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (m.year != null) '${m.year}',
      if (m.runtimeMin != null) humanDuration(Duration(minutes: m.runtimeMin!)),
    ].join(' · ');

    return [
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
          Poster(title: m.displayTitle, url: m.posterUrl, width: 100, radius: 18),
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
                    _statusChip(scheme, m),
                    if (m.isRewatched)
                      _chip(scheme, Icons.repeat_rounded,
                          trf('rewatches_n', {'n': m.rewatchCount}),
                          tone: true),
                    if (m.kpRating != null)
                      _chip(scheme, Icons.star_rounded,
                          '${tr('kp_rating')} ${m.kpRating!.toStringAsFixed(1)}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _scoreCard(scheme, m),
      const SizedBox(height: 16),
      // Отметить просмотр — крупная закрашенная кнопка.
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => showWhenWatchedSheet(context, m),
          icon: const Icon(Icons.add_task_rounded),
          label: Text(tr('mark_watched')),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _repo.toggleFavorite(m.uuid),
              icon: Icon(m.favorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded),
              label: Text(tr('act_favorite')),
            ),
          ),
          if (m.status != LibraryStatus.watched) ...[
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _repo.toggleWatchlist(m.uuid),
                icon: Icon(m.status == LibraryStatus.watchlist
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded),
                label: Text(tr('add_watchlist')),
              ),
            ),
          ],
        ],
      ),
      if (m.emotions.isNotEmpty) ...[
        const SizedBox(height: 18),
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
      if (m.viewings.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text(trf('viewings_n', {'n': m.viewings.length}),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: scheme.primary)),
        const SizedBox(height: 8),
        ..._viewingRows(scheme, m),
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
    ];
  }

  List<Widget> _viewingRows(ColorScheme scheme, LibraryMovie m) {
    // Показываем сверху свежие; повторными считаем все, кроме самого раннего.
    final sorted = m.sortedViewings; // по возрастанию, неизвестные в конце
    final rows = <Widget>[];
    for (var i = sorted.length - 1; i >= 0; i--) {
      final d = sorted[i];
      final unknown = LibraryMovie.isUnknownDate(d);
      final isRewatch = i > 0; // самый ранний просмотр — не повтор
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(isRewatch ? Icons.repeat_rounded : Icons.event_rounded,
                size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              unknown ? tr('when_unknown') : dateExactWithTime(d),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  color: scheme.onSurface),
            ),
            if (isRewatch) ...[
              const SizedBox(width: 8),
              _chip(scheme, Icons.repeat_rounded, tr('rewatch'), tone: true),
            ],
          ],
        ),
      ));
    }
    return rows;
  }

  Widget _statusChip(ColorScheme scheme, LibraryMovie m) {
    final (icon, label) = switch (m.status) {
      LibraryStatus.watched => (Icons.check_circle_rounded, tr('act_watched')),
      LibraryStatus.watchlist => (Icons.bookmark_rounded, tr('in_watchlist')),
      LibraryStatus.library => (Icons.movie_rounded, tr('app_name')),
    };
    return _chip(scheme, icon, label, primary: true);
  }

  Widget _chip(ColorScheme scheme, IconData icon, String label,
      {bool primary = false, bool tone = false}) {
    final bg = primary
        ? scheme.primaryContainer
        : (tone ? scheme.tertiaryContainer : scheme.surfaceContainerHighest);
    final fg = primary
        ? scheme.onPrimaryContainer
        : (tone ? scheme.onTertiaryContainer : scheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: fg)),
        ],
      ),
    );
  }

  Widget _scoreCard(ColorScheme scheme, LibraryMovie m) {
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
}
