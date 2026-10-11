import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/screens/restore_dialog.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Вопрос перед восстановлением из копии. Раньше копия молча заменяла
/// библиотеку, а текст обещал, что данные «будут добавлены».
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<RestoreMode?> Function() open(
    WidgetTester tester, {
    required bool hasData,
    String lang = 'ru',
    double width = 400,
  }) {
    RestoreMode? answer;
    var done = false;
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return () async {
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await askRestoreMode(context,
                    when: '11.10.2026 14:23', hasData: hasData);
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return done ? answer : null;
    };
  }

  testWidgets('в библиотеке есть записи: выбор «Добавить» или «Заменить»', (
    tester,
  ) async {
    await open(tester, hasData: true)();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('11.10.2026 14:23'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, tr('add')), findsOneWidget);
    expect(find.widgetWithText(TextButton, tr('replace')), findsOneWidget);
  });

  testWidgets('пустую библиотеку спрашивать не о чем: копия её заменяет', (
    tester,
  ) async {
    final mode = await open(tester, hasData: false)();
    expect(find.byType(AlertDialog), findsNothing);
    expect(mode, RestoreMode.replace);
  });

  for (final (label, mode) in [
    ('add', RestoreMode.merge),
    ('replace', RestoreMode.replace),
  ]) {
    testWidgets('кнопка «$label» отвечает своим режимом', (tester) async {
      RestoreMode? answer;
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  answer = await askRestoreMode(context, hasData: true),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tr(label)));
      await tester.pumpAndSettle();
      expect(answer, mode);
    });
  }

  for (final lang in ['ru', 'en', 'de', 'fr', 'es', 'it', 'pt']) {
    testWidgets('320 dp без переполнений, $lang', (tester) async {
      await open(tester, hasData: true, lang: lang, width: 320)();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
