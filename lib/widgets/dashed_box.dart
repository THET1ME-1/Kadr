import 'package:flutter/material.dart';

/// Рамка пунктиром со скруглением: так помечено то, что выбрать нельзя
/// (просмотр с готовой рецензией) или чего нет (сезон смотрели, а рецензию
/// не писали).
class DashedBox extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final Color? color;
  final EdgeInsetsGeometry padding;

  const DashedBox({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(10)),
    this.color,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _DashedPainter(
          color ?? Theme.of(context).colorScheme.outlineVariant,
          radius,
        ),
        child: Padding(padding: padding, child: child),
      );
}

class _DashedPainter extends CustomPainter {
  final Color color;
  final BorderRadius radius;
  const _DashedPainter(this.color, this.radius);

  static const double _stroke = 1.5, _dash = 5, _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final path = Path()..addRRect(radius.toRRect(rect));
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius;
}
