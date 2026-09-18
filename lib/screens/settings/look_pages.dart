import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/app_prefs.dart';
import '../../services/notification_service.dart';
import '../../services/store.dart';
import '../../utils/format.dart';
import '../../widgets/settings_kit.dart';
import '../drawer_customize_screen.dart';
import 'settings_sheets.dart';

/// Раздел «Интерфейс»: стартовый экран, формат дат, кнопка «+», боковое меню
/// и режим ТВ.
class InterfacePage extends StatelessWidget {
  const InterfacePage({super.key});

  /// Дата-образец для подписи формата: день и месяц не путаются.
  static final DateTime _sample = DateTime(2026, 6, 24);

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefs.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => SettingsPage(
        title: tr('set_group_interface'),
        children: [
          SettingsGroup([
            SettingsRow(
              icon: Icons.home_rounded,
              title: tr('start_screen'),
              subtitle: startScreenLabel(prefs.startScreen),
              trailing: const SettingsChevron(),
              onTap: () => showChoiceSheet<StartScreen>(
                context,
                title: tr('start_screen'),
                selected: prefs.startScreen,
                options: [
                  for (final s in StartScreen.values)
                    ChoiceOption(
                      value: s,
                      label: startScreenLabel(s),
                      icon: _startScreenIcon(s),
                    ),
                ],
                onPick: prefs.setStartScreen,
              ),
            ),
            SettingsRow(
              icon: Icons.call_to_action_rounded,
              title: tr('set_nav_style'),
              subtitle: prefs.navStyle == NavStyle.floating
                  ? tr('nav_style_floating')
                  : tr('nav_style_classic'),
              trailing: const SettingsChevron(),
              onTap: () => showChoiceSheet<NavStyle>(
                context,
                title: tr('set_nav_style'),
                selected: prefs.navStyle,
                options: [
                  ChoiceOption(
                    value: NavStyle.floating,
                    label: tr('nav_style_floating'),
                    subtitle: tr('nav_style_floating_sub'),
                    icon: Icons.smart_button_rounded,
                  ),
                  ChoiceOption(
                    value: NavStyle.classic,
                    label: tr('nav_style_classic'),
                    subtitle: tr('nav_style_classic_sub'),
                    icon: Icons.call_to_action_rounded,
                  ),
                ],
                onPick: prefs.setNavStyle,
              ),
            ),
            SettingsRow(
              icon: Icons.event_note_rounded,
              title: tr('date_format'),
              subtitle: _dateExample(prefs.numericDates),
              trailing: const SettingsChevron(),
              onTap: () => showChoiceSheet<bool>(
                context,
                title: tr('date_format'),
                selected: prefs.numericDates,
                options: [
                  for (final numeric in [false, true])
                    ChoiceOption(
                      value: numeric,
                      label: numeric
                          ? tr('date_format_numeric')
                          : tr('date_format_long'),
                      subtitle: _dateExample(numeric),
                      icon: numeric
                          ? Icons.pin_rounded
                          : Icons.calendar_month_rounded,
                    ),
                ],
                onPick: prefs.setNumericDates,
              ),
            ),
            SettingsRow(
              icon: Icons.menu_open_rounded,
              title: tr('set_side_menu'),
              subtitle: tr('drawer_customize_sub'),
              trailing: const SettingsChevron(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DrawerCustomizeScreen(),
                ),
              ),
            ),
            SettingsSwitchRow(
              icon: Icons.tv_rounded,
              title: tr('tv_mode'),
              subtitle: tr('tv_mode_sub'),
              value: prefs.forceTvMode,
              onChanged: prefs.setForceTvMode,
            ),
          ]),
        ],
      ),
    );
  }

  static String _dateExample(bool numeric) =>
      numeric ? numericDate(_sample) : longDate(_sample);

  static IconData _startScreenIcon(StartScreen s) => switch (s) {
    StartScreen.watchlist => Icons.bookmark_rounded,
    StartScreen.watched => Icons.check_circle_rounded,
    StartScreen.nowWatching => Icons.live_tv_rounded,
    StartScreen.discover => Icons.explore_rounded,
    StartScreen.cinema => Icons.local_movies_rounded,
  };
}

/// Подпись стартового экрана.
String startScreenLabel(StartScreen s) => switch (s) {
  StartScreen.watchlist => tr('nav_watchlist'),
  StartScreen.watched => tr('nav_watched'),
  StartScreen.nowWatching => tr('now_watching'),
  StartScreen.discover => tr('nav_discover'),
  StartScreen.cinema => tr('nav_cinema'),
};

/// Раздел «Скрывать в „Обзоре“»: что из своей библиотеки не показывать в
/// подборках.
class DiscoverHidePage extends StatelessWidget {
  const DiscoverHidePage({super.key});

  static const _items = [
    (
      DiscoverHide.watchedMovies,
      Icons.check_circle_rounded,
      'disc_hide_watched_movies',
    ),
    (
      DiscoverHide.watchedSeries,
      Icons.check_circle_rounded,
      'disc_hide_watched_series',
    ),
    (
      DiscoverHide.droppedMovies,
      Icons.heart_broken_rounded,
      'disc_hide_dropped_movies',
    ),
    (
      DiscoverHide.droppedSeries,
      Icons.heart_broken_rounded,
      'disc_hide_dropped_series',
    ),
    (
      DiscoverHide.watchlistMovies,
      Icons.bookmark_rounded,
      'disc_hide_watchlist_movies',
    ),
    (
      DiscoverHide.watchlistSeries,
      Icons.bookmark_rounded,
      'disc_hide_watchlist_series',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefs.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => SettingsPage(
        title: tr('disc_hide_section'),
        children: [
          SettingsGroup([
            for (final (h, icon, key) in _items)
              SettingsSwitchRow(
                icon: icon,
                title: tr(key),
                value: prefs.discoverHidden(h),
                onChanged: (v) => prefs.setDiscoverHidden(h, v),
              ),
          ]),
        ],
      ),
    );
  }
}

/// Раздел «Уведомления» о новых сериях: баннер в приложении, пуши и проба.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _inApp = true;
  bool _push = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final inApp = await Store.instance.getBool('notifyInApp', def: true);
    final push = await Store.instance.getBool('notifyPush', def: false);
    if (mounted) {
      setState(() {
        _inApp = inApp;
        _push = push;
      });
    }
  }

  Future<void> _setInApp(bool v) async {
    setState(() => _inApp = v);
    await NotificationService.instance.setInAppEnabled(v);
    if (v) await NotificationService.instance.checkNewEpisodes();
  }

  Future<void> _setPush(bool v) async {
    setState(() => _push = v);
    await NotificationService.instance.setPushEnabled(v);
    if (v) await NotificationService.instance.checkNewEpisodes();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: tr('set_group_notifications'),
      children: [
        SettingsGroup([
          SettingsSwitchRow(
            icon: Icons.dashboard_customize_rounded,
            title: tr('notif_inapp'),
            subtitle: tr('notif_inapp_sub'),
            value: _inApp,
            onChanged: _setInApp,
          ),
          SettingsSwitchRow(
            icon: Icons.notifications_active_rounded,
            title: tr('notif_push'),
            subtitle: tr('notif_push_sub'),
            value: _push,
            onChanged: _setPush,
          ),
          if (_inApp || _push)
            SettingsRow(
              icon: Icons.notifications_none_rounded,
              title: tr('notif_test'),
              subtitle: tr('notif_test_sub'),
              trailing: const SettingsChevron(),
              onTap: () => NotificationService.instance.showTest(),
            ),
        ]),
      ],
    );
  }
}
