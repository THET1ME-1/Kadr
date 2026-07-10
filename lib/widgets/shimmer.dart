import 'package:flutter/material.dart';

/// Переливающийся плейсхолдер-скелет (M3 skeleton loading). Без внешних
/// пакетов: сам гоняет светлый блик по поверхности через движущийся градиент.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const ShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 12,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1150))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    // Блик — чуть светлее базы (в тёмной теме тоже читается).
    final hi = Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.07), base);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 - 1; // -1 → 1: сдвиг блика слева направо
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + t, -0.25),
              end: Alignment(1.0 + t, 0.25),
              colors: [base, hi, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// Скелет ленты постеров на первую загрузку: сетка мерцающих карточек,
/// повторяющая раскладку реальной сетки (колонки по [minTile]).
class PosterGridSkeleton extends StatelessWidget {
  final double minTile;
  final double textExtra;
  final EdgeInsets padding;
  const PosterGridSkeleton({
    super.key,
    this.minTile = 130,
    this.textExtra = 48,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 96),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const spacing = 12.0;
      final avail = c.maxWidth - padding.horizontal;
      final cols = (avail / minTile).floor().clamp(2, 6);
      final w = (avail - spacing * (cols - 1)) / cols;
      final posterH = w * 1.5;
      return GridView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: spacing,
          mainAxisSpacing: 18,
          mainAxisExtent: posterH + textExtra,
        ),
        itemCount: cols * 4,
        itemBuilder: (context, i) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(height: posterH, width: w, radius: 16),
            const SizedBox(height: 8),
            ShimmerBox(height: 11, width: w * 0.82, radius: 4),
            const SizedBox(height: 6),
            ShimmerBox(height: 10, width: w * 0.5, radius: 4),
          ],
        ),
      );
    });
  }
}
