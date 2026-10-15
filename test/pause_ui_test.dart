import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/library_tab.dart';
import 'package:kadr/screens/movie_sheet.dart';
import 'package:kadr/screens/viewing/drop_sheet.dart';
import 'package:kadr/screens/viewing/viewing_host.dart';
import 'package:kadr/screens/viewing/viewing_sheet.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/rating_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Фильм в несколько заходов на экранах (макет «Фильм в несколько заходов»,
/// П1 + Г2 + Ф3): «Досмотрю потом» в меню у главной кнопки и короткое окно
/// «Где остановились?», начатый фильм в ленте карточкой в тон, после
/// досмотра строки «начал» и «продолжил» в дни заходов.

final _oct14 = DateTime(2026, 10, 14, 21, 40);
final _oct15 = DateTime(2026, 10, 15, 22, 10);

LibraryMovie _mercy({
  required List<Viewing> viewings,
  LibraryStatus status = LibraryStatus.watched,
  String uuid = 'jm',
}) =>
    LibraryMovie(
      uuid: uuid,
      title: 'Just Mercy',
      ruTitle: 'Просто помиловать',
      titleLang: 'ru',
      year: 2019,
      runtimeMin: 137,
      status: status,
      viewings: viewings,
    );

Viewing _paused() =>
    Viewing(id: 'a', date: _oct14, pause: PauseMark(atMin: 52));

MovieRepository _detached(List<LibraryMovie> movies) => MovieRepository.detached(
      jsonDecode(jsonEncode({
        'movies': [for (final m in movies) m.toJson()],
      })) as Map<String, dynamic>,
    );

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('Ещё действия'));
  await tester.tap(find.byTooltip('Ещё действия'));
  await tester.pumpAndSettle();
}

Future<MovieRepository> _openCard(WidgetTester tester, LibraryMovie m,
    {String lang = 'ru', double width = 700}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      paths, (_) async => throw PlatformException(code: 'no-dir'));
  addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
  final repo = MovieRepository.instance;
  await tester.runAsync(() => repo.restoreFromSnapshot([m.toJson()], const []));
  await http.runWithClient(
    () async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: MovieScreen(movie: repo.byUuid(m.uuid)!),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
    () => MockClient((_) async => http.Response('{}', 404)),
  );
  return repo;
}

