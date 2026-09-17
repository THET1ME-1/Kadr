import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/settings_kit.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark(AppTheme.defaultSeed),
  home: Scaffold(body: ListView(children: [child])),
);

/// Блок, в который завёрнута строка с заголовком [title].
Material _blockOf(WidgetTester tester, String title) => tester.widget<Material>(
  find.ancestor(of: find.text(title), matching: find.byType(Material)).first,
);

void main() {
  testWidgets('форма блока зависит от места в группе', (tester) async {
    await tester.pumpWidget(
      _host(
        const SettingsGroup([
          SettingsRow(icon: Icons.palette_rounded, title: 'Первый'),
          SettingsRow(icon: Icons.palette_rounded, title: 'Средний'),
          SettingsRow(icon: Icons.palette_rounded, title: 'Последний'),
        ]),
      ),
    );

    const outer = Radius.circular(28);
    const inner = Radius.circular(8);
    expect(
      _blockOf(tester, 'Первый').borderRadius,
      const BorderRadius.vertical(top: outer, bottom: inner),
    );
    expect(
      _blockOf(tester, 'Средний').borderRadius,
      const BorderRadius.vertical(top: inner, bottom: inner),
    );
    expect(
      _blockOf(tester, 'Последний').borderRadius,
      const BorderRadius.vertical(top: inner, bottom: outer),
    );
  });

  testWidgets('единственный пункт скруглён целиком', (tester) async {
    await tester.pumpWidget(
      _host(
        const SettingsGroup([
          SettingsRow(icon: Icons.palette_rounded, title: 'Один'),
        ]),
      ),
    );
    expect(
      _blockOf(tester, 'Один').borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(28),
        bottom: Radius.circular(28),
      ),
    );
  });

  testWidgets('между блоками зазор 4', (tester) async {
    await tester.pumpWidget(
      _host(
        const SettingsGroup([
          SettingsRow(icon: Icons.palette_rounded, title: 'А'),
          SettingsRow(icon: Icons.palette_rounded, title: 'Б'),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    final a = tester.getRect(
      find.ancestor(of: find.text('А'), matching: find.byType(Material)).first,
    );
    final b = tester.getRect(
      find.ancestor(of: find.text('Б'), matching: find.byType(Material)).first,
    );
    expect(b.top - a.bottom, 4);
  });

  testWidgets('тап по строке с тумблером переключает его', (tester) async {
    var value = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => SettingsGroup([
            SettingsSwitchRow(
              icon: Icons.star_rounded,
              title: 'Скрывать оценки',
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ]),
        ),
      ),
    );
    await tester.tap(find.text('Скрывать оценки'));
    await tester.pump();
    expect(value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('подпись раздела пишется капсом', (tester) async {
    await tester.pumpWidget(_host(const SettingsSection('Вид и поведение')));
    expect(find.text('ВИД И ПОВЕДЕНИЕ'), findsOneWidget);
  });
}
