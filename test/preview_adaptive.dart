// Служебный рендер: как Kadr выглядит на планшете и в горизонтальной
// ориентации. Имя без суффикса `_test`, в обычный прогон не попадает:
//
//   FLUTTER_ROOT=<корень flutter> flutter test test/preview_adaptive.dart
//
// Библиотеку берёт из `tool/personal_seed_backup.json`, если он есть.
// Результат — `build/preview/adaptive_*.png`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/social.dart';
import 'package:kadr/screens/home_shell.dart';
import 'package:kadr/screens/library_tab.dart';
import 'package:kadr/screens/series_screen.dart';
import 'package:kadr/screens/settings_screen.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/social/social_controller.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'build/preview';

const _sizes = {
  'phone_land': Size(800, 360),
  'tab_port': Size(800, 1280),
  'tab_land': Size(1280, 800),
};

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)
      ..addFont(File(path).readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }

  await load('Unbounded', 'assets/fonts/Unbounded.ttf');
  await load('Onest', 'assets/fonts/Onest.ttf');
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    await load(
      'MaterialIcons',
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  }
}

Future<void> _shoot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  await tester.runAsync(() async {
    await Directory(_out).create(recursive: true);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(
      '$_out/adaptive_$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('рендер на планшете и в горизонтали', (tester) async {
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final cache = Directory('$_out/cache')..createSync(recursive: true);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          throw MissingPluginException();
        }
        return cache.absolute.path;
      },
    );
    // Уведомления и прочие плагины в тестовой среде молчат.
    FlutterError.onError = (d) {
      if (d.exception is MissingPluginException) return;
      FlutterError.presentError(d);
    };
    await tester.runAsync(() async {
      await _loadFonts();
      await LocaleController.instance.setCode('ru');
      final seed = File('tool/personal_seed_backup.json');
      if (seed.existsSync()) {
        await MovieRepository.instance.importJson(await seed.readAsString());
      }
    });
    SocialController.instance.debugSetSession(
      const SocialUser(
        id: 'me-preview',
        displayName: 'Кинолюб',
        avatarVer: 0,
        friendCode: 'K7QM2X',
        email: 'kino@example.com',
        hasRecovery: true,
      ),
      friends: const FriendsData(),
    );
    final series = MovieRepository.instance.currentlyWatching.isNotEmpty
        ? MovieRepository.instance.currentlyWatching.first
        : null;

    for (final entry in _sizes.entries) {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            navigatorKey: nav,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.dark(AppTheme.defaultSeed),
            home: const HomeShell(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      Future<void> tab(String label) async {
        await tester.tap(find.byTooltip(label).last);
        for (var t = 0; t < 1200; t += 50) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await tab('Просмотрено');
      await _shoot(tester, key, '${entry.key}_1_watched');
      await tab('Буду смотреть');
      await _shoot(tester, key, '${entry.key}_2_watchlist');
      await tab('Обзор');
      await tester.pump(const Duration(seconds: 2));
      await _shoot(tester, key, '${entry.key}_3_discover');
      await tab('Профиль');
      await _shoot(tester, key, '${entry.key}_4_profile');

      Future<void> direct(Widget screen, String name, {int wait = 800}) async {
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
        // Покадрово: анимации появления стартуют с первого кадра.
        for (var t = 0; t < wait; t += 50) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await _shoot(tester, key, '${entry.key}_$name');
      }

      await direct(const SettingsScreen(), '5_settings', wait: 1500);
      if (series != null) {
        await direct(SeriesScreen(series: series), '6_series', wait: 3000);
      }
      await direct(
        const Scaffold(
          body: LibraryTab(
            mode: LibraryMode.watchlist,
            viewMode: LibraryViewMode.posters,
          ),
        ),
        '7_posters',
        wait: 1500,
      );
    }

    SocialController.instance.debugSetSession(null);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
