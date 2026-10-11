import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/series_screen.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Сериал, у которого первый сезон досмотрен один раз, а пересмотр начат:
/// первые две серии смотрели дважды, третью один раз.
LibrarySeries _series(String id, int tvId) => LibrarySeries(
      tvShowId: id,
      title: 'Аркейн',
      tmdbId: tvId,
      episodes: [
        for (var n = 1; n <= 3; n++)
          Episode(
            season: 1,
            number: n,
            watchedAt: DateTime(2023, 5, 29, 13, n),
            score: 9.0 + n * 0.2,
            rewatchViews: [
              if (n <= 2) Viewing(date: DateTime(2026, 8, 18, 20, n)),
            ],
          ),
      ],
    );

Future<MovieRepository> _open(WidgetTester tester, String id, int tvId) async {
  SharedPreferences.setMockInitialValues({});
  // Шире телефона: строка кнопок под шапкой рассчитана на настоящий шрифт,
  // а тестовый вдвое шире.
  tester.view.physicalSize = const Size(700, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode('ru'));
  // Библиотека пишет себя на диск после каждой правки. Каталога документов
  // в тесте нет: канал отвечает ошибкой сразу, запись её глотает. Без
  // заглушки ответ не придёт вовсе, и экран зависнет на загрузке.
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      paths, (_) async => throw PlatformException(code: 'no-dir'));
  addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
  final repo = MovieRepository.instance;
  await tester.runAsync(
      () => repo.restoreFromSnapshot(const [], [_series(id, tvId).toJson()]));
  await http.runWithClient(
    () async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: SeriesScreen(series: repo.seriesById(id)!),
      ));
      // Сезоны и серии грузятся цепочкой запросов: даём ей пройти.
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

Episode _ep(MovieRepository repo, String id, int n) =>
    repo.seriesById(id)!.watchedEpisode(1, n)!;

void main() {
  testWidgets('пересмотр сезона: кнопка, полоса и окно отметки', (
    tester,
  ) async {
    final repo = await _open(tester, 'arc1', 9101);
    // Пересмотр начат: кнопка досматривает оставшуюся серию, полоса
    // показывает ход.
    expect(find.text('Отметить ещё 1'), findsOneWidget);
    expect(find.text('2-й просмотр · 2 из 3'), findsOneWidget);
    expect(find.text('начат 18.08.2026'), findsOneWidget);
    expect(find.text('Снять весь сезон'), findsNothing);

    await tester.tap(find.text('Отметить ещё 1'));
    await tester.pumpAndSettle();
    expect(find.text('Когда досмотрели сезон?'), findsOneWidget);
    expect(find.text('2-й просмотр'), findsOneWidget);
    expect(find.text('Сезон 1 · осталась 1 серия из 3'), findsOneWidget);
    expect(find.text('Снять все просмотры сезона'), findsOneWidget);

    await tester.tap(find.text('Не помню'));
    await tester.pumpAndSettle();
    // Третья серия получила второй просмотр без даты, остальные не тронуты.
    expect(_ep(repo, 'arc1', 3).watchCount, 2);
    expect(_ep(repo, 'arc1', 3).rewatchViews.single.date, isNull);
    expect(_ep(repo, 'arc1', 1).watchCount, 2);
    // Просмотр закончен: кнопка предлагает следующий, полоса подводит итог.
    expect(find.text('Пересмотреть сезон'), findsOneWidget);
    expect(find.text('Сезон просмотрен 2 раза'), findsOneWidget);
  });

  testWidgets('галочка серии: тап спрашивает дату, удержание открывает '
      'просмотр', (tester) async {
    final repo = await _open(tester, 'arc2', 9102);
    // У пересмотренных серий на галочке число просмотров.
    expect(find.text('×2'), findsNWidgets(2));
    await tester.ensureVisible(find.text('×2').first);
    await tester.tap(find.text('×2').first);
    await tester.pumpAndSettle();
    expect(find.text('Когда посмотрели?'), findsOneWidget);
    expect(find.text('3-й просмотр'), findsOneWidget);
    await tester.tap(find.text('Только что'));
    await tester.pumpAndSettle();
    expect(_ep(repo, 'arc2', 1).watchCount, 3);
    expect(find.text('×3'), findsOneWidget);
    // Следующие серии от пересмотра первой не меняются.
    expect(_ep(repo, 'arc2', 2).watchCount, 2);
    expect(_ep(repo, 'arc2', 3).watchCount, 1);

    await tester.longPress(find.text('×3'));
    await tester.pumpAndSettle();
    expect(find.text('Просмотр серии'), findsOneWidget);
    expect(find.text('Оценка просмотра'), findsOneWidget);
  });

  testWidgets('оценка на плитке серии — последняя, а не первого просмотра', (
    tester,
  ) async {
    final repo = await _open(tester, 'arc3', 9103);
    expect(find.text('9.2'), findsOneWidget);
    final first = _ep(repo, 'arc3', 1);
    await tester.runAsync(() => repo.setEpisodeViewScoreById(
        'arc3', 1, 1, first.rewatchViews.single.id, 7.5));
    await tester.pumpAndSettle();
    expect(find.text('7.5'), findsOneWidget);
    expect(find.text('9.2'), findsNothing);
  });

  testWidgets('тап по серии открывает окно серии с новыми кнопками', (
    tester,
  ) async {
    await _open(tester, 'arc4', 9104);
    await tester.ensureVisible(find.text('Серия 3'));
    await tester.tap(find.text('Серия 3'));
    await tester.pumpAndSettle();
    expect(find.text('Оценка серии'), findsOneWidget);
    expect(find.text('Смотрел ещё раз'), findsOneWidget);
    expect(find.text('Отменить просмотр'), findsOneWidget);
    expect(find.text('Просмотры · 1'), findsOneWidget);
    // «Смотрел ещё раз» спрашивает дату, а не пишет «сейчас» молча.
    await tester.tap(find.text('Смотрел ещё раз'));
    await tester.pumpAndSettle();
    expect(find.text('Когда посмотрели?'), findsOneWidget);
  });

  testWidgets('«Снять все просмотры сезона» спрашивает и даёт вернуть', (
    tester,
  ) async {
    final repo = await _open(tester, 'arc5', 9105);
    await tester.tap(find.text('Отметить ещё 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Снять все просмотры сезона'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repo.seriesById('arc5')!.episodes.length, 3);
    await tester.tap(find.widgetWithText(FilledButton, 'Снять'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('arc5')!.episodes, isEmpty);
    expect(find.text('Отметить весь сезон'), findsOneWidget);
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('arc5')!.episodes.length, 3);
    expect(_ep(repo, 'arc5', 1).watchCount, 2);
  });
}
