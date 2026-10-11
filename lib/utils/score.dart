import 'package:flutter/material.dart';

/// Мягкий приглушённый красный — единый акцент для «Брошено» и «Убрать оценку»
/// (кнопки и бейджи-пометки на постерах).
const Color kDroppedColor = Color(0xFFC85A54);

/// Плавный цвет оценки 1.0–10.0: от мягкого красного к тёплому золоту.
///
/// Проходит красный → оранжевый → янтарь → золото. Тона намеренно приглушённые
/// (умеренная насыщенность), чтобы не рябило, но балл читался с одного взгляда.
Color scoreColor(double score) {
  final t = ((score - 1) / 9).clamp(0.0, 1.0);
  // Оттенок: 6° (красный) → 46° (золото). Насыщенность к золоту чуть падает,
  // светлота чуть растёт — золото выглядит мягче и светлее красного.
  final hue = 6 + (46 - 6) * t;
  final sat = 0.60 - 0.08 * t;
  final light = 0.56 + 0.07 * t;
  return HSLColor.fromAHSL(1, hue, sat, light).toColor();
}

/// Цвет разницы оценок: зелёный у роста, красный у падения, приглушённый
/// текст без изменений. Тона свои под светлую и тёмную тему.
Color deltaColor(double d, ColorScheme scheme) {
  if (d.abs() < 0.05) return scheme.onSurfaceVariant;
  final dark = scheme.brightness == Brightness.dark;
  if (d > 0) return dark ? const Color(0xFF6FD39A) : const Color(0xFF1F7D45);
  return dark ? const Color(0xFFFF8A80) : const Color(0xFFB3352E);
}

/// Разница со знаком: «+0.5», «-0.8», без изменений «0.0».
String signedDelta(double d) {
  final r = (d * 10).round() / 10;
  if (r == 0) return '0.0';
  return '${r > 0 ? '+' : ''}${r.toStringAsFixed(1)}';
}

/// Контрастный цвет текста поверх [scoreColor] (для числа внутри бегунка).
/// Порог 0.25 (а не 0.5): у оранжево-янтарной середины luminance ~0.35,
/// и тёмный текст там контрастнее белого (~6:1 против ~2.6:1).
Color onScoreColor(double score) {
  final c = scoreColor(score);
  return c.computeLuminance() > 0.25 ? const Color(0xFF2A1600) : Colors.white;
}
