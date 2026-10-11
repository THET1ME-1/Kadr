import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../utils/score.dart';
import '../rating_slider.dart';
import '../score_pad.dart';

/// Карточка оценки одного просмотра: подпись, крупное число, слайдер-линейка
/// и строка под ним. Одна и та же в карточке фильма, в окне серии и в окне
/// просмотра.
///
/// Пока оценки нет, вместо числа стоит прочерк. Если рядом есть прошлая
/// оценка ([sameAs]), под слайдером появляется кнопка поставить её же.
class ScoreCard extends StatefulWidget {
  /// Подпись над числом: «Оценка · 3-й просмотр».
  final String label;
  final double? value;

  /// Новая оценка: отпустили слайдер, ввели с калькулятора или нажали «те же».
  final ValueChanged<double> onChanged;

  /// Строка под слайдером: «16.08.2026 · в прошлый раз 8.5».
  final String? footer;

  /// Оценка для кнопки «Те же X» и её подпись. Кнопка видна, пока своей
  /// оценки у просмотра нет.
  final double? sameAs;
  final String? sameLabel;

  /// «Убрать оценку» внутри карточки; null — кнопки нет.
  final VoidCallback? onClear;

  const ScoreCard({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.footer,
    this.sameAs,
    this.sameLabel,
    this.onClear,
  });

  @override
  State<ScoreCard> createState() => _ScoreCardState();
}

class _ScoreCardState extends State<ScoreCard> {
  double? _dragging;

  @override
  void didUpdateWidget(ScoreCard old) {
    super.didUpdateWidget(old);
    // Сменился просмотр под карточкой: недотянутое значение не переносим.
    if (old.value != widget.value) _dragging = null;
  }

  Future<void> _pick() async {
    final v = await showScorePad(context);
    if (v == null || !mounted) return;
    setState(() => _dragging = null);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onPrimaryContainer;
    final rated = _dragging != null || widget.value != null;
    // Пока не оценено, бегунок стоит слева, а число показано прочерком: иначе
    // кажется, что оценка уже есть.
    final val = _dragging ?? widget.value ?? 1.0;
    final same = widget.sameAs;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: fg.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          // Тап по числу или прочерку открывает калькулятор.
          Semantics(
            button: true,
            label: tr('your_rating'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pick,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    TweenAnimationBuilder<Color?>(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      tween: ColorTween(
                        end: rated
                            ? scoreColor(val)
                            : fg.withValues(alpha: 0.55),
                      ),
                      builder: (context, color, _) => Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Icon(
                            rated
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: color,
                            size: 32,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            rated ? val.toStringAsFixed(1) : '—',
                            style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 48,
                              height: 1,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      ' / 10',
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: fg.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.dialpad_rounded,
                      size: 18,
                      color: fg.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          RatingSlider(
            value: val,
            rated: rated,
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onChanged(v);
            },
          ),
          if (!rated && same != null && widget.sameLabel != null) ...[
            const SizedBox(height: 4),
            Material(
              color: scheme.surface,
              shape: const StadiumBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onChanged(same);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Icon(Icons.star_rounded,
                          size: 18, color: scheme.onSurface),
                      Flexible(
                        child: Text(
                          widget.sameLabel!,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else if (widget.footer != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.footer!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13,
                color: fg.withValues(alpha: 0.8),
              ),
            ),
          ],
          if (rated && widget.onClear != null)
            TextButton(
              onPressed: () {
                setState(() => _dragging = null);
                widget.onClear!();
              },
              style: TextButton.styleFrom(
                foregroundColor: fg,
                minimumSize: const Size(0, 40),
              ),
              child: Text(tr('remove_score')),
            ),
        ],
      ),
    );
  }
}
