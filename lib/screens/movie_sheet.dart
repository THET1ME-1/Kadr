import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/poster.dart';
import 'when_watched_sheet.dart';

/// Карточка фильма — выезжающая снизу панель (M3). Постер, мета, рейтинг КП,
/// общая оценка + ОЦЕНКА У КАЖДОГО ПРОСМОТРА (мнение меняется при пересмотре) со
/// сравнением. Обновляется на лету.
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

  /// Значение слайдера во время перетаскивания (иначе берём из модели).
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final m = _repo.byUuid(widget.movie.uuid) ?? widget.movie;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
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
                          m.kpRating!.toStringAsFixed(1)),
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
      if (m.hasScoreComparison) ...[
        const SizedBox(height: 22),
        _comparison(scheme, m),
      ],
      if (m.viewings.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text(tr('per_viewing_scores'),
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

  // ---- список просмотров: тап по строке = правка (дата+оценка+удаление) ----
  List<Widget> _viewingRows(ColorScheme scheme, LibraryMovie m) {
    final sorted = m.sortedViewings; // по возрастанию, неизвестные в конце
    final rows = <Widget>[];
    for (var i = sorted.length - 1; i >= 0; i--) {
      final v = sorted[i];
      final isRewatch = i > 0; // самый ранний просмотр — не повтор
      final sc = v.score;
      rows.add(Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editViewing(context, m, v, i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Icon(isRewatch ? Icons.repeat_rounded : Icons.event_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.hasDate
                            ? dateExactWithTime(v.date!)
                            : tr('when_unknown'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 14,
                            color: scheme.onSurface),
                      ),
                      if (isRewatch)
                        Text(trf('viewing_n', {'n': i + 1}),
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sc != null
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          sc != null
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 16,
                          color: sc != null
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        sc != null ? sc.toStringAsFixed(1) : tr('not_rated'),
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: sc != null
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.edit_rounded,
                    size: 17,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ));
    }
    return rows;
  }

  // ------------------ блок сравнения оценок ------------------
  Widget _comparison(ColorScheme scheme, LibraryMovie m) {
    final rated = m.sortedViewings.where((v) => v.score != null).toList();
    final delta = rated.last.score! - rated.first.score!;
    final verdict = delta.abs() < 0.05
        ? tr('cmp_same')
        : (delta > 0
            ? trf('cmp_improved', {'d': delta.toStringAsFixed(1)})
            : trf('cmp_dropped', {'d': (-delta).toStringAsFixed(1)}));
    final verdictColor = delta.abs() < 0.05
        ? scheme.onSurfaceVariant
        : (delta > 0 ? const Color(0xFF2E9B57) : const Color(0xFFD0433B));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('score_comparison'),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: scheme.onSurface)),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < rated.length; i++) ...[
                  if (i > 0) _arrow(scheme, rated[i].score! - rated[i - 1].score!),
                  _scorePill(scheme, rated[i], i),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                  delta.abs() < 0.05
                      ? Icons.drag_handle_rounded
                      : (delta > 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded),
                  size: 18,
                  color: verdictColor),
              const SizedBox(width: 6),
              Text(verdict,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: verdictColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scorePill(ColorScheme scheme, Viewing v, int i) => Column(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: scheme.primaryContainer, shape: BoxShape.circle),
            child: Text(v.score!.toStringAsFixed(1),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: scheme.onPrimaryContainer)),
          ),
          const SizedBox(height: 4),
          Text(
            v.hasDate ? numericDate(v.date!) : tr('when_unknown'),
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 10.5,
                color: scheme.onSurfaceVariant),
          ),
        ],
      );

  Widget _arrow(ColorScheme scheme, double d) {
    final up = d > 0.05, down = d < -0.05;
    final c = up
        ? const Color(0xFF2E9B57)
        : (down ? const Color(0xFFD0433B) : scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.arrow_forward_rounded, size: 18, color: c),
          Text(d == 0 ? '' : '${d > 0 ? '+' : ''}${d.toStringAsFixed(1)}',
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  color: c)),
        ],
      ),
    );
  }

  // ---- полный редактор просмотра: дата + оценка + удаление ----
  void _editViewing(
      BuildContext context, LibraryMovie m, Viewing v, int ordinal) {
    DateTime? date = v.date;
    bool rated = v.score != null;
    double val = v.score ?? m.score ?? 7.0;
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ordinal > 1 ? trf('viewing_n', {'n': ordinal}) : tr('edit_viewing'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: scheme.onSurface),
                  ),
                ),
                const SizedBox(height: 12),
                // дата и время
                Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: sheetCtx,
                        initialDate: date ?? now,
                        firstDate: DateTime(1900),
                        lastDate: now,
                      );
                      if (picked == null || !sheetCtx.mounted) return;
                      final time = await showTimePicker(
                        context: sheetCtx,
                        initialTime: TimeOfDay.fromDateTime(date ?? now),
                      );
                      setSheet(() => date = time == null
                          ? DateTime(picked.year, picked.month, picked.day)
                          : DateTime(picked.year, picked.month, picked.day,
                              time.hour, time.minute));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.event_rounded, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('date_time'),
                                    style: TextStyle(
                                        fontFamily: AppTheme.bodyFont,
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant)),
                                Text(
                                    date == null
                                        ? tr('when_unknown')
                                        : dateExactWithTime(date!),
                                    style: TextStyle(
                                        fontFamily: AppTheme.bodyFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: scheme.onSurface)),
                              ],
                            ),
                          ),
                          if (date != null)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: tr('clear_date'),
                              onPressed: () => setSheet(() => date = null),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // оценка
                Text(rated ? val.toStringAsFixed(1) : '—',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 46,
                        color: rated ? scheme.primary : scheme.onSurfaceVariant)),
                Text(tr('rate_this_viewing'),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant)),
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
                    IconButton.filledTonal(
                      onPressed: () {
                        _repo.removeViewing(m.uuid, v);
                        Navigator.pop(sheetCtx);
                        messenger.showSnackBar(SnackBar(
                            content: Text(tr('viewing_deleted')),
                            behavior: SnackBarBehavior.floating));
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      style: IconButton.styleFrom(
                          backgroundColor: scheme.errorContainer,
                          foregroundColor: scheme.onErrorContainer),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextButton(
                        onPressed: () => setSheet(() => rated = false),
                        child: Text(tr('remove_score')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          _repo.setViewingDate(m.uuid, v, date);
                          _repo.setViewingScore(m.uuid, v, rated ? val : null);
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

  /// Пишет оценку в текущий просмотр (или в общую, если просмотров ещё нет).
  void _commitCurrentScore(LibraryMovie m, double v) {
    final cv = m.currentViewing;
    if (cv != null) {
      _repo.setViewingScore(m.uuid, cv, v);
    } else {
      _repo.setScore(m.uuid, v);
    }
  }

  Widget _scoreCard(ColorScheme scheme, LibraryMovie m) {
    final val = _dragging ?? m.currentScore ?? 7.0;
    final rated = _dragging != null || m.currentScore != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(tr('current_viewing_score'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Icon(Icons.star_rounded,
                  color: scheme.onPrimaryContainer, size: 32),
              const SizedBox(width: 6),
              Text(
                val.toStringAsFixed(1),
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
            value: val,
            min: 1,
            max: 10,
            divisions: 90,
            label: val.toStringAsFixed(1),
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              _commitCurrentScore(m, v);
              setState(() => _dragging = null);
            },
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
