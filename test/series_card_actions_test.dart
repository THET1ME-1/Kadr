import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/series_screen.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Кнопки экрана сериала по варианту Б макета «Кнопки карточки», как у
/// фильма: под оценкой одна связанная группа, широких кнопок «В списке»,
/// «Бросить» и «Написать рецензию» нет.

/// TMDB в тесте: один сезон из трёх вышедших серий, без картинок.
MockClient _tmdb(int tvId) => MockClient((req) async {
      Map<String, dynamic>? body;
      if (req.url.path.endsWith('/tv/$tvId')) {
        body = {
          'first_air_date': '2021-11-06',
          'status': 'Ended',
          'seasons': [
            {
              'season_number': 1,
              'name': 'Сезон 1',
              'episode_count': 3,
              'air_date': '2021-11-06',
            },
          ],
          'last_episode_to_air': {'season_number': 1, 'episode_number': 3},
        };
      } else if (req.url.path.endsWith('/tv/$tvId/season/1')) {
        body = {
          'episodes': [
            for (var n = 1; n <= 3; n++)
              {
                'season_number': 1,
                'episode_number': n,
                'name': 'Серия $n',
                'air_date': '2021-11-06',
                'runtime': 40,
              },
          ],
        };
      }
      return body == null
          ? http.Response('{}', 404)
          : http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
    });

/// Начатый сериал: две серии из трёх отмечены.
LibrarySeries _started(String id, int tvId, {bool watchlist = false}) =>
    LibrarySeries(
      tvShowId: id,
      title: 'Гангстерленд',
      tmdbId: tvId,
      watchlist: watchlist,
      episodes: [
        for (var n = 1; n <= 2; n++)
          Episode(
              season: 1, number: n, watchedAt: DateTime(2026, 10, 1, 21, n)),
      ],
    );

/// Сериал без отмеченных серий.
LibrarySeries _fresh(String id, int tvId) =>
    LibrarySeries(tvShowId: id, title: 'Гангстерленд', tmdbId: tvId);

Future<MovieRepository> _open(WidgetTester tester, LibrarySeries s, int tvId,
    {String lang = 'ru', double width = 700}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  // Библиотека пишет себя на диск после каждой правки. Каталога документов
  // в тесте нет: канал отвечает ошибкой сразу, запись её глотает.
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      paths, (_) async => throw PlatformException(code: 'no-dir'));
  addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
  final repo = MovieRepository.instance;
  await tester.runAsync(() => repo.restoreFromSnapshot(const [], [s.toJson()]));
  await http.runWithClient(
    () async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: SeriesScreen(series: repo.seriesById(s.tvShowId)!),
      ));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'экран сериала не догрузился');
    },
    () => _tmdb(tvId),
  );
  return repo;
}

void main() {
  testWidgets('начатый: одна группа, широких кнопок нет', (tester) async {
    await _open(tester, _started('g1', 9201), 9201);
    for (final gone in ['Написать рецензию', 'В списке', 'Буду смотреть',
        'Бросить']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    // Группа: любимое и «Бросить» значками, рецензия подписью, одним рядом.
    final fav = tester.getRect(find.byTooltip('Избранное'));
    final review = tester.getRect(find.text('Рецензия'));
    final drop = tester.getRect(find.byTooltip('Бросить'));
    expect(review.center.dy, closeTo(fav.center.dy, 1));
    expect(drop.center.dy, closeTo(fav.center.dy, 1));
    // Группа стоит под оценкой.
    final score = tester.getRect(find.text('Оценить сериал'));
    expect(review.top, greaterThan(score.bottom));
  });

  testWidgets('«Рецензия» начинает рецензию с выбора охвата', (tester) async {
    await _open(tester, _started('g2', 9202), 9202);
    await tester.tap(find.text('Рецензия'));
    await tester.pumpAndSettle();
    expect(find.text(tr('rvs_scope_title')), findsOneWidget);
  });

  testWidgets('«Бросить» в группе бросает сериал и возвращает', (tester) async {
    final repo = await _open(tester, _started('g3', 9203), 9203);
    await tester.tap(find.byTooltip('Бросить'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('g3')!.dropped, isTrue);
    // Включённая кнопка подписана «Брошено», тап снимает отметку.
    await tester.tap(find.byTooltip('Брошено'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('g3')!.dropped, isFalse);
  });

  testWidgets('сердечко в группе включает избранное', (tester) async {
    final repo = await _open(tester, _started('g4', 9204), 9204);
    await tester.tap(find.byTooltip('Избранное'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('g4')!.favorite, isTrue);
  });

  testWidgets('не начатый: «Буду смотреть» в группе, рецензии нет',
      (tester) async {
    final repo = await _open(tester, _fresh('f1', 9205), 9205);
    expect(find.text('Рецензия'), findsNothing);
    expect(find.text('Написать рецензию'), findsNothing);
    await tester.tap(find.text('Буду смотреть'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('f1')!.watchlist, isTrue);
    expect(find.widgetWithText(FilledButton, 'В списке'), findsOneWidget);
  });

  testWidgets('начатый в «Буду смотреть»: закладка значком снимает отметку',
      (tester) async {
    final repo =
        await _open(tester, _started('g5', 9206, watchlist: true), 9206);
    expect(find.text('Рецензия'), findsOneWidget);
    await tester.tap(find.byTooltip('В списке'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('g5')!.watchlist, isFalse);
    expect(find.byTooltip('В списке'), findsNothing);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    for (final started in [true, false]) {
      testWidgets('320 dp без переполнений, $lang, '
          '${started ? 'начатый' : 'не начатый'}', (tester) async {
        final id = '${started ? 's' : 'n'}$lang';
        final tvId = 9300 + lang.hashCode % 500 + (started ? 1000 : 0);
        await _open(tester, started ? _started(id, tvId) : _fresh(id, tvId),
            tvId,
            lang: lang, width: 320);
        expect(tester.takeException(), isNull);
        expect(find.byTooltip(tr('act_favorite')), findsOneWidget);
      });
    }
  }
}
