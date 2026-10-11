import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/review.dart';
import '../../theme/app_theme.dart';
import '../../utils/score.dart';
import '../dashed_box.dart';
import '../viewing/view_chip.dart';
import 'verdict_badge.dart';

/// Части блока «Мои рецензии», общие для фильма и сериала: шапка, строка
/// рецензии, короткая строка прошлой рецензии, свёрнутая строка и строка
/// выбора просмотра в листах.

TextStyle _score(Color c, [double size = 16]) => TextStyle(
    fontFamily: AppTheme.displayFont,
    fontWeight: FontWeight.w800,
    fontSize: size,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: c);

/// Шапка блока: «Мои рецензии · N», шеврон сворачивания и «Написать».
class ReviewsHeader extends StatelessWidget {
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  /// null прячет «Написать»: писать не о чем, на каждый просмотр рецензия
  /// уже есть.
  final VoidCallback? onWrite;

  const ReviewsHeader({
    super.key,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    required this.onWrite,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(trf('rvs_my_reviews', {'n': count}),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: scheme.primary)),
            ),
          ),
        ),
        IconButton(
          onPressed: onToggle,
          tooltip: tr(collapsed ? 'rvs_expand' : 'rvs_collapse'),
          icon: AnimatedRotation(
            turns: collapsed ? 0 : 0.5,
            duration: const Duration(milliseconds: 200),
            curve: AppTheme.emphasized,
            child: Icon(Icons.expand_more_rounded,
                color: scheme.onSurfaceVariant),
          ),
        ),
        if (onWrite != null)
          TextButton.icon(
            onPressed: onWrite,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr('rvs_write')),
          ),
      ],
    );
  }
}

/// Таблетка охвата рецензии на сериал: «S2–S3» на тоне secondary, «Весь
/// сериал» нейтральная.
class ScopeChip extends StatelessWidget {
  final String label;
  final bool whole;
  const ScopeChip(this.label, {super.key, this.whole = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            whole ? scheme.surfaceContainerHighest : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: whole ? scheme.onSurface : scheme.onSecondaryContainer)),
    );
  }
}

/// Строка рецензии: таблетки (охват, просмотр), вердикт, заголовок, подпись
/// и оценка справа.
class ReviewRowTile extends StatelessWidget {
  final List<Widget> chips;
  final Verdict? verdict;
  final String title;
  final String sub;
  final double? score;
  final BorderRadius radius;
  final VoidCallback onTap;

