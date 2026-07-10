import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Оборачивает контент в тактильную анимацию нажатия (лёгкое «вдавливание»)
/// в духе Material 3 Expressive, с лёгким виброоткликом при тапе.
///
/// Также фокусируемо с пульта/клавиатуры (Android TV): при фокусе карточка
/// слегка увеличивается — видно, что выбрано, а нажатие OK/Enter вызывает [onTap].
/// На тач-вводе фокус не срабатывает, поэтому на телефоне поведение прежнее.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  /// Лёгкая гаптика при тапе (в духе M3). Отключаемо там, где отклик уже даёт
  /// вызванное действие (иначе двойной тик).
  final bool haptic;

  /// Как ловить нажатие: по умолчанию — по всей области (opaque), чтобы тап
  /// срабатывал и на пустых участках карточки.
  final HitTestBehavior behavior;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.95,
    this.haptic = true,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _focused = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    // Масштаб: нажато → вдавливание; в фокусе (пульт/клавиатура) → лёгкий «поп».
    final scale = _down ? widget.scale : (_focused ? 1.06 : 1.0);
    return FocusableActionDetector(
      enabled: widget.onTap != null || widget.onLongPress != null,
      onShowFocusHighlight: (v) {
        if (_focused != v) setState(() => _focused = v);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _handleTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null ? null : _handleTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 130),
          curve: AppTheme.emphasized,
          child: widget.child,
        ),
      ),
    );
  }
}
