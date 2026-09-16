import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/series_stats_screen.dart';
import 'package:kadr/services/tmdb_service.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пример: сериал на пять сезонов, досмотренный за полтора месяца, с
/// марафонами, паузой между третьим и четвёртым сезоном и пересмотром.
({
  LibrarySeries series,
  List<TmdbSeason> seasons,
  Map<int, List<TmdbEpisode>> tmdb,
})
sampleSeries() {
  const counts = [7, 13, 13, 13, 16];
  // (начало вечера, серий подряд)
  final plan = [
    (DateTime(2026, 2, 3, 21, 10), 2),
    (DateTime(2026, 2, 4, 22, 5), 2),
    (DateTime(2026, 2, 6, 20, 40), 3),
    (DateTime(2026, 2, 7, 15, 20), 5),
    (DateTime(2026, 2, 9, 21, 30), 1),
    (DateTime(2026, 2, 10, 22, 15), 2),
    (DateTime(2026, 2, 12, 21, 0), 2),
    (DateTime(2026, 2, 14, 18, 10), 3),
    (DateTime(2026, 2, 14, 23, 5), 3),
    (DateTime(2026, 2, 16, 21, 40), 1),
    (DateTime(2026, 2, 18, 22, 30), 2),
    (DateTime(2026, 2, 21, 14, 0), 4),
    (DateTime(2026, 2, 22, 23, 20), 3),
    (DateTime(2026, 3, 3, 21, 15), 2),
    (DateTime(2026, 3, 5, 22, 0), 2),
    (DateTime(2026, 3, 7, 16, 30), 6),
    (DateTime(2026, 3, 8, 22, 40), 3),
    (DateTime(2026, 3, 12, 21, 5), 2),
    (DateTime(2026, 3, 14, 13, 30), 5),
    (DateTime(2026, 3, 17, 23, 45), 2),
    (DateTime(2026, 3, 19, 21, 20), 2),
    (DateTime(2026, 3, 21, 22, 10), 3),
    (DateTime(2026, 3, 22, 20, 30), 2),
  ];
  final order = [
    for (var s = 1; s <= counts.length; s++)
      for (var n = 1; n <= counts[s - 1]; n++) (s, n),
  ];
  final episodes = <Episode>[];
  var i = 0;
  for (final (start, count) in plan) {
    var t = start;
    for (var k = 0; k < count; k++) {
      final (s, n) = order[i++];
      t = t.add(const Duration(minutes: 47));
      episodes.add(
        Episode(
          season: s,
          number: n,
          watchedAt: t,
          runtimeMin: 47,
          score: s == 5 && n == 14
              ? 10
              : s == 3 && n == 10
              ? 5.9
              : 7 + ((s * 7 + n * 3) % 5) * 0.5,
          rewatchViews: s == 5 && n == 14
              ? [
                  Viewing(date: DateTime(2026, 3, 29)),
                  Viewing(date: DateTime(2026, 4, 11)),
                ]
              : null,
        ),
      );
      t = t.add(const Duration(minutes: 5));
    }
  }
  final series = LibrarySeries(
    tvShowId: 'tv-bb',
    title: 'Во все тяжкие',
    episodes: episodes,
  );
  final seasons = [
    for (var s = 1; s <= counts.length; s++)
      TmdbSeason(number: s, name: 'S$s', episodeCount: counts[s - 1]),
  ];
  final names = {
    (1, 1): 'Пилот',
    (3, 10): 'Муха',
    (5, 14): 'Озимандия',
    (5, 16): 'Фелина',
  };
  final tmdb = {
    for (var s = 1; s <= counts.length; s++)
      s: [
        for (var n = 1; n <= counts[s - 1]; n++)
          TmdbEpisode(
            season: s,
            number: n,
            name: names[(s, n)] ?? 'Серия $n',
            runtime: 47,
            airDate: '2012-01-01',
          ),
      ],
  };
  return (series: series, seasons: seasons, tmdb: tmdb);
}

Widget app(
  ({
    LibrarySeries series,
    List<TmdbSeason> seasons,
    Map<int, List<TmdbEpisode>> tmdb,
  })
  d,
) => MaterialApp(
  theme: AppTheme.dark(AppTheme.defaultSeed),
  home: SeriesStatsScreen(
    series: d.series,
    seasons: d.seasons,
    preloaded: d.tmdb,
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('на 320 dp ничего не вылезает: $lang', (tester) async {
      tester.view.physicalSize = const Size(320, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));

      await tester.pumpWidget(app(sampleSeries()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('S5'), findsOneWidget);

      await tester.ensureVisible(find.text('S4'));
      await tester.tap(find.text('S4'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('выбор сезона переключает карточку и путь', (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));

    await tester.pumpWidget(app(sampleSeries()));
    await tester.pumpAndSettle();
    expect(find.text('62 из 62 серий'), findsOneWidget);
    expect(find.text('«Фелина». Сериал досмотрен'), findsOneWidget);
    expect(find.textContaining('Пауза 8 дней'), findsOneWidget);
    expect(
      find.textContaining('Рекорд сериала: 6 серий подряд'),
      findsOneWidget,
    );
    expect(
      find.text('Серию «Озимандия» пересматривали ещё 2 раза'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('S4'));
    await tester.tap(find.text('S4'));
    await tester.pumpAndSettle();
    expect(
      find.text(trn('ss_of_season_episodes', 13, {'a': 13})),
      findsOneWidget,
    );
    expect(find.text('Сезон 4'), findsOneWidget);
    expect(find.text('Сезон 3'), findsNothing);
    expect(find.textContaining('Пауза'), findsNothing);

    await tester.ensureVisible(find.text('Все'));
    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();
    expect(find.text('Сезон 3'), findsOneWidget);
  });
}
