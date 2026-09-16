/// Статистика одного сериала для экрана «Статистика» из меню ⋮.
library;

import '../models/library_entry.dart';
import '../services/tmdb_service.dart';

/// Серии, просмотренные подряд или за один день.
class Binge {
  /// Сезон первой серии отрезка.
  final int season;
  final int count;

  /// Отметка первой серии.
  final DateTime day;
  final int minutes;

  const Binge({
    required this.season,
    required this.count,
    required this.day,
    required this.minutes,
  });
}

/// Серия в мини-графике главы.
class EpisodeMark {
  final int number;
  final bool watched;
  final double? score;

  const EpisodeMark({required this.number, required this.watched, this.score});
}

/// Цифры карточки «Время у экрана»: у сериала целиком и у сезона.
class StatsSummary {
  /// Минуты с пересмотрами.
  final int minutes;

  /// Часть длительностей взята по медиане сериала: у серии не было своей.
  final bool estimated;
  final int watched;

  /// Вышедшие серии, если TMDB знает даты, иначе все серии структуры.
  final int aired;

  /// Первая и последняя отметка с датой.
  final DateTime? from;
  final DateTime? to;

  const StatsSummary({
    required this.minutes,
    required this.estimated,
    required this.watched,
    required this.aired,
    this.from,
    this.to,
  });

  /// Дней с первой отметки по последнюю, оба дня включительно.
  int get spanDays {
    if (from == null || to == null) return 0;
    return _dayIndex(to!) - _dayIndex(from!) + 1;
  }
}

class SeasonStats extends StatsSummary {
  final int season;
  final double? avgScore;
  final int rated;
  final List<EpisodeMark> marks;
  final ({int number, double score})? best;

  /// Больше всего серий за один календарный день.
  final Binge? bestDay;

  const SeasonStats({
    required this.season,
    required super.minutes,
    required super.estimated,
    required super.watched,
    required super.aired,
    super.from,
    super.to,
    this.avgScore,
    this.rated = 0,
    this.marks = const [],
    this.best,
    this.bestDay,
  });
}

enum HighlightKind {
  record,
  bestOfSeries,
  worstOfSeries,
  bingeDay,
  bestOfSeason,
}

/// Главный факт главы на линии пути.
class ChapterHighlight {
  final HighlightKind kind;
  final int? number;
  final double? score;
  final Binge? binge;

  const ChapterHighlight(this.kind, {this.number, this.score, this.binge});
}

class SeasonPause {
  final int afterSeason;
  final int days;
  final DateTime resumedAt;

  const SeasonPause({
    required this.afterSeason,
    required this.days,
    required this.resumedAt,
  });
}

typedef EpisodeRef = ({int season, int number});

class SeriesStats extends StatsSummary {
  /// Сезоны, где отмечена хотя бы одна серия, по порядку номеров.
  final List<SeasonStats> seasons;

  /// Отмеченные серии без даты: они в сумме, но не на линии.
  final int undated;

  /// Самый длинный отрезок подряд по всему сериалу.
  final Binge? record;

  /// Лучшая и худшая серия сериала, если такая одна.
  final ({int season, int number, double score})? best;
  final ({int season, int number, double score})? worst;

  final ({int season, int number, DateTime at})? first;
  final ({int season, int number, DateTime at})? last;

  /// Отмечены все вышедшие серии.
  final bool finished;

  /// Серия с наибольшим числом повторных просмотров.
  final ({int season, int number, int times})? topRewatch;

  /// Перерывы между сезонами от [pauseDays] дней.
  final List<SeasonPause> pauses;

  const SeriesStats({
    required super.minutes,
    required super.estimated,
    required super.watched,
    required super.aired,
    super.from,
    super.to,
    this.seasons = const [],
    this.undated = 0,
    this.record,
    this.best,
    this.worst,
    this.first,
    this.last,
    this.finished = false,
    this.topRewatch,
    this.pauses = const [],
  });

  SeasonStats? season(int n) {
    for (final s in seasons) {
      if (s.season == n) return s;
    }
    return null;
  }

