import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Связанная группа кнопок M3 Expressive (вариант Б макета «Кнопки
/// карточки»): кнопки стоят впритык через 2, внешние углы круглые,
/// внутренние 8. Одна на карточку фильма и на экран сериала, чтобы они не
/// расходились.
///
/// Кнопка с подписью растягивается, значок стоит квадратом 56.
class ActionGroup extends StatelessWidget {
  final List<ActionGroupButton> buttons;

  const ActionGroup(this.buttons, {super.key});

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    const outer = Radius.circular(24), inner = Radius.circular(8);
    OutlinedBorder shapeAt(int i) => RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            left: i == 0 ? outer : inner,
            right: i == buttons.length - 1 ? outer : inner,
          ),
        );
    return Row(
      spacing: 2,
      children: [
        for (var i = 0; i < buttons.length; i++)
          buttons[i].label != null
              ? Expanded(child: buttons[i]._build(shapeAt(i)))
              : buttons[i]._build(shapeAt(i)),
      ],
    );
  }
}

/// Кнопка [ActionGroup]: значок с подсказкой или подпись со значком.
/// Включённая ([active]) залита primary, выключенная тональная.
class ActionGroupButton {
  final VoidCallback onPressed;
  final bool active;

  /// Значок кнопки-квадрата и её подсказка.
  final Widget? child;
  final String? tooltip;

  /// Подпись растянутой кнопки и значок перед ней.
  final String? label;
  final IconData? icon;

  /// Заливка включённого значка вместо primary, значок на ней белый.
  final Color? activeColor;

  /// Цвет выключенного значка вместо onSecondaryContainer.
  final Color? tint;

  const ActionGroupButton.icon({
    required String this.tooltip,
    required Widget this.child,
    required this.onPressed,
    this.active = false,
    this.activeColor,
    this.tint,
  })  : label = null,
        icon = null;

  const ActionGroupButton.label({
    required String this.label,
    required IconData this.icon,
    required this.onPressed,
    this.active = false,
  })  : child = null,
        tooltip = null,
        activeColor = null,
        tint = null;

  Widget _build(OutlinedBorder shape) {
    final label = this.label;
    if (label == null) {
      final style = FilledButton.styleFrom(
        minimumSize: const Size(56, ActionGroup.height),
        padding: EdgeInsets.zero,
        shape: shape,
        backgroundColor: active ? activeColor : null,
        foregroundColor:
            active ? (activeColor == null ? null : Colors.white) : tint,
      );
      return Tooltip(
        message: tooltip!,
        child: active
            ? FilledButton(onPressed: onPressed, style: style, child: child)
            : FilledButton.tonal(
                onPressed: onPressed, style: style, child: child),
      );
    }
    final style = FilledButton.styleFrom(
      minimumSize: const Size(0, ActionGroup.height),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: shape,
      textStyle: const TextStyle(
        fontFamily: AppTheme.bodyFont,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
    // Подпись ужимается на узком экране, а не вылезает за край.
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [Icon(icon, size: 20), Text(label, maxLines: 1)],
      ),
    );
    return active
        ? FilledButton(onPressed: onPressed, style: style, child: content)
        : FilledButton.tonal(onPressed: onPressed, style: style, child: content);
  }
}
