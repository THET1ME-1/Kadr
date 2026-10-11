import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/screens/viewing/mark_sheet.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Открывает окно отметки и возвращает то, что оно отдало.
Future<MarkChoice?> _run(
  WidgetTester tester,
  Future<void> Function() act, {
  int? ordinal,
  String subject = 'Легенда об Аанге',
  String? dangerLabel,
  String lang = 'ru',
  double width = 380,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  MarkChoice? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result = await showMarkSheet(
                  context,
                  title: 'Когда посмотрели?',
                  subject: subject,
                  ordinal: ordinal,
                  coWatch: true,
                  dangerLabel: dangerLabel,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await act();
  await tester.pumpAndSettle();
  return result;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('пересмотр: номер просмотра таблеткой перед названием', (
    tester,
  ) async {
    await _run(tester, ordinal: 4, () async {
      expect(find.text('Когда посмотрели?'), findsOneWidget);
      expect(find.text('4-й просмотр'), findsOneWidget);
      expect(find.text('Легенда об Аанге'), findsOneWidget);
    });
  });

  testWidgets('первый просмотр: таблетки с номером нет', (tester) async {
    await _run(tester, ordinal: 1, () async {
      expect(find.textContaining('просмотр'), findsNothing);
    });
  });

  testWidgets('«Только что» одна, дубля «Сегодня» нет', (tester) async {
    final before = DateTime.now();
    final r = await _run(tester, () async {
      expect(find.text('Только что'), findsOneWidget);
      expect(find.text('Сегодня'), findsNothing);
      await tester.tap(find.text('Только что'));
    });
    expect(r!.danger, isFalse);
    expect(r.date!.difference(before).inMinutes, 0);
  });

  testWidgets('«Вчера» ставит вчерашний день', (tester) async {
    final r = await _run(tester, () => tester.tap(find.text('Вчера')));
    final ago = DateTime.now().difference(r!.date!);
    expect(ago.inHours, inInclusiveRange(23, 24));
  });

  testWidgets('«Не помню» отдаёт просмотр без даты', (tester) async {
    final r = await _run(tester, () => tester.tap(find.text('Не помню')));
    expect(r, isNotNull);
    expect(r!.date, isNull);
    expect(r.danger, isFalse);
  });

  testWidgets('красная кнопка отдаёт danger, а не дату', (tester) async {
    final r = await _run(
      tester,
      dangerLabel: 'Снять все просмотры сезона',
      () => tester.tap(find.text('Снять все просмотры сезона')),
    );
    expect(r!.danger, isTrue);
    expect(r.date, isNull);
  });

  testWidgets('без друзей «Посмотрел с другом» не показан', (tester) async {
    await _run(tester, () async {
      expect(find.text('Посмотрел с другом'), findsNothing);
    });
  });

  testWidgets('закрытие без ответа ничего не отдаёт', (tester) async {
    final r = await _run(tester, () => tester.tapAt(const Offset(10, 10)));
    expect(r, isNull);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('320 dp без переполнений, $lang', (tester) async {
      await _run(
        tester,
        lang: lang,
        width: 320,
        ordinal: 3,
        subject: 'Сезон 1 · осталось 4 серии из 9',
        dangerLabel: 'Снять все просмотры сезона',
        () async {},
      );
      expect(tester.takeException(), isNull);
    });
  }
}
