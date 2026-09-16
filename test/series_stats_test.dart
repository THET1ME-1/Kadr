import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/tmdb_service.dart';
import 'package:kadr/utils/series_stats.dart';

/// Статистика одного сериала: время у экрана, путь по сезонам, паузы и
/// акценты глав. Считается из отметок библиотеки и структуры TMDB.
void main() {
  final now = DateTime(2026, 9, 16);

  Episode ep(
    int s,
    int n, [
    DateTime? at,
    int? rt,
    double? score,
    int rewatches = 0,
  ]) => Episode(
    season: s,
    number: n,
    watchedAt: at,
    runtimeMin: rt,
    score: score,
    rewatchViews: [for (var i = 0; i < rewatches; i++) Viewing()],
  );

  List<TmdbSeason> structure(List<int> counts) => [
    for (var i = 0; i < counts.length; i++)
      TmdbSeason(number: i + 1, name: 'S${i + 1}', episodeCount: counts[i]),
  ];

  List<TmdbEpisode> tmdbSeason(
    int s,
    int count, {
    Map<int, int> runtimes = const {},
    Map<int, String> air = const {},
  }) => [
    for (var n = 1; n <= count; n++)
      TmdbEpisode(
        season: s,
        number: n,
        name: 'E$n',
        runtime: runtimes[n],
        airDate: air[n] ?? '2020-01-01',
      ),
  ];

  DateTime at(int month, int day, [int hour = 21, int minute = 0]) =>
      DateTime(2026, month, day, hour, minute);

  test(
    'время: своя длительность, затем TMDB, затем медиана; пересмотры в счёт',
    () {
      final st = computeSeriesStats(
        episodes: [
          ep(1, 1, at(2, 3), 50, null, 1),
          ep(1, 2, at(2, 4), null),
          ep(1, 3, at(2, 5), 999999),
        ],
        seasons: structure([3]),
        tmdb: {
          1: tmdbSeason(1, 3, runtimes: {1: 50, 2: 40}),
        },
        now: now,
      );
      // 50×2 за пересмотр + 40 из TMDB + медиана известных (50, 50, 40) = 50.
      expect(st.minutes, 190);
      expect(st.estimated, isTrue);
      expect(st.watched, 3);
      expect(st.aired, 3);
    },
  );

  test('даты: с первой по последнюю отметку, дни считаются включительно', () {
    final st = computeSeriesStats(
      episodes: [ep(1, 1, at(2, 3)), ep(1, 2, at(2, 5, 0, 30))],
      seasons: structure([2]),
      now: now,
    );
    expect(st.from, at(2, 3));
    expect(st.to, at(2, 5, 0, 30));
    expect(st.spanDays, 3);
  });

  test('сезон, отмеченный пачкой в одну минуту, — не марафон', () {
    final t = at(3, 1, 12);
    final st = computeSeriesStats(
      episodes: [for (var n = 1; n <= 5; n++) ep(1, n, t, 45)],
      seasons: structure([5]),
      now: now,
    );
    expect(st.record, isNull);
    expect(st.season(1)!.bestDay!.count, 1);
    expect(st.highlightFor(1)?.kind, isNot(HighlightKind.record));
  });

  test('марафон: серии подряд с промежутком не больше серии и получаса', () {
    final st = computeSeriesStats(
      episodes: [
        ep(1, 1, at(2, 1, 20, 0), 45),
        ep(1, 2, at(2, 1, 20, 50), 45),
        ep(1, 3, at(2, 1, 21, 40), 45),
        ep(1, 4, at(2, 2, 21, 0), 45),
        ep(2, 1, at(2, 3, 20, 0), 45),
        ep(2, 2, at(2, 3, 23, 0), 45),
      ],
      seasons: structure([4, 2]),
      now: now,
    );
    expect(st.record!.count, 3);
    expect(st.record!.season, 1);
    expect(st.record!.minutes, 135);
    expect(st.highlightFor(1)!.kind, HighlightKind.record);
    expect(st.season(1)!.bestDay!.count, 3);
  });

  test('пауза между сезонами показывается от недели', () {
    final st = computeSeriesStats(
      episodes: [ep(1, 1, at(2, 6)), ep(2, 1, at(2, 14)), ep(3, 1, at(2, 16))],
      seasons: structure([1, 1, 1]),
      now: now,
    );
    expect(st.pauses, hasLength(1));
    expect(st.pauses.single.afterSeason, 1);
    expect(st.pauses.single.days, 8);
    expect(st.pauses.single.resumedAt, at(2, 14));
  });

  test('досмотрен, когда отмечены все вышедшие серии; анонсы не мешают', () {
    final episodes = {
      1: tmdbSeason(1, 3),
      2: tmdbSeason(2, 3, air: {3: '2026-12-01'}),
    };
    final done = computeSeriesStats(
      episodes: [
        for (var n = 1; n <= 3; n++) ep(1, n, at(1, n)),
        ep(2, 1, at(2, 1)),
        ep(2, 2, at(2, 2)),
      ],
      seasons: structure([3, 3]),
      tmdb: episodes,
      now: now,
    );
    expect(done.finished, isTrue);
    expect(done.aired, 5);

    final notYet = computeSeriesStats(
      episodes: [for (var n = 1; n <= 3; n++) ep(1, n, at(1, n))],
      seasons: structure([3, 3]),
      tmdb: episodes,
      now: now,
    );
    expect(notYet.finished, isFalse);
    expect(notYet.last!.season, 1);
  });

  test('акценты: лучшая серия сериала, худшая, лучшая в сезоне', () {
    final st = computeSeriesStats(
      episodes: [
        ep(1, 1, at(1, 1), 45, 7),
        ep(1, 2, at(1, 3), 45, 8),
        ep(2, 1, at(1, 5), 45, 5),
        ep(2, 2, at(1, 7), 45, 7),
        ep(3, 1, at(1, 9), 45, 10),
        ep(3, 2, at(1, 11), 45, 8),
      ],
      seasons: structure([2, 2, 2]),
      now: now,
    );
    expect(st.highlightFor(3)!.kind, HighlightKind.bestOfSeries);
    expect(st.highlightFor(3)!.number, 1);
    expect(st.highlightFor(2)!.kind, HighlightKind.worstOfSeries);
    expect(st.highlightFor(2)!.score, 5);
    expect(st.highlightFor(1)!.kind, HighlightKind.bestOfSeason);
    expect(st.highlightFor(1)!.number, 2);
    expect(st.season(1)!.avgScore, 7.5);
  });

  test('лучшая серия сериала только одна: при ничьей акцента нет', () {
    final st = computeSeriesStats(
      episodes: [
        ep(1, 1, at(1, 1), 45, 10),
        ep(1, 2, at(1, 2), 45, 10),
        ep(1, 3, at(1, 3), 45, 6),
      ],
      seasons: structure([3]),
      now: now,
    );
    expect(st.best, isNull);
    expect(st.worst!.number, 3);
  });

  test('без дат: время и серии есть, линии и пауз нет', () {
    final st = computeSeriesStats(
      episodes: [ep(1, 1, null, 45), ep(1, 2, null, 45)],
      seasons: structure([2]),
      now: now,
    );
    expect(st.minutes, 90);
    expect(st.undated, 2);
    expect(st.from, isNull);
    expect(st.first, isNull);
    expect(st.pauses, isEmpty);
    expect(st.season(1)!.watched, 2);
  });

  test('серии за пределами структуры TMDB не считаются', () {
    final st = computeSeriesStats(
      episodes: [ep(1, 1, at(1, 1)), ep(1, 9, at(1, 2)), ep(4, 1, at(1, 3))],
      seasons: structure([3]),
      now: now,
    );
    expect(st.watched, 1);
    expect(st.seasons.map((s) => s.season), [1]);
    expect(st.to, at(1, 1));
  });

  test('без структуры TMDB сезоны берутся из отметок, спецвыпуски мимо', () {
    final st = computeSeriesStats(
      episodes: [ep(0, 1, at(1, 1)), ep(1, 1, at(1, 2)), ep(2, 3, at(1, 3))],
      seasons: const [],
      now: now,
    );
    expect(st.seasons.map((s) => s.season), [1, 2]);
    expect(st.season(2)!.marks.length, 3);
    expect(st.season(2)!.marks.where((m) => m.watched).single.number, 3);
  });

  test('самая пересматриваемая серия', () {
    final st = computeSeriesStats(
      episodes: [
        ep(1, 1, at(1, 1), 45, null, 1),
        ep(1, 2, at(1, 2), 45, null, 2),
      ],
      seasons: structure([2]),
      now: now,
    );
    expect(st.topRewatch!.number, 2);
    expect(st.topRewatch!.times, 2);
  });

  test('цифры сезона считаются отдельно от сериала', () {
    final st = computeSeriesStats(
      episodes: [
        ep(1, 1, at(1, 1), 30),
        ep(2, 1, at(1, 10), 60),
        ep(2, 2, at(1, 12), 60),
      ],
      seasons: structure([1, 3]),
      now: now,
    );
    final s2 = st.season(2)!;
    expect(s2.minutes, 120);
    expect(s2.watched, 2);
    expect(s2.aired, 3);
    expect(s2.from, at(1, 10));
    expect(s2.spanDays, 3);
    expect(st.minutes, 150);
  });
}
