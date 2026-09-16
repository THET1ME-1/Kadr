import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/tmdb_service.dart';
import 'package:kadr/utils/season_pick.dart';

/// Экран сериала открывается на сезоне, который человек смотрит сейчас.
/// Досмотрел сезон — открывается следующий, а не тот же самый.
void main() {
  final now = DateTime(2026, 9, 16);
  const past = '2026-01-01';
  const future = '2026-12-31';

  List<TmdbSeason> seasons(List<int> counts) => [
        for (var i = 0; i < counts.length; i++)
          TmdbSeason(number: i + 1, name: 'S${i + 1}', episodeCount: counts[i]),
      ];

  // Серии TMDB: по сезону — список дат выхода.
  Future<List<TmdbEpisode>> Function(int) tmdb(Map<int, List<String?>> air) =>
      (season) async => [
            for (var i = 0; i < (air[season] ?? const []).length; i++)
              TmdbEpisode(
                season: season,
                number: i + 1,
                name: 'E${i + 1}',
                airDate: air[season]![i],
              ),
          ];

  Episode ep(int season, int number, [DateTime? at]) =>
      Episode(season: season, number: number, watchedAt: at);

  final air = {
    1: [past, past, past],
    2: [past, past, past],
  };

  Future<int> pick(List<Episode> watched,
          {List<int> counts = const [3, 3],
          Map<int, List<String?>>? episodes}) =>
      pickInitialSeason(
        seasons: seasons(counts),
        watched: watched,
        episodesOf: tmdb(episodes ?? air),
        now: now,
      );

  test('досмотренный сезон открывает следующий', () async {
    final watched = [
      ep(1, 1, DateTime(2026, 9, 1)),
      ep(1, 2, DateTime(2026, 9, 2)),
      ep(1, 3, DateTime(2026, 9, 3)),
    ];
    expect(await pick(watched), 2);
  });

  test('недосмотренный сезон остаётся открытым', () async {
    final watched = [
      ep(1, 1, DateTime(2026, 9, 1)),
      ep(1, 2, DateTime(2026, 9, 2)),
    ];
    expect(await pick(watched), 1);
  });

  test('после последнего сезона переходить некуда', () async {
    final watched = [
      for (var n = 1; n <= 3; n++) ep(2, n, DateTime(2026, 9, n)),
    ];
    expect(await pick(watched), 2);
  });

  test('сезон, отмеченный целиком одной датой, тоже досмотрен', () async {
    final at = DateTime(2026, 9, 5);
    final watched = [ep(1, 1, at), ep(1, 2, at), ep(1, 3, at)];
    expect(await pick(watched), 2);
  });

  test('невышедшие серии не держат сезон открытым', () async {
    final watched = [
      ep(1, 1, DateTime(2026, 9, 1)),
      ep(1, 2, DateTime(2026, 9, 2)),
    ];
    final episodes = {
      1: [past, past, future],
      2: [past, past, past],
    };
    expect(await pick(watched, episodes: episodes), 2);
  });

  test('серии без дат: сезон ищется по самой дальней отметке', () async {
    final watched = [ep(1, 1), ep(1, 2), ep(1, 3), ep(2, 1)];
    expect(await pick(watched), 2);
  });

  test('досмотренный без дат сезон тоже открывает следующий', () async {
    final watched = [ep(1, 1), ep(1, 2), ep(1, 3)];
    expect(await pick(watched), 2);
  });

  test('TMDB не отдал серии — остаёмся на сезоне последней отметки', () async {
    final watched = [
      for (var n = 1; n <= 3; n++) ep(1, n, DateTime(2026, 9, n)),
    ];
    expect(await pick(watched, episodes: {2: [past]}), 1);
  });

  test('ничего не смотрел — первый сезон', () async {
    expect(await pick(const []), 1);
  });
}
