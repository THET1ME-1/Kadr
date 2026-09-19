import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/social.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../widgets/poster.dart';
import '../../widgets/review/verdict_badge.dart';
import 'review_screen.dart';
import 'review_target.dart';

/// Строка рецензии в списках: постер, заголовок рецензии, название картины,
/// вердикт и оценка. Тап открывает рецензию.
class ReviewListTile extends StatelessWidget {
  final ReviewTarget target;
  final SocialUser? author;
  final BorderRadius radius;

  const ReviewListTile({
    super.key,
    required this.target,
    this.author,
    this.radius = const BorderRadius.all(Radius.circular(20)),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = target.meta;
    final title = meta?.title?.trim();
    final score = target.score;
    final date = meta?.shownDate;
    final sub = [
      '${target.title}${target.year != null ? ' · ${target.year}' : ''}',
      if (date != null) dayMonth(date),
    ].join(' · ');
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openReview(context, target, author: author),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            spacing: 12,
            children: [
              Poster(
                  title: target.title,
                  url: target.poster,
                  width: 48,
                  radius: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 6,
                  children: [
                    Text(
                        title == null || title.isEmpty
                            ? tr('rv_untitled')
                            : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.25,
                            color: scheme.onSurface)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 12,
                            color: scheme.onSurfaceVariant)),
                    if (meta?.verdict != null)
                      VerdictBadge(meta!.verdict!, small: true),
                  ],
                ),
              ),
              if (score != null)
                Text(score.toStringAsFixed(1),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: scoreColor(score))),
            ],
          ),
        ),
      ),
    );
  }
}
