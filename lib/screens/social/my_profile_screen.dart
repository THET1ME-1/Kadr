import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/social.dart';
import '../../services/movie_repository.dart';
import '../../services/social/avatar_util.dart';
import '../../services/social/social_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';
import '../statistics_screen.dart';
import 'auth_screen.dart';
import 'friend_profile_screen.dart';
import 'profile_stats.dart';

/// Свой профиль (4-я вкладка навигации). Не вошёл — приглашение войти; вошёл —
/// аватар/ник/код с правкой, входящие заявки, друзья и своя статистика.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    // Подтянуть свежие заявки/друзей при открытии вкладки.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocialController.instance.refreshFriends();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SocialController.instance,
      builder: (context, _) {
        final ctl = SocialController.instance;
        if (!ctl.isLoggedIn) return _loggedOut(context);
        return _profile(context, ctl.user!, ctl);
      },
    );
  }

  // ------------------------------ не вошёл ------------------------------

  Widget _loggedOut(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.tertiary],
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.group_rounded,
                  color: Colors.white.withValues(alpha: 0.95), size: 40),
              const SizedBox(height: 14),
              Text(tr('profile_join_title'),
                  style: const TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(tr('profile_join_sub'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13.5,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: 0.9))),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuthScreen())),
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15)),
          icon: const Icon(Icons.login_rounded),
          label: Text(tr('profile_login_cta'),
              style: const TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ),
      ],
    );
  }

  // ------------------------------- профиль -------------------------------

  Widget _profile(BuildContext context, SocialUser me, SocialController ctl) {
    return RefreshIndicator(
      onRefresh: () => ctl.refreshFriends(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          _header(context, me),
          if (ctl.friends.incoming.isNotEmpty) ...[
            const SizedBox(height: 24),
            _incomingSection(context, ctl),
          ],
          const SizedBox(height: 24),
          _friendsSection(context, ctl),
          const SizedBox(height: 24),
          Text(tr('drawer_stats'),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 12),
          ProfileStats(
            repo: MovieRepository.instance,
            onHeroTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StatisticsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, SocialUser me) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        GestureDetector(
          onTap: _uploading ? null : _pickAvatar,
          child: Stack(
            children: [
              UserAvatar(user: me, size: 76),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 2),
                  ),
                  child: _uploading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: scheme.onPrimary))
                      : Icon(Icons.photo_camera_rounded,
                          size: 14, color: scheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(me.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            color: scheme.onSurface)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _editName,
                  ),
                ],
              ),
              _codeChip(context, me.friendCode),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _confirmLogout,
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: Text(tr('social_logout')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _codeChip(BuildContext context, String code) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _copyCode(code),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tag_rounded, size: 15, color: scheme.primary),
              const SizedBox(width: 4),
              Text(code,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 1.5,
                      color: scheme.onSurface)),
              const SizedBox(width: 6),
              Text(tr('profile_your_code'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Icon(Icons.copy_rounded, size: 14, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(tr('profile_code_copied')),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  // ------------------------------ заявки ------------------------------

  Widget _incomingSection(BuildContext context, SocialController ctl) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(trf('profile_requests', {'n': ctl.friends.incoming.length}),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: scheme.onSurface)),
        const SizedBox(height: 12),
        for (final f in ctl.friends.incoming) _incomingCard(context, ctl, f),
      ],
    );
  }

  Widget _incomingCard(
      BuildContext context, SocialController ctl, FriendEntry f) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              UserAvatar(user: f.user, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Text(f.user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: scheme.onSurface)),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.check_rounded),
                onPressed: () => ctl.respond(f.user.id, accept: true),
                tooltip: tr('accept'),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => ctl.respond(f.user.id, accept: false),
                tooltip: tr('decline'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------ друзья ------------------------------

  Widget _friendsSection(BuildContext context, SocialController ctl) {
    final scheme = Theme.of(context).colorScheme;
    final friends = ctl.friends.friends;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(trf('profile_friends_n', {'n': friends.length}),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: scheme.onSurface)),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _addFriendSheet,
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: Text(tr('social_add_friend')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (friends.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(tr('profile_no_friends'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant)),
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 16,
            children: [for (final f in friends) _friendTile(context, f)],
          ),
        if (ctl.friends.outgoing.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(trf('profile_outgoing', {'n': ctl.friends.outgoing.length}),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }

  Widget _friendTile(BuildContext context, FriendEntry f) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FriendProfileScreen(user: f.user))),
      onLongPress: () => _confirmRemove(f),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            UserAvatar(user: f.user, size: 62),
            const SizedBox(height: 6),
            Text(f.user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurface)),
          ],
        ),
      ),
    );
  }

  // ------------------------------ действия ------------------------------

  Future<void> _pickAvatar() async {
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (res == null || res.files.isEmpty) return;
      final file = res.files.single;
      final raw = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (raw == null) return;
      setState(() => _uploading = true);
      final png = await resizeAvatarPng(raw);
      await SocialController.instance.setAvatar(png);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _editName() {
    final scheme = Theme.of(context).colorScheme;
    final ctl = SocialController.instance;
    final c = TextEditingController(text: ctl.user?.displayName ?? '');
    bool busy = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  Text(tr('profile_edit_name'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: scheme.onSurface)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: c,
                    autofocus: true,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(fontFamily: AppTheme.bodyFont),
                    decoration: InputDecoration(
                      labelText: tr('social_name'),
                      prefixIcon: const Icon(Icons.badge_rounded),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final name = c.text.trim();
                              if (name.isEmpty) return;
                              setSheet(() => busy = true);
                              try {
                                await ctl.updateProfile(displayName: name);
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                setSheet(() => busy = false);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(socialErrorText(e))));
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2))
                          : Text(tr('save')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _addFriendSheet() {
    final scheme = Theme.of(context).colorScheme;
    final c = TextEditingController();
    bool busy = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  Text(tr('social_add_friend'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: scheme.onSurface)),
                  const SizedBox(height: 6),
                  Text(tr('profile_add_hint'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: c,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2),
                    decoration: InputDecoration(
                      labelText: tr('profile_friend_code'),
                      prefixIcon: const Icon(Icons.tag_rounded),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final code = c.text.trim().toUpperCase();
                              if (code.isEmpty) return;
                              setSheet(() => busy = true);
                              try {
                                final status = await SocialController.instance
                                    .addFriend(code: code);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(status == 'accepted'
                                              ? tr('social_now_friends')
                                              : tr('social_request_sent'))));
                                }
                              } catch (e) {
                                setSheet(() => busy = false);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(socialErrorText(e))));
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.2))
                          : Text(tr('social_send_request')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(FriendEntry f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('profile_remove_friend')),
        content: Text(trf('profile_remove_q', {'name': f.user.displayName})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('delete'))),
        ],
      ),
    );
    if (ok == true) await SocialController.instance.removeFriend(f.user.id);
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('social_logout')),
        content: Text(tr('profile_logout_q')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('social_logout'))),
        ],
      ),
    );
    if (ok == true) await SocialController.instance.logout();
  }
}
