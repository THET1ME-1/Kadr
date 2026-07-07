import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../widgets/poster.dart';

/// Read-only просмотр фильма из библиотеки ДРУГА (без кнопок правки). Показывает
/// постер, мету, оценку и историю просмотров с оценками — как у себя, но смотреть.
void showReadonlyMovieSheet(BuildContext context, LibraryMovie m) {
  final scheme = Theme.of(context).colorScheme;
  final meta = [
    if (m.year != null) '${m.year}',
    if (m.runtimeMin != null) humanDuration(Duration(minutes: m.runtimeMin!)),
  ].join(' · ');
  final views = m.sortedViewings.reversed.toList();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _handle(scheme)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Poster(title: m.displayTitle, url: m.posterUrl, width: 92),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.displayTitle,
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              height: 1.1,
                              color: scheme.onSurface)),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(meta,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 13,
                                color: scheme.onSurfaceVariant)),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (m.currentScore != null)
                            _bigScore(m.currentScore!),
                          if (m.favorite) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.favorite_rounded,
                                size: 22, color: scheme.primary),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (m.genres.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in m.genres.take(6)) _chip(scheme, capitalize(g)),
                ],
              ),
            ],
            if (views.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(tr('nav_watched'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: scheme.primary)),
              const SizedBox(height: 8),
              for (final v in views) _viewingRow(scheme, m, v),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Read-only просмотр сериала друга: постер, оценка, прогресс и список
/// просмотренных серий с оценками (без правки).
void showReadonlySeriesSheet(BuildContext context, LibrarySeries s) {
  final scheme = Theme.of(context).colorScheme;
  final eps = [...s.episodes]..sort((a, b) {
      final sa = (a.season ?? 0).compareTo(b.season ?? 0);
      return sa != 0 ? sa : (a.number ?? 0).compareTo(b.number ?? 0);
    });

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _handle(scheme)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Poster(title: s.displayTitle, url: s.posterUrl, width: 92),
                    Positioned(
                      left: 5,
                      top: 5,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                            color: scheme.tertiary,
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.live_tv_rounded,
                            size: 13, color: scheme.onTertiary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
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
                      const SizedBox(height: 6),
                      Text(
                          [
                            if (s.year != null) '${s.year}',
                            trf('stat_eps_n', {'n': s.episodesSeen}),
                          ].join(' · '),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 13,
                              color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (s.displayScore != null) _bigScore(s.displayScore!),
                          if (s.favorite) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.favorite_rounded,
                                size: 22, color: scheme.primary),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: eps.length,
                itemBuilder: (ctx, i) => _episodeRow(scheme, eps[i]),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ------------------------------ вспомогательное ------------------------------

Widget _handle(ColorScheme scheme) => Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
        color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)));

Widget _bigScore(double score) {
  final c = scoreColor(score);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 18, color: onScoreColor(score)),
        const SizedBox(width: 4),
        Text(score.toStringAsFixed(1),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: onScoreColor(score))),
      ],
    ),
  );
}

Widget _chip(ColorScheme scheme, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16)),
      child: Text(label,
          style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: scheme.onSurfaceVariant)),
    );

Widget _viewingRow(ColorScheme scheme, LibraryMovie m, Viewing v) {
  final sc = m.scoreOf(v);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(Icons.visibility_rounded, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              v.date != null ? dateExactWithTime(v.date!) : tr('when_unknown'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13.5,
                  color: scheme.onSurface)),
        ),
        if (sc != null) _miniScore(scheme, sc),
      ],
    ),
  );
}

Widget _episodeRow(ColorScheme scheme, Episode e) {
  final sc = e.score;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(Icons.play_circle_outline_rounded,
            size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        SizedBox(
          width: 96,
          child: Text(e.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: scheme.onSurface)),
        ),
        if (e.watchedAt != null)
          Expanded(
            child: Text(dateExactWithTime(e.watchedAt!),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.85))),
          )
        else
          const Spacer(),
        if (sc != null) _miniScore(scheme, sc),
      ],
    ),
  );
}

Widget _miniScore(ColorScheme scheme, double score) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: scoreColor(score), borderRadius: BorderRadius.circular(14)),
      child: Text(score.toStringAsFixed(1),
          style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: onScoreColor(score))),
    );
