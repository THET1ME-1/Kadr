import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../services/social/social_controller.dart';
import '../../services/store.dart';
import '../../widgets/settings_kit.dart';
import '../../widgets/user_avatar.dart';
import '../social/auth_screen.dart';
import '../social/recovery.dart';
import 'settings_sheets.dart';

/// Раздел «Аккаунт»: код друга, почта, код восстановления, что видят друзья и
/// выход. Раньше всё это лежало в профиле вперемешку с темой и бэкапами.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _hideRatings = false;
  bool _hideDates = false;

  @override
  void initState() {
    super.initState();
    _loadPrivacy();
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
    // Витрину перепубликовать, иначе друзья увидят старые оценки.
    unawaited(SocialController.instance.publishSilently());
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
        final me = SocialController.instance.user;
        final scheme = Theme.of(context).colorScheme;
        if (me == null) {
          return SettingsPage(
            title: tr('set_group_account'),
            children: [
              SettingsGroup([
                SettingsRow(
                  icon: Icons.login_rounded,
                  title: tr('profile_login_cta'),
                  subtitle: tr('set_account_out_sub'),
                  trailing: const SettingsChevron(),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AuthScreen())),
                ),
              ]),
            ],
          );
        }
        final email = me.email;
        return SettingsPage(
          title: tr('set_group_account'),
          children: [
            SettingsGroup([
              SettingsRow(
                leading: UserAvatar(user: me, size: 44),
                title: me.displayName,
                subtitle: '${tr('profile_friend_code')} · ${me.friendCode}',
                trailing: Icon(Icons.copy_rounded, color: scheme.outline),
                onTap: () => _copy(me.friendCode, tr('profile_code_copied')),
              ),
              if (email != null && email.isNotEmpty)
                SettingsRow(
                  icon: Icons.alternate_email_rounded,
                  title: email,
                  subtitle: tr('set_account_email_sub'),
                  iconBg: scheme.surfaceContainerHighest,
                  iconFg: scheme.onSurfaceVariant,
                  onTap: () => _copy(email, tr('set_email_copied')),
                ),
              // Код не задан — значок залит акцентом как призыв создать его.
              SettingsRow(
                icon: Icons.vpn_key_rounded,
                title: tr('recovery_title'),
                subtitle: me.hasRecovery
                    ? tr('recovery_sub')
                    : tr('recovery_missing'),
                iconBg: me.hasRecovery ? null : scheme.primary,
                iconFg: me.hasRecovery ? null : scheme.onPrimary,
                trailing: const SettingsChevron(),
                onTap: _regenerateRecovery,
              ),
            ]),
            SettingsSection(
              tr('set_sec_privacy'),
              icon: Icons.visibility_rounded,
            ),
            SettingsGroup([
              SettingsSwitchRow(
                icon: Icons.star_rounded,
                title: tr('privacy_hide_ratings'),
                subtitle: tr('privacy_hide_ratings_sub'),
                value: _hideRatings,
                onChanged: _setHideRatings,
              ),
              SettingsSwitchRow(
                icon: Icons.event_busy_rounded,
                title: tr('privacy_hide_dates'),
                subtitle: tr('privacy_hide_dates_sub'),
                value: _hideDates,
                onChanged: _setHideDates,
              ),
            ]),
            const SizedBox(height: 24),
            SettingsGroup([
              SettingsRow(
                icon: Icons.logout_rounded,
                title: tr('social_logout'),
                iconBg: scheme.errorContainer,
                iconFg: scheme.onErrorContainer,
                titleColor: scheme.error,
                onTap: _confirmLogout,
              ),
            ]),
          ],
        );
      },
    );
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showSettingsSnack(context, done);
  }

  Future<void> _regenerateRecovery() async {
    // Подтверждение: старый код перестанет работать.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('recovery_title')),
        content: Text(tr('recovery_regen_q')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('recovery_regen')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final code = await SocialController.instance.regenerateRecovery();
      if (mounted) await showRecoveryCodeSheet(context, code, isNew: true);
    } catch (e) {
      if (mounted) showSettingsSnack(context, socialErrorText(e));
    }
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
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('social_logout')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Страницу закрываем до выхода: logout() сразу стирает сессию и потом
    // ждёт сервер. Если закрывать после, pop снимет то, что человек успел
    // открыть поверх, например экран входа.
    Navigator.of(context).pop();
    await SocialController.instance.logout();
  }
}
