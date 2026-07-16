import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/app_icon_service.dart';

/// Превью launcher-иконки: знак «Засечка» на подложке.
///
/// Рисуется кодом, а не берётся из mipmap: ассеты лаунчера лежат в `android/`
/// и во Flutter не видны. Геометрия повторяет `docs/logo/E-zasechka.svg`
/// (см. `docs/logo_prompt.md`) — сквиркл-суперэллипс, срезанный угол,
/// сквозные вырезы. Числа даны в системе координат 0..100 и масштабируются.
class AppIconPreview extends StatelessWidget {
  const AppIconPreview({
    super.key,
    required this.option,
    this.size = 56,
    this.radiusFactor = 0.24,
  }) : mark = null,
       background = null;

  /// Превью произвольной пары цветов (экран «Своя иконка»).
  const AppIconPreview.colors({
    super.key,
    required Color this.mark,
    required Color this.background,
    this.size = 56,
    this.radiusFactor = 0.24,
  }) : option = null;

  final AppIconOption? option;
  final Color? mark;
  final Color? background;
  final double size;

  /// Скругление подложки в долях стороны (0.5 — круг).
  final double radiusFactor;

  @override
  Widget build(BuildContext context) {
    final m = mark ?? option!.mark;
    final b = background ?? option!.background;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * radiusFactor),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ZasechkaPainter(mark: m, background: b),
        ),
      ),
    );
  }
}

/// Рендерит знак в PNG для закрепляемого ярлыка.
///
/// Канва — вся картинка (adaptive-битмап: маску наложит лаунчер), знак ужат до
/// [scale]. Значение совпадает с `FG_SCALE` в `tool/gen_icons.py`: знак сам
/// сквиркл, и при большем размере он распирает маску лаунчера — фон вырождается
/// в кайму, а срезанный угол режется краем круглой маски.
Future<Uint8List?> renderIconPng({
  required Color mark,
  required Color background,
  int size = 432,
  double scale = 0.56,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  _ZasechkaPainter(mark: mark, background: background, scale: scale)
      .paint(canvas, Size(size.toDouble(), size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}

class _ZasechkaPainter extends CustomPainter {
  const _ZasechkaPainter({
    required this.mark,
    required this.background,
    this.scale = 0.78,
  });

  final Color mark;
  final Color background;

  /// Знак внутри подложки. 0.78 — как LEGACY_SCALE в генераторе; для adaptive
  /// берётся 0.68 (запас под маску лаунчера).
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final k = size.width / 100.0;
    canvas.save();
    // тот же центрирующий сдвиг, что в gen_icons.py: translate(off) + scale
    final off = 50 * (1 - scale) * k;
    canvas.translate(off, off);
    canvas.scale(scale * k);

    // Плита со срезанным верхним правым углом ∩ маска среза.
    final plate = Path.combine(
      PathOperation.intersect,
      _squircle(50, 50, 42),
      Path()
        ..moveTo(0, 0)
        ..lineTo(52, 0)
        ..lineTo(100, 48)
        ..lineTo(100, 100)
        ..lineTo(0, 100)
        ..close(),
    );

    // Сквозные вырезы: play и две перфорации.
    var body = Path.combine(PathOperation.difference, plate,
        _playTriangle(r: 23, cx: 56, cy: 56, round: 3.3));
    for (final cy in const [46.0, 66.0]) {
      body = Path.combine(
          PathOperation.difference, body, _capsule(16.5, cy, 7, 12));
    }

    canvas.drawPath(body, Paint()..color = mark..isAntiAlias = true);
    canvas.restore();
  }

  /// Суперэллипс |x/a|^4 + |y/a|^4 = 1 кубическими Безье (n = 4).
  Path _squircle(double cx, double cy, double a) {
    const n = 4.0;
    final s = a * math.pow(0.5, 1 / n);
    final kk = (8 * s - 4 * a) / 3.0;
    final r = cx + a, l = cx - a, t = cy - a, b = cy + a;
    return Path()
      ..moveTo(r, cy)
      ..cubicTo(r, cy + kk, cx + kk, b, cx, b)
      ..cubicTo(cx - kk, b, l, cy + kk, l, cy)
      ..cubicTo(l, cy - kk, cx - kk, t, cx, t)
      ..cubicTo(cx + kk, t, r, cy - kk, r, cy)
      ..close();
  }

  /// Равносторонний play вершиной вправо со скруглёнными углами.
  Path _playTriangle({
    required double r,
    required double cx,
    required double cy,
    required double round,
  }) {
    final pts = <Offset>[
      for (final deg in const [0.0, 120.0, 240.0])
        Offset(cx + r * math.cos(deg * math.pi / 180),
            cy + r * math.sin(deg * math.pi / 180)),
    ];
    return _roundedPoly(pts, round);
  }

  /// Многоугольник со скруглёнными углами: отступаем по рёбрам и гасим угол дугой.
  Path _roundedPoly(List<Offset> pts, double radius) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final prev = pts[(i - 1 + pts.length) % pts.length];
      final next = pts[(i + 1) % pts.length];
      final toPrev = (prev - p);
      final toNext = (next - p);
      final uPrev = toPrev / toPrev.distance;
      final uNext = toNext / toNext.distance;
      final angle = math.acos(
          (uPrev.dx * uNext.dx + uPrev.dy * uNext.dy).clamp(-1.0, 1.0));
      final d = radius / math.tan(angle / 2);
      final aIn = p + uPrev * d;
      final aOut = p + uNext * d;
      if (i == 0) {
        path.moveTo(aIn.dx, aIn.dy);
      } else {
        path.lineTo(aIn.dx, aIn.dy);
      }
      path.arcToPoint(aOut, radius: Radius.circular(radius), clockwise: true);
    }
    path.close();
    return path;
  }

  /// Капсула-перфорация: радиус — половина короткой стороны.
  Path _capsule(double cx, double cy, double w, double h) {
    final r = math.min(w, h) / 2;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
        Radius.circular(r),
      ));
  }

  @override
  bool shouldRepaint(_ZasechkaPainter old) =>
      old.mark != mark || old.background != background || old.scale != scale;
}
