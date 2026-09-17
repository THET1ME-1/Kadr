import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/services/app_prefs.dart';
import 'package:kadr/services/store.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/floating_nav_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<FloatingNavItem> _items() => [
  FloatingNavItem(
    icon: Icons.bookmark_border_rounded,
    selectedIcon: Icons.bookmark_rounded,
    label: tr('nav_watchlist'),
  ),
  FloatingNavItem(
    icon: Icons.check_circle_outline_rounded,
    selectedIcon: Icons.check_circle_rounded,
    label: tr('nav_watched'),
  ),
  FloatingNavItem(
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore_rounded,
    label: tr('nav_discover'),
  ),
  FloatingNavItem(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: tr('nav_profile'),
    badge: 2,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required int selected,
  ValueChanged<int>? onSelect,
  VoidCallback? onAdd,
  double width = 400,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Scaffold(
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: FloatingNavBar(
          items: _items(),
          selectedIndex: selected,
          onSelect: onSelect ?? (_) {},
          onAdd: onAdd,
          addTooltip: tr('add'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('вид меню в настройках', () {
    test('по умолчанию плавающее, выбор сохраняется', () async {
      await Store.instance.remove('navStyle');
      final prefs = AppPrefs.instance;
      await prefs.load();
      expect(prefs.navStyle, NavStyle.floating);

      await prefs.setNavStyle(NavStyle.classic);
      expect(await Store.instance.getString('navStyle'), 'classic');

      prefs.navStyle = NavStyle.floating;
      await prefs.load();
      expect(prefs.navStyle, NavStyle.classic);
      await prefs.setNavStyle(NavStyle.floating);
    });
  });

  testWidgets('подпись только у открытой вкладки', (tester) async {
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await _pump(tester, selected: 1, onAdd: () {});
    expect(find.text(tr('nav_watched')), findsOneWidget);
    expect(find.text(tr('nav_watchlist')), findsNothing);
    expect(find.text(tr('nav_discover')), findsNothing);
  });

  testWidgets('у таблетки меню нет обводки', (tester) async {
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await _pump(tester, selected: 0, onAdd: () {});
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.byType(DecoratedBox),
      ),
    );
    for (final b in boxes) {
      final d = b.decoration;
      if (d is BoxDecoration) expect(d.border, isNull);
    }
  });

  testWidgets('нажатие на значок переключает вкладку', (tester) async {
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    int? picked;
    await _pump(tester, selected: 0, onSelect: (i) => picked = i);
    await tester.tap(find.byTooltip(tr('nav_discover')));
    expect(picked, 2);
  });

  testWidgets('кнопка «+» есть, только когда её передали', (tester) async {
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    var adds = 0;
    await _pump(tester, selected: 0, onAdd: () => adds++);
    await tester.tap(find.byTooltip(tr('add')));
    expect(adds, 1);

    await _pump(tester, selected: 2);
    expect(find.byTooltip(tr('add')), findsNothing);
  });

  testWidgets('число заявок висит на значке профиля', (tester) async {
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await _pump(tester, selected: 0);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('на телефоне в 352 dp подпись «Просмотрено» видна рядом с «+»', (
    tester,
  ) async {
    // Замер подписи идёт по шрифту: с тестовым Ahem буквы шире настоящих.
    await tester.runAsync(() async {
      await LocaleController.instance.setCode('ru');
      final loader = FontLoader('Onest')
        ..addFont(
          File(
            'assets/fonts/Onest.ttf',
          ).readAsBytes().then((b) => ByteData.view(b.buffer)),
        );
      await loader.load();
    });
    await _pump(tester, selected: 1, onAdd: () {}, width: 352);
    expect(tester.takeException(), isNull);
    expect(find.text(tr('nav_watched')), findsOneWidget);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('на 320 dp ничего не вылезает: $lang', (tester) async {
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      for (var i = 0; i < 4; i++) {
        for (final add in [true, false]) {
          await _pump(
            tester,
            selected: i,
            onAdd: add ? () {} : null,
            width: 320,
          );
          expect(tester.takeException(), isNull, reason: '$i $add');
        }
      }
    });
  }
}