  const ReviewRowTile({
    super.key,
    required this.chips,
    required this.verdict,
    required this.title,
    required this.sub,
    required this.score,
    required this.radius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = score;
    final top = [
      ...chips,
      if (verdict != null) VerdictBadge(verdict!, small: true),
    ];
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    if (top.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: top,
                      ),
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.25,
                            color: scheme.onSurface)),
                    if (sub.isNotEmpty)
                      Text(sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 12,
                              color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Text(s != null ? s.toStringAsFixed(1) : '—',
                  style: _score(
                      s != null ? scoreColor(s) : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Прошлая рецензия короткой строкой под новой: номер просмотра, заголовок
/// в одну строку и оценка.
class ReviewPrevTile extends StatelessWidget {
  final Widget chip;
  final String title;
  final double? score;
  final BorderRadius radius;
  final VoidCallback onTap;

  const ReviewPrevTile({
    super.key,
    required this.chip,
    required this.title,
    required this.score,
    required this.radius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = score;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            spacing: 8,
            children: [
              chip,
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: scheme.onSurfaceVariant)),
              ),
              Text(s != null ? s.toStringAsFixed(1) : '—',
                  style: _score(
                      s != null ? scoreColor(s) : scheme.onSurfaceVariant,
                      13.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Свёрнутый блок: таблетка и оценка каждой рецензии в строку, в конце
/// итог («Свод 9.4», «Разница -0.8»). Тап разворачивает.
class ReviewsFolded extends StatelessWidget {
  final List<({Widget chip, double? score})> items;
  final String? total;
  final VoidCallback onOpen;

  const ReviewsFolded({
    super.key,
    required this.items,
    required this.total,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          // Пары и итог одним переносом: отдельной колонкой итог отнимал
          // место, и «Весь сериал 9.0» вылезал.
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final it in items)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 5,
                  children: [
                    it.chip,
                    Text(it.score?.toStringAsFixed(1) ?? '—',
                        style: _score(
                            it.score != null
                                ? scoreColor(it.score!)
                                : scheme.onSurfaceVariant,
                            13)),
                  ],
                ),
              if (total != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(total!,
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: scheme.onPrimaryContainer)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка выбора просмотра в листах «О каком просмотре» и «О чём рецензия».
/// Выбранная залита и с галочкой; просмотр, на который рецензия уже есть,
/// обведён пунктиром и не нажимается.
class ViewChoiceRow extends StatelessWidget {
  final int ordinal;
  final String title;
  final String? sub;
  final bool selected;
  final bool taken;
  final BorderRadius radius;
  final VoidCallback? onTap;

  const ViewChoiceRow({
    super.key,
    required this.ordinal,
    required this.title,
    required this.radius,
    this.sub,
    this.selected = false,
    this.taken = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = taken
        ? scheme.onSurfaceVariant
        : (selected ? scheme.onPrimaryContainer : scheme.onSurface);
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      child: Row(
        spacing: 12,
        children: [
          ViewOrdinal(ordinal, latest: selected, dim: taken),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(title,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: fg)),
                if (sub != null && sub!.isNotEmpty)
                  Text(sub!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: selected
                              ? fg.withValues(alpha: 0.85)
                              : scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (selected) Icon(Icons.check_rounded, size: 20, color: fg),
        ],
      ),
    );
    if (taken) {
      return Semantics(
        enabled: false,
        child: DashedBox(radius: radius, child: body),
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color:
            selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

/// Пара плиток «было / стало»: левая нейтральная, правая выделена.
class BeforeAfterTiles extends StatelessWidget {
  final String beforeLabel;
  final double? before;
  final String afterLabel;
  final double? after;

  /// Плитки стоят вплотную, с общим скруглением (страница рецензии); иначе
  /// отдельными блоками с зазором (свод сериала).
  final bool joined;

  const BeforeAfterTiles({
    super.key,
    required this.beforeLabel,
    required this.before,
    required this.afterLabel,
    required this.after,
    this.joined = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tile(String label, double? v, {required bool on, required BorderRadius r}) {
      final bg = joined
          ? scheme.surfaceContainerHighest
          : (on ? scheme.primaryContainer : scheme.surfaceContainer);
      final labelColor = joined
          ? scheme.onSurfaceVariant
          : (on ? scheme.onPrimaryContainer : scheme.onSurface)
              .withValues(alpha: 0.85);
      final Color valueColor;
      if (v == null) {
        valueColor = scheme.onSurfaceVariant;
      } else if (joined) {
        valueColor = on ? scheme.primary : scoreColor(v);
      } else {
        valueColor = on ? scheme.onPrimaryContainer : scoreColor(v);
      }
      return Expanded(
        child: Container(
          padding: joined
              ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
              : const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(color: bg, borderRadius: r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: joined ? 2 : 6,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: joined ? FontWeight.w400 : FontWeight.w600,
                      fontSize: 12,
                      color: labelColor)),
              Text(v != null ? v.toStringAsFixed(1) : '—',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      height: joined ? null : 1,
                      color: valueColor)),
            ],
          ),
        ),
      );
    }

    const big = Radius.circular(20), small = Radius.circular(8);
    return Row(
      spacing: joined ? 4 : 10,
      children: [
        tile(beforeLabel, before,
            on: false,
            r: joined
                ? const BorderRadius.horizontal(left: big, right: small)
                : BorderRadius.circular(20)),
        tile(afterLabel, after,
            on: true,
            r: joined
                ? const BorderRadius.horizontal(left: small, right: big)
                : BorderRadius.circular(20)),
      ],
    );
  }
}
