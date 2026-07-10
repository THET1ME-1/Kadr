import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Иконка с пружинным «попом» при ВКЛючении [active] — для delight-моментов
/// (избранное, отметки). M3 Expressive: перелёт масштаба и мягкий возврат.
/// При выключении меняется без прыжка.
class PopIcon extends StatefulWidget {
  final bool active;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color? activeColor;
  final Color? inactiveColor;
  final double size;
  const PopIcon({
    super.key,
    required this.active,
    required this.activeIcon,
    required this.inactiveIcon,
    this.activeColor,
    this.inactiveColor,
    this.size = 24,
  });

  @override
  State<PopIcon> createState() => _PopIconState();
}

class _PopIconState extends State<PopIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: AppTheme.emphasizedDecelerate)),
        weight: 45),
    TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 0.9)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 25),
    TweenSequenceItem(
        tween: Tween(begin: 0.9, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30),
  ]).animate(_c);

  @override
  void didUpdateWidget(covariant PopIcon old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(
        widget.active ? widget.activeIcon : widget.inactiveIcon,
        color: widget.active ? widget.activeColor : widget.inactiveColor,
        size: widget.size,
      ),
    );
  }
}
