import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../widgets/poster.dart';
import '../widgets/reveal.dart';
import 'movie_sheet.dart';
import 'series_screen.dart';

/// Экран статистики (Material 3 Expressive): градиентная шапка-итог, крупные
/// тональные плитки, графики активности (годы/месяцы/дни недели/десятилетия),
/// распределение оценок в фирменной палитре балла, сравнение с Кинопоиском,
/// рекорды, эмоции, топы и сериалы. Максимум данных — минимум скуки.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final s = _Stats.compute(repo);
        return Scaffold(
          appBar: AppBar(title: Text(tr('drawer_stats'))),
          body: !s.hasData
              ? Center(
                  child: Text(tr('stat_empty'),
                      style: const TextStyle(fontFamily: AppTheme.bodyFont)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    _hero(context, s),
                    const SizedBox(height: 16),
                    _tiles(context, s),
                    if (s.records.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _records(context, s),
                    ],
                    if (s.byYear.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _card(context, tr('stat_by_year'),
                          _barChart(context, s.yearLabels, s.yearValues)),
                    ],
                    if (s.byMonth.any((v) => v > 0)) ...[
                      const SizedBox(height: 20),
                      _card(context, tr('stat_by_month'),
                          _barChart(context, s.monthLabels, s.byMonth)),
                    ],
                    if (s.byWeekday.any((v) => v > 0)) ...[
                      const SizedBox(height: 20),
                      _card(context, tr('stat_by_weekday'),
                          _barChart(context, weekdayShort, s.byWeekday,
                              colorOf: (context, i) =>
                                  _weekdayColor(context, i))),
                    ],
                    if (s.byDay.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _heatmapCard(context, s),
                    ],
                    const SizedBox(height: 20),
                    _card(
                      context,
                      tr('stat_scores'),
                      _barChart(context, s.scoreLabels, s.scoreDist,
                          colorOf: (_, i) => scoreColor((i + 1).toDouble())),
                      subtitle: s.avgScore == 0
                          ? null
                          : '${tr('stat_avg')}: ${s.avgScore.toStringAsFixed(1)}',
                    ),
                    if (s.byDecade.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _card(context, tr('stat_by_decade'),
                          _barChart(context, s.decadeLabels, s.decadeValues)),
                    ],
                    if (s.genres.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _genresCard(context, s),
                    ],
                    if (s.moviesForSplit + s.episodesWatched > 0) ...[
                      const SizedBox(height: 20),
                      _splitCard(context, s),
                    ],
                    if (s.kpCount > 0) ...[
                      const SizedBox(height: 20),
                      _kpCard(context, s),
                    ],
                    if (s.emotions.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _emotions(context, s),
                    ],
                    if (s.topRated.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _section(context, tr('stat_top')),
                      const SizedBox(height: 10),
                      ...s.topRated.asMap().entries.map(
                          (e) => _movieRow(context, e.value, rank: e.key + 1)),
                    ],
                    if (s.mostRewatched.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _section(context, tr('stat_most_rewatched')),
                      const SizedBox(height: 10),
                      ...s.mostRewatched.map((m) => _movieRow(context, m,
                          trailing: trf('stat_times_n', {'n': m.viewCount}))),
                    ],
                    if (s.topSeries.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _section(context, tr('stat_top_series')),
                      const SizedBox(height: 10),
                      ...s.topSeries.map((x) => _seriesRow(context, x)),
                    ],
                  ],
                ),
        );
      },
    );
  }

  // ------------------------------ шапка-итог ------------------------------

  Widget _hero(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    return Reveal(
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -6,
              child: Icon(Icons.movie_filter_rounded,
                  size: 96, color: Colors.white.withValues(alpha: 0.14)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('stat_screen_time'),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 2,
                        color: Colors.white.withValues(alpha: 0.85))),
                const SizedBox(height: 6),
                // Число может быть длинным — ужимаем в одну строку по ширине.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(_fmtNum(s.hours),
                          maxLines: 1,
                          style: const TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 56,
                              height: 1,
                              color: Colors.white)),
                      const SizedBox(width: 8),
                      Text(tr('stat_hours_unit'),
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                              color: Colors.white.withValues(alpha: 0.85))),
                    ],
                  ),
                ),
                if (s.hours >= 24) ...[
                  const SizedBox(height: 4),
                  Text(trf('stat_days_watching', {'n': _fmtNum(s.hours ~/ 24)}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ],
                const SizedBox(height: 12),
                Text(
                    trf('stat_summary_sub', {
                      'f': _fmtNum(s.watchedMovies),
                      's': _fmtNum(s.seriesCount),
                      'e': _fmtNum(s.episodesWatched)
                    }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------- плитки -------------------------------

  Widget _tiles(BuildContext context, _Stats s) {
    final tiles = <(IconData, String, String)>[
      (Icons.movie_rounded, _fmtNum(s.watchedMovies), tr('stat_movies')),
      (Icons.schedule_rounded, _fmtNum(s.hours), tr('stat_hours')),
      (
        Icons.star_rounded,
        s.avgScore == 0 ? '—' : s.avgScore.toStringAsFixed(1),
        tr('stat_avg')
      ),
      (Icons.visibility_rounded, _fmtNum(s.totalViewings), tr('stat_viewings')),
      (Icons.live_tv_rounded, _fmtNum(s.seriesCount), tr('stat_series')),
      (Icons.playlist_play_rounded, _fmtNum(s.episodesWatched),
          tr('stat_episodes')),
      (Icons.favorite_rounded, _fmtNum(s.favorites), tr('stat_favorites')),
      (Icons.repeat_rounded, _fmtNum(s.rewatches), tr('stat_rewatches')),
      (Icons.heart_broken_rounded, _fmtNum(s.droppedCount), tr('stat_dropped')),
      (Icons.bookmark_rounded, _fmtNum(s.watchlistCount), tr('stat_watchlist')),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(Row(children: [
        _tile(context, tiles[i], i),
        const SizedBox(width: 12),
        if (i + 1 < tiles.length)
          _tile(context, tiles[i + 1], i + 1)
        else
          const Expanded(child: SizedBox.shrink()),
      ]));
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  Widget _tile(BuildContext context, (IconData, String, String) t, int i) {
    final scheme = Theme.of(context).colorScheme;
    final bg = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ][i % 3];
    final fg = [
      scheme.onPrimaryContainer,
      scheme.onSecondaryContainer,
      scheme.onTertiaryContainer,
    ][i % 3];
    return Expanded(
      child: Reveal(
        delay: Duration(milliseconds: i * 45),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(t.$1, color: fg, size: 22),
              const SizedBox(height: 10),
              // Фикс. высота + FittedBox: длинное число ужимается в одну строку,
              // а все плитки остаются одной высоты (не переносится и не растёт).
              SizedBox(
                height: 34,
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(t.$2,
                      maxLines: 1,
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 30,
                          height: 1,
                          color: fg)),
                ),
              ),
              const SizedBox(height: 3),
              Text(t.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: fg.withValues(alpha: 0.85))),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------ рекорды ------------------------------

  Widget _records(BuildContext context, _Stats s) {
    return _card(
      context,
      tr('stat_records'),
      Column(
        children: [
          for (var i = 0; i < s.records.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _recordRow(context, s.records[i]),
          ],
        ],
      ),
    );
  }

  Widget _recordRow(BuildContext context, _Record r) {
    final scheme = Theme.of(context).colorScheme;
    final accent = r.color ?? scheme.primary;
    // Подпись сверху, значение снизу на всю ширину: длинные названия/даты
    // влезают (до 2 строк), а отступ у всех строк одинаковый.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(r.icon, size: 20, color: accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 1),
              Text(r.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.15,
                      color: scheme.onSurface)),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------- фильмы vs сериалы ---------------------------

  Widget _splitCard(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    final total = s.moviesForSplit + s.episodesWatched;
    final movieFrac = total == 0 ? 0.0 : s.moviesForSplit / total;
    return _card(
      context,
      tr('stat_split'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: movieFrac),
              duration: const Duration(milliseconds: 700),
              curve: AppTheme.emphasized,
              builder: (_, v, _) => Row(
                children: [
                  if (v > 0)
                    Expanded(
                      flex: (v * 1000).round().clamp(1, 1000),
                      child: Container(height: 22, color: scheme.primary),
                    ),
                  if (v < 1)
                    Expanded(
                      flex: ((1 - v) * 1000).round().clamp(1, 1000),
                      child: Container(height: 22, color: scheme.tertiary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legendDot(scheme.primary),
              const SizedBox(width: 6),
              Text('${tr('filter_movies')} · ${s.moviesForSplit}',
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant)),
              const Spacer(),
              _legendDot(scheme.tertiary),
              const SizedBox(width: 6),
              Text('${tr('filter_series')} · ${s.episodesWatched}',
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color c) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  // -------------------------- сравнение с КП --------------------------

  Widget _kpCard(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    final d = s.kpDelta;
    final up = d > 0.05, down = d < -0.05;
    final accent = up
        ? const Color(0xFF2E9B57)
        : (down ? kDroppedColor : scheme.onSurfaceVariant);
    final text = up
        ? trf('stat_vs_kp_higher', {'d': d.abs().toStringAsFixed(1)})
        : (down
            ? trf('stat_vs_kp_lower', {'d': d.abs().toStringAsFixed(1)})
            : tr('stat_vs_kp_same'));
    return _card(
      context,
      tr('stat_vs_kp'),
      Row(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(
                up
                    ? Icons.trending_up_rounded
                    : (down
                        ? Icons.trending_down_rounded
                        : Icons.drag_handle_rounded),
                color: accent,
                size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.15,
                        color: accent)),
                const SizedBox(height: 4),
                Text(trf('stat_vs_kp_sub', {'n': s.kpCount}),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------ эмоции ------------------------------

  Widget _emotions(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    final top = s.emotions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _card(
      context,
      tr('stat_emotions'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in top.take(10))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.key.split('|').first,
                      style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(
                      e.key.contains('|') ? e.key.split('|')[1] : '',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: scheme.onSecondaryContainer)),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                        color: scheme.secondary,
                        borderRadius: BorderRadius.circular(12)),
                    child: Text('${e.value}',
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: scheme.onSecondary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------- строки топов ---------------------------

  Widget _movieRow(BuildContext context, LibraryMovie m,
      {int? rank, String? trailing}) {
    final scheme = Theme.of(context).colorScheme;
    final sc = m.currentScore;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showMovieSheet(context, m),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (rank != null) ...[
                  SizedBox(
                    width: 24,
                    child: Text('$rank',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.7))),
                  ),
                  const SizedBox(width: 4),
                ],
                Poster(title: m.displayTitle, url: m.posterUrl, width: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(m.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: scheme.onSurface)),
                      if (m.year != null)
                        Text('${m.year}',
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailing != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(16)),
                    child: Text(trailing,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: scheme.onTertiaryContainer)),
                  )
                else if (sc != null)
                  _scorePill(sc),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seriesRow(BuildContext context, ({LibrarySeries s, int seen}) x) {
    final scheme = Theme.of(context).colorScheme;
    final s = x.s;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s))),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Stack(
                  children: [
                    Poster(title: s.displayTitle, url: s.posterUrl, width: 44),
                    Positioned(
                      left: 3,
                      top: 3,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                            color: scheme.tertiary,
                            borderRadius: BorderRadius.circular(7)),
                        child: Icon(Icons.live_tv_rounded,
                            size: 11, color: scheme.onTertiary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: scheme.onSurface)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(trf('stat_eps_n', {'n': x.seen}),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: scheme.onTertiaryContainer)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scorePill(double score) {
    final c = scoreColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 15, color: onScoreColor(score)),
          const SizedBox(width: 3),
          Text(score.toStringAsFixed(1),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: onScoreColor(score))),
        ],
      ),
    );
  }

  // ------------------------- переиспользуемое -------------------------

  /// Столбчатая диаграмма: подписи снизу, значения сверху, плавный рост.
  /// Если столбцов много (>12) — горизонтальная прокрутка фиксированной ширины.
  Widget _barChart(BuildContext context, List<String> labels, List<int> values,
      {Color Function(BuildContext, int)? colorOf}) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = values.fold(0, (a, b) => a > b ? a : b);
    final n = values.length;

    Widget bar(int i) {
      final frac = maxV == 0 ? 0.0 : values[i] / maxV;
      return Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(values[i] == 0 ? '' : '${values[i]}',
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: frac),
            duration: Duration(milliseconds: 550 + i * 30),
            curve: AppTheme.emphasized,
            builder: (_, v, _) => Container(
              height: 100 * v + 4,
              margin: const EdgeInsets.symmetric(horizontal: 3.5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    (colorOf?.call(context, i) ?? scheme.primary),
                    (colorOf?.call(context, i) ?? scheme.primary)
                        .withValues(alpha: 0.7),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7), bottom: Radius.circular(3)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(labels[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 11,
                  color: scheme.onSurfaceVariant)),
        ],
      );
    }

    return SizedBox(
      height: 154,
      child: n > 12
          ? ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: n,
              itemBuilder: (_, i) => SizedBox(width: 42, child: bar(i)),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [for (var i = 0; i < n; i++) Expanded(child: bar(i))],
            ),
    );
  }

  Color _weekdayColor(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    // Выходные (Сб/Вс) — тёплым третичным, будни — основным.
    return (i >= 5) ? scheme.tertiary : scheme.primary;
  }

  /// Топ жанров — горизонтальные бары (название · полоса · число).
  Widget _genresCard(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    final top = s.genres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = top.take(10).toList();
    final maxV = shown.first.value;
    return _card(
      context,
      tr('stat_genres'),
      Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Text(capitalize(shown[i].key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: scheme.onSurface)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 20,
                      color: scheme.surfaceContainerHighest,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: shown[i].value / maxV),
                        duration: Duration(milliseconds: 600 + i * 40),
                        curve: AppTheme.emphasized,
                        builder: (_, v, _) => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: v.clamp(0.02, 1.0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                scheme.primary.withValues(alpha: 0.75),
                                scheme.primary,
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text('${shown[i].value}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: scheme.primary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Тепловая карта активности (в духе GitHub-contributions): недели-столбцы,
  /// дни-строки (Пн→Вс), цвет по числу отметок за день. Прокручивается,
  /// открывается на свежих неделях (справа).
  Widget _heatmapCard(BuildContext context, _Stats s) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const weeksBack = 26; // ~полгода
    final startRaw = today.subtract(const Duration(days: weeksBack * 7));
    final start = startRaw.subtract(Duration(days: startRaw.weekday - 1));
    final numWeeks = (today.difference(start).inDays / 7).floor() + 1;
    var maxC = 1;
    for (final v in s.byDay.values) {
      if (v > maxC) maxC = v;
    }
    Color cell(int c) {
      if (c <= 0) return scheme.surfaceContainerHighest;
      final t = (c / maxC).clamp(0.0, 1.0);
      return Color.lerp(
          scheme.primary.withValues(alpha: 0.3), scheme.primary, t)!;
    }

    const size = 15.0;
    Widget box(Color c) => Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
              color: c, borderRadius: BorderRadius.circular(3)),
        );

    final columns = <Widget>[];
    for (var w = 0; w < numWeeks; w++) {
      final weekStart = start.add(Duration(days: w * 7));
      final cells = <Widget>[];
      for (var d = 0; d < 7; d++) {
        final day = weekStart.add(Duration(days: d));
        if (day.isAfter(today)) {
          cells.add(const SizedBox(width: size, height: size + 3));
        } else {
          final key = '${day.year}-${day.month}-${day.day}';
          cells.add(box(cell(s.byDay[key] ?? 0)));
        }
      }
      columns.add(Padding(
        padding: const EdgeInsets.only(right: 3),
        child: Column(children: cells),
      ));
    }

    return _card(
      context,
      tr('stat_activity'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true, // открываемся на свежих неделях
            child: Row(children: columns),
          ),
          const SizedBox(height: 12),
          // Легенда «меньше → больше».
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(tr('stat_less'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              for (final f in const [0.0, 0.3, 0.55, 0.8, 1.0])
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: f == 0
                          ? scheme.surfaceContainerHighest
                          : Color.lerp(scheme.primary.withValues(alpha: 0.3),
                              scheme.primary, f),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              const SizedBox(width: 3),
              Text(tr('stat_more'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, String title, Widget child,
      {String? subtitle}) {
    final scheme = Theme.of(context).colorScheme;
    return Reveal(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          color: scheme.onSurface)),
                ),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          color: scheme.primary)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(title,
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: Theme.of(context).colorScheme.onSurface)),
      );
}

/// Число с разделителями тысяч (узкий пробел): 71588 → «71 588».
String _fmtNum(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$b';
}

/// Строка рекорда/факта.
class _Record {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _Record(this.icon, this.label, this.value, {this.color});
}

/// Посчитанная статистика библиотеки — максимум срезов без сети.
class _Stats {
  final int watchedMovies;
  final int totalViewings;
  final int hours;
  final double avgScore;
  final int seriesCount;
  final int episodesWatched;
  final int favorites;
  final int rewatches;
  final int droppedCount;
  final int watchlistCount;
  final int moviesForSplit;

  final Map<int, int> byYear;
  final List<int> byMonth; // 12 (янв..дек)
  final List<int> byWeekday; // 7 (пн..вс)
  final List<int> scoreDist; // 10 (1..10)
  final Map<int, int> byDecade;

  final double kpDelta; // ср. (твоя − КП)
  final int kpCount;

  final List<LibraryMovie> topRated;
  final List<LibraryMovie> mostRewatched;
  final List<({LibrarySeries s, int seen})> topSeries;
  final Map<String, int> emotions; // ключ «emoji|label»
  final Map<String, int> genres; // жанр → число фильмов
  final Map<String, int> byDay; // «y-m-d» → активность (тепловая карта)
  final List<_Record> records;

  _Stats({
    required this.watchedMovies,
    required this.totalViewings,
    required this.hours,
    required this.avgScore,
    required this.seriesCount,
    required this.episodesWatched,
    required this.favorites,
    required this.rewatches,
    required this.droppedCount,
    required this.watchlistCount,
    required this.moviesForSplit,
    required this.byYear,
    required this.byMonth,
    required this.byWeekday,
    required this.scoreDist,
    required this.byDecade,
    required this.kpDelta,
    required this.kpCount,
    required this.topRated,
    required this.mostRewatched,
    required this.topSeries,
    required this.emotions,
    required this.genres,
    required this.byDay,
    required this.records,
  });

  bool get hasData =>
      totalViewings > 0 || episodesWatched > 0 || seriesCount > 0;

  // Метки/значения для графиков.
  List<int> get _sortedYears => byYear.keys.toList()..sort();
  List<String> get yearLabels =>
      [for (final y in _sortedYears) '$y'];
  List<int> get yearValues => [for (final y in _sortedYears) byYear[y]!];

  List<String> get monthLabels => [for (var m = 1; m <= 12; m++) monthShort(m)];

  List<String> get scoreLabels => [for (var i = 1; i <= 10; i++) '$i'];

  List<int> get _sortedDecades => byDecade.keys.toList()..sort();
  List<String> get decadeLabels => [for (final d in _sortedDecades) "'${d % 100}"];
  List<int> get decadeValues => [for (final d in _sortedDecades) byDecade[d]!];

  static _Stats compute(MovieRepository repo) {
    final watched = repo.watched;
    final allSeries = repo.series.where((s) => s.episodes.isNotEmpty).toList();

    var totalViewings = 0;
    var minutes = 0;
    var rewatches = 0;
    final byYear = <int, int>{};
    final byMonth = List<int>.filled(12, 0);
    final byWeekday = List<int>.filled(7, 0);
    final scoreDist = List<int>.filled(10, 0);
    final byDecade = <int, int>{};
    final emotions = <String, int>{};
    final genres = <String, int>{};
    final byDay = <String, int>{}; // самый активный день + тепловая карта
    var scoreSum = 0.0, scoreN = 0;
    var kpSum = 0.0, kpN = 0;
    var runtimeSum = 0, runtimeN = 0;
    DateTime? firstMark;
    LibraryMovie? longest;

    void bumpDate(DateTime d) {
      byYear[d.year] = (byYear[d.year] ?? 0) + 1;
      byMonth[d.month - 1]++;
      byWeekday[d.weekday - 1]++;
      final key = '${d.year}-${d.month}-${d.day}';
      byDay[key] = (byDay[key] ?? 0) + 1;
      if (firstMark == null || d.isBefore(firstMark!)) firstMark = d;
    }

    for (final m in watched) {
      final vc = m.viewings.isEmpty ? 1 : m.viewings.length;
      if (vc > 1) rewatches += vc - 1;
      // Импорт TV Time иногда кладёт мусорную длительность (млн «минут») —
      // учитываем только вменяемую (1..600 мин ≈ до 10 ч), иначе итоги врут.
      final rt = m.runtimeMin;
      final saneRt = (rt != null && rt > 0 && rt <= 600) ? rt : null;
      for (final v in m.viewings) {
        totalViewings++;
        if (saneRt != null) minutes += saneRt;
        if (v.date != null) bumpDate(v.date!);
      }
      if (m.viewings.isEmpty) totalViewings++; // отмечен без даты просмотра
      if (saneRt != null) {
        runtimeSum += saneRt;
        runtimeN++;
        if (longest == null || saneRt > (longest.runtimeMin ?? 0)) {
          longest = m;
        }
      }
      final sc = m.currentScore;
      if (sc != null) {
        scoreSum += sc;
        scoreN++;
        scoreDist[(sc.round()).clamp(1, 10) - 1]++;
        if (m.kpRating != null && m.kpRating! > 0) {
          kpSum += sc - m.kpRating!;
          kpN++;
        }
      }
      if (m.year != null && m.year! > 1000) {
        final dec = (m.year! ~/ 10) * 10;
        byDecade[dec] = (byDecade[dec] ?? 0) + 1;
      }
      for (final e in m.emotions) {
        final key = '${e.emoji}|${e.label}';
        emotions[key] = (emotions[key] ?? 0) + 1;
      }
      for (final g in m.genres) {
        genres[g] = (genres[g] ?? 0) + 1;
      }
    }

    // Сериалы: время + активность по датам просмотра серий.
    var episodesWatched = 0;
    for (final s in allSeries) {
      for (final e in s.episodes) {
        episodesWatched++;
        final ert = e.runtimeMin;
        if (ert != null && ert > 0 && ert <= 600) {
          minutes += ert * e.watchCount.clamp(1, 100);
        }
        if (e.watchedAt != null) bumpDate(e.watchedAt!);
      }
    }

    final topRated = watched.where((m) => m.currentScore != null).toList()
      ..sort((a, b) => b.currentScore!.compareTo(a.currentScore!));
    final mostRewatched = watched.where((m) => m.viewCount > 1).toList()
      ..sort((a, b) => b.viewCount.compareTo(a.viewCount));
    final topSeries = [
      for (final s in allSeries) (s: s, seen: s.episodesSeen)
    ]..sort((a, b) => b.seen.compareTo(a.seen));

    // ----- рекорды -----
    final records = <_Record>[];
    if (byDay.isNotEmpty) {
      final best = byDay.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final parts = best.key.split('-').map(int.parse).toList();
      records.add(_Record(
          Icons.local_fire_department_rounded,
          tr('stat_most_active_day'),
          '${numericDate(DateTime(parts[0], parts[1], parts[2]))} · ${best.value}',
          color: const Color(0xFFE8833A)));
    }
    if (firstMark != null) {
      records.add(_Record(Icons.flag_rounded, tr('stat_first_mark'),
          numericDate(firstMark!)));
      final days = DateTime.now().difference(firstMark!).inDays + 1;
      records.add(_Record(
          Icons.calendar_month_rounded, tr('stat_days_tracked'), '$days'));
    }
    if (runtimeN > 0) {
      records.add(_Record(Icons.timelapse_rounded, tr('stat_avg_runtime'),
          humanDuration(Duration(minutes: runtimeSum ~/ runtimeN))));
    }
    if (longest != null) {
      records.add(_Record(
          Icons.straighten_rounded,
          tr('stat_longest'),
          '${longest.displayTitle} · ${humanDuration(Duration(minutes: longest.runtimeMin!))}'));
    }
    if (genres.isNotEmpty) {
      final top = genres.entries.reduce((a, b) => a.value >= b.value ? a : b);
      records.add(_Record(Icons.theaters_rounded, tr('stat_fav_genre'),
          '${capitalize(top.key)} · ${top.value}'));
    }
    if (topRated.isNotEmpty) {
      final hi = topRated.first;
      records.add(_Record(
          Icons.emoji_events_rounded,
          tr('stat_highest'),
          '${hi.currentScore!.toStringAsFixed(1)} · ${hi.displayTitle}',
          color: scoreColor(hi.currentScore!)));
      final lo = topRated.last;
      if (topRated.length > 1) {
        records.add(_Record(
            Icons.thumb_down_rounded,
            tr('stat_lowest'),
            '${lo.currentScore!.toStringAsFixed(1)} · ${lo.displayTitle}',
            color: scoreColor(lo.currentScore!)));
      }
    }

    return _Stats(
      watchedMovies: watched.length,
      totalViewings: totalViewings,
      hours: minutes ~/ 60,
      avgScore: scoreN == 0 ? 0 : scoreSum / scoreN,
      seriesCount: repo.seriesCount,
      episodesWatched: episodesWatched,
      favorites: repo.favorites.length,
      rewatches: rewatches,
      droppedCount: repo.droppedMovies.length + repo.droppedSeries.length,
      watchlistCount: repo.watchlist.length,
      moviesForSplit: watched.length,
      byYear: byYear,
      byMonth: byMonth,
      byWeekday: byWeekday,
      scoreDist: scoreDist,
      byDecade: byDecade,
      kpDelta: kpN == 0 ? 0 : kpSum / kpN,
      kpCount: kpN,
      topRated: topRated.take(10).toList(),
      mostRewatched: mostRewatched.take(5).toList(),
      topSeries: topSeries.take(5).toList(),
      emotions: emotions,
      genres: genres,
      byDay: byDay,
      records: records,
    );
  }
}
