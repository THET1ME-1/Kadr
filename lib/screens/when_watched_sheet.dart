import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';

/// Панель «Когда вы посмотрели?» в стиле Kadr (M3 Expressive). Отмечает
/// просмотр; если фильм уже смотрели — автоматически повторный просмотр.
Future<void> showWhenWatchedSheet(BuildContext context, LibraryMovie movie) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _WhenWatchedSheet(movie: movie),
  );
}

class _WhenWatchedSheet extends StatelessWidget {
  final LibraryMovie movie;
  const _WhenWatchedSheet({required this.movie});

  Future<void> _log(BuildContext context, DateTime? date) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    final wasRewatch =
        await MovieRepository.instance.addViewing(movie.uuid, date);
    messenger.showSnackBar(SnackBar(
      content: Text(tr(wasRewatch ? 'rewatch_added' : 'viewing_added')),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    final dt = time == null
        ? DateTime(date.year, date.month, date.day)
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (context.mounted) await _log(context, dt);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('when_watched_q'),
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          if (movie.isRewatched ||
              movie.status == LibraryStatus.watched)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('rewatch_full'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          _tile(context, Icons.help_outline_rounded, tr('when_unknown'),
              () => _log(context, null)),
          _tile(context, Icons.flag_rounded, tr('when_just_finished'),
              () => _log(context, now)),
          _tile(context, Icons.today_rounded, tr('when_today'),
              () => _log(context, now)),
          _tile(context, Icons.history_rounded, tr('when_yesterday'),
              () => _log(context, now.subtract(const Duration(days: 1)))),
          _tile(context, Icons.event_rounded, tr('when_pick_date'),
              () => _pickDate(context)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _tile(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, color: scheme.onPrimaryContainer, size: 24),
            ),
            const SizedBox(width: 16),
            Text(label,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}
