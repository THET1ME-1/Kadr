import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/poster.dart';
import '../widgets/reveal.dart';
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

  TmdbDetails? _details;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final m = widget.movie;
    var id = m.tmdbId;
    if (id == null) {
      // Нет tmdbId (напр. сопоставлен через KinoPoisk) — ищем по названию+году.
      final match = await TmdbService.search(m.title, year: m.year);
      id = match?.tmdbId;
      if (id != null) _repo.setTmdbId(m.uuid, id);
    }
    if (id == null) return;
    final d = await TmdbService.details(id);
    if (mounted && d != null) setState(() => _details = d);
  }

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
      const SizedBox(height: 16),
      if (_details?.backdropUrl != null) _backdrop(scheme),
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
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: () => _manageListsSheet(m),
          icon: const Icon(Icons.playlist_add_rounded),
          label: Text(tr('manage_lists')),
        ),
      ),
      ..._detailsWidgets(scheme),
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

  // ------------------------ детали TMDB ------------------------
  Widget _backdrop(ColorScheme scheme) {
    return Reveal(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: _details!.backdropUrl!,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 350),
                  placeholder: (c, _) =>
                      Container(color: scheme.surfaceContainerHighest),
                  errorWidget: (c, u, e) =>
                      Container(color: scheme.surfaceContainerHighest),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        scheme.surfaceContainer.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _detailsWidgets(ColorScheme scheme) {
    final d = _details;
    if (d == null) return [];
    final facts = <Widget>[
      if (d.director != null && d.director!.isNotEmpty)
        _fact(scheme, Icons.movie_creation_rounded, tr('director'), d.director!),
      if (d.budget != null && d.budget! > 0)
        _fact(scheme, Icons.payments_rounded, tr('budget'), _money(d.budget!)),
      if (d.revenue != null && d.revenue! > 0)
        _fact(scheme, Icons.trending_up_rounded, tr('revenue'),
            _money(d.revenue!)),
    ];
    return [
      if (d.tagline != null) ...[
        const SizedBox(height: 18),
        Text('«${d.tagline!}»',
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant)),
      ],
      if (d.overview != null && d.overview!.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionTitle(scheme, tr('overview')),
        const SizedBox(height: 6),
        Text(d.overview!,
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                height: 1.45,
                color: scheme.onSurface)),
      ],
      if (d.genres.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final g in d.genres)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20)),
                child: Text(g,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: scheme.onSecondaryContainer)),
              ),
          ],
        ),
      ],
      if (d.cast.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionTitle(scheme, tr('cast')),
        const SizedBox(height: 12),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: d.cast.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (c, i) => Reveal(
              delay: Duration(milliseconds: i * 45),
              beginOffset: const Offset(0.15, 0),
              child: _castCard(scheme, d.cast[i]),
            ),
          ),
        ),
      ],
      if (facts.isNotEmpty) ...[
        const SizedBox(height: 16),
        ...facts,
      ],
    ];
  }

  Widget _sectionTitle(ColorScheme scheme, String title) => Text(title,
      style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: scheme.primary));

  Widget _castCard(ColorScheme scheme, TmdbCast c) {
    return SizedBox(
      width: 84,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: c.photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: c.photoUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (ctx, u, e) => Icon(Icons.person_rounded,
                        color: scheme.onSurfaceVariant, size: 34),
                  )
                : Icon(Icons.person_rounded,
                    color: scheme.onSurfaceVariant, size: 34),
          ),
          const SizedBox(height: 6),
          Text(c.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  height: 1.1,
                  color: scheme.onSurface)),
          if (c.character != null && c.character!.isNotEmpty)
            Text(c.character!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _fact(ColorScheme scheme, IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text('$label: ',
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    color: scheme.onSurfaceVariant)),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: scheme.onSurface)),
            ),
          ],
        ),
      );

  String _money(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '$buf \$';
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

  // ------------------ управление списками ------------------
  void _manageListsSheet(LibraryMovie m) {
    final scheme = Theme.of(context).colorScheme;
    final ctl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final lists = _repo.lists;
          final inLists = _repo.listsForMovie(m.uuid).toSet();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(tr('manage_lists'),
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: scheme.onSurface)),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (lists.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                            child: Text(tr('no_lists_yet'),
                                style: TextStyle(
                                    fontFamily: AppTheme.bodyFont,
                                    color: scheme.onSurfaceVariant)),
                          ),
                        for (final l in lists)
                          CheckboxListTile(
                            value: inLists.contains(l.name),
                            title: Text(l.name,
                                style: const TextStyle(
                                    fontFamily: AppTheme.bodyFont,
                                    fontWeight: FontWeight.w600)),
                            onChanged: (_) {
                              _repo.toggleInList(l.name, m.uuid);
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctl,
                            decoration: InputDecoration(hintText: tr('new_list')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: () {
                            _repo.createList(ctl.text, withMovieUuid: m.uuid);
                            ctl.clear();
                            setSheet(() {});
                          },
                          child: Text(tr('create')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
