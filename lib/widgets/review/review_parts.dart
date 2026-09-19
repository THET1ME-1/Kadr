import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/review.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/review_markdown.dart';
import '../../utils/score.dart';
import 'verdict_badge.dart';

/// Цвет автора чужой рецензии в сравнении «Вы и друг»: золото оценки, чтобы
/// не спорить с `primary`, которым рисуется своё.
Color authorCompareColor() => scoreColor(9.2);

String critLabel(String id) => tr('crit_$id');

/// Пункты в каноническом порядке: сначала известные, потом незнакомые (от
/// более новой версии приложения друга).
List<String> orderedCriteria(Iterable<String> ids) {
  final set = ids.toSet();
  return [
    for (final id in kCriteria)
      if (set.contains(id)) id,
    for (final id in set)
      if (!kCriteria.contains(id)) id,
  ];
}

TextStyle _capsLabel(Color c) => TextStyle(
    fontFamily: AppTheme.bodyFont,
    fontWeight: FontWeight.w700,
    fontSize: 12,
    letterSpacing: 1.1,
    color: c);

/// Подпись раздела капсом, как в настройках.
class ReviewCaps extends StatelessWidget {
  final String text;
  final Color? color;
  const ReviewCaps(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: _capsLabel(
          color ?? Theme.of(context).colorScheme.onSurfaceVariant));
}

/// Полоса одной оценки 1–10.
class ScoreBar extends StatelessWidget {
  final double? value;
  final Color color;
  final double height;
  const ScoreBar(
      {super.key, required this.value, required this.color, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    final f = ((value ?? 0) / 10).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(double? v) => v == null ? '—' : v.toStringAsFixed(1);

TextStyle _num(Color c, [double size = 14]) => TextStyle(
    fontFamily: AppTheme.displayFont,
    fontWeight: FontWeight.w800,
    fontSize: size,
    color: c,
    fontFeatures: const [FontFeature.tabularFigures()]);

/// Оценки по пунктам полосами. С [other] рисует пары «автор / я».
class CriteriaBars extends StatelessWidget {
  final Map<String, double> criteria;
  final Map<String, double>? other;
  const CriteriaBars({super.key, required this.criteria, this.other});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final o = other;
    final ids = orderedCriteria({...criteria.keys, ...?o?.keys});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        for (final id in ids)
          Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(critLabel(id),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13.5,
                        height: 1.2,
                        color: scheme.onSurface)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: o == null
                    ? ScoreBar(
                        value: criteria[id],
                        color: scoreColor(criteria[id] ?? 1))
                    : Column(
                        spacing: 4,
                        children: [
                          ScoreBar(
                              value: criteria[id],
                              color: authorCompareColor(),
                              height: 6),
                          ScoreBar(
                              value: o[id], color: scheme.primary, height: 6),
                        ],
                      ),
              ),
              const SizedBox(width: 10),
              if (o == null)
                SizedBox(
                  width: 34,
                  child: Text(_fmt(criteria[id]),
                      textAlign: TextAlign.right,
                      style: _num(scoreColor(criteria[id] ?? 1))),
                )
              else
                SizedBox(
                  width: 68,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: _fmt(criteria[id]),
                          style: _num(authorCompareColor(), 12.5)),
                      const TextSpan(text: '  '),
                      TextSpan(
                          text: _fmt(o[id]),
                          style: _num(scheme.primary, 12.5)),
                    ]),
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Сильное и слабое двумя соединёнными блоками (как группы настроек).
class ProsConsBlock extends StatelessWidget {
  final List<String> pros;
  final List<String> cons;
  const ProsConsBlock({super.key, required this.pros, required this.cons});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bad = verdictTone(Verdict.miss, scheme);
    final both = pros.isNotEmpty && cons.isNotEmpty;
    Widget block(String title, List<String> items, IconData icon, Color accent,
        BorderRadius r) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh, borderRadius: r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            ReviewCaps(title, color: accent),
            for (final t in items)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  Expanded(
                    child: Text(t,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 14,
                            height: 1.35,
                            color: scheme.onSurface)),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    const big = Radius.circular(20), small = Radius.circular(8);
    final left = both
        ? const BorderRadius.horizontal(left: big, right: small)
        : BorderRadius.circular(20);
    final right = both
        ? const BorderRadius.horizontal(left: small, right: big)
        : BorderRadius.circular(20);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          if (pros.isNotEmpty)
            Expanded(
                child: block(tr('rv_pros'), pros, Icons.add_rounded,
                    scheme.primary, left)),
          if (cons.isNotEmpty)
            Expanded(
                child: block(tr('rv_cons'), cons, Icons.remove_rounded,
                    bad.color, right)),
        ],
      ),
    );
  }
}

/// Круг с оценкой — рядом с автором рецензии.
class ReviewScoreCircle extends StatelessWidget {
  final double score;
  final double size;
  const ReviewScoreCircle(this.score, {super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: scoreColor(score), shape: BoxShape.circle),
      child: Text(score.toStringAsFixed(1),
          style: _num(onScoreColor(score), size * 0.32)),
    );
  }
}

