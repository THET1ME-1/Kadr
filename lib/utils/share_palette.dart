import 'dart:typed_data';
import 'package:flutter/painting.dart';

/// Пара цветов, которой красится карточка «Поделиться»: очень тёмный фон и
/// живой акцент. Оба берутся из самого постера, поэтому у каждого фильма
/// картинка своя, а тема приложения на неё не влияет.
class SharePalette {
  const SharePalette({required this.deep, required this.accent});

  /// Почти чёрный тон фильма — фон карточки.
  final Color deep;

  /// Живой цвет постера — свечение, кромки, мелкие акценты.
  final Color accent;

  /// Палитра, когда постера нет или он ничего не сказал о цвете.
  static const SharePalette fallback = SharePalette(
    deep: Color(0xFF06171A),
    accent: Color(0xFF4B97A2),
  );

  @override
  bool operator ==(Object other) =>
      other is SharePalette && other.deep == deep && other.accent == accent;

  @override
  int get hashCode => Object.hash(deep, accent);
}

/// Считает палитру по сырым пикселям постера (RGBA8888, как отдаёт
/// `Image.toByteData(format: rawRgba)`).
///
/// Оттенки складываются в гистограмму из 36 корзин по 10°, и каждый пиксель
/// весит свою насыщенность: серая масса почти ничего не добавляет, а редкое
/// цветное пятно перевешивает её и задаёт тон. Прозрачные пиксели пропускаются.
SharePalette sharePaletteFromPixels(Uint8List rgba, {int stride = 1}) {
  if (rgba.length < 4) return SharePalette.fallback;

  const bins = 36;
  final weights = List<double>.filled(bins, 0);
  final sats = List<double>.filled(bins, 0);
  final step = 4 * (stride < 1 ? 1 : stride);

  for (var i = 0; i + 3 < rgba.length; i += step) {
    if (rgba[i + 3] < 128) continue;
    final hsl = HSLColor.fromColor(
      Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]),
    );
    // Слишком тёмные и слишком светлые пиксели о цвете говорят плохо.
    final lightness = hsl.lightness;
    if (lightness < 0.06 || lightness > 0.94) continue;
    // Вес = насыщенность в квадрате: разница между «чуть цветным» и «цветным»
    // становится резче, и серый фон не забивает акцент числом пикселей.
    final w = hsl.saturation * hsl.saturation;
    if (w <= 0.0001) continue;
    final bin = (hsl.hue / (360 / bins)).floor() % bins;
    weights[bin] += w;
    sats[bin] += hsl.saturation * w;
  }

  var best = -1;
  var bestWeight = 0.0;
  for (var i = 0; i < bins; i++) {
    if (weights[i] > bestWeight) {
      bestWeight = weights[i];
      best = i;
    }
  }

  // Постер без цвета (чёрно-белый кадр, тёмная афиша) — уходим в нейтральный
  // холодный тон вместо чёрной дыры.
  if (best < 0 || bestWeight < 0.05) {
    return const SharePalette(
      deep: Color(0xFF0B1113),
      accent: Color(0xFF6E7E82),
    );
  }

  final hue = (best + 0.5) * (360 / bins);
  final saturation = (sats[best] / weights[best]).clamp(0.30, 0.85);

  return SharePalette(
    deep: HSLColor.fromAHSL(
      1,
      hue,
      (saturation * 0.75).clamp(0.25, 0.6),
      0.055,
    ).toColor(),
    accent: HSLColor.fromAHSL(1, hue, saturation, 0.55).toColor(),
  );
}
