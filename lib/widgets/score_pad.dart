import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/score.dart';

/// Открывает кастомную M3-клавиатуру-калькулятор для ручного ввода оценки
/// (1.0–10.0, шаг 0.1). Возвращает введённый балл или null (отмена).
Future<double?> showScorePad(BuildContext context, {double? initial}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ScorePad(initial: initial),
  );
}

class _ScorePad extends StatefulWidget {
  final double? initial;
  const _ScorePad({this.initial});

  @override
  State<_ScorePad> createState() => _ScorePadState();
}

class _ScorePadState extends State<_ScorePad> {
  late String _input =
      widget.initial == null ? '' : _trim(widget.initial!.toStringAsFixed(1));

  static String _trim(String s) =>
      s.endsWith('.0') ? s.substring(0, s.length - 2) : s;

  double? get _value => double.tryParse(_input);
  bool get _valid => _value != null && _value! > 0;

  /// Можно ли дописать клавишу к текущему вводу (держим 1..10, 1 знак после точки).
  bool _canAppend(String key) {
    if (key == '.') return !_input.contains('.') && _input.isNotEmpty;
    if (_input.isEmpty && key == '0') return false; // минимум 1.0
    final next = _input + key;
    final dot = next.indexOf('.');
    if (dot >= 0 && next.length - dot - 1 > 1) return false; // >1 знака дробной
    final intPart = dot >= 0 ? next.substring(0, dot) : next;
    if (intPart.length > 2) return false; // максимум «10»
    final v = double.tryParse(next);
    if (v == null || v > 10.0) return false;
    return true;
  }

  void _tap(String key) {
    if (!_canAppend(key)) return;
    HapticFeedback.selectionClick();
    setState(() => _input += key);
  }

  void _backspace() {
    if (_input.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  void _confirm() {
    final v = _value;
    if (v == null) return;
    final clamped = (v.clamp(1.0, 10.0) * 10).round() / 10;
    Navigator.of(context).pop(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = _value;
    final accent = (v != null && v > 0)
        ? scoreColor(v.clamp(1.0, 10.0))
        : scheme.onSurfaceVariant;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text(tr('enter_score'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            // Табло ввода.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Icon(_valid ? Icons.star_rounded : Icons.star_border_rounded,
                    color: accent, size: 34),
                const SizedBox(width: 8),
                Text(_input.isEmpty ? '—' : _input,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 52,
                        height: 1,
                        color: accent)),
                Text(' / 10',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 16),
            // Клавиатура калькулятора.
            for (final row in const [
              ['7', '8', '9'],
              ['4', '5', '6'],
              ['1', '2', '3'],
              ['.', '0', '⌫'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (final k in row) ...[
                      _key(scheme, k),
                      if (k != row.last) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _valid ? _confirm : null,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: Text(tr('done'),
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _key(ColorScheme scheme, String k) {
    final isBack = k == '⌫';
    final isDot = k == '.';
    final bg = isBack
        ? scheme.secondaryContainer
        : (isDot ? scheme.surfaceContainerHighest : scheme.surfaceContainerHigh);
    final fg = isBack
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    final enabled = isBack ? _input.isNotEmpty : _canAppend(k);
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1.7,
        child: Material(
          color: bg.withValues(alpha: enabled ? 1 : 0.4),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? (isBack ? _backspace : () => _tap(k)) : null,
            child: Center(
              child: isBack
                  ? Icon(Icons.backspace_rounded, size: 24, color: fg)
                  : Text(k,
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 26,
                          color: fg.withValues(alpha: enabled ? 1 : 0.5))),
            ),
          ),
        ),
      ),
    );
  }
}
