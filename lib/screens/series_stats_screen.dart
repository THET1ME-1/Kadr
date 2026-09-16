import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../utils/series_stats.dart';

/// Статистика одного сериала: сверху выбор «Все / S1…» и карточка «Время у
/// экрана», ниже путь по сезонам — даты, время, оценки, паузы и главный
/// факт каждого сезона. Открывается из меню ⋮ экрана сериала.
class SeriesStatsScreen extends StatefulWidget {
  const SeriesStatsScreen({
    super.key,
    required this.series,
    this.seasons = const [],
    this.tmdbId,
    this.preloaded,
  });

  final LibrarySeries series;

  /// Структура сезонов, как её показывает экран сериала.
  final List<TmdbSeason> seasons;
  final int? tmdbId;

  /// Серии TMDB по сезонам, если уже есть (тесты). Иначе грузятся здесь.
  final Map<int, List<TmdbEpisode>>? preloaded;

  @override
  State<SeriesStatsScreen> createState() => _SeriesStatsScreenState();
}

class _SeriesStatsScreenState extends State<SeriesStatsScreen> {
  final _repo = MovieRepository.instance;
  Map<int, List<TmdbEpisode>> _tmdb = const {};

  /// Выбранный сезон; null — сериал целиком.
  int? _selected;

  @override
  void initState() {
    super.initState();
    final pre = widget.preloaded;
    if (pre != null) {
      _tmdb = pre;
    } else {
      _loadEpisodes();
    }
  }

  /// Серии всех сезонов: длительность, названия и даты выхода. Кэш TMDB
  /// общий с экраном сериала, поэтому открытые сезоны не качаются заново.
  Future<void> _loadEpisodes() async {
    final id = widget.tmdbId;
    if (id == null || widget.seasons.isEmpty) return;
    final lists = await Future.wait(
      widget.seasons.map((s) => TmdbService.episodesOf(id, s.number)),
    );
    if (!mounted) return;
    setState(() {
      _tmdb = {
        for (var i = 0; i < widget.seasons.length; i++)
          if (lists[i].isNotEmpty) widget.seasons[i].number: lists[i],
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final series =
            _repo.seriesById(widget.series.tvShowId) ?? widget.series;
        final st = computeSeriesStats(
          episodes: series.episodes,
          seasons: widget.seasons,
          tmdb: _tmdb,
        );
        final selected = _selected != null && st.season(_selected!) != null
            ? _selected
            : null;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('drawer_stats')),
                Text(
                  series.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          body: st.watched == 0
              ? _empty(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    if (st.seasons.length > 1) ...[
                      _chips(context, st, selected),
                      const SizedBox(height: 12),
                    ],
                    _hero(
                      context,
                      selected == null ? st : st.season(selected)!,
                      season: selected != null,
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 14),
                      child: Text(
                        tr('ss_timeline'),
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    ..._timeline(context, st, selected),
                    if (selected == null && st.undated > 0) ...[
                      const SizedBox(height: 20),
                      _undatedNote(context, st.undated),
                    ],
                  ],
                ),
        );
      },
    );
  }

  // ------------------------------------------------------------ выбор

