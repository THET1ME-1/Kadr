import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/social.dart';
import '../../services/social/social_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';

/// Мульти-выбор друзей для «Посмотрел с другом». Возвращает выбранных (или null,
/// если отменили / друзей нет).
Future<List<SocialUser>?> pickCoWatchFriends(BuildContext context) {
  final friends =
      SocialController.instance.friends.friends.map((f) => f.user).toList();
  if (friends.isEmpty) return Future.value(null);
  return showModalBottomSheet<List<SocialUser>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _FriendPickSheet(friends: friends),
  );
}

class _FriendPickSheet extends StatefulWidget {
  final List<SocialUser> friends;
  const _FriendPickSheet({required this.friends});

  @override
  State<_FriendPickSheet> createState() => _FriendPickSheetState();
}

class _FriendPickSheetState extends State<_FriendPickSheet> {
  final Set<String> _sel = {};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('cowatch_pick_title'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: scheme.primary)),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.friends.length,
              itemBuilder: (context, i) {
                final u = widget.friends[i];
                final on = _sel.contains(u.id);
                return CheckboxListTile(
                  value: on,
                  onChanged: (_) => setState(() {
                    if (on) {
                      _sel.remove(u.id);
                    } else {
                      _sel.add(u.id);
                    }
                  }),
                  secondary: UserAvatar(user: u, size: 44),
                  title: Text(u.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600)),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sel.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        widget.friends
                            .where((u) => _sel.contains(u.id))
                            .toList()),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(tr('save'),
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
