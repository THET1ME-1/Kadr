import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/review.dart';
import '../../theme/app_theme.dart';
import '../../utils/score.dart';

/// Четыре тона вердикта по ролям M3: заливка значка, текст на ней,
/// контейнер-таблетка и текст на контейнере.
class VerdictTone {
  final Color color, onColor, container, onContainer;
  const VerdictTone(this.color, this.onColor, this.container, this.onContainer);
}

final Map<String, ColorScheme> _seeded = {};

ColorScheme _fromSeed(Color seed, Brightness b) =>
    _seeded.putIfAbsent('${seed.toARGB32()}:${b.name}', () {
      return ColorScheme.fromSeed(
        seedColor: seed,
        brightness: b,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );
    });

/// «Обязательно», «Стоит времени» и «На любителя» берут роли темы, поэтому
/// перекрашиваются вместе с выбранным цветом приложения. «Шедевр» и «Мимо»
/// держат свои оттенки (золото оценки и приглушённый красный «Брошено»),
/// а тональные роли для них строятся из этих оттенков тем же способом.
VerdictTone verdictTone(Verdict v, ColorScheme scheme) {
  VerdictTone of(ColorScheme s) => VerdictTone(
      s.primary, s.onPrimary, s.primaryContainer, s.onPrimaryContainer);
  return switch (v) {
    Verdict.masterpiece => of(_fromSeed(scoreColor(10), scheme.brightness)),
    Verdict.must => of(scheme),
    Verdict.worth => VerdictTone(scheme.tertiary, scheme.onTertiary,
        scheme.tertiaryContainer, scheme.onTertiaryContainer),
    Verdict.niche => VerdictTone(scheme.secondary, scheme.onSecondary,
        scheme.secondaryContainer, scheme.onSecondaryContainer),
    Verdict.miss => of(_fromSeed(kDroppedColor, scheme.brightness)),
  };
}

IconData verdictIcon(Verdict v) => switch (v) {
      Verdict.masterpiece => Icons.emoji_events_rounded,
      Verdict.must => Icons.verified_rounded,
      Verdict.worth => Icons.thumb_up_alt_rounded,
      Verdict.niche => Icons.balance_rounded,
      Verdict.miss => Icons.thumb_down_alt_rounded,
    };

String verdictLabel(Verdict v) => tr('verdict_${v.name}');

/// Значок вердикта: тональная таблетка, слева форма «печенье» из M3
/// Expressive со значком. Заменил штамп-печать макета.
class VerdictBadge extends StatelessWidget {
  final Verdict verdict;

  /// Компактный вариант для ленты и превью.
  final bool small;

  const VerdictBadge(this.verdict, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) {
    final tone = verdictTone(verdict, Theme.of(context).colorScheme);
    final cookie = small ? 24.0 : 30.0;
    return Semantics(
      label: verdictLabel(verdict),
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(small ? 4 : 5, small ? 4 : 5,
            small ? 12 : 16, small ? 4 : 5),
        decoration:
            ShapeDecoration(shape: const StadiumBorder(), color: tone.container),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CookieIcon(
                icon: verdictIcon(verdict),
                size: cookie,
                color: tone.color,
                iconColor: tone.onColor),
            SizedBox(width: small ? 6 : 8),
            Flexible(
              child: Text(
                verdictLabel(verdict),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: small ? 11.5 : 13,
                  color: tone.onContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Значок в форме «печенья» (девять мягких зубцов, форма M3 Expressive).
class CookieIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final Color iconColor;

  const CookieIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipPath(
        clipper: const CookieClipper(),
        child: ColoredBox(
          color: color,
          child: Icon(icon, size: size * 0.56, color: iconColor),
        ),
      ),
    );
  }
}

/// Контур «печенья»: окружность с девятью мягкими волнами по краю.
class CookieClipper extends CustomClipper<Path> {
  final int lobes;
  final double depth;
  const CookieClipper({this.lobes = 9, this.depth = 0.075});

  @override
  Path getClip(Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path();
    const steps = 180;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      final rr = r * (1 - depth + depth * math.cos(lobes * t));
      final p = c + Offset(math.cos(t - math.pi / 2), math.sin(t - math.pi / 2)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldReclip(CookieClipper old) =>
      old.lobes != lobes || old.depth != depth;
}
