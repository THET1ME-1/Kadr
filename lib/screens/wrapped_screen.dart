import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../widgets/poster.dart';

/// «Кинокод года» — красивый шареабельный итог года из данных библиотеки.
class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key});

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  final _shotKey = GlobalKey();
  late int _year;
  late List<int> _years;

  @override
  void initState() {
    super.initState();
    _years = _availableYears(MovieRepository.instance);
    _year = _years.isNotEmpty ? _years.first : DateTime.now().year;
  }

  static List<int> _availableYears(MovieRepository repo) {
    final set = <int>{};
    for (final m in repo.watched) {
      for (final v in m.viewings) {
        if (v.date != null) set.add(v.date!.year);
      }
    }
    for (final s in repo.series) {
      for (final e in s.episodes) {
        for (final v in e.views) {
          if (v.date != null) set.add(v.date!.year);
        }
      }
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  Future<void> _share() async {
    try {
      final boundary =
          _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kadr_wrapped_$_year.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')],
          subject: 'Kadr · ${tr('wrapped_title')} $_year');
    } catch (_) {/* молча */}
  }

  @override
  Widget build(BuildContext context) {
    final stats = _YearStats.forYear(MovieRepository.instance, _year);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('wrapped_title')),
        actions: [
          if (stats.total > 0)
            IconButton(
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: tr('share'),
              onPressed: _share,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_years.length > 1)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final y in _years) _yearChip(y),
                ],
              ),
            ),
          Expanded(
            child: stats.total == 0
                ? Center(
                    child: Text(tr('wrapped_empty'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: RepaintBoundary(
                      key: _shotKey,
                      child: _content(stats),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _yearChip(int y) {
    final scheme = Theme.of(context).colorScheme;
    final sel = y == _year;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: sel,
        label: Text('$y'),
        labelStyle: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w700,
            color: sel ? scheme.onPrimary : scheme.onSurfaceVariant),
        selectedColor: scheme.primary,
        showCheckmark: false,
        onSelected: (_) => setState(() => _year = y),
      ),
    );
  }

  Widget _content(_YearStats s) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Обложка-хиро
        Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.tertiary],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tr('wrapped_title')} · $_year',
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: scheme.onPrimary.withValues(alpha: 0.9))),
              const SizedBox(height: 10),
              Text('${s.movies + s.episodes}',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 64,
                      height: 1,
                      color: scheme.onPrimary)),
              Text(trf('wrapped_watched', {'m': s.movies, 'e': s.episodes}),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: scheme.onPrimary)),
              if (s.prevTotal > 0) ...[
                const SizedBox(height: 8),
                Text(
                    trf(s.total >= s.prevTotal ? 'wrapped_more' : 'wrapped_less',
                        {'n': (s.total - s.prevTotal).abs()}),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13,
                        color: scheme.onPrimary.withValues(alpha: 0.9))),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _statCard(Icons.schedule_rounded, '${s.hours}',
                    tr('wrapped_hours'), scheme.secondaryContainer,
                    scheme.onSecondaryContainer)),
            const SizedBox(width: 12),
            Expanded(
                child: _statCard(
                    Icons.star_rounded,
                    s.avgScore > 0 ? s.avgScore.toStringAsFixed(1) : '—',
                    tr('wrapped_avg'),
                    scheme.tertiaryContainer,
                    scheme.onTertiaryContainer)),
          ],
        ),
        const SizedBox(height: 12),
        if (s.busiestMonth >= 0)
          _wideCard(
            Icons.local_fire_department_rounded,
            tr('wrapped_busiest'),
            '${capitalize(monthName(s.busiestMonth + 1))} · ${s.busiestMonthCount}',
          ),
        if (s.topGenres.isNotEmpty) ...[
          const SizedBox(height: 12),
          _wideCard(
            Icons.theaters_rounded,
            tr('wrapped_top_genres'),
            s.topGenres.take(3).map((e) => capitalize(e.key)).join(' · '),
          ),
        ],
        if (s.topEmotion != null) ...[
          const SizedBox(height: 12),
          _wideCard(Icons.mood_rounded, tr('wrapped_mood'), s.topEmotion!,
              big: true),
        ],
        if (s.topMovie != null) ...[
          const SizedBox(height: 16),
          _hero(tr('wrapped_movie'), s.topMovie!.displayTitle,
              s.topMovie!.posterUrl, s.topMovie!.currentScore),
        ],
        if (s.topSeries != null) ...[
          const SizedBox(height: 12),
          _hero(
              tr('wrapped_series'),
              s.topSeries!.s.displayTitle,
              s.topSeries!.s.posterUrl,
              s.topSeries!.s.displayScore,
              subtitle: trf('episodes_n', {'n': s.topSeries!.seen})),
        ],
        const SizedBox(height: 14),
        Center(
          child: Text('Kadr',
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
        ),
      ],
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  color: fg)),
          Text(label,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont, fontSize: 12.5, color: fg)),
        ],
      ),
    );
  }

  Widget _wideCard(IconData icon, String label, String value,
      {bool big = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: big ? 26 : 17,
                        color: scheme.onSurface)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(String label, String title, String? poster, double? score,
      {String? subtitle}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          Poster(title: title, url: poster, width: 64, radius: 12),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 0.6,
                        color: scheme.primary)),
                const SizedBox(height: 4),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        height: 1.1,
                        color: scheme.onSurface)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (score != null) ...[
            const SizedBox(width: 8),
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: scoreColor(score), shape: BoxShape.circle),
              child: Text(score.toStringAsFixed(1),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: onScoreColor(score))),
            ),
          ],
        ],
      ),
    );
  }
}

