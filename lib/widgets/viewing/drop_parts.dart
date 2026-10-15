import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';

/// Заливка брошенного: мягкий красный поверх [base] (по умолчанию
/// surfaceContainerHigh). Так залиты карточка попытки в ленте и блок
/// «Брошен» в карточке фильма (вариант Л2 макета KADR-1).
Color dropTint(ColorScheme scheme, {Color? base, double alpha = 0.14}) =>
    Color.alphaBlend(kDroppedColor.withValues(alpha: alpha),
        base ?? scheme.surfaceContainerHigh);

/// Причины брошенного фильма мелкими красными метками.
class DropReasonPills extends StatelessWidget {
  final List<String> reasons;
  const DropReasonPills(this.reasons, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = dropTint(scheme, base: scheme.surface, alpha: 0.18);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final r in reasons)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(r,
                style: const TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    height: 1.5,
                    color: kDroppedColor)),
          ),
      ],
    );
  }
}

/// Заливка начатого фильма: основной цвет поверх [base] (по умолчанию
/// surfaceContainerHigh). Так залиты карточка начатого в ленте и блок
/// «Начат» в карточке фильма (вариант Г2 макета «Фильм в несколько
/// заходов»): в тон, как брошенный, только не красным.
Color pauseTint(ColorScheme scheme, {Color? base, double alpha = 0.12}) =>
    Color.alphaBlend(scheme.primary.withValues(alpha: alpha),
        base ?? scheme.surfaceContainerHigh);

/// День для заголовков блоков: год пишется, только если не этот.
String _blockDate(DateTime d) =>
    d.year == DateTime.now().year ? dayMonthLong(d) : longDate(d);

/// Блок «Начат» наверху карточки фильма: когда начал и на какой минуте
/// остановился. Тап открывает окно этой попытки.
class PausedBlock extends StatelessWidget {
  final Viewing viewing;
  final int? runtimeMin;
  final VoidCallback onTap;
  const PausedBlock({
    super.key,
    required this.viewing,
    required this.runtimeMin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = viewing.startedAt ?? viewing.date;
    final rt = runtimeMin;
    final knownRt = rt != null && rt > 0 && rt <= 600;
    final at = viewing.pause?.atMin;
    return _AttemptBlock(
      color: scheme.primary,
      onColor: scheme.onPrimary,
      background: pauseTint(scheme),
      track: pauseTint(scheme, base: scheme.surfaceContainerHighest, alpha: 0.2),
      icon: Icons.pause_circle_rounded,
      title: d == null
          ? tr('pause_chip')
          : trf('pause_on', {'date': _blockDate(d)}),
      sub: at == null
          ? null
          : (knownRt
              ? trf('pause_at_of', {'n': at, 'm': rt})
              : trf('pause_at', {'n': at})),
      fraction: at != null && knownRt ? at / rt : null,
      onTap: onTap,
    );
  }
}

/// Блок «Брошен» наверху карточки фильма: когда, на какой минуте и почему.
/// Тап открывает окно этой попытки.
class DroppedBlock extends StatelessWidget {
  final Viewing viewing;
  final int? runtimeMin;
  final VoidCallback onTap;
  const DroppedBlock({
    super.key,
    required this.viewing,
    required this.runtimeMin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final drop = viewing.drop ?? DropMark();
    final d = viewing.date;
    final rt = runtimeMin;
    final knownRt = rt != null && rt > 0 && rt <= 600;
    final at = drop.atMin;
    return _AttemptBlock(
      color: kDroppedColor,
      onColor: Colors.white,
      background: dropTint(scheme),
      track: dropTint(scheme,
          base: scheme.surfaceContainerHighest, alpha: 0.2),
      icon: Icons.heart_broken_rounded,
      title: d == null
          ? tr('dropped_plain')
          : trf('drop_on', {'date': _blockDate(d)}),
      sub: at == null
          ? null
          : (knownRt
              ? trf('drop_at_of', {'n': at, 'm': rt})
              : trf('drop_at', {'n': at})),
      fraction: at != null && knownRt ? at / rt : null,
      reasons: drop.reasons,
      onTap: onTap,
    );
  }
}

/// Общий вид блоков «Начат» и «Брошен»: значок в круге, заголовок с
/// минутой, полоса пройденного и причины.
class _AttemptBlock extends StatelessWidget {
  final Color color;
  final Color onColor;
  final Color background;
  final Color track;
  final IconData icon;
  final String title;
  final String? sub;
  final double? fraction;
  final List<String> reasons;
  final VoidCallback onTap;
  const _AttemptBlock({
    required this.color,
    required this.onColor,
    required this.background,
    required this.track,
    required this.icon,
    required this.title,
    required this.sub,
    required this.fraction,
    required this.onTap,
    this.reasons = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 12,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, size: 22, color: onColor),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 3,
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                height: 1.15,
                                color: scheme.onSurface)),
                        if (sub != null)
                          Text(sub!,
                              style: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 22, color: scheme.onSurfaceVariant),
                ],
              ),
              if (fraction != null)
                Container(
                  height: 6,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: track,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: fraction!.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              if (reasons.isNotEmpty) DropReasonPills(reasons),
            ],
          ),
        ),
      ),
    );
  }
}
