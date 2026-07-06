import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Компактная «пилюля» прогресса сериала для угла постера: кольцо-прогресс +
/// «12/24». Если общее число серий неизвестно — показывает только счётчик серий.
class SeriesProgressPill extends StatelessWidget {
  final int seen;
  final int? total;
  const SeriesProgressPill({super.key, required this.seen, this.total});

  @override
  Widget build(BuildContext context) {
    final has = total != null && total! > 0;
    final progress = has ? (seen / total!).clamp(0.0, 1.0) : null;
    final done = has && seen >= total!;
    const green = Color(0xFF3DDC84);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: has
                ? CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2.6,
                    backgroundColor: Colors.white.withValues(alpha: 0.28),
                    valueColor: AlwaysStoppedAnimation(
                        done ? green : Colors.white),
                  )
                : const Icon(Icons.live_tv_rounded, size: 13, color: Colors.white),
          ),
          const SizedBox(width: 5),
          Text(
            has ? '$seen/$total' : '$seen',
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
