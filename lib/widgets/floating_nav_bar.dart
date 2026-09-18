import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Высота пустого хвоста в конце списка вкладки.
///
/// С плавающим меню ([FloatingNavBar] и `extendBody`) нижний отступ тела
/// равен высоте меню, и последней карточке нужно место над ним. С
/// классическим меню отступа нет, а хвост 96 оставлен под кнопку «+».
double bottomListTail(BuildContext context) =>
    math.max(96, MediaQuery.paddingOf(context).bottom + 16);

/// Вкладка плавающего меню.
class FloatingNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Вместо значка, например аватар на вкладке профиля.
  final Widget? leading;

  /// Число на значке (входящие заявки). 0 — без числа.
  final int badge;

  const FloatingNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.leading,
    this.badge = 0,
  });
}

/// Плавающее нижнее меню (вариант N3 макета, 2026-09-17): полупрозрачная
/// таблетка с вкладками во всю ширину. Кнопки «+» в ряду нет, добавляют через
/// «Обзор».
///
/// У открытой вкладки значок с подписью, у остальных только значки. Подпись
/// получает место, которое осталось после значков: на узком телефоне она
/// ужимается до [_minLabelScale], а если не влезает и так, остаётся только
/// значок в подсвеченной таблетке.
///
/// Кладётся в `Scaffold.bottomNavigationBar` вместе с `extendBody: true`:
/// тогда лента уходит под меню, а нижний отступ списков берётся из
/// `MediaQuery.paddingOf(context).bottom`.
class FloatingNavBar extends StatelessWidget {
  final List<FloatingNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const FloatingNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const double height = 64;
  static const double _itemHeight = 52;
  static const double _minItemWidth = 42;
  static const double _minLabelScale = 0.8;

  /// Поля таблетки открытой вкладки: слева до значка, между значком и
  /// подписью, справа после подписи.
  static const double _selLeft = 10, _selGap = 6, _selRight = 12;

  static const Duration _motion = Duration(milliseconds: 280);

  static const TextStyle _labelStyle = TextStyle(
    fontFamily: AppTheme.bodyFont,
    fontWeight: FontWeight.w700,
    fontSize: 13,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
        child: _pill(context, scheme),
      ),
    );
  }

  Widget _pill(BuildContext context, ColorScheme scheme) {
    final radius = BorderRadius.circular(height / 2);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          // Без обводки: таблетку отделяет от ленты только тон и размытие.
          decoration: BoxDecoration(
            color: scheme.surfaceContainer.withValues(alpha: 0.88),
            borderRadius: radius,
          ),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: LayoutBuilder(
                builder: (context, box) {
                  final label = _labelFor(context, box.maxWidth);
                  return Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        if (i == selectedIndex)
                          _item(context, scheme, i, label)
                        else
                          Expanded(child: _item(context, scheme, i, null)),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Подпись открытой вкладки, ужатая под свободное место, или null.
  Widget? _labelFor(BuildContext context, double width) {
    if (selectedIndex < 0 || selectedIndex >= items.length) return null;
    final text = items[selectedIndex].label;
    final room =
        width -
        (items.length - 1) * _minItemWidth -
        (_selLeft + 24 + _selGap + _selRight);
    if (room <= 0) return null;
    final natural = (TextPainter(
      text: TextSpan(text: text, style: _labelStyle),
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout()).width;
    final label = Text(text, maxLines: 1, softWrap: false, style: _labelStyle);
    if (natural <= room) return label;
    if (natural * _minLabelScale > room) return null;
    return SizedBox(
      width: room,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: label,
      ),
    );
  }

  Widget _item(BuildContext context, ColorScheme scheme, int i, Widget? label) {
    final item = items[i];
    final selected = i == selectedIndex;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    Widget icon =
        item.leading ??
        Icon(selected ? item.selectedIcon : item.icon, size: 24, color: fg);
    if (item.badge > 0) {
      icon = Badge(label: Text('${item.badge}'), child: icon);
    }
    final withLabel = selected && label != null;
    return Tooltip(
      message: item.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            if (!selected) HapticFeedback.selectionClick();
            onSelect(i);
          },
          child: AnimatedContainer(
            duration: _motion,
            curve: AppTheme.emphasized,
            height: _itemHeight,
            constraints: const BoxConstraints(minWidth: _minItemWidth),
            padding: withLabel
                ? const EdgeInsetsDirectional.fromSTEB(
                    _selLeft,
                    0,
                    _selRight,
                    0,
                  )
                : const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(_itemHeight / 2),
            ),
            child: withLabel
                ? DefaultTextStyle.merge(
                    style: TextStyle(color: fg),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        icon,
                        const SizedBox(width: _selGap),
                        label,
                      ],
                    ),
                  )
                : icon,
          ),
        ),
      ),
    );
  }
}
