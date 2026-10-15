import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/movie_sheet.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Кнопки карточки фильма (вариант Б макета «Кнопки карточки», KADR-1):
/// одна главная кнопка, разделённая на две, меню у стрелки и связанная
/// группа под ней. Широких кнопок одна на карточку.

LibraryMovie _watched(String uuid) => LibraryMovie(
      uuid: uuid,
      title: 'Миньоны и монстры',
      year: 2026,
      runtimeMin: 90,
      status: LibraryStatus.watched,
      viewings: [Viewing(date: DateTime(2026, 9, 26, 18, 15), score: 7.5)],
    );

LibraryMovie _unwatched(String uuid) => LibraryMovie(
      uuid: uuid,
      title: 'Одиссея',
      year: 2026,
      runtimeMin: 173,
      status: LibraryStatus.library,
    );

Future<MovieRepository> _open(WidgetTester tester, LibraryMovie m,
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

Future<void> _openMenu(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('Ещё действия'));
  await tester.tap(find.byTooltip('Ещё действия'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('просмотренный: одна главная кнопка, остальное в меню и группе',
      (tester) async {
    await _open(tester, _watched('a1'));
    expect(find.text('Смотрел ещё раз'), findsOneWidget);
    // Широких кнопок прежней карточки нет.
    for (final gone in [
      'Написать рецензию',
      'Отменить просмотр',
      'Советовать другу',
      'Бросить',
      'Бросить пересмотр',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    // «Убрать оценку» живёт в карточке оценки.
    expect(find.text('Убрать оценку'), findsOneWidget);
    // Группа: любимое значком, рецензия и списки подписью.
    expect(find.byTooltip('Избранное'), findsOneWidget);
    expect(find.text('Рецензия'), findsOneWidget);
    expect(find.text('Списки'), findsOneWidget);
    // Группа стоит сразу под главной кнопкой, одним рядом.
    final main = tester.getRect(find.text('Смотрел ещё раз'));
    final review = tester.getRect(find.text('Рецензия'));
    final lists = tester.getRect(find.text('Списки'));
    expect(review.top, greaterThan(main.bottom));
    expect(review.center.dy, closeTo(lists.center.dy, 1));

    await _openMenu(tester);
    expect(find.text('Бросить пересмотр'), findsOneWidget);
    expect(find.text('Отменить просмотр'), findsOneWidget);
  });

  testWidgets('«Бросить пересмотр» открывает окно «Где бросили?»',
      (tester) async {
    await _open(tester, _watched('a2'));
    await _openMenu(tester);
    await tester.tap(find.text('Бросить пересмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Где бросили?'), findsOneWidget);
  });

  testWidgets('непросмотренный: «Отметить просмотр», «Буду смотреть» в группе',
      (tester) async {
    final repo = await _open(tester, _unwatched('b1'));
    expect(find.text('Отметить просмотр'), findsOneWidget);
    expect(find.text('Рецензия'), findsNothing);
    expect(find.byTooltip('Списки'), findsOneWidget);
    await tester.tap(find.text('Буду смотреть'));
    await tester.pumpAndSettle();
    expect(repo.byUuid('b1')!.status, LibraryStatus.watchlist);
    // «В списке» и в чипе статуса наверху, и на включённой кнопке группы.
    expect(find.widgetWithText(FilledButton, 'В списке'), findsOneWidget);
    await _openMenu(tester);
    expect(find.text('Бросить'), findsOneWidget);
    expect(find.text('Отменить просмотр'), findsNothing);
  });

  testWidgets('сердечко в группе включает избранное', (tester) async {
    final repo = await _open(tester, _watched('a3'));
    await tester.tap(find.byTooltip('Избранное'));
    await tester.pumpAndSettle();
    expect(repo.byUuid('a3')!.favorite, isTrue);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    for (final watched in [true, false]) {
      testWidgets('320 dp без переполнений, $lang, '
          '${watched ? 'просмотренный' : 'непросмотренный'}', (tester) async {
        await _open(tester, watched ? _watched('w$lang') : _unwatched('u$lang'),
            lang: lang, width: 320);
        expect(tester.takeException(), isNull);
        expect(find.text(tr(watched ? 'watch_again' : 'mark_watched')),
            findsOneWidget);
      });
    }
  }
}
