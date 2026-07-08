import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../models/social.dart';
import '../services/movie_repository.dart';
import '../services/social/social_controller.dart';
import '../theme/app_theme.dart';
import 'social/friend_pick_sheet.dart';

/// Панель «Когда вы посмотрели?» в стиле Kadr (M3 Expressive). Отмечает
/// просмотр; если фильм уже смотрели — автоматически повторный просмотр.
/// Есть опция «Посмотрел с другом» — просмотр засчитывается и другу.
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

class _WhenWatchedSheet extends StatefulWidget {
  final LibraryMovie movie;
  const _WhenWatchedSheet({required this.movie});

  @override
  State<_WhenWatchedSheet> createState() => _WhenWatchedSheetState();
}

class _WhenWatchedSheetState extends State<_WhenWatchedSheet> {
  List<SocialUser>? _with; // с кем смотрели (co-watch)

  bool get _hasFriends =>
      SocialController.instance.friends.friends.isNotEmpty;

  Future<void> _log(BuildContext context, DateTime? date) async {
    final messenger = ScaffoldMessenger.of(context);
    final withFriends = _with;
    HapticFeedback.mediumImpact(); // тактильный отклик на отметку просмотра
    Navigator.pop(context);
    final wasRewatch =
        await MovieRepository.instance.addViewing(widget.movie.uuid, date);
    if (withFriends != null && withFriends.isNotEmpty) {
      for (final f in withFriends) {
        try {
          await SocialController.instance.sendMovieCoWatch(
            toUserId: f.id,
            title: widget.movie.displayTitle,
            origTitle: widget.movie.title,
            year: widget.movie.year,
            tmdbId: widget.movie.tmdbId,
            posterUrl: widget.movie.posterUrl,
            watchedAt: date,
          );
        } catch (_) {/* пропускаем этого друга */}
      }
      messenger.showSnackBar(SnackBar(
        content: Text(trf('cowatch_marked', {'n': withFriends.length})),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(tr(wasRewatch ? 'rewatch_added' : 'viewing_added')),
        behavior: SnackBarBehavior.floating,
      ));
    }
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

  Future<void> _pickFriends() async {
    final picked = await pickCoWatchFriends(context);
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => _with = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final withFriends = _with;
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
          if (withFriends != null)
            _coWatchBanner(scheme, withFriends)
          else if (widget.movie.isRewatched ||
              widget.movie.status == LibraryStatus.watched)
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
          // «Посмотрел с другом» — только пока друг не выбран и друзья есть.
          if (withFriends == null && _hasFriends) ...[
            Divider(
                height: 18,
                indent: 24,
                endIndent: 24,
                color: scheme.outlineVariant),
            _tile(context, Icons.group_rounded, tr('cowatch_with_friend'),
                _pickFriends,
                accent: true),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Плашка «С: имена» + «Изменить» (когда выбран совместный просмотр).
  Widget _coWatchBanner(ColorScheme scheme, List<SocialUser> friends) {
    final names = friends.map((f) => f.displayName).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(Icons.group_rounded, size: 20, color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(trf('cowatch_with', {'names': names}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: scheme.onPrimaryContainer)),
            ),
            TextButton(
              onPressed: _pickFriends,
              child: Text(tr('cowatch_change')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
      BuildContext context, IconData icon, String label, VoidCallback onTap,
      {bool accent = false}) {
    final scheme = Theme.of(context).colorScheme;
    final bg = accent ? scheme.tertiaryContainer : scheme.primaryContainer;
    final fg = accent ? scheme.onTertiaryContainer : scheme.onPrimaryContainer;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: fg, size: 24),
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
