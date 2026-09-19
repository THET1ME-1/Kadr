// Превью рецензий в PNG: `FLUTTER_ROOT=<корень flutter> flutter test
// test/preview_review.dart` кладёт build/preview/review_*.png. Без суффикса
// `_test`, в обычный прогон не попадает.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/models/social.dart';
import 'package:kadr/screens/review/review_editor_screen.dart';
import 'package:kadr/screens/review/review_screen.dart';
import 'package:kadr/screens/review/review_target.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/review/review_parts.dart';
import 'package:kadr/widgets/review/verdict_badge.dart';
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

const _text = '''Скорсезе снимает [нуар](term:noir) по всем правилам жанра: шторм, остров, маршал с тёмным прошлым. Главное он прячет в мелочах, которые замечаешь только на втором просмотре.

Первые полчаса работают как **классический детектив**. Каждый санитар отвечает на вопросы на полсекунды позже, чем нужно, а Ди Каприо играет человека, которого мигрень мучает сильнее, чем дело.

> Остров давит: низкое небо, мокрый камень, коридоры без окон.

## Где фильм провисает

Сцены в блоке C тянутся, а сон с дочерью повторяется на раз больше, чем нужно. Зато финал ||переворачивает всё, что было до него||.

||Тедди Дэниелс оказывается пациентом Эндрю Лэддисом.||

- музыка Пендерецкого и Лигети
- сцена на пароме
- последняя реплика''';

ReviewMeta _meta() => ReviewMeta(
      title: 'Маяк, который светит внутрь',
      criteria: {
        'story': 9.0,
        'direction': 9.3,
        'acting': 9.1,
        'visuals': 8.6,
        'sound': 8.8,
        'pace': 6.8,
      },
      verdict: Verdict.must,
      pros: ['Финальный твист', 'Атмосфера острова', 'Ди Каприо', 'Музыка'],
      cons: ['Провисает середина', 'Сны повторяются'],
      publishedAt: DateTime(2026, 9, 19),
    );

MovieRepository _repo({bool withReview = true}) => MovieRepository.detached({
      'movies': [
        LibraryMovie(
          uuid: 'm1',
          title: 'Остров проклятых',
          year: 2010,
          status: LibraryStatus.watched,
          viewings: [Viewing(date: DateTime(2024, 3, 12), score: 8.5)],
          review: withReview ? _text : null,
          reviewMeta: withReview ? _meta() : null,
        ).toJson(),
      ],
    });

Future<void> _shoot(WidgetTester tester, String name, Widget screen,
    {double height = 844, bool light = false, Future<void> Function()? act}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: light
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
    await File('$_out/review_$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('рендер рецензий', (tester) async {
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await _loadFonts();
      await LocaleController.instance.setCode('ru');
    });
    const friend = SocialUser(
        id: 'u2', displayName: 'Марина', avatarVer: 0, friendCode: 'MARINA');

    ReviewTarget t(MovieRepository r, {bool? mine}) =>
        ReviewTarget.movie(r.byUuid('m1')!, repo: r, mine: mine);

    await _shoot(tester, '1_rate', ReviewEditorScreen(target: t(_repo())),
        height: 1900);
    await _shoot(tester, '2_text',
        ReviewEditorScreen(target: t(_repo()), initialStep: 1),
        height: 844);
    await _shoot(
        tester,
        '3_text_preview',
        ReviewEditorScreen(target: t(_repo()), initialStep: 1),
        height: 1700,
        act: () => tester.tap(find.text('Просмотр')));
    await _shoot(tester, '4_publish',
        ReviewEditorScreen(target: t(_repo()), initialStep: 2),
        height: 1300);
    await _shoot(tester, '5_read_friend',
        ReviewScreen(target: t(_repo()), author: friend),
        height: 2700);
    await _shoot(tester, '6_read_mine_light',
        ReviewScreen(target: t(_repo(), mine: true)),
        height: 2700, light: true);
    await _shoot(
        tester,
        '7_glossary',
        ReviewEditorScreen(target: t(_repo()), initialStep: 1),
        act: () => tester.tap(find.byTooltip('Термин')));
    await _shoot(
        tester,
        '8_badges',
        Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  for (final v in Verdict.values) VerdictBadge(v),
                  ReviewPreviewCard(
                      text: _text, meta: _meta(), onOpen: () {}),
                ],
              ),
            ),
          ),
        ),
        height: 1000);
  });
}
