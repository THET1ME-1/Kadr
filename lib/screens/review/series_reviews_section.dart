import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/movie_repository.dart';
import '../../services/store.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../utils/season_reviews.dart';
import '../../widgets/review/review_parts.dart';
import '../../widgets/review/verdict_badge.dart';
import '../../widgets/settings_kit.dart';
import 'review_editor_screen.dart';
import 'review_scope_sheet.dart';
import 'review_screen.dart';
import 'review_target.dart';

/// Новая рецензия на сериал: сначала «О чём рецензия», потом редактор.
Future<void> startSeriesReview(BuildContext context, LibrarySeries series,
    {required List<TmdbSeason> seasons, MovieRepository? repo}) async {
  final scope =
      await showReviewScopeSheet(context, series: series, seasons: seasons);
  if (scope == null || !context.mounted) return;
  await openReviewEditor(
    context,
    ReviewTarget.series(series, repo: repo, from: scope.from, to: scope.to),
  );
}

/// Рецензии на экране сериала (вариант A макета): список с охватом в
/// таблетке и карточка свода — средняя по сериям против средней по
/// рецензиям, сравнение по сезонам и «Выставить сериалу».
///
/// Блок сворачивается в одну строку «S1 8.6 · S2–S3 9.2 · Свод 8.8», чтобы
/// до сезонов не листать. Состояние одно на все сериалы, ключ в `Store`.
class SeriesReviewsSection extends StatefulWidget {
  final LibrarySeries series;
  final MovieRepository repo;
  final List<TmdbSeason> seasons;

  const SeriesReviewsSection({
    super.key,
    required this.series,
    required this.repo,
    required this.seasons,
  });

  static const collapsedKey = 'seriesReviewsCollapsed';

  @override
  State<SeriesReviewsSection> createState() => _SeriesReviewsSectionState();
}

class _SeriesReviewsSectionState extends State<SeriesReviewsSection> {
  bool _collapsed = false;

  LibrarySeries get series => widget.series;
  MovieRepository get repo => widget.repo;
  List<TmdbSeason> get seasons => widget.seasons;

  @override
  void initState() {
    super.initState();
    Store.instance.getBool(SeriesReviewsSection.collapsedKey).then((v) {
      if (mounted && v != _collapsed) setState(() => _collapsed = v);
    });
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _collapsed = !_collapsed);
    Store.instance.setBool(SeriesReviewsSection.collapsedKey, _collapsed);
  }

  List<ReviewTarget> get _targets => [
        for (final p in series.seasonReviews)
          if (p.hasReview) ReviewTarget.series(series, repo: repo, part: p),
        if (series.hasReview) ReviewTarget.series(series, repo: repo),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final targets = _targets;
    void write() =>
        startSeriesReview(context, series, seasons: seasons, repo: repo);
    if (targets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: write,
            icon: const Icon(Icons.rate_review_rounded),
            label: Text(tr('write_review')),
          ),
        ),
      );
    }
    final hasSummary = reviewsAverage(series) != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                        trf('rvs_my_reviews', {'n': targets.length}),
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: scheme.primary)),
                  ),
                ),
              ),
              IconButton(
                onPressed: _toggle,
                tooltip: tr(_collapsed ? 'rvs_expand' : 'rvs_collapse'),
                icon: AnimatedRotation(
                  turns: _collapsed ? 0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  curve: AppTheme.emphasized,
                  child: Icon(Icons.expand_more_rounded,
                      color: scheme.onSurfaceVariant),
                ),
              ),
              TextButton.icon(
                onPressed: write,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('rvs_write')),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: AppTheme.emphasized,
            alignment: Alignment.topCenter,
            child: _collapsed
                ? _Folded(targets: targets, series: series, onOpen: _toggle)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _unfolded(targets, hasSummary),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _unfolded(List<ReviewTarget> targets, bool hasSummary) => [
          for (var i = 0; i < targets.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : SettingsGroup.gap),
              child: _ReviewRow(
                target: targets[i],
                seasons: seasons,
                radius: groupBlockRadius(i, targets.length, outer: 24),
              ),
            ),
          if (hasSummary) ...[
            const SizedBox(height: 12),
            _Summary(series: series, repo: repo),
          ],
      ];
}

/// Свёрнутый блок: охват и средняя каждой рецензии в строку, справа свод.
/// Тап разворачивает.
class _Folded extends StatelessWidget {
  final List<ReviewTarget> targets;
  final LibrarySeries series;
  final VoidCallback onOpen;
  const _Folded(
      {required this.targets, required this.series, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rv = reviewsAverage(series);
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          // Пары «охват + средняя» и свод одним переносом: справа отдельной
          // колонкой свод отнимал место, и «Весь сериал 9.0» вылезал.
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in targets)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 5,
                  children: [
                    _ScopeChip(target: t),
                    Text(t.meta?.average?.toStringAsFixed(1) ?? '—',
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: t.meta?.average != null
                                ? scoreColor(t.meta!.average!)
                                : scheme.onSurfaceVariant)),
                  ],
                ),
              if (rv != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                      trf('rvs_summary_short', {'v': rv.toStringAsFixed(1)}),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: scheme.onPrimaryContainer)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка рецензии: охват, вердикт, заголовок, дата и средняя по пунктам.
