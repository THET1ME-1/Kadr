import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/social.dart';
import '../../services/social/social_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/score.dart';
import '../../widgets/viewing/view_chip.dart';
import '../social/friend_pick_sheet.dart';

/// Ответ окна отметки.
class MarkChoice {
  /// Когда посмотрели; null — «не помню» (в ленту такой просмотр не попадёт).
  final DateTime? date;

  /// С кем смотрели: им уйдёт совместный просмотр. Пусто, если не выбирали.
  final List<SocialUser> friends;

  /// Нажата красная кнопка под ответами (например «Снять все просмотры
  /// сезона»); дата тогда пустая и ничего не значит.
  final bool danger;

  const MarkChoice({this.date, this.friends = const [], this.danger = false});
}

/// Окно «Отметить просмотр»: одно на фильм, серию, сезон и пересмотр.
///
/// Частый ответ «Только что» стоит крупной кнопкой, «Вчера», «Дата и время»
/// и «Не помню» плитками в ряд. [ordinal] — номер будущего просмотра: со
/// второго он показан таблеткой перед [subject]. [coWatch] добавляет
/// «Посмотрел с другом», [dangerLabel] — красную кнопку внизу.
Future<MarkChoice?> showMarkSheet(
  BuildContext context, {
  required String title,
  required String subject,
  int? ordinal,
  bool coWatch = false,
  String? dangerLabel,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<MarkChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _MarkSheet(
      title: title,
      subject: subject,
      ordinal: ordinal,
      coWatch: coWatch,
      dangerLabel: dangerLabel,
    ),
  );
}

class _MarkSheet extends StatefulWidget {
  final String title;
  final String subject;
  final int? ordinal;
  final bool coWatch;
  final String? dangerLabel;
  const _MarkSheet({
    required this.title,
    required this.subject,
    this.ordinal,
    this.coWatch = false,
    this.dangerLabel,
  });

  @override
  State<_MarkSheet> createState() => _MarkSheetState();
}

class _MarkSheetState extends State<_MarkSheet> {
  List<SocialUser> _with = const [];

  bool get _hasFriends =>
      SocialController.instance.friends.friends.isNotEmpty;

  void _choose(DateTime? date) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(MarkChoice(date: date, friends: _with));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted) return;
    _choose(time == null
        ? DateTime(date.year, date.month, date.day)
        : DateTime(date.year, date.month, date.day, time.hour, time.minute));
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
    final ordinal = widget.ordinal ?? 1;
    final now = DateTime.now();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(widget.title,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      height: 1.15,
                      color: scheme.primary)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (ordinal >= 2) ViewChip(trf('viewing_n', {'n': ordinal})),
                Text(widget.subject,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w500,
                        fontSize: 13.5,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
            _NowButton(onTap: () => _choose(now)),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.history_rounded,
                      label: tr('when_yesterday'),
                      onTap: () =>
                          _choose(now.subtract(const Duration(days: 1))),
                    ),
                  ),
                  Expanded(
                    child: _Tile(
                      icon: Icons.event_rounded,
                      label: tr('date_time'),
                      onTap: _pickDate,
                    ),
                  ),
                  Expanded(
                    child: _Tile(
                      icon: Icons.help_outline_rounded,
                      label: tr('when_forgot'),
                      onTap: () => _choose(null),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.coWatch && _hasFriends)
              _WithFriend(friends: _with, onTap: _pickFriends),
            if (widget.dangerLabel != null)
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop(const MarkChoice(danger: true));
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: kDroppedColor,
                    minimumSize: const Size(0, 40),
                  ),
                  icon: const Icon(Icons.remove_done_rounded, size: 20),
                  label: Text(widget.dangerLabel!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Крупная кнопка «Только что».
class _NowButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NowButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                spacing: 12,
                children: [
                  Icon(Icons.flag_rounded, size: 24, color: scheme.onPrimary),
                  Expanded(
                    child: Text(tr('when_now'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                            color: scheme.onPrimary)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Плитка ответа: значок над подписью.
class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 78),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 6,
                children: [
                  Icon(icon, size: 24, color: scheme.primary),
                  Text(label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.15,
                          color: scheme.onSurface)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «Посмотрел с другом»; после выбора показывает, с кем.
class _WithFriend extends StatelessWidget {
  final List<SocialUser> friends;
  final VoidCallback onTap;
  const _WithFriend({required this.friends, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onTertiaryContainer;
    final picked = friends.isNotEmpty;
    return Semantics(
      button: true,
      child: Material(
        color: scheme.tertiaryContainer,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                spacing: 10,
                children: [
                  Icon(Icons.group_rounded, size: 20, color: fg),
                  Expanded(
                    child: Text(
                        picked
                            ? trf('cowatch_with', {
                                'names': friends
                                    .map((f) => f.displayName)
                                    .join(', '),
                              })
                            : tr('cowatch_with_friend'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            color: fg)),
                  ),
                  if (picked) Icon(Icons.edit_rounded, size: 18, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
