import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/app_prefs.dart';
import '../../services/movie_repository.dart';
import '../../services/store.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../utils/season_reviews.dart';
import '../../widgets/review/review_parts.dart';
import '../../widgets/review/review_rows.dart';
import '../../widgets/review/reviews_table.dart';
import '../../widgets/settings_kit.dart';
import '../../widgets/viewing/view_chip.dart';
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
    ReviewTarget.series(series,
        repo: repo, from: scope.from, to: scope.to, pass: scope.pass),
  );
}

/// Подтверждение перед «Выставить сериалу»: оценка сериала сменится на
/// [value]. [current] — нынешняя средняя по сериям, если есть.
Future<bool> confirmSetSeriesScore(BuildContext context,
    {required double value, double? current}) async {
  final scheme = Theme.of(context).colorScheme;
  final v = value.toStringAsFixed(1);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.rate_review_rounded, color: scheme.primary, size: 32),
      title: Text(trf('rvs_set_confirm_title', {'v': v})),
      content: Text(current == null
          ? trf('rvs_set_confirm_body_plain', {'v': v})
          : trf('rvs_set_confirm_body',
              {'v': v, 'e': current.toStringAsFixed(1)})),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('rvs_set_confirm_ok')),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Рецензии на одни и те же сезоны: последняя по просмотру и прошлые.
class _ScopeGroup {
  /// Рецензия на последний просмотр; у рецензии на весь сериал она одна.
  final ReviewTarget latest;

  /// Рецензии на прошлые просмотры этих сезонов, свежие сверху.
  final List<ReviewTarget> earlier;
  const _ScopeGroup(this.latest, [this.earlier = const []]);
}

/// Рецензии на экране сериала (вариант A макета): список с охватом в
/// таблетке и карточка свода — средняя по сериям против средней по
/// рецензиям, сравнение по сезонам и «Выставить сериалу».
///
/// Рецензия на пересмотр несёт таблетку с номером просмотра, прошлые
/// рецензии на те же сезоны стоят под ней короткой строкой. Когда у сезона
/// есть рецензии на два просмотра, в своде появляется вкладка «Пересмотры».
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

  static const collapsedKey = AppPrefs.seriesReviewsCollapsedKey;

  /// Сериалы, у которых человек убрал кнопку «Выставить сериалу» крестиком.
  static const hiddenSetKey = 'seriesReviewsSetHidden';

  @override
  State<SeriesReviewsSection> createState() => _SeriesReviewsSectionState();
}

class _SeriesReviewsSectionState extends State<SeriesReviewsSection> {
  // Ответ известен сразу, см. [AppPrefs.movieReviewsCollapsed]: блок не
  // должен менять высоту после того, как появился.
  bool _collapsed = AppPrefs.instance.seriesReviewsCollapsed;
  bool _setHidden = false;

  LibrarySeries get series => widget.series;
  MovieRepository get repo => widget.repo;
  List<TmdbSeason> get seasons => widget.seasons;

  @override
  void initState() {
    super.initState();
    Store.instance.getStringList(SeriesReviewsSection.hiddenSetKey).then((l) {
      final v = l.contains(series.tvShowId);
      if (mounted && v != _setHidden) setState(() => _setHidden = v);
    });
  }

  Future<void> _saveHidden(bool hidden) async {
    final list = [
      ...await Store.instance.getStringList(SeriesReviewsSection.hiddenSetKey),
    ]..remove(series.tvShowId);
    if (hidden) list.add(series.tvShowId);
    await Store.instance.setStringList(SeriesReviewsSection.hiddenSetKey, list);
  }

