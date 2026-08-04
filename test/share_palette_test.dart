import 'dart:typed_data';
import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/utils/share_palette.dart';

/// Собирает RGBA-буфер из списка цветов (по пикселю на цвет).
Uint8List _pixels(List<Color> colors) {
  final bytes = Uint8List(colors.length * 4);
  for (var i = 0; i < colors.length; i++) {
    final c = colors[i];
    bytes[i * 4] = (c.r * 255).round();
    bytes[i * 4 + 1] = (c.g * 255).round();
    bytes[i * 4 + 2] = (c.b * 255).round();
    bytes[i * 4 + 3] = (c.a * 255).round();
  }
  return bytes;
}

double _hue(Color c) => HSLColor.fromColor(c).hue;

void main() {
  group('sharePaletteFromPixels', () {
    test('акцент берёт оттенок постера', () {
      const red = Color(0xFFD32F2F);
      final p = sharePaletteFromPixels(_pixels(List.filled(40, red)));

      expect((_hue(p.accent) - _hue(red)).abs(), lessThan(25));
    });

    test('тёмный тон темнее акцента, но того же оттенка', () {
      const teal = Color(0xFF1B9AAA);
      final p = sharePaletteFromPixels(_pixels(List.filled(40, teal)));

      expect(p.deep.computeLuminance(), lessThan(p.accent.computeLuminance()));
      expect(p.deep.computeLuminance(), lessThan(0.06));
      expect((_hue(p.deep) - _hue(p.accent)).abs(), lessThan(25));
    });

    test('редкое цветное пятно побеждает серую массу', () {
      // Постер почти весь серый, но с ярким зелёным пятном — оно и есть цвет.
      const grey = Color(0xFF6E6E6E);
      const green = Color(0xFF2FBF5B);
      final p = sharePaletteFromPixels(
        _pixels([...List.filled(90, grey), ...List.filled(10, green)]),
      );

      expect((_hue(p.accent) - _hue(green)).abs(), lessThan(25));
    });

    test('прозрачные пиксели не участвуют', () {
      const transparentRed = Color(0x00FF0000);
      const blue = Color(0xFF2962FF);
      final p = sharePaletteFromPixels(
        _pixels([...List.filled(80, transparentRed), ...List.filled(20, blue)]),
      );

      expect((_hue(p.accent) - _hue(blue)).abs(), lessThan(25));
    });

    test('чёрно-белый постер даёт нейтральную, но не чёрную палитру', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      final p = sharePaletteFromPixels(
        _pixels([...List.filled(50, black), ...List.filled(50, white)]),
      );

      expect(p.accent.computeLuminance(), greaterThan(0.05));
      expect(p.deep.computeLuminance(), greaterThan(0.0));
    });

    test('пустые данные дают палитру по умолчанию', () {
      final p = sharePaletteFromPixels(Uint8List(0));

      expect(p, SharePalette.fallback);
    });
  });
}
