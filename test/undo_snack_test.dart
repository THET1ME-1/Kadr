import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/widgets/undo_snack.dart';

/// Плашка с отменой возвращает данные такими, какими они были до действия.
/// Если она висит, пока её не смахнут, отмена через полчаса стирает всё, что
/// человек успел сделать после.
void main() {
  Future<void> show(WidgetTester tester, VoidCallback onUndo) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              undoSnackBar(text: 'Удалено', label: 'Отменить', onUndo: onUndo),
            ),
            child: const Text('Удалить'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Удалить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('плашка гаснет сама', (tester) async {
    await show(tester, () {});
    expect(find.text('Удалено'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Удалено'), findsNothing);
  });

  testWidgets('пока плашка на экране, отмена срабатывает', (tester) async {
    var undone = 0;
    await show(tester, () => undone++);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(undone, 1);
  });
}