  /// Один факт на главу, самый заметный.
  ChapterHighlight? highlightFor(int n) {
    final r = record;
    if (r != null && r.count >= minRecord && r.season == n) {
      return ChapterHighlight(HighlightKind.record, binge: r);
    }
    final b = best;
    if (b != null && b.season == n) {
      return ChapterHighlight(
        HighlightKind.bestOfSeries,
        number: b.number,
        score: b.score,
      );
    }
    final w = worst;
    if (w != null && w.season == n) {
      return ChapterHighlight(
        HighlightKind.worstOfSeries,
        number: w.number,
        score: w.score,
      );
    }
    final s = season(n);
    if (s == null) return null;
    final day = s.bestDay;
    if (day != null && day.count >= minRecord) {
      return ChapterHighlight(HighlightKind.bingeDay, binge: day);
    }
    final sb = s.best;
    if (sb != null && s.rated >= 2) {
      return ChapterHighlight(
        HighlightKind.bestOfSeason,
        number: sb.number,
        score: sb.score,
      );
    }
    return null;
  }

  /// С какого размера отрезок подряд или за день стоит отдельного факта.
  static const minRecord = 3;

  /// Короче этого перерыв между сезонами не показывается.
  static const pauseDays = 7;
}

/// Длительность серии, которой можно верить: импорт TV Time приносил мусор
/// в миллионы минут.
int? _sane(int? rt) => rt != null && rt >= 1 && rt <= 600 ? rt : null;

