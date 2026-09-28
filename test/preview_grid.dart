// Служебный рендер сетки оценок в PNG, чтобы посмотреть без телефона. Имя без
// суффикса `_test`, в обычный прогон не попадает. Запуск руками:
//
//   flutter test test/preview_grid.dart
//
// Постеры берутся из `build/preview/grid_<имя>.jpg`, если лежат (любые
// картинки), результат — туда же, `grid_*.png`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/utils/episode_grid.dart';
import 'package:kadr/utils/format.dart';
import 'package:kadr/utils/share_palette.dart';
import 'package:kadr/widgets/episode_grid_card.dart';

const _out = 'build/preview';

Future<void> _loadFonts() async {
  for (final family in ['Unbounded', 'Onest']) {
    final loader = FontLoader(family)
      ..addFont(File('assets/fonts/$family.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
}

Future<ui.Image?> _load(String path) async {
  final file = File(path);
  if (!file.existsSync()) return null;
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  return (await codec.getNextFrame()).image;
}

/// Сериал по оценкам сезонов; `null` в списке — серия не просмотрена.
LibrarySeries _series(List<List<double?>> seasons) {
  final s = LibrarySeries(tvShowId: 'x', title: 'x');
  for (var i = 0; i < seasons.length; i++) {
    for (var j = 0; j < seasons[i].length; j++) {
      final v = seasons[i][j];
      if (v == null) continue;
      s.episodes.add(Episode(season: i + 1, number: j + 1, score: v));
    }
  }
  return s;
}

List<double> _r(double v, int n) => List.filled(n, v);

void main() {
  testWidgets('Рендер сетки оценок', (tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadFonts);

    // Оценки из бэкапа владельца (2026-09-10), структура сезонов из TMDB.
    final shows = {
      'got': (
        'Игра престолов',
        2011,
        _series([
          _r(9.5, 10),
          [9, 9, 9, 9, 9, 9, 9.5, 9.5, 9.6, 8.8],
          [9, 9.5, 9.5, 9.5, 9.6, 9.6, 9.6, 9.5, 9.9, 9.5],
          [9.5, 9.6, 9.4, 9.5, 9.4, 9.5, 9.4, 9.6, 9.7, 9.3],
          [9.4, 9.4, 9.4, 9, 9, 9, 9, 9, 8.5, 9],
          [8.8, 8.8, 8.8, 8],
        ]),
        {1: 10, 2: 10, 3: 10, 4: 10, 5: 10, 6: 10, 7: 7, 8: 6},
      ),
      'flash': (
        'Флэш',
        2014,
        _series([
          _r(10, 23), _r(10, 23), _r(9, 23), _r(8, 23), _r(5, 22),
          _r(5, 19), _r(4, 18), _r(4, 20),
          [4, 4, 4, 4, 4, 4, 4, 4, 4, 8, 4, 4, 4],
        ]),
        {1: 23, 2: 23, 3: 23, 4: 23, 5: 22, 6: 19, 7: 18, 8: 20, 9: 13},
      ),
      'sev': (
        'Разделение',
        2022,
        _series([
          [9, 8, 8, 8, 8, 8, 8, 6, 9],
          [8, 8, 7.1, 6.5, 7, 7.5, 8, 6, 8, 8],
        ]),
        {1: 9, 2: 10},
      ),
    };

    for (final MapEntry(key: name, value: show) in shows.entries) {
      final (title, year, series, sizes) = show;
      ui.Image? poster;
      var palette = SharePalette.fallback;
      await tester.runAsync(() async {
        poster = await _load('$_out/grid_$name.jpg');
        if (poster != null) {
          final raw = await poster!.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          palette = sharePaletteFromPixels(raw!.buffer.asUint8List(), stride: 7);
        }
      });

      final key = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1200, 3600)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: EpisodeGridCard(
                  data: EpisodeGridCardData(
                    title: title,
                    year: year,
                    palette: palette,
                    poster: poster,
                    grid: buildEpisodeGrid(series, sizes),
                    dateNote: '${dayMonth(DateTime(2026, 9, 28))} 2026',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Directory(_out).create(recursive: true);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await File('$_out/grid_$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
      });
    }
  });
}
