import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
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

/// Брошенный фильм на экранах (KADR-1): окно «Где бросили?» с причинами как
/// «Слабое» в рецензии, попытка в ленте карточкой в тон, блок «Брошен» в
/// карточке фильма и «Досмотрел» в окне просмотра.

final _dropAt = DateTime(2026, 10, 14, 23, 10);

LibraryMovie _blonde({
  required List<Viewing> viewings,
  LibraryStatus status = LibraryStatus.watched,
  String uuid = 'b',
}) =>
    LibraryMovie(
      uuid: uuid,
      title: 'Blonde',
      ruTitle: 'Блондинка',
      titleLang: 'ru',
      year: 2022,
      runtimeMin: 166,
      status: status,
      viewings: viewings,
    );

Viewing _attempt({List<String> why = const ['Затянуто', 'Тяжело смотреть']}) =>
    Viewing(id: 'a', date: _dropAt, drop: DropMark(atMin: 52, reasons: [...why]));

MovieRepository _detached(List<LibraryMovie> movies) => MovieRepository.detached(
      jsonDecode(jsonEncode({
        'movies': [for (final m in movies) m.toJson()],
      })) as Map<String, dynamic>,
    );

Future<DropChoice?> _runSheet(
  WidgetTester tester,
  Future<void> Function() act, {
  DropMark? initial,
  MovieRepository? repo,
  String lang = 'ru',
  double width = 380,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  DropChoice? result;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(AppTheme.defaultSeed),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              result = await showDropSheet(
                context,
                subject: 'Блондинка',
                runtimeMin: 166,
                initial: initial,
                repo: repo ?? _detached(const []),
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

bool _chipOn(WidgetTester tester, String text) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, text)).selected;

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<MovieRepository> _openCard(WidgetTester tester, LibraryMovie m) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(700, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode('ru'));
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('окно «Где бросили?»', () {
    testWidgets('причина горит на своей полке, своё слово встаёт на «Свои»',
        (tester) async {
      final r = await _runSheet(tester, () async {
        expect(find.text('Где бросили?'), findsOneWidget);
        expect(find.text('Блондинка'), findsOneWidget);
        expect(find.text('ЧТО НЕ ТАК'), findsOneWidget);
        expect(find.text('Сюжет'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilterChip, 'Затянуто'));
        await tester.pumpAndSettle();
        expect(_chipOn(tester, 'Затянуто'), isTrue);
        await tester.enterText(find.byType(TextField), 'Плохой звук');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text('Свои'), findsOneWidget);
        expect(_chipOn(tester, 'Плохой звук'), isTrue);
        await _tapText(tester, 'Бросить');
      });
      expect(r, isNotNull);
      expect(r!.drop.reasons, ['Затянуто', 'Плохой звук']);
      expect(r.drop.atMin, isNull);
      expect(DateTime.now().difference(r.date!).inMinutes, 0);
    });

    testWidgets('линейка ставит минуту, крестик её убирает', (tester) async {
      final r = await _runSheet(tester, () async {
        expect(find.text('Минуту можно не ставить'), findsOneWidget);
        await tester.tap(find.byType(RatingSlider));
        await tester.pumpAndSettle();
        expect(find.textContaining('% фильма'), findsOneWidget);
        await tester.tap(find.byTooltip('Убрать'));
        await tester.pumpAndSettle();
        expect(find.text('Минуту можно не ставить'), findsOneWidget);
        await tester.tap(find.byType(RatingSlider));
        await tester.pumpAndSettle();
        await _tapText(tester, 'Бросить');
      });
      expect(r!.drop.atMin, inInclusiveRange(70, 96));
    });

    testWidgets('правка попытки: без даты, «Готово», прежнее на месте',
        (tester) async {
      final r = await _runSheet(
        tester,
        initial: DropMark(atMin: 52, reasons: ['Скучно']),
        () async {
          expect(find.text('Когда'), findsNothing);
          expect(find.text('52'), findsWidgets);
          expect(_chipOn(tester, 'Скучно'), isTrue);
          expect(find.text('31% фильма'), findsOneWidget);
          await _tapText(tester, 'Готово');
        },
      );
      expect(r!.drop.atMin, 52);
      expect(r.drop.reasons, ['Скучно']);
    });

    testWidgets('свои причины из прошлых попыток подсказываются',
        (tester) async {
      final repo = _detached([
        _blonde(viewings: [_attempt(why: ['Мутная картинка'])]),
      ]);
      await _runSheet(tester, repo: repo, () async {
        expect(find.text('Свои'), findsOneWidget);
        expect(_chipOn(tester, 'Мутная картинка'), isFalse);
      });
    });

    for (final lang in LocaleController.languages.map((l) => l.code)) {
      testWidgets('320 dp без переполнений, $lang', (tester) async {
        await _runSheet(
          tester,
          lang: lang,
          width: 320,
          initial: DropMark(
              atMin: 52, reasons: ['Затянуто', 'Очень длинная своя причина']),
          () async {},
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('лента «Просмотрено»', () {
    Future<void> pumpFeed(WidgetTester tester, MovieRepository repo) async {
      tester.view.physicalSize = const Size(400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
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

    testWidgets('попытка карточкой в тон: минута и причины', (tester) async {
      await pumpFeed(tester, _detached([_blonde(viewings: [_attempt()])]));
      expect(find.text('Блондинка'), findsOneWidget);
      expect(find.text('Брошен на 52-й мин'), findsOneWidget);
      expect(find.text('Затянуто'), findsOneWidget);
      expect(find.text('Тяжело смотреть'), findsOneWidget);
      expect(find.byIcon(Icons.heart_broken_rounded), findsWidgets);
    });

    testWidgets('досмотр после попытки не помечен пересмотром', (tester) async {
      await pumpFeed(
        tester,
        _detached([
          _blonde(viewings: [
            _attempt(),
            Viewing(id: 'f', date: DateTime(2026, 10, 15, 21), score: 7),
          ]),
        ]),
      );
      expect(find.text('Блондинка'), findsNWidgets(2));
      expect(find.byIcon(Icons.repeat_rounded), findsNothing);
    });
  });

  group('карточка фильма', () {
    testWidgets('брошенный: блок наверху, «Отметить просмотр», без «Бросить»',
        (tester) async {
      await _openCard(tester, _blonde(uuid: 'b1', viewings: [_attempt()]));
      // Год в заголовке блока только у прошлых лет.
      expect(
          find.text(DateTime.now().year == 2026
              ? 'Брошен 14 октября'
              : 'Брошен 14 октября 2026'),
          findsOneWidget);
      expect(find.text('на 52-й минуте из 166'), findsOneWidget);
      expect(find.text('Брошено'), findsOneWidget);
      expect(find.text('Отметить просмотр'), findsOneWidget);
      expect(find.text('Смотрел ещё раз'), findsNothing);
      expect(find.text('Бросить'), findsNothing);
      expect(find.text('Оценка брошенного просмотра'), findsOneWidget);
      expect(find.text('Брошен на 52-й мин'), findsOneWidget);
    });

    testWidgets('«Бросить» записывает попытку с причиной', (tester) async {
      final repo = await _openCard(
        tester,
        _blonde(
            uuid: 'b2',
            viewings: const [],
            status: LibraryStatus.watchlist),
      );
      // «Бросить» живёт в меню у главной кнопки.
      await tester.ensureVisible(find.byTooltip('Ещё действия'));
      await tester.tap(find.byTooltip('Ещё действия'));
      await tester.pumpAndSettle();
      await _tapText(tester, 'Бросить');
      expect(find.text('Где бросили?'), findsOneWidget);
      final boring = find.widgetWithText(FilterChip, 'Скучно');
      await tester.ensureVisible(boring);
      await tester.pumpAndSettle();
      await tester.tap(boring);
      await tester.pumpAndSettle();
      final button = find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Бросить'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final m = repo.byUuid('b2')!;
      expect(m.viewings.single.drop?.reasons, ['Скучно']);
      expect(m.isDropped, isTrue);
      expect(repo.watchlist, isEmpty);
      expect(find.text('Брошено. Попытка в «Просмотрено»'), findsOneWidget);
    });
  });

  testWidgets('окно просмотра: «Досмотрел» спрашивает день, попытка — начало',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _detached([_blonde(viewings: [_attempt()])]);
    final host = MovieViewingHost('b', repo: repo);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showViewingSheet(context, host, viewId: 'a'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Брошен'), findsOneWidget);
    expect(find.text('на 52-й мин · Затянуто, Тяжело смотреть'), findsOneWidget);
    await _tapText(tester, 'Досмотрел');
    expect(find.text('Когда досмотрели?'), findsOneWidget);
    await _tapText(tester, 'Только что');
    final v = repo.byUuid('b')!.viewings.single;
    expect(v.drop, isNull);
    // День, когда бросил, остался заходом: в ленте это строка «начал».
    expect(v.parts.single.date, _dropAt);
    expect(v.parts.single.toMin, 52);
    expect(find.text('Брошен'), findsNothing);
  });
}
