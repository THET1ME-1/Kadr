import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/social.dart';
import 'package:kadr/screens/social/my_profile_screen.dart';
import 'package:kadr/services/social/social_controller.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app() => MaterialApp(
  theme: AppTheme.dark(AppTheme.defaultSeed),
  home: const Scaffold(body: MyProfileScreen()),
);

void _phone(WidgetTester tester, {double width = 400}) {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

SocialUser _user(String id, String name, String code) =>
    SocialUser(id: id, displayName: name, avatarVer: 0, friendCode: code);

final _me = SocialUser(
  id: 'me',
  displayName: 'Кинолюб',
  avatarVer: 0,
  friendCode: 'K7QM2X',
  email: 'kino@test.kadr',
);

final _friends = FriendsData(
  friends: [
    FriendEntry(user: _user('f1', 'Аня', 'AAAAAA')),
    FriendEntry(user: _user('f2', 'Макс', 'BBBBBB')),
  ],
  incoming: [FriendEntry(user: _user('f3', 'Оля', 'CCCCCC'))],
);

/// Всё, что переехало в настройки и в профиле больше не встречается.
List<String> _settingsLabels() => [
  tr('appearance'),
  tr('language'),
  tr('sync_backup'),
  tr('check_updates'),
  tr('scrobble_title'),
  tr('tvtime_title'),
  tr('recovery_title'),
  tr('privacy_hide_ratings'),
  tr('social_logout'),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SocialController.instance.debugSetSession(null);
  });

  testWidgets('без входа: приглашение и статистика, настроек нет', (
    tester,
  ) async {
    _phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text(tr('profile_login_cta')), findsOneWidget);
    expect(find.text(tr('drawer_stats')), findsOneWidget);
    for (final label in _settingsLabels()) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('вошёл: шапка, заявки, статистика, друзья и ничего лишнего', (
    tester,
  ) async {
    _phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    SocialController.instance.debugSetSession(_me, friends: _friends);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Кинолюб'), findsOneWidget);
    expect(find.text('K7QM2X'), findsOneWidget);
    for (final label in _settingsLabels()) {
      expect(find.text(label), findsNothing, reason: label);
    }

    // Порядок блоков: заявки → статистика → друзья.
    final requests = tester.getTopLeft(find.text('Оля')).dy;
    final stats = tester.getTopLeft(find.text(tr('drawer_stats'))).dy;
    final friends = tester.getTopLeft(find.text('Аня')).dy;
    expect(requests, lessThan(stats));
    expect(stats, lessThan(friends));
  });

  testWidgets('поиск друзей знает, кто уже в друзьях и кому ушла заявка', (
    tester,
  ) async {
    _phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    SocialController.instance.debugSetSession(
      _me,
      friends: FriendsData(
        friends: [FriendEntry(user: _user('f1', 'jbsharan', '9VFV4Z'))],
        incoming: [FriendEntry(user: _user('f2', 'jbasks', 'AAAAAA'))],
        outgoing: [FriendEntry(user: _user('f3', 'jbwaits', 'BBBBBB'))],
      ),
    );
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text(tr('social_add_friend')));
    await tester.pumpAndSettle();

    Map<String, Object> user(String id, String name, String code) => {
      'id': id,
      'displayName': name,
      'friendCode': code,
      'avatar': 0,
    };
    final server = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'users': [
            user('f1', 'jbsharan', '9VFV4Z'),
            user('f2', 'jbasks', 'AAAAAA'),
            user('f3', 'jbwaits', 'BBBBBB'),
            user('f9', 'jbnew', 'CCCCCC'),
          ],
        }),
        200,
      ),
    );
    await http.runWithClient(
      () => tester.enterText(find.byType(TextField).first, 'jb'),
      () => server,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    Finder inRow(String name, String label) => find.descendant(
      of: find.ancestor(
        of: find.descendant(of: sheet, matching: find.text(name)),
        matching: find.byType(ListTile),
      ),
      matching: find.text(label),
    );

    expect(inRow('jbsharan', tr('profile_in_friends')), findsOneWidget);
    expect(inRow('jbsharan', tr('profile_add_btn')), findsNothing);
    expect(inRow('jbasks', tr('accept')), findsOneWidget);
    expect(inRow('jbwaits', tr('profile_request_pending')), findsOneWidget);
    expect(inRow('jbnew', tr('profile_add_btn')), findsOneWidget);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('на 320 dp ничего не вылезает: $lang', (tester) async {
      _phone(tester, width: 320);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      SocialController.instance.debugSetSession(_me, friends: _friends);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