  Widget _chips(BuildContext context, SeriesStats st, int? selected) {
    void pick(int? season) {
      if (season == selected) return;
      HapticFeedback.selectionClick();
      setState(() => _selected = season);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(context, tr('filter_all'), selected == null, () => pick(null)),
          for (final s in st.seasons)
            _chip(
              context,
              'S${s.season}',
              selected == s.season,
              () => pick(s.season),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        shape: const StadiumBorder(),
        side: BorderSide(color: on ? scheme.primary : scheme.outlineVariant),
        color: WidgetStatePropertyAll(on ? scheme.primary : Colors.transparent),
        labelStyle: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 14,
          fontWeight: on ? FontWeight.w700 : FontWeight.w600,
          color: on ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ герой

  Widget _hero(BuildContext context, StatsSummary sum, {required bool season}) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onPrimary;
    final h = sum.minutes ~/ 60;
    final m = sum.minutes % 60;
    final approx = sum.minutes >= 1440
        ? trn('ss_nonstop_days', (sum.minutes / 1440).round())
        : sum.minutes >= 90
        ? trn('ss_like_movies', (sum.minutes / 120).round())
        : null;
    final progress = sum.aired == 0
        ? 0.0
        : (sum.watched / sum.aired).clamp(0.0, 1.0);
    const big = TextStyle(
      fontFamily: AppTheme.displayFont,
      fontWeight: FontWeight.w800,
      fontSize: 58,
      height: 1,
    );
    final unit = TextStyle(
      fontFamily: AppTheme.displayFont,
      fontWeight: FontWeight.w700,
      fontSize: 22,
      color: fg,
    );
    final from = sum.from, to = sum.to;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(28),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontFamily: AppTheme.bodyFont, color: fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('ss_screen_time'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: sum.minutes == 0
                  ? Text(
                      trn('ss_episodes', sum.watched),
                      style: big.copyWith(fontSize: 40, color: fg),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (sum.estimated)
                          Text('≈ ', style: unit.copyWith(fontSize: 34)),
                        if (h > 0) ...[
                          Text('$h', style: big.copyWith(color: fg)),
                          const SizedBox(width: 6),
                          Text(tr('stat_hours_unit'), style: unit),
                          const SizedBox(width: 12),
                        ],
                        Text('$m', style: big.copyWith(color: fg)),
                        const SizedBox(width: 6),
                        Text(tr('ss_min_unit'), style: unit),
                      ],
                    ),
            ),
            if (approx != null) ...[
              const SizedBox(height: 6),
              Text(
                approx,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (from != null && to != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _span(from, to),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    trn('ss_days', sum.spanDays),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: fg.withValues(alpha: 0.22)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: fg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              trn(
                season ? 'ss_of_season_episodes' : 'ss_of_episodes',
                sum.aired,
                {'a': sum.watched},
              ),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: fg.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// «3 фев — 22 мар 2026»; год у начала, только если годы разные.
  String _span(DateTime from, DateTime to) {
    if (from.year == to.year && from.month == to.month && from.day == to.day) {
      return '${dayMonth(from)} ${from.year}';
    }
    if (from.year == to.year) {
      return '${dayMonth(from)} — ${dayMonth(to)} ${to.year}';
    }
    return '${dayMonth(from)} ${from.year} — ${dayMonth(to)} ${to.year}';
  }

  // ------------------------------------------------------------ путь

  List<Widget> _timeline(BuildContext context, SeriesStats st, int? selected) {
    if (selected != null) {
      return [_chapter(context, st, st.season(selected)!, rail: false)];
    }
    final rows = <_Row>[];
    final first = st.first;
    if (first != null) {
      rows.add(
        _Row(
          node: _dot(context),
          pad: 22,
          content: [
            _caption(context, _moment(first.at)),
            _strong(
              trf('ss_started', {'t': _title(first.season, first.number)}),
            ),
          ],
        ),
      );
    }
    for (final s in st.seasons) {
      rows.add(_Row.chapter(s));
      for (final p in st.pauses) {
        if (p.afterSeason == s.season) rows.add(_Row.pause(p));
      }
    }
    final last = st.last;
    if (last != null) {
      final t = _title(last.season, last.number);
      rows.add(
        _Row(
          node: st.finished ? _flag(context) : _dot(context),
          pad: 22,
          content: [
            _caption(context, _moment(last.at)),
            _strong(
              st.finished
                  ? trf('ss_finished', {'t': t})
                  : trf('ss_last', {'t': t}),
            ),
          ],
        ),
      );
    }
    final rw = st.topRewatch;
    if (rw != null) {
      rows.add(
        _Row(
          node: _dot(context),
          pad: 0,
          content: [
            _strong(
              trn('ss_rewatched', rw.times, {
                't': _title(rw.season, rw.number),
              }),
            ),
          ],
        ),
      );
    }

    return [
      for (var i = 0; i < rows.length; i++)
        _build(context, st, rows[i], rail: i < rows.length - 1),
    ];
  }

  Widget _build(
    BuildContext context,
    SeriesStats st,
    _Row row, {
    required bool rail,
  }) {
    final chapter = row.chapter;
    if (chapter != null) return _chapter(context, st, chapter, rail: rail);
    final pause = row.pause;
    if (pause != null) return _pause(context, pause);
    return _railRow(
      context,
      node: row.node!,
      content: row.content,
      rail: rail,
      pad: row.pad,
    );
  }

  Widget _chapter(
    BuildContext context,
    SeriesStats st,
    SeasonStats s, {
    required bool rail,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final from = s.from, to = s.to;
    final dates = from != null && to != null
        ? '${_range(from, to)} · ${trn('ss_days', s.spanDays)}'
        : null;
    final facts = [
      trn('ss_episodes', s.watched),
      if (s.minutes > 0) _duration(s.minutes, s.estimated),
      if (s.avgScore != null) trf('ss_avg', {'v': _score(s.avgScore!)}),
    ].join(' · ');
    final hl = st.highlightFor(s.season);

    return _railRow(
      context,
      rail: rail,
      node: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${s.season}',
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
      content: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            runSpacing: 2,
            children: [
              Text(
                trf('season_n', {'n': s.season}),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: scheme.onSurface,
                ),
              ),
              if (dates != null)
                Text(
                  dates,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
        ),
        _caption(context, facts),
        _spark(context, s),
        if (hl != null) _highlight(context, hl, s.season),
      ],
    );
  }

  /// Оценки серий сезона столбиками, по порядку серий.
  Widget _spark(BuildContext context, SeasonStats s) {
    final scheme = Theme.of(context).colorScheme;
    final gap = s.marks.length > 40 ? 0.5 : 1.5;
    return ExcludeSemantics(
      child: SizedBox(
        height: 30,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final m in s.marks)
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 14),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap),
                    child: FractionallySizedBox(
                      widthFactor: 1,
                      heightFactor: _barHeight(m),
                      alignment: Alignment.bottomCenter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: !m.watched
                              ? scheme.surfaceContainerHighest
                              : m.score != null
                              ? scoreColor(m.score!)
                              : scheme.outline,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                            bottom: Radius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  double _barHeight(EpisodeMark m) {
    if (!m.watched) return 0.2;
    final sc = m.score;
    if (sc == null) return 0.5;
    return 0.2 + 0.8 * ((sc - 4) / 6).clamp(0.0, 1.0);
  }

  Widget _highlight(BuildContext context, ChapterHighlight hl, int season) {
    final scheme = Theme.of(context).colorScheme;
    final binge = hl.binge;
    if (hl.kind == HighlightKind.record && binge != null) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.bolt_rounded,
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                trn('ss_record', binge.count, {
                  'date': dayMonth(binge.day),
                  'time': _duration(binge.minutes, false),
                }),
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final (IconData icon, String text) = switch (hl.kind) {
      HighlightKind.bingeDay when binge != null => (
        Icons.bolt_outlined,
        trn('ss_binge_day', binge.count, {'date': dayMonth(binge.day)}),
      ),
      HighlightKind.bestOfSeries => (
        Icons.star_rounded,
        trf('ss_best_series', {
          't': _title(season, hl.number!),
          's': _score(hl.score!),
        }),
      ),
      HighlightKind.worstOfSeries => (
        Icons.trending_down_rounded,
        trf('ss_worst_series', {
          't': _title(season, hl.number!),
          's': _score(hl.score!),
        }),
      ),
      _ => (
        Icons.star_outline_rounded,
        trf('ss_best_season', {
          't': _title(season, hl.number ?? 0),
          's': _score(hl.score ?? 0),
        }),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: scheme.primary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13.5,
                height: 1.4,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pause(BuildContext context, SeasonPause p) {
    final scheme = Theme.of(context).colorScheme;
    return _railRow(
      context,
      node: _dot(context),
      dashed: true,
      pad: 22,
      content: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pause_rounded,
                size: 16,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  trf('ss_pause', {'d': _pauseLength(p.days)}),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        _caption(
          context,
          trf('ss_came_back', {
            's': p.afterSeason,
            'date': dayMonth(p.resumedAt),
          }),
        ),
      ],
    );
  }

  String _pauseLength(int days) {
    if (days < 60) return trn('ss_days', days);
    if (days < 365) return trn('ss_months', (days / 30).round());
    return trn('ss_years', (days / 365).round());
  }

  // ------------------------------------------------------------ детали

  Widget _railRow(
    BuildContext context, {
    required Widget node,
    required List<Widget> content,
    bool rail = true,
    bool dashed = false,
    double pad = 28,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                node,
                if (rail) ...[
                  const SizedBox(height: 4),
                  Expanded(
                    child: dashed
                        ? CustomPaint(
                            painter: _DashPainter(scheme.outline),
                            child: const SizedBox(width: 2),
                          )
                        : Container(width: 2, color: scheme.outlineVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: rail ? pad : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: content,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 22,
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surface,
            border: Border.all(color: scheme.primary, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _flag(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primary),
      child: Icon(Icons.flag_rounded, size: 20, color: scheme.onPrimary),
    );
  }

  Widget _caption(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontFamily: AppTheme.bodyFont,
      fontSize: 13,
      height: 1.4,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );

  Widget _strong(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: AppTheme.bodyFont,
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _undatedNote(BuildContext context, int n) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(child: _caption(context, trn('ss_undated', n))),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded, size: 48, color: scheme.primary),
            const SizedBox(height: 14),
            Text(
              tr('ss_no_marks'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 15,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// «3 февраля 2026, вторник, 21:10»; время, только если оно есть.
  String _moment(DateTime d) {
    final time = d.hour != 0 || d.minute != 0 ? ', ${hhmm(d)}' : '';
    return '${longDate(d)}, ${weekdayName(d)}$time';
  }

  String _range(DateTime from, DateTime to) {
    if (from.year == to.year && from.month == to.month && from.day == to.day) {
      return dayMonth(from);
    }
    return '${dayMonth(from)} – ${dayMonth(to)}';
  }

  String _duration(int minutes, bool estimated) {
    final h = minutes ~/ 60, m = minutes % 60;
    final text = h > 0 && m > 0
        ? trf('ss_hm', {'h': h, 'm': m})
        : h > 0
        ? trf('ss_h', {'h': h})
        : trf('ss_m', {'m': m});
    return estimated ? '≈ $text' : text;
  }

  String _score(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Название серии из TMDB, иначе «S1E5».
  String _title(int season, int number) {
    for (final e in _tmdb[season] ?? const <TmdbEpisode>[]) {
      if (e.number == number && e.name.trim().isNotEmpty) return e.name.trim();
    }
    return 'S${season}E$number';
  }
}

/// Строка линии пути: узел с текстом, глава сезона или пауза.
class _Row {
  final Widget? node;
  final List<Widget> content;
  final double pad;
  final SeasonStats? chapter;
  final SeasonPause? pause;

  _Row({required this.node, required this.content, this.pad = 28})
    : chapter = null,
      pause = null;

  _Row.chapter(SeasonStats this.chapter)
    : node = null,
      content = const [],
      pad = 28,
      pause = null;

  _Row.pause(SeasonPause this.pause)
    : node = null,
      content = const [],
      pad = 22,
      chapter = null;
}

/// Пунктирная линия паузы по центру своей колонки.
class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    for (var y = 2.0; y < size.height; y += 9) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, (y + 4).clamp(0, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
