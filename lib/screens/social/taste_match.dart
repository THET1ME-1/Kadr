import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/movie_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/score.dart';
import '../../widgets/poster.dart';

/// Сравнение вкусов со мной: общие просмотренные фильмы, совпадение оценок и
/// процент совпадения вкуса. Считается на клиенте (моя библиотека ∩ друга).
class TasteMatch extends StatelessWidget {
  final MovieRepository mine;
  final MovieRepository friend;
  const TasteMatch({super.key, required this.mine, required this.friend});

  static String _key(LibraryMovie m) =>
      '${(m.ruTitle ?? m.title).toLowerCase().trim()}|${m.year ?? 0}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Общие просмотренные фильмы (по названию+году — uuid у друга свои).
    final byKey = {for (final m in mine.watched) _key(m): m};
    final common = <(LibraryMovie mineM, LibraryMovie friendM)>[];
    for (final f in friend.watched) {
      final me = byKey[_key(f)];
      if (me != null) common.add((me, f));
    }

    if (common.isEmpty) {
      return _card(
        context,
        child: Row(
          children: [
            Icon(Icons.compare_arrows_rounded,
                color: scheme.onSurfaceVariant, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('taste_none'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13.5,
                      color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      );
    }

    // Совпадение вкуса: по фильмам, где у ОБОИХ есть оценка.
    final rated = [
      for (final c in common)
        if (c.$1.currentScore != null && c.$2.currentScore != null)
          (c.$1.currentScore!, c.$2.currentScore!)
    ];
    int? matchPct;
    if (rated.isNotEmpty) {
      final avgDiff =
          rated.map((p) => (p.$1 - p.$2).abs()).reduce((a, b) => a + b) /
              rated.length;
      matchPct = (100 * (1 - avgDiff / 9)).round().clamp(0, 100);
    }

    // Сортируем: сначала где оба оценили (по близости оценок), потом остальные.
    common.sort((a, b) {
      final ar = a.$1.currentScore != null && a.$2.currentScore != null;
      final br = b.$1.currentScore != null && b.$2.currentScore != null;
      if (ar != br) return ar ? -1 : 1;
      return 0;
    });

    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tr('taste_title'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: scheme.onSurface)),
              const Spacer(),
              if (matchPct != null) _matchBadge(scheme, matchPct),
            ],
          ),
          const SizedBox(height: 4),
          Text(trf('taste_common_n', {'n': common.length}),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          // Легенда колонок оценок: слева — твоя, справа — друга.
          Row(
            children: [
              const Spacer(),
              SizedBox(
                  width: 34,
                  child: Text(tr('taste_you'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant))),
              const SizedBox(width: 6),
              SizedBox(
                  width: 34,
                  child: Text(tr('taste_friend'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant))),
            ],
          ),
          const SizedBox(height: 4),
          for (final c in common.take(15)) _row(context, c.$1, c.$2),
          if (common.length > 15) ...[
            const SizedBox(height: 8),
            Text(trf('taste_and_more', {'n': common.length - 15}),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _matchBadge(ColorScheme scheme, int pct) {
    // Цвет как у оценки: делим процент на 10 → шкала 0..10.
    final c = scoreColor(pct / 10);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_rounded, size: 14, color: onScoreColor(pct / 10)),
          const SizedBox(width: 4),
          Text('$pct%',
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: onScoreColor(pct / 10))),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, LibraryMovie mineM, LibraryMovie friendM) {
    final scheme = Theme.of(context).colorScheme;
    final ms = mineM.currentScore, fs = friendM.currentScore;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Poster(title: mineM.displayTitle, url: mineM.posterUrl, width: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(mineM.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: scheme.onSurface)),
          ),
          const SizedBox(width: 8),
          _scoreDot(scheme, ms, mine: true),
          const SizedBox(width: 6),
          _scoreDot(scheme, fs, mine: false),
        ],
      ),
    );
  }

  Widget _scoreDot(ColorScheme scheme, double? score, {required bool mine}) {
    if (score == null) {
      return Container(
        width: 34,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(9)),
        child: Text('—',
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color: scheme.onSurfaceVariant)),
      );
    }
    final c = scoreColor(score);
    return Container(
      width: 34,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(9)),
      child: Text(score.toStringAsFixed(1),
          style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: onScoreColor(score))),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22)),
      child: child,
    );
  }
}

/// «Посмотреть вместе»: фильмы, которые ОБА добавили в «Буду смотреть».
/// Прячется, если пересечения нет.
class WatchTogether extends StatelessWidget {
  final MovieRepository mine;
  final MovieRepository friend;
  const WatchTogether({super.key, required this.mine, required this.friend});

  static String _key(LibraryMovie m) =>
      '${(m.ruTitle ?? m.title).toLowerCase().trim()}|${m.year ?? 0}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byKey = {for (final m in mine.watchlist) _key(m): m};
    final common = <LibraryMovie>[];
    for (final f in friend.watchlist) {
      final me = byKey[_key(f)];
      if (me != null) common.add(me);
    }
    if (common.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: 18, color: scheme.tertiary),
              const SizedBox(width: 8),
              Text(tr('together_title'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 4),
          Text(trf('together_n', {'n': common.length}),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: common.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final m = common[i];
                return SizedBox(
                  width: 84,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Poster(
                          title: m.displayTitle,
                          url: m.posterUrl,
                          width: 84,
                          radius: 12),
                      const SizedBox(height: 5),
                      Text(m.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              height: 1.1,
                              color: scheme.onSurface)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
