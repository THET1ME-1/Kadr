import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/widgets/app_icon_preview.dart';

/// Знак рисуется кодом (CustomPainter), поэтому «собралось» не значит
/// «видно». Тест проверяет, что в PNG реально попали и подложка, и знак,
/// и что play — сквозная дыра, а не залитый треугольник.
void main() {
  const mark = Color(0xFF00B5C7);
  const bg = Color(0xFF0E1316);

  Future<ui.Image> decode(List<int> png) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
    return (await codec.getNextFrame()).image;
  }

  Future<Color> pixel(ui.Image img, int x, int y) async {
    final data = await img.toByteData();
    final i = (y * img.width + x) * 4;
    return Color.fromARGB(
      data!.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }

  test('renderIconPng рисует знак на подложке', () async {
    final png = await renderIconPng(mark: mark, background: bg, size: 216);
    expect(png, isNotNull);
    expect(png!.length, greaterThan(500), reason: 'PNG подозрительно пустой');

    final img = await decode(png);
    expect(img.width, 216);

    // Угол — подложка: фон рисуется на всю канву, маску наложит лаунчер.
    expect(await pixel(img, 3, 3), bg);

    // Тело плиты: точка между перфорацией и play на центральной оси.
    // При scale=0.56 плита занимает 26.5..73.5, перфорация кончается на ~33,
    // play начинается на ~46 — значит 40% ширины гарантированно тело знака.
    expect(await pixel(img, (216 * 0.40).round(), 108), mark);
  });

  test('play — сквозной вырез: сквозь него виден фон', () async {
    const scale = 0.56; // = FG_SCALE в tool/gen_icons.py
    final png =
        await renderIconPng(mark: mark, background: bg, size: 216, scale: scale);
    final img = await decode(png!);

    // Центр play-выреза должен показывать подложку, а не заливку знака.
    // Треугольник (cx=56, cy=56) в системе 0..100; знак ужат scale со сдвигом
    // off=50*(1-scale) → экранная координата = (off + 56*scale)/100.
    const off = 50 * (1 - scale);
    const c = (off + 56 * scale) / 100;
    final p = await pixel(img, (216 * c).round(), (216 * c).round());
    expect(p, bg, reason: 'play должен быть дырой, а не залитым треугольником');
  });

  test('вокруг знака остаётся воздух: под маской лаунчера виден фон', () async {
    final png = await renderIconPng(mark: mark, background: bg, size: 216);
    final img = await decode(png!);

    // Точка внутри видимых 72dp из 108dp, но за пределами знака: там обязан
    // быть фон. Иначе знак распирает маску и срез режется её краем.
    // Видимая зона: 0.5 ± 36/108 → берём край видимой зоны по горизонтали.
    const edge = 0.5 - 32 / 108;
    final p = await pixel(img, (216 * edge).round(), 108);
    expect(p, bg, reason: 'знак не должен доходить до края маски лаунчера');
  });
}
