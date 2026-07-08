import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../l10n/strings.dart';
import '../../models/social.dart';
import '../../services/movie_repository.dart';
import '../../services/social/avatar_util.dart';
import '../../services/social/social_controller.dart';
import '../../services/store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_banner.dart';
import '../../widgets/user_avatar.dart';
import '../statistics_screen.dart';
import 'auth_screen.dart';
import 'friend_profile_screen.dart';
import 'media_image_picker.dart';
import 'profile_stats.dart';
import 'recovery.dart';

/// Свой профиль (4-я вкладка навигации). Не вошёл — приглашение войти; вошёл —
/// аватар/ник/код с правкой, входящие заявки, друзья и своя статистика.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  bool _uploading = false;
  bool _uploadingBanner = false;
  bool _hideRatings = false;
  bool _hideDates = false;

  @override
  void initState() {
    super.initState();
    _loadPrivacy();
    // Подтянуть свежие заявки/друзей при открытии вкладки.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocialController.instance.refreshFriends();
    });
  }

  Future<void> _loadPrivacy() async {
    final r = await Store.instance.getBool('socialHideRatings');
    final d = await Store.instance.getBool('socialHideDates');
    if (mounted) {
      setState(() {
        _hideRatings = r;
        _hideDates = d;
      });
    }
  }

  Future<void> _setHideRatings(bool v) async {
    setState(() => _hideRatings = v);
    await Store.instance.setBool('socialHideRatings', v);
    unawaited(SocialController.instance.publishSilently()); // перепубликовать
  }

  Future<void> _setHideDates(bool v) async {
    setState(() => _hideDates = v);
    await Store.instance.setBool('socialHideDates', v);
    unawaited(SocialController.instance.publishSilently());
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
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () => ctl.refreshFriends(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _header(context, me),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ctl.friends.incoming.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _incomingSection(context, ctl),
                ],
                const SizedBox(height: 24),
                _friendsSection(context, ctl),
                const SizedBox(height: 24),
                _accountSection(context, me),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(tr('drawer_stats'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: scheme.onSurface)),
                ),
                const SizedBox(height: 12),
                ProfileStats(
                  repo: MovieRepository.instance,
                  onHeroTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const StatisticsScreen())),
                ),
                const SizedBox(height: 32),
                _logoutButton(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, SocialUser me) {
    final scheme = Theme.of(context).colorScheme;
    const avatarSize = 88.0;
    const overlap = 42.0; // насколько аватар свисает ниже баннера
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: _uploadingBanner ? null : _bannerMenu,
              child: ProfileBanner(user: me, height: 178),
            ),
            Positioned(top: 12, right: 12, child: _bannerEditButton(scheme)),
            Positioned(
              left: 20,
              bottom: -overlap,
              child: GestureDetector(
                onTap: _uploading ? null : _avatarMenu,
                child: _avatarWithBadge(scheme, me, avatarSize),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(122, 10, 16, 0),
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
              const SizedBox(height: 2),
              Align(
                  alignment: Alignment.centerLeft,
                  child: _codeChip(context, me.friendCode)),
            ],
          ),
        ),
      ],
    );
  }

  /// Аватар со значком «сменить фото» (перекрывает низ баннера, в кольце фона).
  Widget _avatarWithBadge(ColorScheme scheme, SocialUser me, double size) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
          child: UserAvatar(user: me, size: size),
        ),
        Positioned(
          right: 2,
          bottom: 2,
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
    );
  }

  /// Круглая кнопка «сменить баннер» поверх обложки (правый верхний угол).
  Widget _bannerEditButton(ColorScheme scheme) {
    return Material(
      color: Colors.black.withValues(alpha: 0.38),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _uploadingBanner ? null : _bannerMenu,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _uploadingBanner
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
        ),
      ),
    );
  }

  /// Широкая закрашенная кнопка «Выйти» — в самом низу профиля.
  Widget _logoutButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _confirmLogout,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.errorContainer,
          foregroundColor: scheme.onErrorContainer,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon: const Icon(Icons.logout_rounded),
        label: Text(tr('social_logout'),
            style: const TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
      ),
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

  // -------------------------- аккаунт/приватность --------------------------

  Widget _accountSection(BuildContext context, SocialUser me) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22)),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // Код восстановления. Если не задан — подсвечиваем как призыв к действию.
          ListTile(
            leading: Icon(Icons.vpn_key_rounded,
                color: me.hasRecovery ? scheme.onSurfaceVariant : scheme.primary),
            title: Text(tr('recovery_title'),
                style: const TextStyle(
                    fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
            subtitle: Text(
                me.hasRecovery ? tr('recovery_sub') : tr('recovery_missing'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    color: me.hasRecovery
                        ? scheme.onSurfaceVariant
                        : scheme.primary)),
            trailing: Icon(Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant),
            onTap: _regenerateRecovery,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile(
            value: _hideRatings,
            onChanged: _setHideRatings,
            secondary:
                Icon(Icons.star_border_rounded, color: scheme.onSurfaceVariant),
            title: Text(tr('privacy_hide_ratings'),
                style: const TextStyle(
                    fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
          ),
          SwitchListTile(
            value: _hideDates,
            onChanged: _setHideDates,
            secondary: Icon(Icons.event_busy_rounded,
                color: scheme.onSurfaceVariant),
            title: Text(tr('privacy_hide_dates'),
                style: const TextStyle(
                    fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
            subtitle: Text(tr('privacy_hide_dates_sub'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Future<void> _regenerateRecovery() async {
    // Подтверждение — старый код перестанет работать.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('recovery_title')),
        content: Text(tr('recovery_regen_q')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('recovery_regen'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final code = await SocialController.instance.regenerateRecovery();
      if (mounted) await showRecoveryCodeSheet(context, code, isNew: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    }
  }

  // ------------------------------ действия ------------------------------

  /// Меню аватара: из галереи / из постера фильма.
  void _avatarMenu() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
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
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.image_rounded, color: scheme.primary),
              title: Text(tr('banner_choose'),
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _pickAvatar();
              },
            ),
            ListTile(
              leading: Icon(Icons.movie_filter_rounded, color: scheme.primary),
              title: Text(tr('pick_from_poster'),
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final url = await showMediaImagePicker(context, backdrop: false);
                if (url != null) await _applyAvatarFromUrl(url);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

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
      final enc = await encodeAvatar(raw);
      await SocialController.instance
          .setAvatar(enc.bytes, contentType: enc.contentType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Скачивает картинку по URL (постер/кадр TMDB). Возвращает байты или null.
  Future<Uint8List?> _downloadImage(String url) async {
    final resp =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
    return resp.bodyBytes;
  }

  /// Ставит аватар из постера фильма (квадратный кроп).
  Future<void> _applyAvatarFromUrl(String url) async {
    setState(() => _uploading = true);
    try {
      final raw = await _downloadImage(url);
      if (raw == null) return;
      final enc = await encodeAvatar(raw);
      await SocialController.instance
          .setAvatar(enc.bytes, contentType: enc.contentType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Ставит баннер из кадра фильма (широкий кроп).
  Future<void> _applyBannerFromUrl(String url) async {
    setState(() => _uploadingBanner = true);
    try {
      final raw = await _downloadImage(url);
      if (raw == null) return;
      final enc = await encodeBanner(raw);
      await SocialController.instance
          .setBanner(enc.bytes, contentType: enc.contentType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  /// Меню баннера: выбрать картинку / убрать (если задан).
  void _bannerMenu() {
    final scheme = Theme.of(context).colorScheme;
    final hasBanner = (SocialController.instance.user?.bannerVer ?? 0) > 0;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
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
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.image_rounded, color: scheme.primary),
              title: Text(tr('banner_choose'),
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _pickBanner();
              },
            ),
            ListTile(
              leading: Icon(Icons.movie_filter_rounded, color: scheme.primary),
              title: Text(tr('pick_from_backdrop'),
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final url = await showMediaImagePicker(context, backdrop: true);
                if (url != null) await _applyBannerFromUrl(url);
              },
            ),
            if (hasBanner)
              ListTile(
                leading: Icon(Icons.hide_image_rounded, color: scheme.error),
                title: Text(tr('banner_remove'),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        color: scheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeBanner();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBanner() async {
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (res == null || res.files.isEmpty) return;
      final file = res.files.single;
      final raw = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (raw == null) return;
      setState(() => _uploadingBanner = true);
      final enc = await encodeBanner(raw);
      await SocialController.instance
          .setBanner(enc.bytes, contentType: enc.contentType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  Future<void> _removeBanner() async {
    setState(() => _uploadingBanner = true);
    try {
      await SocialController.instance.removeBanner();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
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
