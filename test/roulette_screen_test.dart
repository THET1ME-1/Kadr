import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/social/roulette_screen.dart';
import 'package:kadr/services/social/social_controller.dart';
import 'package:kadr/services/store.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _titles = ['Дюна', 'Сияние', 'Бразилия', 'Сталкер', 'Солярис'];

List<RoulettePick> _pool() => [
  for (var i = 0; i < _titles.length; i++)
    RoulettePick.movie(
      LibraryMovie(
        uuid: 'm$i',
        title: _titles[i],
        status: LibraryStatus.watchlist,
      ),
    ),
];

Widget _app({Key? key}) => MaterialApp(
  key: key,
  theme: AppTheme.dark(AppTheme.defaultSeed),
  home: RouletteScreen(pool: _pool()),
);

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _phone = Size(400, 860);

/// Крутит барабан до остановки и возвращает выпавшее название.
Future<String> _spin(WidgetTester tester) async {
  await tester.tap(find.text(tr('roulette_spin')));
  await tester.pump(const Duration(seconds: 15));
  await tester.pumpAndSettle();
  expect(find.text(tr('roulette_open')), findsOneWidget);
  return _titles.singleWhere((t) => find.text(t).evaluate().isNotEmpty);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SocialController.instance.debugSetSession(null);
    // Store держит экземпляр настроек между тестами: чистим итоги руками.
    await Store.instance.remove('roulettePick.watchlist');
    await Store.instance.remove('roulettePick.friends');
  });

  testWidgets('выпавший фильм остаётся после переключения источника', (
    tester,
  ) async {
    _screen(tester, _phone);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final picked = await _spin(tester);

    await tester.tap(find.text(tr('roulette_src_friends')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('roulette_src_watchlist')));
    await tester.pumpAndSettle();

    expect(find.text(picked), findsOneWidget);
    expect(find.text(tr('roulette_open')), findsOneWidget);
  });

  testWidgets('выпавший фильм ждёт при повторном входе на экран', (
    tester,
  ) async {
    _screen(tester, _phone);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app(key: const ValueKey(1)));
    await tester.pumpAndSettle();

    final picked = await _spin(tester);

    // Уходим с экрана и открываем его заново: состояние создаётся с нуля.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(key: const ValueKey(2)));
    await tester.pumpAndSettle();

    expect(find.text(picked), findsOneWidget);
    expect(find.text(tr('roulette_open')), findsOneWidget);
  });

  testWidgets('на экране телевизора итог помещается', (tester) async {
    _screen(tester, const Size(960, 540));
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _spin(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('до первого вращения фильм не выдаётся за выпавший', (
    tester,
  ) async {
    _screen(tester, _phone);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text(tr('roulette_open')), findsNothing);
  });
}