/// Где рецензия видна: черновик, только я, друзья.
({IconData icon, String label}) reviewStatus(ReviewMeta? meta) {
  if (meta == null || !meta.shared) {
    return (icon: Icons.lock_rounded, label: tr('rv_status_private'));
  }
  if (meta.draft) {
    return (icon: Icons.edit_note_rounded, label: tr('rv_status_draft'));
  }
  return (icon: Icons.group_rounded, label: tr('rv_status_friends'));
}

/// Карточка рецензии в экране фильма/сериала и превью перед публикацией:
/// вердикт, заголовок, начало текста, пункты, сильное и слабое.
class ReviewPreviewCard extends StatelessWidget {
  final String? text;
  final ReviewMeta? meta;
  final VoidCallback? onOpen;

  /// Показывать строку «Читать целиком» и статус видимости.
  final bool showFooter;

  /// Статус видимости («Видят друзья») — только у своей рецензии.
  final bool showStatus;

  /// Чужая рецензия: если автор пометил спойлеры, начало текста не
  /// показываем, как и на экране чтения.
  final bool guardSpoilers;

  /// Подпись кнопки; по умолчанию «Читать целиком».
  final String? openLabel;

  const ReviewPreviewCard({
    super.key,
    required this.text,
    required this.meta,
    this.onOpen,
    this.showFooter = true,
    this.showStatus = true,
    this.guardSpoilers = false,
    this.openLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = meta;
    final gated = guardSpoilers && (m?.spoilers ?? false);
    final body = text == null || gated
        ? ''
        : reviewPlainText(text!, spoilerMask: tr('rv_spoiler_mask'));
    final date = m?.shownDate;
    final status = reviewStatus(m);
    final title = m?.title?.trim();
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              if (m?.verdict != null || date != null)
                Row(
                  spacing: 12,
                  children: [
                    if (m?.verdict != null)
                      Flexible(child: VerdictBadge(m!.verdict!, small: true)),
                    if (date != null)
                      Expanded(
                        child: Text(longDate(date),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              if (title != null && title.isNotEmpty)
                Text(title,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        height: 1.2,
                        color: scheme.onSurface)),
              if (m != null && m.criteria.isNotEmpty) _miniCriteria(context, m),
              if (m != null && (m.pros.isNotEmpty || m.cons.isNotEmpty))
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in m.pros.take(3))
                      _tag(context, p, positive: true),
                    for (final c in m.cons.take(2))
                      _tag(context, c, positive: false),
                  ],
                ),
              if (gated && (text?.trim().isNotEmpty ?? false))
                Row(
                  spacing: 8,
                  children: [
                    Icon(Icons.visibility_off_rounded,
                        size: 18, color: scheme.error),
                    Expanded(
                      child: Text(tr('rv_gate_title'),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 14,
                              color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              if (body.isNotEmpty)
                Text(body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 14.5,
                        height: 1.5,
                        color: scheme.onSurface)),
              if (showFooter)
                Row(
                  children: [
                    if (onOpen != null)
                      FilledButton.tonal(
                          onPressed: onOpen,
                          child: Text(openLabel ?? tr('rv_read_full'))),
                    const SizedBox(width: 12),
                    if (showStatus)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        spacing: 6,
                        children: [
                          Icon(status.icon,
                              size: 16, color: scheme.onSurfaceVariant),
                          Flexible(
                            child: Text(status.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: AppTheme.bodyFont,
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniCriteria(BuildContext context, ReviewMeta m) {
    final scheme = Theme.of(context).colorScheme;
    final ids = orderedCriteria(m.criteria.keys);
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 20) / 2;
      return Wrap(
        spacing: 20,
        runSpacing: 12,
        children: [
          for (final id in ids)
            SizedBox(
              width: w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(critLabel(id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 13,
                                color: scheme.onSurfaceVariant)),
                      ),
                      Text(_fmt(m.criteria[id]),
                          style: _num(scoreColor(m.criteria[id]!), 13)),
                    ],
                  ),
                  ScoreBar(
                      value: m.criteria[id],
                      color: scoreColor(m.criteria[id]!),
                      height: 6),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _tag(BuildContext context, String t, {required bool positive}) {
    final scheme = Theme.of(context).colorScheme;
    final bad = verdictTone(Verdict.miss, scheme);
    final bg = positive ? scheme.primaryContainer : bad.container;
    final fg = positive ? scheme.onPrimaryContainer : bad.onContainer;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
      decoration: ShapeDecoration(shape: const StadiumBorder(), color: bg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Icon(positive ? Icons.add_rounded : Icons.remove_rounded,
              size: 16, color: fg),
          Flexible(
            child: Text(t,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w500,
                    fontSize: 12.5,
                    color: fg)),
          ),
        ],
      ),
    );
  }
}
