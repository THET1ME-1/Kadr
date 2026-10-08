import 'package:flutter/material.dart';

import '../models/library_entry.dart';
import '../theme/app_theme.dart';
import '../utils/series_finale.dart';

/// Компактная «пилюля» прогресса сериала для угла постера: кольцо-прогресс +
/// «12/24». Если общее число серий неизвестно — показывает только счётчик серий.
/// Досмотренный сериал вместо кольца получает зелёный флажок, догнанный —
/// стрелки и счёт вышедших серий.
class SeriesProgressPill extends StatelessWidget {
  final int seen;
  final int? total;
  final SeriesRun run;
  const SeriesProgressPill({
    super.key,
    required this.seen,
    this.total,
    this.run = SeriesRun.watching,
  });

  @override
  Widget build(BuildContext context) {
    final has = total != null && total! > 0;
    final progress = has ? (seen / total!).clamp(0.0, 1.0) : null;
    final done = has && seen >= total!;
    const green = Color(0xFF3DDC84);
    final Widget lead = switch (run) {
      SeriesRun.finished =>
        const Icon(Icons.flag_rounded, size: 14, color: green),
      SeriesRun.caughtUp =>
        const Icon(Icons.update_rounded, size: 14, color: Colors.white),
      SeriesRun.watching => has
          ? CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.6,
              backgroundColor: Colors.white.withValues(alpha: 0.28),
              valueColor: AlwaysStoppedAnimation(done ? green : Colors.white),
            )
          : const Icon(Icons.live_tv_rounded, size: 13, color: Colors.white),
    };
    final label = run == SeriesRun.finished || !has ? '$seen' : '$seen/$total';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: lead),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Таблетка статуса в шапке экрана сериала: «Досмотрел 7 октября 2026» или
/// «Догнал · ждём 4-й сезон». Пока сериал смотрят, не рисуется.
class SeriesStatusPill extends StatelessWidget {
  final LibrarySeries series;
  const SeriesStatusPill({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final text = statusPill(series);
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final finale = seriesRun(series) == SeriesRun.finished;
    final bg = finale ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = finale ? scheme.onPrimaryContainer : scheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 12, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            finale ? Icons.flag_rounded : Icons.update_rounded,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
