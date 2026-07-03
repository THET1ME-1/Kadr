import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/score.dart';

/// Слайдер-«линейка» для оценки 1.0–10.0.
///
/// Вместо тонкого стандартного бегунка — широкий круг с числом внутри, который
/// едет по дорожке с делениями (как линейка). Крупный бегунок и деления делают
/// выбор точным: сложно случайно перепрыгнуть через нужный балл. Залитая часть
/// дорожки и сам круг плавно перекрашиваются от красного к золоту.
class RatingSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const RatingSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  State<RatingSlider> createState() => _RatingSliderState();
}

class _RatingSliderState extends State<RatingSlider> {
  static const double _knob = 48;
  static const double _trackH = 12;
  bool _active = false;

  /// Последнее значение, отданное в onChanged: родитель мог ещё не
  /// перестроиться к моменту onChangeEnd (быстрый тап), а widget.value
  /// тогда устаревшее — коммитим именно это.
  double? _lastEmitted;

  double _valueFromDx(double dx, double width) {
    final usable = (width - _knob).clamp(1.0, double.infinity);
    final frac = ((dx - _knob / 2) / usable).clamp(0.0, 1.0);
    final v = 1 + frac * 9;
    return (v * 10).round() / 10; // шаг 0.1
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = scoreColor(widget.value);
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final usable = (width - _knob).clamp(1.0, double.infinity);
      final frac = ((widget.value - 1) / 9).clamp(0.0, 1.0);
      final knobX = _knob / 2 + frac * usable;

      void update(double dx) {
        final v = _valueFromDx(dx, width);
        // Эмитим и «щёлкаем» тактильно только на смене деления (0.1) — чтобы
        // выбор ощущался как линейка с насечками и не спамил вибрацией.
        if (v == _lastEmitted) return;
        _lastEmitted = v;
        HapticFeedback.selectionClick();
        widget.onChanged(v);
      }

      void finish() {
        setState(() => _active = false);
        final v = _lastEmitted;
        _lastEmitted = null;
        // Коммитим только если значение реально менялось: отменённый жест
        // (например, победил вертикальный скролл) не должен ничего записать.
        if (v != null) widget.onChangeEnd?.call(v);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Тап меняет значение только при отпускании — случайное касание при
        // скролле листа (tapCancel) ничего не портит.
        onTapDown: (_) {
          setState(() => _active = true);
          widget.onChangeStart?.call(widget.value);
        },
        onTapUp: (d) {
          update(d.localPosition.dx);
          finish();
        },
        onTapCancel: () => setState(() => _active = false),
        onHorizontalDragStart: (d) {
          setState(() => _active = true);
          widget.onChangeStart?.call(widget.value);
          update(d.localPosition.dx);
        },
        onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
        onHorizontalDragEnd: (_) => finish(),
        onHorizontalDragCancel: finish,
        child: SizedBox(
          height: 64,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Дорожка с делениями + залитая часть.
              Positioned(
                left: 0,
                right: 0,
                top: (64 - _trackH) / 2,
                child: CustomPaint(
                  size: Size(width, _trackH),
                  painter: _TrackPainter(
                    frac: frac,
                    knob: _knob,
                    fill: c,
                    track: scheme.surfaceContainerHighest,
                    tick: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  ),
                ),
              ),
              // Крупный бегунок-круг с числом внутри.
              Positioned(
                left: knobX - _knob / 2,
                top: (64 - _knob) / 2,
                child: AnimatedScale(
                  scale: _active ? 1.08 : 1,
                  duration: const Duration(milliseconds: 120),
                  curve: AppTheme.emphasized,
                  child: Container(
                    width: _knob,
                    height: _knob,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: c.withValues(alpha: 0.45),
                          blurRadius: _active ? 16 : 9,
                          spreadRadius: _active ? 1 : 0,
                        ),
                      ],
                    ),
                    child: Text(
                      widget.value.toStringAsFixed(1),
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: onScoreColor(widget.value),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _TrackPainter extends CustomPainter {
  final double frac;
  final double knob;
  final Color fill;
  final Color track;
  final Color tick;

  _TrackPainter({
    required this.frac,
    required this.knob,
    required this.fill,
    required this.track,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final left = knob / 2;
    final right = size.width - knob / 2;
    final cy = size.height / 2;

    // Фон дорожки.
    final bgRect =
        RRect.fromLTRBR(0, 0, size.width, size.height, r);
    canvas.drawRRect(bgRect, Paint()..color = track);

    // Деления-линейка (1..10).
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 9; i++) {
      final x = left + (right - left) * (i / 9);
      canvas.drawLine(Offset(x, cy - 3), Offset(x, cy + 3), tickPaint);
    }

    // Залитая часть до бегунка.
    final knobX = left + (right - left) * frac;
    if (knobX > 0.5) {
      final fillRect =
          RRect.fromLTRBR(0, 0, knobX.clamp(0.0, size.width), size.height, r);
      canvas.drawRRect(fillRect, Paint()..color = fill);
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.frac != frac || old.fill != fill || old.track != track;
}
