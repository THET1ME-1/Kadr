import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/score.dart';

/// Тон таблетки с номером просмотра.
enum ViewChipTone {
  /// tertiary: пересмотр в окне отметки и у рецензии на сезон.
  rewatch,

  /// secondary: номер просмотра у рецензии фильма.
  review,

  /// Нейтральная: прошлая рецензия короткой строкой.
  plain,
}

/// Таблетка «👁 3-й»: значок-глаз и номер просмотра.
class ViewChip extends StatelessWidget {
  final String label;
  final ViewChipTone tone;
  const ViewChip(this.label, {super.key, this.tone = ViewChipTone.rewatch});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      ViewChipTone.rewatch => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer
        ),
      ViewChipTone.review => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer
        ),
      ViewChipTone.plain => (scheme.surfaceContainerHighest, scheme.onSurface),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(Icons.visibility_rounded, size: 14, color: fg),
          Text(label,
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: 0.2,
                  color: fg)),
        ],
      ),
    );
  }
}

/// Кружок с номером просмотра в строках списка; у последнего просмотра
/// залит `primary`. С [icon] вместо числа стоит значок (строка «Без даты»).
class ViewOrdinal extends StatelessWidget {
  final int ordinal;
  final bool latest;
  final IconData? icon;
  final bool dim;
  const ViewOrdinal(
    this.ordinal, {
    super.key,
    this.latest = false,
    this.icon,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = latest
        ? scheme.onPrimary
        : (icon != null ? scheme.onSurfaceVariant : scheme.onSurface);
    return Opacity(
      opacity: dim ? 0.6 : 1,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: latest ? scheme.primary : scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: icon != null
            ? Icon(icon, size: 20, color: fg)
            : Text('$ordinal',
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: fg)),
      ),
    );
  }
}

/// Таблетка оценки просмотра: звезда и число на цвете оценки, без оценки
/// серая с прочерком.
class ViewScorePill extends StatelessWidget {
  final double? score;
  const ViewScorePill(this.score, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = score;
    final fg = s != null ? onScoreColor(s) : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: s != null ? scoreColor(s) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(Icons.star_rounded, size: 15, color: fg),
          Text(s != null ? s.toStringAsFixed(1) : '—',
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: fg)),
        ],
      ),
    );
  }
}
