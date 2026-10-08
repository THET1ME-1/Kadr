import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/tmdb_service.dart';
import 'package:kadr/utils/series_finale.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Серии подряд с шагом в час, начиная с [from].
List<Episode> _run(int season, int count, DateTime from, {int first = 1}) => [
  for (var i = 0; i < count; i++)
    Episode(
      season: season,
      number: first + i,
      watchedAt: from.add(Duration(hours: i)),
    ),
];

LibrarySeries _series(List<Episode> eps, {SeriesAir? air, bool dropped = false}) =>
    LibrarySeries(
      tvShowId: 'aot',
      title: 'Атака титанов',
      episodes: eps,
      air: air,
      dropped: dropped,
    );

SeriesAir _ended(int aired) =>
    SeriesAir(status: 'Ended', aired: aired, lastSeason: 1);

SeriesAir _returning(int aired, {int lastSeason = 1}) =>
    SeriesAir(status: 'Returning Series', aired: aired, lastSeason: lastSeason);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleController.instance.setCode('ru');
  });

  group('статус сериала', () {
    final eps = _run(1, 3, DateTime(2026, 10, 7, 20));

    test('сериал закрыт и все серии отмечены: досмотрел', () {
      expect(seriesRun(_series(eps, air: _ended(3))), SeriesRun.finished);
    });

    test('сериал выходит и все вышедшие отмечены: догнал', () {
      expect(seriesRun(_series(eps, air: _returning(3))), SeriesRun.caughtUp);
    });

    test('вышла серия, которой нет в отметках: смотрю', () {
      expect(seriesRun(_series(eps, air: _returning(4))), SeriesRun.watching);
    });

    test('без TMDB решает ручная отметка «Досмотрел»', () {
      final s = _series(eps)..finished = true;
      expect(seriesRun(s), SeriesRun.finished);
      expect(seriesRun(_series(eps)), SeriesRun.watching);
    });

    test('брошенный сериал финала не получает', () {
      expect(
        seriesRun(_series(eps, air: _ended(3), dropped: true)),
        SeriesRun.watching,
      );
    });

    test('спецвыпуски не засчитываются в просмотренные', () {
      final withSpecial = [
        ..._run(1, 2, DateTime(2026, 10, 7, 20)),
        Episode(season: 0, number: 1, watchedAt: DateTime(2026, 10, 7, 23)),
      ];
      expect(
        seriesRun(_series(withSpecial, air: _ended(3))),
        SeriesRun.watching,
      );
    });
  });

  group('срок просмотра', () {
    test('длинный перерыв между заходами в срок не входит', () {
      // Первый сезон за 20 дней два года назад, остальное за два месяца.
      final days = activeDays([
        DateTime(2024, 9, 1),
        DateTime(2024, 9, 20),
        DateTime(2026, 8, 8),
        DateTime(2026, 10, 7),
      ]);
      expect(days, 20 + 61);
      expect(spanLabel(days), 'за 3 месяца');
    });

    test('всё за один вечер', () {
      final days = activeDays([
        DateTime(2026, 10, 7, 20),
        DateTime(2026, 10, 7, 23),
      ]);
      expect(spanLabel(days), 'за один день');
    });

    test('неделя пишется днями, больше года годами', () {
      expect(spanLabel(6), 'за 6 дней');
      expect(spanLabel(800), 'за 2 года');
    });

    test('сериал отмечен одной пачкой: срока нет', () {
      final at = DateTime(2025, 3, 1, 12, 0);
      final days = activeDays([
        for (var i = 0; i < 10; i++) at.add(Duration(seconds: i)),
      ]);
      expect(days, isNull);
      expect(spanLabel(days), isNull);
    });
  });

  group('плашка на сессии', () {
    test('финал стоит на сессии с последней серией, а не раньше', () {
      final s = _series([
        ..._run(1, 2, DateTime(2026, 10, 1, 20)),
        ..._run(1, 2, DateTime(2026, 10, 7, 20), first: 3),
      ], air: _ended(4));
      final sessions = s.sessions();
      expect(sessions, hasLength(2));
      expect(milestoneOf(sessions.first), isNull);
      final m = milestoneOf(sessions.last)!;
      expect(m.finale, isTrue);
      expect(
        milestoneLine(m, sessions.last),
        'Финал · 4\u00A0серии за\u00A07\u00A0дней',
      );
    });

    test('пересмотр после финала плашку не забирает', () {
      final eps = _run(1, 2, DateTime(2026, 10, 1, 20));
      eps.last.rewatchViews.add(Viewing(date: DateTime(2026, 10, 20, 21)));
      final s = _series(eps, air: _ended(2));
      final sessions = s.sessions();
      expect(milestoneOf(sessions.first)!.finale, isTrue);
      expect(milestoneOf(sessions.last), isNull);
    });

    test('догнал: ждём следующий сезон', () {
      final s = _series(
        _run(3, 2, DateTime(2026, 10, 2, 22)),
        air: _returning(2, lastSeason: 3),
      );
      final session = s.sessions().single;
      final m = milestoneOf(session)!;
      expect(m.finale, isFalse);
      expect(m.current, isTrue);
      expect(milestoneLine(m, session), 'Догнал · ждём 4-й сезон');
    });

    test('догнал: дата нового сезона известна', () {
      final s = _series(
        _run(3, 2, DateTime(2026, 10, 2, 22)),
        air: SeriesAir(
          status: 'Returning Series',
          aired: 2,
          lastSeason: 3,
          nextSeason: 4,
          nextDate: '2027-03-12',
        ),
      );
      final session = s.sessions().single;
      expect(
        milestoneLine(milestoneOf(session)!, session),
        'Догнал · 4-й сезон 12 мар',
      );
    });
  });

  group('сведения TMDB', () {
    const seasons = [
      TmdbSeason(number: 1, name: 'S1', episodeCount: 10),
      TmdbSeason(number: 2, name: 'S2', episodeCount: 8),
    ];

    test('вышедшие серии: прошлые сезоны целиком плюс номер последней', () {
      final air = TmdbService.airFromTv({
        'status': 'Returning Series',
        'last_episode_to_air': {'season_number': 2, 'episode_number': 5},
        'next_episode_to_air': {
          'season_number': 2,
          'episode_number': 6,
          'air_date': '2026-10-15',
        },
      }, seasons, DateTime(2026, 10, 8));
      expect(air.status, 'Returning Series');
      expect(air.aired, 15);
      expect(air.lastSeason, 2);
      expect(air.nextNumber, 6);
      expect(air.nextDate, '2026-10-15');
      expect(air.checkedAt, DateTime(2026, 10, 8));
    });

    test('последней вышла спецсерия: число вышедших неизвестно', () {
      final air = TmdbService.airFromTv({
        'status': 'Ended',
        'last_episode_to_air': {'season_number': 0, 'episode_number': 3},
      }, seasons, DateTime(2026, 10, 8));
      expect(air.aired, isNull);
    });
  });

  group('история «Догнал»', () {
    test('вышла новая серия: плашка в истории остаётся', () async {
      final s = _series(
        _run(3, 2, DateTime(2026, 10, 2, 22)),
        air: _returning(2, lastSeason: 3),
      );
      final repo = MovieRepository.detached(
        jsonDecode(jsonEncode({'series': [s.toJson()]})) as Map<String, dynamic>,
      );
      await repo.setSeriesAir('aot', _returning(3, lastSeason: 4));
      final now = repo.seriesById('aot')!;
      expect(seriesRun(now), SeriesRun.watching);
      final session = now.sessions().single;
      final m = milestoneOf(session)!;
      expect(m.current, isFalse);
      expect(milestoneLine(m, session), 'Догнал 3-й сезон');
    });

    test('сведения о выходе и история переживают сохранение', () {
      final s = _series(
        _run(1, 1, DateTime(2026, 10, 2, 22)),
        air: SeriesAir(
          status: 'Returning Series',
          aired: 1,
          lastSeason: 1,
          nextSeason: 2,
          nextNumber: 1,
          nextDate: '2027-01-05',
          checkedAt: DateTime(2026, 10, 8),
        ),
      )..caughtUpAt.add(DateTime(2026, 5, 1, 21));
      final back = LibrarySeries.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.air!.status, 'Returning Series');
      expect(back.air!.aired, 1);
      expect(back.air!.nextDate, '2027-01-05');
      expect(back.air!.checkedAt, DateTime(2026, 10, 8));
      expect(back.caughtUpAt, [DateTime(2026, 5, 1, 21)]);
    });
  });
}
