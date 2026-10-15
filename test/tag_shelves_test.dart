import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/review/tag_shelves.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Полки по темам (вариант Б макета «Причины брошенного»): готовые фразы
/// горят на месте, своё слово встаёт на полку «Свои» выбранным.
class _Host extends StatefulWidget {
  final List<TagShelf> shelves;
  final List<String> extra;
  const _Host({required this.shelves, this.extra = const []});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final selected = <String>[];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TagShelves(
            title: tr('drop_why'),
            shelves: widget.shelves,
            selected: selected,
            extra: widget.extra,
            onToggle: (t) => setState(
                () => selected.contains(t) ? selected.remove(t) : selected.add(t)),
            onAdd: (t) => setState(() => selected.add(t)),
          ),
        ),
      );
}

Future<_HostState> _pump(WidgetTester tester,
    {String lang = 'ru', double width = 400, List<String> extra = const []}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(AppTheme.defaultSeed),
    home: _Host(shelves: kDropShelves, extra: extra),
  ));
  await tester.pumpAndSettle();
  return tester.state<_HostState>(find.byType(_Host));
}

bool _on(WidgetTester tester, String text) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, text)).selected;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('темы подписаны, подсказка горит на месте и гаснет', (tester) async {
    final host = await _pump(tester);
    for (final t in ['Сюжет', 'Герои', 'Ощущения', 'Картинка и звук']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Свои'), findsNothing);
    expect(_on(tester, 'Затянуто'), isFalse);
    await tester.tap(find.widgetWithText(FilterChip, 'Затянуто'));
    await tester.pumpAndSettle();
    expect(_on(tester, 'Затянуто'), isTrue);
    expect(host.selected, ['Затянуто']);
    // Чип остался на своей полке, второго не появилось.
    expect(find.widgetWithText(FilterChip, 'Затянуто'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Затянуто'));
    await tester.pumpAndSettle();
    expect(host.selected, isEmpty);
  });

  testWidgets('своё слово встаёт на полку «Свои» выбранным', (tester) async {
    final host = await _pump(tester, extra: ['Мутная картинка']);
    expect(find.text('Свои'), findsOneWidget);
    expect(_on(tester, 'Мутная картинка'), isFalse);
    await tester.enterText(find.byType(TextField), 'Плохой звук');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(host.selected, ['Плохой звук']);
    expect(_on(tester, 'Плохой звук'), isTrue);
    // Готовую фразу полем не задваиваем: она горит на своей полке.
    await tester.enterText(find.byType(TextField), 'затянуто');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(host.selected, ['Плохой звук', 'Затянуто']);
    expect(find.widgetWithText(FilterChip, 'Затянуто'), findsOneWidget);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('320 dp без переполнений, $lang', (tester) async {
      await _pump(tester, lang: lang, width: 320, extra: ['Очень длинная своя причина']);
      expect(tester.takeException(), isNull);
    });
  }
}
