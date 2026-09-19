import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/score_pad.dart';

/// Калькулятор оценки открывается пустым: старое число пришлось бы стирать,
/// прежде чем набрать новое.
void main() {
  testWidgets('калькулятор открывается пустым и не вылезает на 320 dp',
      (tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    double? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Builder(
        builder: (c) => FilledButton(
          onPressed: () async => result = await showScorePad(c),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('—'), findsOneWidget);

    final pad = find.byType(BottomSheet);
    for (final k in ['7', '.', '4']) {
      await tester.tap(find.descendant(of: pad, matching: find.text(k)));
      await tester.pump();
    }
    await tester.tap(find.descendant(of: pad, matching: find.text('Готово')));
    await tester.pumpAndSettle();
    expect(result, 7.4);
  });
}
