import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/movie_sheet.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Человек-паук: Новый день» из базы: два просмотра по 9.5 и рецензия,
/// написанная через двенадцать минут после второго. Привязки к просмотру у
/// неё нет, как у всех рецензий до этой версии.
LibraryMovie _spider(String uuid) => LibraryMovie(
      uuid: uuid,
      title: 'Человек-паук: Новый день',
      year: 2026,
      status: LibraryStatus.watched,
      viewings: [
        Viewing(date: DateTime(2026, 9, 4, 16, 7), score: 9.5),
        Viewing(date: DateTime(2026, 10, 10, 23, 32), score: 9.5),
      ],
      reviewMeta: ReviewMeta(
        title: 'Это прекрасно было.',
        verdict: Verdict.masterpiece,
        criteria: {'story': 9.0},
        createdAt: DateTime(2026, 10, 10, 23, 44),
        publishedAt: DateTime(2026, 10, 10, 23, 44),
      ),
    );

Future<MovieRepository> _open(WidgetTester tester, String uuid) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(700, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode('ru'));
  // Каталога документов в тесте нет: канал отвечает ошибкой сразу, и запись
  // библиотеки её глотает.
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      paths, (_) async => throw PlatformException(code: 'no-dir'));
  addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
  final repo = MovieRepository.instance;
  await tester.runAsync(
      () => repo.restoreFromSnapshot([_spider(uuid).toJson()], const []));
  // Сеть отвечает «не найдено»: карточка остаётся без деталей TMDB.
  await http.runWithClient(
    () async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: MovieScreen(movie: repo.byUuid(uuid)!),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
    () => MockClient((_) async => http.Response('{}', 404)),
  );
  return repo;
}

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('карточка фильма: рецензии под оценкой, просмотры под кнопками',
      (tester) async {
    await _open(tester, 'sp1');
    expect(find.text('2 просмотра'), findsOneWidget);
    expect(find.text('Повторов: 1'), findsNothing);
    expect(find.text('Оценка · 2-й просмотр'), findsOneWidget);
    expect(find.text('10.10.2026 · в прошлый раз 9.5'), findsOneWidget);
    // Старая рецензия встала ко второму просмотру: она написана после него.
    expect(find.text('Мои рецензии · 1'), findsOneWidget);
    expect(find.text('2-й'), findsOneWidget);
    expect(find.text('Это прекрасно было.'), findsOneWidget);
    expect(find.text('Просмотры · 2'), findsOneWidget);
    expect(find.text('04.09.2026 16:07'), findsOneWidget);
    // Порядок блоков сверху вниз. «Отменить просмотр» спрятан в меню у
    // главной кнопки, под ней связанная группа.
    expect(find.text('Отменить просмотр'), findsNothing);
    final ys = [
      _y(tester, 'Оценка · 2-й просмотр'),
      _y(tester, 'Мои рецензии · 1'),
      _y(tester, 'Смотрел ещё раз'),
      _y(tester, 'Списки'),
      _y(tester, 'Просмотры · 2'),
    ];
    expect(ys, [...ys]..sort());
    // Прежних блоков внизу карточки нет.
    expect(find.text('Оценки по просмотрам'), findsNothing);
    expect(find.text('Моя рецензия'), findsNothing);
  });

  testWidgets('«Смотрел ещё раз» открывает окно отметки с номером просмотра',
      (tester) async {
    final repo = await _open(tester, 'sp2');
    await tester.tap(find.text('Смотрел ещё раз'));
    await tester.pumpAndSettle();
    expect(find.text('Когда посмотрели?'), findsOneWidget);
    expect(find.text('3-й просмотр'), findsOneWidget);
    await tester.tap(find.text('Только что'));
    await tester.pumpAndSettle();
    final m = repo.byUuid('sp2')!;
    expect(m.viewings.length, 3);
    expect(find.text('3 просмотра'), findsOneWidget);
    // Новый просмотр ещё не оценён: карточка пустая и предлагает прошлую
    // оценку, а фильм в списках остаётся с 9.5.
    expect(find.text('Оценка · 3-й просмотр'), findsOneWidget);
    expect(find.text('Те же 9.5, что в прошлый раз'), findsOneWidget);
    expect(m.currentScore, 9.5);
    // Рецензия осталась у второго просмотра.
    expect(find.text('2-й'), findsOneWidget);
  });

  testWidgets('«Отменить просмотр» спрашивает о просмотре с рецензией и '
      'даёт вернуть', (tester) async {
    final repo = await _open(tester, 'sp3');
    await tester.ensureVisible(find.byTooltip('Ещё действия'));
    await tester.tap(find.byTooltip('Ещё действия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить просмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить просмотр 10.10.2026?'), findsOneWidget);
    expect(find.text('Вместе с ним уйдут оценка 9.5 и рецензия.'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    var m = repo.byUuid('sp3')!;
    expect(m.viewings.length, 1);
    expect(m.hasReview, isFalse);
    // Фильм остался просмотренным: первый просмотр на месте.
    expect(m.status, LibraryStatus.watched);
    expect(find.text('Просмотр удалён'), findsOneWidget);
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    m = repo.byUuid('sp3')!;
    expect(m.viewings.length, 2);
    expect(m.reviewMeta!.title, 'Это прекрасно было.');
    expect(find.text('Мои рецензии · 1'), findsOneWidget);
  });

  testWidgets('строка просмотра открывает окно просмотра', (tester) async {
    await _open(tester, 'sp4');
    await tester.ensureVisible(find.text('04.09.2026 16:07'));
    await tester.tap(find.text('04.09.2026 16:07'));
    await tester.pumpAndSettle();
    expect(find.text('Оценка просмотра'), findsOneWidget);
    expect(find.text('1-й · 04.09'), findsOneWidget);
    expect(find.text('На этот просмотр пока нет'), findsOneWidget);
  });
}