class _ReviewRow extends StatelessWidget {
  final ReviewTarget target;
  final List<TmdbSeason> seasons;
  final BorderRadius radius;
  const _ReviewRow(
      {required this.target, required this.seasons, required this.radius});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = target.meta;
    final title = meta?.title?.trim();
    final score = meta?.average;
    final date = meta?.shownDate;
    final eps = target.isPart
        ? seasons
            .where((s) => s.number >= target.from! && s.number <= target.to!)
            .fold(0, (sum, s) => sum + s.episodeCount)
        : 0;
    final sub = [
      if (date != null) '${dayMonth(date)} ${date.year}',
      if (eps > 0) trn('ss_episodes', eps),
      if (!target.isPart) tr('rvs_not_in_summary'),
      if (meta?.draft ?? false) tr('rvs_draft'),
    ].join(' · ');
    final draft = meta?.draft ?? false;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => draft
            ? openReviewEditor(context, target)
            : openReview(context, target),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _ScopeChip(target: target),
                        if (meta?.verdict != null)
                          VerdictBadge(meta!.verdict!, small: true),
                      ],
                    ),
                    Text(
                        title == null || title.isEmpty
                            ? tr('rv_untitled')
                            : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.25,
                            color: scheme.onSurface)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 12,
                              color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Text(score != null ? score.toStringAsFixed(1) : '—',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: score != null
                          ? scoreColor(score)
                          : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Таблетка охвата: «S2–S3» на тоне secondary, «Весь сериал» нейтральная.
class _ScopeChip extends StatelessWidget {
  final ReviewTarget target;
  const _ScopeChip({required this.target});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final part = target.isPart;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            part ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(target.scopeShortLabel!,
          style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: part ? scheme.onSecondaryContainer : scheme.onSurface)),
    );
  }
}

/// Карточка свода: по сериям против по рецензиям, вывод, сравнение по
/// сезонам и «Выставить сериалу».
class _Summary extends StatelessWidget {
  final LibrarySeries series;
  final MovieRepository repo;
  const _Summary({required this.series, required this.repo});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rv = reviewsAverage(series)!;
    final ep = series.episodeScoreAvg;
    final delta = reviewsDeltaLine(series);
    final rows = compareSeasons(series);
    final applied = series.scoreSource == SeriesScoreSource.reviews;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          ReviewCaps(tr('rvs_summary')),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: _Box(
                  icon: Icons.play_arrow_rounded,
                  label: tr('rvs_episodes_box'),
                  value: ep,
                  bg: scheme.surfaceContainer,
                  fg: scheme.onSurface,
                  colorValue: true,
                ),
              ),
              Expanded(
                child: _Box(
                  icon: Icons.rate_review_rounded,
                  label: tr('rvs_by_reviews'),
                  value: rv,
                  bg: scheme.primaryContainer,
                  fg: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          if (delta != null)
            Text(delta,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant)),
          if (rows.isNotEmpty)
            Column(
              spacing: 10,
              children: [for (final r in rows) _CompareRow(row: r)],
            ),
          if (rows.isNotEmpty)
            Wrap(
              spacing: 14,
              children: [
                _Key(color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                    label: tr('rvs_key_episodes')),
                _Key(color: scoreColor(rv), label: tr('rvs_key_review')),
              ],
            ),
          if (applied)
            Text(tr('rvs_score_from_summary'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: scheme.primary))
          else
            FilledButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                repo.setSeriesScoreSource(
                    series.tvShowId, SeriesScoreSource.reviews);
              },
              child: Text(trf('rvs_set_series', {'v': rv.toStringAsFixed(1)})),
            ),
          Text(tr('rvs_summary_note'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  final IconData icon;
  final String label;
  final double? value;
  final Color bg, fg;

  /// Число окрашено цветом оценки, как в остальном приложении.
  final bool colorValue;
  const _Box({
    required this.icon,
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
    this.colorValue = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            spacing: 5,
            children: [
              Icon(icon, size: 15, color: fg.withValues(alpha: 0.85)),
              Expanded(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: fg.withValues(alpha: 0.85))),
              ),
            ],
          ),
          Text(v != null ? v.toStringAsFixed(1) : '—',
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  height: 1,
                  color: v != null && colorValue ? scoreColor(v) : fg)),
        ],
      ),
    );
  }
}

/// Сезон: две полосы (серии и рецензия), числа и разница.
class _CompareRow extends StatelessWidget {
  final SeasonCompare row;
  const _CompareRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ep = row.episodes, rv = row.review;
    final d = ep != null && rv != null ? ((rv - ep) * 10).round() / 10 : null;
    final sign = d == null ? '' : (d > 0 ? '+' : (d < 0 ? '−' : '±'));
    return Row(
      spacing: 10,
      children: [
        SizedBox(
          width: 34,
          child: Text('S${row.season}',
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: scheme.onSurface)),
        ),
        Expanded(
          child: Column(
            spacing: 4,
            children: [
              ScoreBar(
                  value: ep,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                  height: 6),
              ScoreBar(
                  value: rv,
                  color: rv != null ? scoreColor(rv) : Colors.transparent,
                  height: 6),
            ],
          ),
        ),
        SizedBox(
          width: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: ep != null ? ep.toStringAsFixed(1) : '—'),
                  const TextSpan(text: ' → '),
                  TextSpan(
                      text: rv != null ? rv.toStringAsFixed(1) : '—',
                      style: TextStyle(
                          color: rv != null ? scoreColor(rv) : null)),
                ]),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: scheme.onSurface),
              ),
              if (d != null)
                Text('$sign${d.abs().toStringAsFixed(1)}',
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  final Color color;
  final String label;
  const _Key({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Container(
            width: 16,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Text(label,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}