Future<void> _pumpFeed(WidgetTester tester, MovieRepository repo,
    {String lang = 'ru', double width = 400}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(AppTheme.defaultSeed),
    home: Scaffold(
      body: LibraryTab(
        mode: LibraryMode.watched,
        repository: repo,
        readOnly: true,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openViewing(
    WidgetTester tester, MovieRepository repo, String viewId) async {
  tester.view.physicalSize = const Size(400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode('ru'));
  final host = MovieViewingHost('jm', repo: repo);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(AppTheme.defaultSeed),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => showViewingSheet(context, host, viewId: viewId),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('окно «Где остановились?»', () {
    Future<PauseChoice?> run(WidgetTester tester, Future<void> Function() act,
        {String lang = 'ru', double width = 380, bool first = true}) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      PauseChoice? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showPauseSheet(
                    context,
                    subject: 'Просто помиловать',
                    runtimeMin: 137,
                    initialMin: first ? null : 52,
                    first: first,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('минута и день без причин, кнопка «Досмотрю потом»',
        (tester) async {
      final r = await run(tester, () async {
        expect(find.text('Где остановились?'), findsOneWidget);
        expect(find.text('Начал'), findsOneWidget);
        expect(find.byType(FilterChip), findsNothing);
        final box = tester.getRect(find.byType(RatingSlider));
        await tester.tapAt(Offset(
            box.left + 24 + (box.width - 48) * 52 / 137, box.center.dy));
        await tester.pumpAndSettle();
        await _tapText(tester, 'Досмотрю потом');
      });
      expect(r, isNotNull);
      expect(r!.atMin, closeTo(52, 2));
      expect(r.date, isNotNull);
    });

    testWidgets('следующий заход: минута с прошлого раза, день «Когда»',
        (tester) async {
      await run(tester, () async {
        expect(find.text('52'), findsWidgets);
        expect(find.text('Когда'), findsOneWidget);
      }, first: false);
    });

    for (final lang in LocaleController.languages.map((l) => l.code)) {
      testWidgets('320 dp без переполнений, $lang', (tester) async {
        await run(tester, () async {}, lang: lang, width: 320, first: false);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('карточка фильма', () {
    testWidgets('«Досмотрю потом» в меню записывает начатый фильм',
        (tester) async {
      final repo = await _openCard(
          tester,
          _mercy(
              uuid: 'p1',
              viewings: const [],
              status: LibraryStatus.watchlist));
      await _openMenu(tester);
      await _tapText(tester, 'Досмотрю потом');
      expect(find.text('Где остановились?'), findsOneWidget);
      final button = find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Досмотрю потом'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final m = repo.byUuid('p1')!;
      expect(m.pausedViewing, isNotNull);
      expect(repo.watchlist, isEmpty);
      expect(find.text('Досмотрел'), findsOneWidget);
      // «Начат» у метки статуса и у строки в «Просмотрах»: минуту не ставили.
      expect(find.text('Начат'), findsNWidgets(2));
    });

    testWidgets('начатый: блок наверху, «Досмотрел», оценка после досмотра',
        (tester) async {
      await _openCard(tester, _mercy(uuid: 'p2', viewings: [_paused()]));
      expect(
          find.text(DateTime.now().year == 2026
              ? 'Начат 14 октября'
              : 'Начат 14 октября 2026'),
          findsOneWidget);
      expect(find.text('остановился на 52-й минуте из 137'), findsOneWidget);
      expect(find.text('Досмотрел'), findsOneWidget);
      expect(find.text('Отметить просмотр'), findsNothing);
      expect(find.text('Досмотрите фильм, чтобы его оценить'), findsOneWidget);
      await _openMenu(tester);
      expect(find.text('Досмотрю потом'), findsOneWidget);
      expect(find.text('Бросить'), findsOneWidget);
    });

    testWidgets('«Досмотрел» спрашивает день и делает просмотр', (tester) async {
      final repo =
          await _openCard(tester, _mercy(uuid: 'p3', viewings: [_paused()]));
      await _tapText(tester, 'Досмотрел');
      expect(find.text('Когда досмотрели?'), findsOneWidget);
      await _tapText(tester, tr('when_now'));
      final m = repo.byUuid('p3')!;
      expect(m.isWatched, isTrue);
      expect(m.viewings.single.parts.single.date, _oct14);
      expect(m.viewings.single.parts.single.toMin, 52);
    });

    testWidgets('«Бросить» у начатого: окно «Где бросили?» с той же минутой',
        (tester) async {
      final repo =
          await _openCard(tester, _mercy(uuid: 'p4', viewings: [_paused()]));
      await _openMenu(tester);
      await _tapText(tester, 'Бросить');
      expect(find.text('Где бросили?'), findsOneWidget);
      expect(find.text('52'), findsWidgets);
      final button = find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Бросить'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final m = repo.byUuid('p4')!;
      expect(m.isDropped, isTrue);
      expect(m.viewings.single.drop?.atMin, 52);
      expect(m.viewings.single.date, _oct14);
    });

    for (final lang in LocaleController.languages.map((l) => l.code)) {
      testWidgets('320 dp без переполнений у начатого, $lang', (tester) async {
        await _openCard(tester, _mercy(uuid: 'w$lang', viewings: [_paused()]),
            lang: lang, width: 320);
        expect(tester.takeException(), isNull);
        expect(find.text(tr('drop_finished')), findsOneWidget);
      });
    }
  });

  group('лента «Просмотрено»', () {
    testWidgets('начатый: карточка в тон с минутами', (tester) async {
      await _pumpFeed(tester, _detached([_mercy(viewings: [_paused()])]));
      expect(find.text('Просто помиловать'), findsOneWidget);
      expect(find.text('52 из 137 мин'), findsOneWidget);
    });

    testWidgets('досмотренный в два захода: карточка и строка «начал»',
        (tester) async {
      await _pumpFeed(
        tester,
        _detached([
          _mercy(viewings: [
            Viewing(
                id: 'a',
                date: _oct15,
                score: 8.5,
                parts: [Sitting(date: _oct14, toMin: 52)]),
          ]),
        ]),
      );
      expect(find.text('Просто помиловать'), findsNWidgets(2));
      expect(find.text('начал · до 52-й мин'), findsOneWidget);
      expect(find.text('14 октября 2026'), findsOneWidget);
      expect(find.text('15 октября 2026'), findsOneWidget);
    });

    testWidgets('три захода: «начал» и «продолжил» в свои дни',
        (tester) async {
      await _pumpFeed(
        tester,
        _detached([
          _mercy(viewings: [
            Viewing(id: 'a', date: _oct15, parts: [
              Sitting(date: DateTime(2026, 10, 1, 20), toMin: 64),
              Sitting(date: DateTime(2026, 10, 8, 22, 5), toMin: 115),
            ]),
          ]),
        ]),
      );
      expect(find.text('начал · до 64-й мин'), findsOneWidget);
      expect(find.text('продолжил · до 115-й мин'), findsOneWidget);
    });

    for (final lang in LocaleController.languages.map((l) => l.code)) {
      testWidgets('320 dp без переполнений, $lang', (tester) async {
        await _pumpFeed(
          tester,
          _detached([
            _mercy(uuid: 'a', viewings: [_paused()]),
            _mercy(uuid: 'b', viewings: [
              Viewing(
                  id: 'b',
                  date: _oct15,
                  parts: [Sitting(date: _oct14, toMin: 52)]),
            ]),
          ]),
          lang: lang,
          width: 320,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('окно просмотра', () {
    testWidgets('начатый: строка «Остановился» и «Досмотрел»', (tester) async {
      final repo = _detached([_mercy(viewings: [_paused()])]);
      await _openViewing(tester, repo, 'a');
      expect(find.text('Остановился'), findsOneWidget);
      expect(find.text('на 52-й мин'), findsOneWidget);
      await _tapText(tester, 'Досмотрел');
      expect(find.text('Когда досмотрели?'), findsOneWidget);
      await _tapText(tester, tr('when_now'));
      final v = repo.byUuid('jm')!.viewings.single;
      expect(v.isFull, isTrue);
      expect(v.parts.single.date, _oct14);
    });

    testWidgets('досмотренный: «Начал» задним числом, строка «Досмотрел»',
        (tester) async {
      final repo = _detached([
        _mercy(viewings: [
          Viewing(
              id: 'a', date: _oct15, parts: [Sitting(date: _oct14, toMin: 52)]),
        ]),
      ]);
      await _openViewing(tester, repo, 'a');
      expect(find.text('Начал'), findsOneWidget);
      expect(find.text('14.10.2026 21:40'), findsOneWidget);
      expect(find.text('Досмотрел'), findsOneWidget);
      expect(find.text('15.10.2026 22:10'), findsOneWidget);
    });

    testWidgets('просмотр в один вечер: «Начал» в тот же день', (tester) async {
      final repo = _detached([
        _mercy(viewings: [Viewing(id: 'a', date: _oct15)]),
      ]);
      await _openViewing(tester, repo, 'a');
      expect(find.text('Начал'), findsOneWidget);
      expect(find.text('В тот же день'), findsOneWidget);
      expect(find.text('Когда'), findsOneWidget);
    });
  });
}
