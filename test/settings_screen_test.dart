import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/social.dart';
import 'package:kadr/screens/settings_screen.dart';
import 'package:kadr/services/social/social_controller.dart';
import 'package:kadr/services/store.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MaterialApp(
  theme: AppTheme.dark(AppTheme.defaultSeed),
  home: const SettingsScreen(),
);

void _phone(WidgetTester tester, {double width = 320}) {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Разделы хаба, которые открываются отдельной страницей с тем же заголовком.
List<String> _pageTitles() => [
  tr('appearance'),
  tr('set_group_interface'),
  tr('disc_hide_section'),
  tr('set_group_notifications'),
  tr('set_group_catalog'),
  tr('set_group_tracking'),
  tr('set_group_sync'),
  tr('set_group_import'),
  tr('set_group_storage'),
  tr('set_group_support'),
  tr('about'),
];

const _me = SocialUser(
  id: 'u1',
  displayName: 'Кинолюб',
  avatarVer: 0,
  friendCode: 'K7QM2X',
  email: 'kino@test.kadr',
  hasRecovery: true,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SocialController.instance.debugSetSession(null);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('на 320 dp открывается каждый раздел: $lang', (tester) async {
      _phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final title in _pageTitles()) {
        final row = find.text(title);
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: title);
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text(title)),
          findsOneWidget,
          reason: title,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('шестерёнка открывает настройки', (tester) async {
    _phone(tester, width: 400);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(appBar: AppBar(actions: const [SettingsButton()])),
      ),
    );
    await tester.tap(find.byTooltip(tr('settings_title')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('строка языка открывает список языков', (tester) async {
    _phone(tester, width: 400);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('language')));
    await tester.pumpAndSettle();
    expect(find.text('Deutsch'), findsOneWidget);
    expect(find.text('Português'), findsOneWidget);
  });

  testWidgets('без входа строка аккаунта зовёт войти', (tester) async {
    _phone(tester, width: 400);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text(tr('profile_login_cta')), findsOneWidget);
    expect(find.text(tr('set_hint_account')), findsNothing);
  });

  testWidgets('аккаунт: почта, код, приватность и выход', (tester) async {
    _phone(tester, width: 400);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    SocialController.instance.debugSetSession(_me);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Кинолюб'), findsOneWidget);
    await tester.tap(find.text('Кинолюб'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(tr('set_group_account')),
      ),
      findsOneWidget,
    );
    expect(find.text('kino@test.kadr'), findsOneWidget);
    expect(find.text(tr('recovery_title')), findsOneWidget);
    expect(find.text(tr('social_logout')), findsOneWidget);

    await tester.tap(find.text(tr('privacy_hide_ratings')));
    await tester.pumpAndSettle();
    final hidden = await tester.runAsync(
      () => Store.instance.getBool('socialHideRatings'),
    );
    expect(hidden, isTrue);
  });

  testWidgets('после выхода закрывается страница аккаунта, не дожидаясь сети', (
    tester,
  ) async {
    _phone(tester, width: 400);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    SocialController.instance.debugSetSession(_me);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кинолюб'));
    await tester.pumpAndSettle();

    // Сервер не отвечает: запрос выхода висит до таймаута. Клиент берётся
    // из зоны, где началась обработка нажатия.
    final hanging = MockClient((_) => Completer<http.Response>().future);
    await http.runWithClient(
      () => tester.tap(find.text(tr('social_logout'))),
      () => hanging,
    );
    await tester.pumpAndSettle();
    // Кнопка подтверждения в диалоге.
    await tester.tap(find.widgetWithText(FilledButton, tr('social_logout')));
    await tester.pumpAndSettle();

    // Страница аккаунта закрыта, хаб зовёт войти. Если pop ждёт сетевой
    // запрос, поверх успевает открыться экран входа, и закрывается он.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(tr('set_group_account')),
      ),
      findsNothing,
    );
    expect(find.text(tr('profile_login_cta')), findsOneWidget);
    expect(SocialController.instance.isLoggedIn, isFalse);

    // Даём запросу упасть по таймауту, чтобы таймер не пережил тест.
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
  });
}
