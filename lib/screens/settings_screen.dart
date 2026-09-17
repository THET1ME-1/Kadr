import 'package:flutter/material.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../services/social/social_controller.dart';
import '../widgets/settings_kit.dart';
import '../widgets/user_avatar.dart';
import 'settings/account_page.dart';
import 'settings/appearance_page.dart';
import 'settings/kadr_pages.dart';
import 'settings/library_pages.dart';
import 'settings/look_pages.dart';
import 'settings/settings_sheets.dart';
import 'social/auth_screen.dart';

/// Настройки: список разделов, каждый открывается своей страницей.
///
/// Вид перенесён из Togetherly (`widgets/settings_kit.dart`): подпись раздела
/// капсом, каждый пункт отдельным блоком, круглый значок. До 2026-09-17 здесь
/// были сворачиваемые группы, а тема, язык, бэкапы и выход дублировались в
/// профиле. Открывается шестерёнкой на вкладке «Профиль» и из бокового меню.
///
/// Под каждым разделом подпись перечисляет, что внутри (`set_hint_*`).
/// Добавляешь пункт на страницу — допиши его в подпись.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        LocaleController.instance,
        SocialController.instance,
      ]),
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return SettingsPage(
          title: tr('settings_title'),
          children: [
            SettingsGroup([_accountRow(context)]),
            SettingsSection(tr('set_sec_look'), icon: Icons.tune_rounded),
            SettingsGroup([
              _link(
                context,
                Icons.palette_rounded,
                tr('appearance'),
                tr('set_hint_appearance'),
                const AppearancePage(),
              ),
              SettingsRow(
                icon: Icons.translate_rounded,
                title: tr('language'),
                subtitle: currentLanguageName(),
                trailing: const SettingsChevron(),
                onTap: () => pickLanguage(context),
              ),
              _link(
                context,
                Icons.dashboard_customize_rounded,
                tr('set_group_interface'),
                tr('set_hint_interface'),
                const InterfacePage(),
              ),
              _link(
                context,
                Icons.explore_rounded,
                tr('disc_hide_section'),
                tr('set_hint_discover'),
                const DiscoverHidePage(),
              ),
              _link(
                context,
                Icons.notifications_rounded,
                tr('set_group_notifications'),
                tr('set_hint_notifications'),
                const NotificationsPage(),
              ),
            ]),
            SettingsSection(
              tr('set_sec_library'),
              icon: Icons.video_library_rounded,
            ),
            SettingsGroup([
              _link(
                context,
                Icons.movie_filter_rounded,
                tr('set_group_catalog'),
                tr('set_hint_catalog'),
                const CatalogPage(),
              ),
              _link(
                context,
                Icons.task_alt_rounded,
                tr('set_group_tracking'),
                tr('set_hint_tracking'),
                const TrackingPage(),
              ),
              _link(
                context,
                Icons.cloud_sync_rounded,
                tr('set_group_sync'),
                tr('set_hint_sync'),
                const SyncPage(),
              ),
              _link(
                context,
                Icons.move_to_inbox_rounded,
                tr('set_group_import'),
                tr('set_hint_import'),
                const ImportPage(),
              ),
              _link(
                context,
                Icons.storage_rounded,
                tr('set_group_storage'),
                tr('set_hint_storage'),
                const StoragePage(),
              ),
            ]),
            SettingsSection(tr('app_name'), icon: Icons.local_movies_rounded),
            SettingsGroup([
              // Донат раньше был раскрыт по умолчанию, чтобы его видели.
              // Теперь его выделяет залитый значок.
              _link(
                context,
                Icons.volunteer_activism_rounded,
                tr('set_group_support'),
                tr('set_hint_support'),
                const SupportPage(),
                iconBg: scheme.primary,
                iconFg: scheme.onPrimary,
              ),
              _link(
                context,
                Icons.info_rounded,
                tr('about'),
                tr('set_hint_about'),
                const AboutPage(),
              ),
            ]),
          ],
        );
      },
    );
  }

  /// Верхняя строка: свой аккаунт или приглашение войти.
  Widget _accountRow(BuildContext context) {
    final me = SocialController.instance.user;
    if (me == null) {
      return SettingsRow(
        icon: Icons.person_rounded,
        title: tr('profile_login_cta'),
        subtitle: tr('set_account_out_sub'),
        trailing: const SettingsChevron(),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AuthScreen())),
      );
    }
    return SettingsRow(
      leading: UserAvatar(user: me, size: 44),
      title: me.displayName,
      subtitle: tr('set_hint_account'),
      trailing: const SettingsChevron(),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AccountPage())),
    );
  }

  Widget _link(
    BuildContext context,
    IconData icon,
    String title,
    String hint,
    Widget page, {
    Color? iconBg,
    Color? iconFg,
  }) {
    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: hint,
      iconBg: iconBg,
      iconFg: iconFg,
      trailing: const SettingsChevron(),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
    );
  }
}

/// Шестерёнка в шапке вкладки «Профиль»: быстрый вход в настройки.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      icon: const Icon(Icons.settings_rounded),
      tooltip: tr('settings_title'),
      onPressed: () {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      },
    );
  }
}
