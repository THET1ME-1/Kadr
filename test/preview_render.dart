// Служебный рендер: рисует все стили карточки «Поделиться» в PNG, чтобы
// посмотреть результат без телефона. Имя без суффикса `_test`, поэтому
// `flutter test` его не подхватывает — запуск руками:
//
//   flutter test test/preview_render.dart
//
// Кладёт постер и кадр из `build/preview/poster.jpg` и `backdrop.jpg`
// (положи туда любые), результат — туда же, `render_*.png`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/utils/share_card_data.dart';
import 'package:kadr/utils/share_palette.dart';
import 'package:kadr/widgets/share_card.dart';

const _out = 'build/preview';

Future<ui.Image> _load(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<void> _shoot(WidgetTester tester, Widget child, String name) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(1200, 1800)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(key: key, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  // toImage и файловый ввод-вывод живут вне фейкового времени теста.
  // Файловые операции — только внутри runAsync: снаружи тест живёт в фейковом
  // времени, и любое ожидание ввода-вывода зависает до таймаута.
  await tester.runAsync(() async {
    await Directory(_out).create(recursive: true);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File('$_out/$name.png').writeAsBytes(data!.buffer.asUint8List());
  });
}

/// Подшивает шрифты проекта: в тестовой среде их нет, и без этого весь текст
/// рисуется квадратами.
Future<void> _loadFonts() async {
  for (final family in ['Unbounded', 'Onest']) {
    final loader = FontLoader(family)
      ..addFont(File('assets/fonts/$family.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
}

void main() {
  testWidgets('рендер карточек', (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(_loadFonts);

    late final ui.Image poster;
    late final ui.Image backdrop;
    late final SharePalette palette;
    await tester.runAsync(() async {
      poster = await _load('$_out/poster.jpg');
      backdrop = await _load('$_out/backdrop.jpg');
      final raw = await poster.toByteData(format: ui.ImageByteFormat.rawRgba);
      palette = sharePaletteFromPixels(raw!.buffer.asUint8List(), stride: 7);
    });
    debugPrint('палитра: deep=${palette.deep} accent=${palette.accent}');

    final movie = LibraryMovie(
      uuid: 'colony',
      title: 'Колония',
      status: LibraryStatus.watched,
      year: 2026,
      runtimeMin: 118,
      genres: ['ужасы', 'триллер'],
      viewings: [
        Viewing(date: DateTime(2024, 3, 2), score: 6.0),
        Viewing(date: DateTime(2026, 8, 3), score: 6.9),
      ],
      emotions: const [
        MovieEmotion(id: 'wow', label: 'Взрыв мозга', emoji: '🤯', score: 9),
      ],
    );

    ShareCardData data(ShareTexture texture) => ShareCardData(
          title: movie.displayTitle,
          meta: shareMetaLine(movie),
          palette: palette,
          facts: shareFactsOf(movie),
          footerNote: shareFooterNote(movie),
          texture: texture,
          poster: poster,
          backdrop: backdrop,
        );

    for (final style in ShareCardStyle.values) {
      await _shoot(
        tester,
        ShareCard(data: data(ShareTexture.frame), style: style),
        'render_${style.name}',
      );
    }
    for (final texture in ShareTexture.values) {
      await _shoot(
        tester,
        ShareCard(data: data(texture), style: ShareCardStyle.poster),
        'render_texture_${texture.name}',
      );
    }
  });
}