  /// Крестик у «Выставить сериалу»: прячет кнопку у этого сериала.
  Future<void> _hideSet() async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.visibility_off_rounded,
            color: scheme.onSurfaceVariant, size: 32),
        title: Text(tr('rvs_hide_title')),
        content: Text(tr('rvs_hide_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('rvs_hide_ok')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _setHidden = true);
    await _saveHidden(true);
  }

  Future<void> _showSet() async {
    HapticFeedback.selectionClick();
    setState(() => _setHidden = false);
    await _saveHidden(false);
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _collapsed = !_collapsed);
    AppPrefs.instance.setSeriesReviewsCollapsed(_collapsed);
  }

  /// Рецензии по охвату: на каждые сезоны последняя и прошлые, в конце
  /// рецензия на весь сериал.
  List<_ScopeGroup> get _groups {
    final byScope = <String, List<SeasonReview>>{};
    for (final p in series.seasonReviews) {
      if (p.hasReview) byScope.putIfAbsent('${p.from}-${p.to}', () => []).add(p);
    }
    ReviewTarget of(SeasonReview p) =>
        ReviewTarget.series(series, repo: repo, part: p);
    return [
      for (final parts in byScope.values)
        () {
          final sorted = [...parts]..sort((a, b) => b.pass.compareTo(a.pass));
          return _ScopeGroup(
              of(sorted.first), [for (final p in sorted.skip(1)) of(p)]);
        }(),
      if (series.hasReview) _ScopeGroup(ReviewTarget.series(series, repo: repo)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    void write() =>
        startSeriesReview(context, series, seasons: seasons, repo: repo);
    if (groups.isEmpty) {
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
    final count = groups.fold(0, (n, g) => n + 1 + g.earlier.length);
    final hasSummary = reviewsAverage(series) != null;
    final rv = reviewsAverage(series);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewsHeader(
            count: count,
            collapsed: _collapsed,
            onToggle: _toggle,
            onWrite: write,
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: AppTheme.emphasized,
            alignment: Alignment.topCenter,
            child: _collapsed
                // В свёрнутой строке от каждых сезонов одна рецензия:
                // последняя, она же идёт в свод.
                ? ReviewsFolded(
                    items: [
                      for (final g in groups)
                        (
                          chip: ScopeChip(g.latest.scopeShortLabel!,
                              whole: !g.latest.isPart),
                          score: g.latest.meta?.average,
                        ),
                    ],
                    total: rv == null
                        ? null
                        : trf('rvs_summary_short',
                            {'v': rv.toStringAsFixed(1)}),
                    onOpen: _toggle,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _unfolded(groups, count, hasSummary),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _unfolded(List<_ScopeGroup> groups, int count, bool hasSummary) {
    final rows = <Widget>[];
    var i = 0;
    void add(Widget Function(BorderRadius) build) {
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : SettingsGroup.gap),
        child: build(groupBlockRadius(i, count, outer: 24)),
      ));
      i++;
    }

    for (final g in groups) {
      // Номер просмотра виден у рецензии на пересмотр и когда на эти сезоны
      // рецензий несколько.
      final showPass =
          g.latest.isPart && (g.latest.pass > 1 || g.earlier.isNotEmpty);
      add((r) => _ReviewRow(
          target: g.latest, seasons: seasons, radius: r, showPass: showPass));
      for (final t in g.earlier) {
        add((r) => _PrevRow(target: t, radius: r));
      }
    }
    return [
      ...rows,
      if (hasSummary) ...[
        const SizedBox(height: 12),
        _Summary(
          series: series,
          repo: repo,
          setHidden: _setHidden,
          onHideSet: _hideSet,
          onShowSet: _showSet,
        ),
      ],
    ];
  }
}

void _openTarget(BuildContext context, ReviewTarget target) =>
    (target.meta?.draft ?? false)
        ? openReviewEditor(context, target)
        : openReview(context, target);

/// Строка рецензии: охват, номер просмотра, вердикт, заголовок, дата и
/// средняя по пунктам.
class _ReviewRow extends StatelessWidget {
  final ReviewTarget target;
  final List<TmdbSeason> seasons;
  final BorderRadius radius;
  final bool showPass;
  const _ReviewRow({
    required this.target,
    required this.seasons,
    required this.radius,
    required this.showPass,
  });

  @override
  Widget build(BuildContext context) {
    final meta = target.meta;
    final title = meta?.title?.trim();
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
    return ReviewRowTile(
      chips: [
        ScopeChip(target.scopeShortLabel!, whole: !target.isPart),
        if (showPass) ViewChip(ordinalShort(target.pass)),
      ],
      verdict: meta?.verdict,
      title: title == null || title.isEmpty ? tr('rv_untitled') : title,
      sub: sub,
      score: meta?.average,
      radius: radius,
      onTap: () => _openTarget(context, target),
    );
  }
}

/// Прошлая рецензия на те же сезоны: короткая строка под новой.
class _PrevRow extends StatelessWidget {
  final ReviewTarget target;
  final BorderRadius radius;
  const _PrevRow({required this.target, required this.radius});

  @override
  Widget build(BuildContext context) {
    final title = target.meta?.title?.trim();
    return ReviewPrevTile(
      chip: ViewChip(ordinalShort(target.pass), tone: ViewChipTone.plain),
      title: title == null || title.isEmpty ? tr('rv_untitled') : title,
      score: target.meta?.average,
      radius: radius,
      onTap: () => _openTarget(context, target),
    );
  }
}

/// Карточка свода: по сериям против по рецензиям, вывод, сравнение по
/// сезонам и «Выставить сериалу». С рецензиями на пересмотр — вторая
/// вкладка «Пересмотры»: сезоны по просмотрам.
class _Summary extends StatefulWidget {
  final LibrarySeries series;
  final MovieRepository repo;

  /// Кнопку «Выставить сериалу» убрали крестиком: вместо неё значок в
  /// заголовке, который её возвращает.
  final bool setHidden;
  final VoidCallback onHideSet;
  final VoidCallback onShowSet;
  const _Summary({
    required this.series,
    required this.repo,
    required this.setHidden,
    required this.onHideSet,
    required this.onShowSet,
  });

  @override
  State<_Summary> createState() => _SummaryState();
}

class _SummaryState extends State<_Summary> {
  bool _passes = false;

  LibrarySeries get series => widget.series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rv = reviewsAverage(series)!;
    final ep = series.episodeScoreAvg;
    final applied = series.scoreSource == SeriesScoreSource.reviews;
    final table = passTable(series);
    final showPasses = _passes && table != null;
    final eye = widget.setHidden && !applied
        ? SizedBox(
            height: 24,
            child: IconButton(
              onPressed: widget.onShowSet,
              tooltip: tr('rvs_show_set'),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: Icon(Icons.visibility_rounded,
                  color: scheme.onSurfaceVariant),
            ),
          )
        : null;
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
          if (table != null)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: _Tabs(
                    passes: showPasses,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _passes = v);
                    },
                  ),
                ),
                ?eye,
              ],
            )
          else
            Row(
              children: [
                Expanded(child: ReviewCaps(tr('rvs_summary'))),
                ?eye,
              ],
            ),
          if (showPasses) ..._passesTab(scheme, table) else ..._mainTab(scheme, rv, ep),
          if (applied)
            Text(tr('rvs_score_from_summary'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: scheme.primary))
          else if (!widget.setHidden)
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      HapticFeedback.selectionClick();
                      if (!await confirmSetSeriesScore(context,
                          value: rv, current: ep ?? series.score)) {
                        return;
                      }
                      await widget.repo.setSeriesScoreSource(
                          series.tvShowId, SeriesScoreSource.reviews);
                    },
                    child: Text(
                        trf('rvs_set_series', {'v': rv.toStringAsFixed(1)})),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: widget.onHideSet,
                  tooltip: tr('rvs_hide_set'),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(56, 56),
                    backgroundColor: scheme.surfaceContainerHighest,
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// «Серии и рецензии»: две средние, вывод и полосы по сезонам.
  List<Widget> _mainTab(ColorScheme scheme, double rv, double? ep) {
    final delta = reviewsDeltaLine(series);
    final rows = compareSeasons(series);
    return [
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
            _Key(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                label: tr('rvs_key_episodes')),
            _Key(color: scoreColor(rv), label: tr('rvs_key_review')),
          ],
        ),
    ];
  }

  /// «Пересмотры»: первый раз против последнего и таблица сезонов по
  /// просмотрам.
  List<Widget> _passesTab(ColorScheme scheme, PassTable table) {
    final d = table.delta;
    final head = d == 0
        ? tr('rvs_pass_same')
        : trf(d > 0 ? 'rvs_pass_up' : 'rvs_pass_down',
            {'d': d.abs().toStringAsFixed(1)});
    final strongest = table.strongest;
    final line = strongest == null
        ? head
        : '$head ${trf('rvs_pass_most', {'n': strongest})}';
    return [
      BeforeAfterTiles(
        beforeLabel: tr('rvs_pass_first'),
        before: table.first,
        afterLabel: tr('rvs_pass_last'),
        after: table.last,
      ),
      Text(line,
          style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: scheme.onSurfaceVariant)),
      ReviewsGrid(
        boxedHeader: false,
        displayLabels: true,
        labelWidth: 52,
        columns: [
          for (var pass = 1; pass <= table.passes; pass++)
            GridColumn(ordinal: pass),
        ],
        rows: [
          for (final r in table.rows)
            GridRowData(
              label: 'S${r.season}',
              delta: r.delta,
              cells: [
                for (final c in r.cells)
                  GridCell(
                    value: c.value,
                    highlight: c.inSummary,
                    missing: c.missing,
                    none: c.none,
                  ),
              ],
            ),
        ],
      ),
      Text(tr('rvs_pass_note'),
          style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 12.5,
              color: scheme.onSurfaceVariant)),
    ];
  }
}

/// Переключатель вкладок свода.
class _Tabs extends StatelessWidget {
  final bool passes;
  final ValueChanged<bool> onChanged;
  const _Tabs({required this.passes, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget seg(String label, bool value) {
      final on = passes == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on ? scheme.primaryContainer : Colors.transparent,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onChanged(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                // Длинная подпись («Folgen und Kritiken») ужимается, а не
                // обрезается: вкладок всего две, и обе должны читаться.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: on
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        spacing: 4,
        children: [
          seg(tr('rvs_tab_main'), false),
          seg(tr('rvs_tab_passes'), true),
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