int _dayIndex(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

bool _airedBy(TmdbEpisode e, DateTime now) {
  final d = DateTime.tryParse(e.airDate ?? '');
  return d == null || !d.isAfter(now);
}

double? _scoreOf(Episode e) {
  if (e.score != null) return e.score;
  for (final v in e.rewatchViews.reversed) {
    if (v.score != null) return v.score;
  }
  return null;
}

class _Watched {
  final Episode e;
  final int season;
  final int number;
  final int? runtime;

  _Watched(this.e, this.season, this.number, this.runtime);

  DateTime? get at => e.watchedAt;
  double? get score => _scoreOf(e);
}

/// Считает статистику сериала.
///
/// [seasons] — структура TMDB, как её показывает экран сериала (без
/// спецвыпусков и не начавших выходить). Пустая — сезоны берутся из отметок.
/// [tmdb] — серии сезонов из TMDB: длительность и даты выхода. Чего нет,
/// то заменяется: длительность медианой сериала, вышедшие серии числом из
/// структуры.
SeriesStats computeSeriesStats({
  required List<Episode> episodes,
  required List<TmdbSeason> seasons,
  Map<int, List<TmdbEpisode>> tmdb = const {},
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();

  // Отметки по сезонам, первая отметка серии главная (как watchedEpisode).
  final bySeason = <int, Map<int, Episode>>{};
  for (final e in episodes) {
    final s = e.season, n = e.number;
    if (s == null || n == null || s < 1 || n < 1) continue;
    bySeason.putIfAbsent(s, () => {}).putIfAbsent(n, () => e);
  }

  // Структура: номер сезона → номера серий и вышедшие из них.
  final numbersOf = <int, List<int>>{};
  final airedOf = <int, Set<int>>{};
  if (seasons.isNotEmpty) {
    for (final se in seasons) {
      final list = tmdb[se.number] ?? const <TmdbEpisode>[];
      if (list.isNotEmpty) {
        numbersOf[se.number] = [for (final t in list) t.number];
        airedOf[se.number] = {
          for (final t in list)
            if (_airedBy(t, clock)) t.number,
        };
      } else {
        final all = [for (var n = 1; n <= se.episodeCount; n++) n];
        numbersOf[se.number] = all;
        airedOf[se.number] = all.toSet();
      }
    }
  } else {
    for (final entry in bySeason.entries) {
      final maxN = entry.value.keys.reduce((a, b) => a > b ? a : b);
      final all = [for (var n = 1; n <= maxN; n++) n];
      numbersOf[entry.key] = all;
      airedOf[entry.key] = all.toSet();
    }
  }
  final seasonNumbers = numbersOf.keys.toList()..sort();

  // Длительности: своя → TMDB → медиана известных.
  final tmdbRuntime = <EpisodeRef, int>{};
  final known = <int>[];
  for (final entry in tmdb.entries) {
    for (final t in entry.value) {
      final rt = _sane(t.runtime);
      if (rt == null) continue;
      tmdbRuntime[(season: entry.key, number: t.number)] = rt;
      known.add(rt);
    }
  }

  final watched = <_Watched>[];
  for (final s in seasonNumbers) {
    final inStructure = numbersOf[s]!.toSet();
    final marks = bySeason[s] ?? const <int, Episode>{};
    for (final n in marks.keys.toList()..sort()) {
      if (!inStructure.contains(n)) continue;
      final e = marks[n]!;
      final own = _sane(e.runtimeMin);
      if (own != null) known.add(own);
      watched.add(
        _Watched(e, s, n, own ?? tmdbRuntime[(season: s, number: n)]),
      );
    }
  }
  known.sort();
  final median = known.isEmpty ? null : known[known.length ~/ 2];

  int minutesOf(_Watched w) => (w.runtime ?? median ?? 0) * w.e.watchCount;
  bool guessed(_Watched w) => w.runtime == null && median != null;

  StatsSummary summarize(List<_Watched> list, int aired) {
    DateTime? from, to;
    for (final w in list) {
      final at = w.at;
      if (at == null) continue;
      if (from == null || at.isBefore(from)) from = at;
      if (to == null || at.isAfter(to)) to = at;
    }
    return StatsSummary(
      minutes: list.fold(0, (a, w) => a + minutesOf(w)),
      estimated: list.any(guessed),
      watched: list.length,
      aired: aired,
      from: from,
      to: to,
    );
  }

  // Сезоны.
  final seasonStats = <SeasonStats>[];
  for (final s in seasonNumbers) {
    final list = [
      for (final w in watched)
        if (w.season == s) w,
    ];
    if (list.isEmpty) continue;
    final sum = summarize(list, airedOf[s]!.length);
    final scores = [
      for (final w in list)
        if (w.score != null) w.score!,
    ];
    ({int number, double score})? best;
    for (final w in list) {
      final sc = w.score;
      if (sc != null && (best == null || sc > best.score)) {
        best = (number: w.number, score: sc);
      }
    }
    final byNumber = {for (final w in list) w.number: w};
    seasonStats.add(
      SeasonStats(
        season: s,
        minutes: sum.minutes,
        estimated: sum.estimated,
        watched: sum.watched,
        aired: sum.aired,
        from: sum.from,
        to: sum.to,
        avgScore: scores.isEmpty
            ? null
            : scores.reduce((a, b) => a + b) / scores.length,
        rated: scores.length,
        marks: [
          for (final n in numbersOf[s]!)
            EpisodeMark(
              number: n,
              watched: byNumber.containsKey(n),
              score: byNumber[n]?.score,
            ),
        ],
        best: best,
        bestDay: _bestDay(list, minutesOf),
      ),
    );
  }

  // Сериал целиком.
  final airedTotal = seasonNumbers.fold<int>(
    0,
    (a, s) => a + airedOf[s]!.length,
  );
  final total = summarize(watched, airedTotal);
  final dated =
      [
        for (final w in watched)
          if (w.at != null) w,
      ]..sort((a, b) {
        final c = a.at!.compareTo(b.at!);
        if (c != 0) return c;
        if (a.season != b.season) return a.season.compareTo(b.season);
        return a.number.compareTo(b.number);
      });

  final rated = [
    for (final w in watched)
      if (w.score != null) w,
  ];
  ({int season, int number, double score})? best, worst;
  if (rated.length >= 3) {
    final hi = rated.map((w) => w.score!).reduce((a, b) => a > b ? a : b);
    final lo = rated.map((w) => w.score!).reduce((a, b) => a < b ? a : b);
    final top = rated.where((w) => w.score == hi).toList();
    final bottom = rated.where((w) => w.score == lo).toList();
    if (top.length == 1) {
      best = (season: top.first.season, number: top.first.number, score: hi);
    }
    if (bottom.length == 1 && lo < hi) {
      worst = (
        season: bottom.first.season,
        number: bottom.first.number,
        score: lo,
      );
    }
  }

  ({int season, int number, int times})? topRewatch;
  for (final w in watched) {
    final times = w.e.watchCount - 1;
    if (times > 0 && (topRewatch == null || times > topRewatch.times)) {
      topRewatch = (season: w.season, number: w.number, times: times);
    }
  }

  final pauses = <SeasonPause>[];
  final datedSeasons = [
    for (final s in seasonStats)
      if (s.from != null) s,
  ];
  for (var i = 1; i < datedSeasons.length; i++) {
    final prev = datedSeasons[i - 1], next = datedSeasons[i];
    final days = _dayIndex(next.from!) - _dayIndex(prev.to!);
    if (days >= SeriesStats.pauseDays) {
      pauses.add(
        SeasonPause(
          afterSeason: prev.season,
          days: days,
          resumedAt: next.from!,
        ),
      );
    }
  }

  final watchedSet = {
    for (final w in watched) (season: w.season, number: w.number),
  };
  final finished =
      airedTotal > 0 &&
      seasonNumbers.every(
        (s) => airedOf[s]!.every(
          (n) => watchedSet.contains((season: s, number: n)),
        ),
      );

  return SeriesStats(
    minutes: total.minutes,
    estimated: total.estimated,
    watched: total.watched,
    aired: airedTotal,
    from: total.from,
    to: total.to,
    seasons: seasonStats,
    undated: watched.length - dated.length,
    record: _longestRun(dated, minutesOf),
    best: best,
    worst: worst,
    first: dated.isEmpty
        ? null
        : (
            season: dated.first.season,
            number: dated.first.number,
            at: dated.first.at!,
          ),
    last: dated.isEmpty
        ? null
        : (
            season: dated.last.season,
            number: dated.last.number,
            at: dated.last.at!,
          ),
    finished: finished,
    topRewatch: topRewatch,
    pauses: pauses,
  );
}

/// Отметки в одну минуту — пачка (сезон целиком одной датой), а не
/// просмотр подряд.
int _minuteStamp(DateTime d) => d.millisecondsSinceEpoch ~/ 60000;

Binge? _bestDay(List<_Watched> list, int Function(_Watched) minutesOf) {
  final days = <int, List<_Watched>>{};
  for (final w in list) {
    if (w.at == null) continue;
    days.putIfAbsent(_dayIndex(w.at!), () => []).add(w);
  }
  Binge? best;
  for (final key in days.keys.toList()..sort()) {
    final day = days[key]!;
    final count = day.map((w) => _minuteStamp(w.at!)).toSet().length;
    if (best == null || count > best.count) {
      final first = day.reduce((a, b) => a.at!.isBefore(b.at!) ? a : b);
      best = Binge(
        season: first.season,
        count: count,
        day: first.at!,
        minutes: day.fold(0, (a, w) => a + minutesOf(w)),
      );
    }
  }
  return best;
}

/// Серии подряд: следующая отмечена не раньше чем через 5 минут и не позже
/// чем через свою длительность и ещё полчаса.
Binge? _longestRun(List<_Watched> dated, int Function(_Watched) minutesOf) {
  if (dated.isEmpty) return null;
  List<_Watched> bestRun = const [];
  var bestMinutes = 0;
  var run = [dated.first];
  void close() {
    final m = run.fold<int>(0, (a, w) => a + minutesOf(w));
    if (run.length > bestRun.length ||
        (run.length == bestRun.length && m > bestMinutes)) {
      bestRun = run;
      bestMinutes = m;
    }
  }

  for (var i = 1; i < dated.length; i++) {
    final prev = dated[i - 1], cur = dated[i];
    final gap = cur.at!.difference(prev.at!).inMinutes;
    final limit = (cur.runtime ?? 60) + 30;
    if (gap >= 5 && gap <= limit) {
      run.add(cur);
    } else {
      close();
      run = [cur];
    }
  }
  close();
  if (bestRun.length < 2) return null;
  return Binge(
    season: bestRun.first.season,
    count: bestRun.length,
    day: bestRun.first.at!,
    minutes: bestMinutes,
  );
}
