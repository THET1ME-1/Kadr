import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Таблетка сезона на экране сериала (вариант S3 макета, 2026-09-17).
///
/// Фон заполняется слева направо на долю отмеченных серий, досмотренный сезон
/// залит целиком и помечен галочкой. Выбранный сезон обведён акцентом, а не
/// залит им: заливка уже занята прогрессом.
class SeasonPill extends StatelessWidget {
  final String label;

  /// Доля отмеченных серий, 0…1.
  final double fraction;
  final bool done;
  final bool selected;
  final VoidCallback onTap;

  const SeasonPill({
    super.key,
    required this.label,
    required this.fraction,
    required this.done,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = done ? 1.0 : fraction.clamp(0.0, 1.0);
    final fill = scheme.primaryContainer;
    final rest = scheme.surfaceContainerHighest;
    final fg = done ? scheme.onPrimaryContainer : scheme.onSurface;
    final shape = StadiumBorder(
      side: selected
          ? BorderSide(color: scheme.primary, width: 2)
          : BorderSide.none,
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: ShapeDecoration(
            shape: shape,
            // Жёсткая граница: заполненная часть и остаток без перелива.
            gradient: LinearGradient(
              colors: [fill, fill, rest, rest],
              stops: [0, p, p, 1],
            ),
          ),
          child: InkWell(
            customBorder: shape,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 40,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (done) ...[
                      Icon(Icons.check_rounded, size: 18, color: fg),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
