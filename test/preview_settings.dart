// Служебный рендер профиля, настроек и ленты «Просмотрено» в PNG, чтобы посмотреть вёрстку без
// телефона. Имя без суффикса `_test`, поэтому `flutter test` его не
// подхватывает. Запуск руками:
//
//   flutter test test/preview_settings.dart
//
// Статистику берёт из `tool/personal_seed_backup.json`, если он есть.
// Результат — `build/preview/settings_*.png`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/social.dart';
import 'package:kadr/screens/library_tab.dart';
import 'package:kadr/screens/series_stats_screen.dart';
import 'package:kadr/screens/settings/account_page.dart';
import 'package:kadr/screens/settings/appearance_page.dart';
import 'package:kadr/screens/settings/library_pages.dart';
import 'package:kadr/screens/settings_screen.dart';
import 'package:kadr/screens/social/my_profile_screen.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/social/social_controller.dart';
import 'package:kadr/services/store.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/floating_nav_bar.dart';
import 'package:kadr/widgets/season_pill.dart';
import 'package:kadr/widgets/user_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'series_stats_screen_test.dart' show sampleSeries;

const _out = 'build/preview';
const _width = 390.0;

Future<void> _loadFonts() async {
  for (final family in ['Unbounded', 'Onest']) {
    final loader = FontLoader(family)
      ..addFont(
        File(
          'assets/fonts/$family.ttf',
        ).readAsBytes().then((b) => ByteData.view(b.buffer)),
      );
    await loader.load();
  }
  // Значки Material лежат в SDK, в тестовой среде их нет.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!icons.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(icons.readAsBytes().then((b) => ByteData.view(b.buffer)));
  await loader.load();
}

/// Шапка и нижняя навигация как у вкладки «Профиль» в оболочке.
Widget _profileTab() => Scaffold(
  appBar: AppBar(
    leading: const Icon(Icons.menu_rounded),
    title: Text(tr('nav_profile')),
    actions: const [SettingsButton(), SizedBox(width: 8)],
  ),
  body: const MyProfileScreen(),
  bottomNavigationBar: NavigationBar(
    selectedIndex: 3,
    destinations: [
      NavigationDestination(
        icon: const Icon(Icons.bookmark_border_rounded),
        label: tr('nav_watchlist'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.check_circle_outline_rounded),
        label: tr('nav_watched'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.explore_outlined),
        label: tr('nav_discover'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_rounded),
        label: tr('nav_profile'),
      ),
    ],
  ),
);

Future<void> _shoot(
  WidgetTester tester,
  String name,
  Widget screen, {
  double height = 844,
  double width = _width,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await Directory(_out).create(recursive: true);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(
      '$_out/settings_$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
  });
}

SocialUser _u(String id, String name) =>
    SocialUser(id: id, displayName: name, avatarVer: 0, friendCode: 'AAAAAA');

void main() {
  testWidgets('рендер профиля и настроек', (tester) async {
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    // Кэшу постеров нужна временная папка. Документы не отдаём: библиотека из
    // копии не должна никуда записаться.
    final cache = Directory('$_out/cache')..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              throw MissingPluginException();
            }
            return cache.absolute.path;
          },
        );
    await tester.runAsync(() async {
      await _loadFonts();
      await LocaleController.instance.setCode('ru');
      final seed = File('tool/personal_seed_backup.json');
      if (seed.existsSync()) {
        await MovieRepository.instance.importJson(await seed.readAsString());
      }
    });

    await _shoot(tester, '0_profile_guest', _profileTab(), height: 1500);

    SocialController.instance.debugSetSession(
      const SocialUser(
        id: 'me-preview',
        displayName: 'Кинолюб',
        avatarVer: 0,
        friendCode: 'K7QM2X',
        email: 'kino@example.com',
        hasRecovery: true,
      ),
      friends: FriendsData(
        friends: [
          FriendEntry(user: _u('f1', 'Аня')),
          FriendEntry(user: _u('f2', 'Макс')),
          FriendEntry(user: _u('f3', 'Лена')),
          FriendEntry(user: _u('f4', 'Дима')),
        ],
        incoming: [FriendEntry(user: _u('f5', 'Оля'))],
        outgoing: [FriendEntry(user: _u('f6', 'Игорь'))],
      ),
    );

    await _shoot(tester, '1_profile', _profileTab(), height: 1560);
    await _shoot(tester, '2_hub', const SettingsScreen(), height: 1320);
    await _shoot(tester, '3_account', const AccountPage());
    await _shoot(tester, '4_appearance', const AppearancePage());
    await _shoot(tester, '5_sync', const SyncPage());
    await _shoot(
      tester,
      '6_watched',
      const Scaffold(body: LibraryTab(mode: LibraryMode.watched)),
      height: 1600,
    );

    // Плавающее меню над лентой на ширине телефона владельца (~352 dp).
    for (final tab in [1, 3]) {
      await _shoot(
        tester,
        '7_nav_$tab',
        Scaffold(
          extendBody: true,
          body: const LibraryTab(mode: LibraryMode.watched),
          bottomNavigationBar: FloatingNavBar(
            selectedIndex: tab,
            onSelect: (_) {},
            items: [
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
                leading: UserAvatar(
                  user: SocialController.instance.user!,
                  size: 26,
                ),
                badge: 1,
              ),
            ],
          ),
        ),
        height: 760,
        width: 352,
      );
    }

    // Таблетки сезонов: досмотрены три, четвёртый начат и выбран, пятый нет.
    await _shoot(
      tester,
      '8_seasons',
      Scaffold(
        body: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final (n, f) in [
                  (1, 1.0),
                  (2, 1.0),
                  (3, 1.0),
                  (4, 0.3),
                  (5, 0.0),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SeasonPill(
                      label: trf('season_n', {'n': n}),
                      fraction: f,
                      done: f >= 1,
                      selected: n == 4,
                      onTap: () {},
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      height: 120,
      width: 640,
    );

    // Статистика сериала с рейтингом сезонов: развёрнутый и свёрнутый.
    final sample = sampleSeries();
    for (final short in [false, true]) {
      await tester.runAsync(
        () => Store.instance.setBool('seriesStatsRankShort', short),
      );
      await _shoot(
        tester,
        '9_stats_${short ? 'short' : 'full'}',
        SeriesStatsScreen(
          series: sample.series,
          seasons: sample.seasons,
          preloaded: sample.tmdb,
        ),
        height: 900,
        width: 352,
      );
    }
    await tester.runAsync(() => Store.instance.remove('seriesStatsRankShort'));

    SocialController.instance.debugSetSession(null);
    // Картинкам и ленте нужны таймеры: даём им отработать до конца теста.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