class _YearStats {
  final int movies;
  final int episodes;
  final int hours;
  final double avgScore;
  final List<MapEntry<String, int>> topGenres;
  final int busiestMonth; // 0-11, -1 нет
  final int busiestMonthCount;
  final LibraryMovie? topMovie;
  final ({LibrarySeries s, int seen})? topSeries;
  final int prevTotal;
  final String? topEmotion;

  _YearStats({
    required this.movies,
    required this.episodes,
    required this.hours,
    required this.avgScore,
    required this.topGenres,
    required this.busiestMonth,
    required this.busiestMonthCount,
    required this.topMovie,
    required this.topSeries,
    required this.prevTotal,
    required this.topEmotion,
  });

  int get total => movies + episodes;

  static int _countYear(MovieRepository repo, int year) {
    var n = 0;
    for (final m in repo.watched) {
      for (final v in m.viewings) {
        if (v.date?.year == year) n++;
      }
    }
    for (final s in repo.series) {
      for (final e in s.episodes) {
        for (final v in e.views) {
          if (v.date?.year == year) n++;
        }
      }
    }
    return n;
  }

  static _YearStats forYear(MovieRepository repo, int year) {
    var movies = 0, episodes = 0, minutes = 0;
    var scoreSum = 0.0, scoreN = 0;
    final byMonth = List<int>.filled(12, 0);
    final genres = <String, int>{};
    final emotions = <String, int>{};
    LibraryMovie? topMovie;
    var topScore = -1.0;
    ({LibrarySeries s, int seen})? topSeries;

    for (final m in repo.watched) {
      final rt = m.runtimeMin;
      final saneRt = (rt != null && rt > 0 && rt <= 600) ? rt : 0;
      var counted = false;
      for (final v in m.viewings) {
        if (v.date?.year != year) continue;
        movies++;
        minutes += saneRt;
        byMonth[v.date!.month - 1]++;
        counted = true;
      }
      if (counted) {
        for (final g in m.genres) {
          genres[g] = (genres[g] ?? 0) + 1;
        }
        for (final e in m.emotions) {
          emotions[e.emoji] = (emotions[e.emoji] ?? 0) + 1;
        }
        final sc = m.currentScore;
        if (sc != null) {
          scoreSum += sc;
          scoreN++;
          if (sc > topScore) {
            topScore = sc;
            topMovie = m;
          }
        }
      }
    }

    for (final s in repo.series) {
      var seen = 0;
      for (final e in s.episodes) {
        final ert = e.runtimeMin;
        final saneErt = (ert != null && ert > 0 && ert <= 600) ? ert : 0;
        for (final v in e.views) {
          if (v.date?.year != year) continue;
          episodes++;
          seen++;
          minutes += saneErt;
          byMonth[v.date!.month - 1]++;
        }
      }
      if (seen > 0 && (topSeries == null || seen > topSeries.seen)) {
        topSeries = (s: s, seen: seen);
      }
    }

    var bm = -1, bmc = 0;
    for (var i = 0; i < 12; i++) {
      if (byMonth[i] > bmc) {
        bmc = byMonth[i];
        bm = i;
      }
    }
    final topGenres = genres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topEmotion = emotions.isEmpty
        ? null
        : (emotions.entries.reduce((a, b) => a.value >= b.value ? a : b).key);

    return _YearStats(
      movies: movies,
      episodes: episodes,
      hours: minutes ~/ 60,
      avgScore: scoreN == 0 ? 0 : scoreSum / scoreN,
      topGenres: topGenres,
      busiestMonth: bm,
      busiestMonthCount: bmc,
      topMovie: topMovie,
      topSeries: topSeries,
      prevTotal: _countYear(repo, year - 1),
      topEmotion: topEmotion,
    );
  }
}
