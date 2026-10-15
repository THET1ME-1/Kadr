// Превью брошенного фильма (KADR-1) в PNG:
// `FLUTTER_ROOT=<корень flutter> flutter test test/preview_dropped.dart`
// кладёт build/preview/dropped_*.png в светлой и тёмной теме. Без суффикса
// `_test`, в обычный прогон не попадает. Данные повторяют макет: «Блондинка»
// брошена без оценки, «Субстанция» с оценкой, рядом обычные просмотры.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/dropped_screen.dart';
import 'package:kadr/screens/library_tab.dart';
import 'package:kadr/screens/movie_sheet.dart';
import 'package:kadr/screens/viewing/drop_sheet.dart';
import 'package:kadr/screens/viewing/viewing_host.dart';
import 'package:kadr/screens/viewing/viewing_sheet.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/rating_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'build/preview';

Future<void> _loadFonts() async {
  for (final family in ['Unbounded', 'Onest']) {
    final loader = FontLoader(family)
      ..addFont(File('assets/fonts/$family.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final icons =
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(icons.readAsBytes().then((b) => ByteData.view(b.buffer)));
  await loader.load();
}

LibraryMovie _blonde() => LibraryMovie(
      uuid: 'blonde',
      title: 'Blonde',
      ruTitle: 'Блондинка',
      titleLang: 'ru',
      year: 2022,
      runtimeMin: 166,
      kpRating: 5.898,
      status: LibraryStatus.watched,
      viewings: [
        Viewing(
          id: 'b1',
          date: DateTime(2026, 10, 14, 23, 10),
          drop: DropMark(atMin: 52, reasons: ['Затянуто', 'Тяжело смотреть']),
        ),
      ],
    );

LibraryMovie _substance() => LibraryMovie(
      uuid: 'subst',
      title: 'The Substance',
      ruTitle: 'Субстанция',
      titleLang: 'ru',
      year: 2024,
      runtimeMin: 138,
      status: LibraryStatus.watched,
      viewings: [
        Viewing(
          id: 's1',
          date: DateTime(2026, 10, 3, 22, 40),
          score: 4.0,
          drop: DropMark(
              atMin: 71,
              reasons: ['Не мой жанр', 'После середины смотреть противно']),
        ),
      ],
    );

LibraryMovie _spider() => LibraryMovie(
      uuid: 'spider',
      title: 'Человек-паук: Новый день',
      ruTitle: 'Человек-паук: Новый день',
      titleLang: 'ru',
      year: 2026,
      runtimeMin: 144,
      status: LibraryStatus.watched,
      viewings: [
        Viewing(id: 'p1', date: DateTime(2026, 9, 4, 16, 7), score: 9.5),
        Viewing(id: 'p2', date: DateTime(2026, 10, 10, 23, 32), score: 9.5),
      ],
    );

LibraryMovie _minions() => LibraryMovie(
      uuid: 'minions',
      title: 'Миньоны и монстры',
      ruTitle: 'Миньоны и монстры',
      titleLang: 'ru',
      year: 2026,
      runtimeMin: 90,
      status: LibraryStatus.watched,
      viewings: [
        Viewing(id: 'm1', date: DateTime(2026, 9, 26, 18, 15), score: 7.5),
      ],
    );

LibrarySeries _witcher() => LibrarySeries(
      tvShowId: 'witcher',
      title: 'Ведьмак',
      dropped: true,
      episodes: [
        for (var n = 1; n <= 3; n++)
          Episode(season: 1, number: n, watchedAt: DateTime(2024, 1, n)),
      ],
    );

MovieRepository _repo() => MovieRepository.detached({
      'movies': [
        _blonde().toJson(),
        _substance().toJson(),
        _spider().toJson(),
        _minions().toJson(),
      ],
    });

late bool _light;

Future<void> _shoot(WidgetTester tester, String name, Widget screen,
    {double height = 844, Future<void> Function()? act}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _light
          ? AppTheme.light(AppTheme.defaultSeed)
          : AppTheme.dark(AppTheme.defaultSeed),
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
  if (act != null) {
    await act();
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    await Directory(_out).create(recursive: true);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File('$_out/dropped_${name}_${_light ? 'light' : 'dark'}.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

Widget _opener(Future<void> Function(BuildContext) open) => Builder(
      builder: (context) => Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: FilledButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> _all(WidgetTester tester) async {
  Future<void> tapOpen() => tester.tap(find.text('open'));
  var repo = _repo();

  // Окно «Где бросили?»: минута, выбранные причины, подсказки, дата.
  await _shoot(
    tester,
    '01_sheet',
    _opener((c) => showDropSheet(c,
        subject: 'Блондинка',
        runtimeMin: 166,
        repo: repo,
        initial: null)),
    height: 1300,
    act: () async {
      await tapOpen();
      await tester.pumpAndSettle();
      for (final reason in ['Затянуто', 'Тяжело смотреть']) {
        final chip = find.widgetWithText(FilterChip, reason);
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
      // Полки снова в начало, как их видит человек.
      for (final e in find.byType(Scrollable).evaluate()) {
        final s = (e as StatefulElement).state as ScrollableState;
        if (s.axisDirection == AxisDirection.right) s.position.jumpTo(0);
      }
      // Тап по линейке на 52-й минуте из 166.
      final box = tester.getRect(find.byType(RatingSlider));
      await tester.tapAt(Offset(
          box.left + 24 + (box.width - 48) * 52 / 166, box.center.dy));
    },
  );

  // Лента «Просмотрено»: попытки карточкой в тон.
  repo = _repo();
  await _shoot(
    tester,
    '02_feed',
    Scaffold(
      body: SafeArea(
        child: LibraryTab(
          mode: LibraryMode.watched,
          repository: repo,
          readOnly: true,
        ),
      ),
    ),
    height: 1250,
  );

  // Карточка брошенного фильма. Экран читает основную библиотеку.
  await tester.runAsync(() => MovieRepository.instance.restoreFromSnapshot(
      [_blonde().toJson(), _substance().toJson()], [_witcher().toJson()]));
  final main = MovieRepository.instance;
  await _shoot(tester, '03_card', MovieScreen(movie: main.byUuid('blonde')!),
      height: 1500);

  // Окно попытки: строка «Брошен» и «Досмотрел».
  repo = _repo();
  await _shoot(
    tester,
    '04_viewing',
    _opener((c) => showViewingSheet(
        c, MovieViewingHost('blonde', repo: repo),
        viewId: 'b1')),
    act: tapOpen,
  );

  // Меню → «Брошено»: причина под названием.
  await _shoot(tester, '05_list', const DroppedScreen(), height: 760);

  // Кнопки карточки (вариант Б): просмотренный без рецензии и фильм в «Буду
  // смотреть»; у просмотренного ещё и с открытым меню.
  final odyssey = LibraryMovie(
    uuid: 'odyssey',
    title: 'The Odyssey',
    ruTitle: 'Одиссея',
    titleLang: 'ru',
    year: 2026,
    runtimeMin: 173,
    status: LibraryStatus.watchlist,
  );
  await tester.runAsync(() => MovieRepository.instance.restoreFromSnapshot(
      [_minions().toJson(), odyssey.toJson()], const []));
  await _shoot(tester, '06_card_watched',
      MovieScreen(movie: main.byUuid('minions')!), height: 1100);
  await _shoot(tester, '07_card_menu',
      MovieScreen(movie: main.byUuid('minions')!), height: 1100,
      act: () async {
    await tester.tap(find.byTooltip('Ещё действия'));
  });
  await _shoot(tester, '08_card_unwatched',
      MovieScreen(movie: main.byUuid('odyssey')!), height: 900);
}

void main() {
  testWidgets('рендер брошенного фильма', (tester) async {
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        paths, (_) async => throw PlatformException(code: 'no-dir'));
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    await tester.runAsync(() async {
      await _loadFonts();
      await LocaleController.instance.setCode('ru');
    });
    for (final light in [true, false]) {
      _light = light;
      await _all(tester);
    }
  });
}
