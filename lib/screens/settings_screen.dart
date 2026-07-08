import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../services/app_prefs.dart';
import '../services/backup_service.dart';
import '../services/import_service.dart';
import '../services/update_service.dart';
import '../widgets/update_sheet.dart';
import '../services/movie_repository.dart';
import '../services/movie_source.dart';
import '../services/notification_service.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../theme/theme_controller.dart';
import '../widgets/color_picker_sheet.dart';
import 'about_screen.dart';
import 'auto_backup_screen.dart';
import 'sync_screen.dart';
import 'tmdb_key_screen.dart';

/// Экран настроек в духе Material 3 Expressive (перенос из ScoreMaster):
/// внешний вид (тема, цвет, палитры, Material You, AMOLED), язык (7 языков),
/// данные (бэкап/синхронизация). Все выборы — выезжающими снизу панелями.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _theme = ThemeController.instance;
  final _locale = LocaleController.instance;
  final _source = SourceController.instance;
  final _prefs = AppPrefs.instance;
  bool _notify = true;
  bool _sequential = true;
  bool _restrictUnaired = true;

  @override
  void initState() {
    super.initState();
    Store.instance.getBool('notifyNewEpisodes', def: true).then((v) {
      if (mounted) setState(() => _notify = v);
    });
    Store.instance.getBool('sequentialEpisodes', def: true).then((v) {
      if (mounted) setState(() => _sequential = v);
    });
    Store.instance.getBool('restrictUnaired', def: true).then((v) {
      if (mounted) setState(() => _restrictUnaired = v);
    });
  }

  /// Фирменные палитры (кинематографичные), включая бирюзовую по умолчанию.
  static const List<Color> _palettes = [
    Color(0xFF00B5C7), // бирюзовый (по умолчанию)
    Color(0xFF7C4DFF), // фиолетовый
    Color(0xFFE53935), // красный (кинозал)
    Color(0xFFFF7043), // коралловый
    Color(0xFFFFB300), // янтарный
    Color(0xFF43A047), // зелёный
    Color(0xFF1E88E5), // синий
    Color(0xFFEC407A), // розовый
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_theme, _locale, _source, _prefs]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(tr('settings_title'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _section(tr('appearance')),
              _card([
                _tile(
                  icon: Icons.brightness_6_rounded,
                  title: tr('theme_mode'),
                  subtitle: _themeModeLabel(_theme.mode),
                  onTap: _pickThemeMode,
                ),
                _divider(),
                _tile(
                  icon: Icons.palette_rounded,
                  title: tr('theme_color'),
                  subtitle: _theme.isDefaultSeed
                      ? tr('theme_color_custom')
                      : colorToHex(_theme.seedColor),
                  trailing: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _theme.seedColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 2),
                    ),
                  ),
                  enabled: !_theme.useDynamicColor,
                  onTap: _pickColor,
                ),
                if (!_theme.useDynamicColor) _paletteRow(),
                _divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome_rounded),
                  title: Text(tr('dynamic_color')),
                  subtitle: Text(tr('dynamic_color_sub')),
                  value: _theme.useDynamicColor,
                  onChanged: _theme.setUseDynamicColor,
                ),
                if (_theme.isDark) ...[
                  _divider(),
                  SwitchListTile(
                    secondary: const Icon(Icons.contrast_rounded),
                    title: Text(tr('amoled')),
                    subtitle: Text(tr('amoled_sub')),
                    value: _theme.amoled,
                    onChanged: _theme.setAmoled,
                  ),
                ],
              ]),
              _section(tr('language')),
              _card([
                _tile(
                  icon: Icons.translate_rounded,
                  title: tr('language'),
                  subtitle: _currentLanguageName(),
                  onTap: _pickLanguage,
                ),
              ]),
              _section(tr('general')),
              _card([
                _tile(
                  icon: Icons.home_rounded,
                  title: tr('start_screen'),
                  subtitle: _startScreenLabel(_prefs.startScreen),
                  onTap: _pickStartScreen,
                ),
                _divider(),
                _tile(
                  icon: Icons.event_note_rounded,
                  title: tr('date_format'),
                  subtitle: _dateFormatExample(_prefs.numericDates),
                  onTap: _pickDateFormat,
                ),
              ]),
              _section(tr('movies_section')),
              _card([
                _tile(
                  icon: Icons.movie_filter_rounded,
                  title: tr('movie_source'),
                  subtitle: '${_source.source.label} · ${_source.source.note}',
                  onTap: _pickSource,
                ),
                _divider(),
                _tile(
                  icon: Icons.vpn_key_rounded,
                  title: tr('api_keys_title'),
                  subtitle: tr('api_keys_sub'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TmdbKeyScreen())),
                ),
              ]),
              _section(tr('nav_series')),
              _card([
                SwitchListTile(
                  secondary: const Icon(Icons.playlist_add_check_rounded),
                  title: Text(tr('seq_mode')),
                  subtitle: Text(tr('seq_mode_sub')),
                  value: _sequential,
                  onChanged: (v) {
                    setState(() => _sequential = v);
                    Store.instance.setBool('sequentialEpisodes', v);
                  },
                ),
                _divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.event_busy_rounded),
                  title: Text(tr('restrict_unaired')),
                  subtitle: Text(tr('restrict_unaired_sub')),
                  value: _restrictUnaired,
                  onChanged: (v) {
                    setState(() => _restrictUnaired = v);
                    Store.instance.setBool('restrictUnaired', v);
                  },
                ),
              ]),
              _section(tr('notif_new_episodes')),
              _card([
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_rounded),
                  title: Text(tr('notif_new_episodes')),
                  subtitle: Text(tr('notif_new_episodes_sub')),
                  value: _notify,
                  onChanged: (v) async {
                    setState(() => _notify = v);
                    await NotificationService.instance.setEnabled(v);
                    if (v) await NotificationService.instance.checkNewEpisodes();
                  },
                ),
                if (_notify) ...[
                  _divider(),
                  _tile(
                    icon: Icons.notifications_none_rounded,
                    title: tr('notif_test'),
                    subtitle: tr('notif_test_sub'),
                    onTap: () => NotificationService.instance.showTest(),
                  ),
                ],
              ]),
              _section(tr('data')),
              _card([
                _tile(
                  icon: Icons.folder_zip_rounded,
                  title: tr('auto_backup'),
                  subtitle: tr('auto_backup_sub'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AutoBackupScreen())),
                ),
                _divider(),
                _tile(
                  icon: Icons.cloud_sync_rounded,
                  title: tr('sync_webdav'),
                  subtitle: tr('sync_webdav_sub'),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SyncScreen())),
                ),
                _divider(),
                _tile(
                  icon: Icons.backup_rounded,
                  title: tr('sync_backup'),
                  subtitle: tr('sync_backup_sub'),
                  onTap: _backupSheet,
                ),
                _divider(),
                ListTile(
                  leading: Icon(Icons.delete_forever_rounded,
                      color: Theme.of(context).colorScheme.error),
                  title: Text(tr('clear_all_data'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.error)),
                  subtitle: Text(tr('clear_all_data_sub')),
                  onTap: _confirmClearAll,
                ),
              ]),
              _section(tr('about')),
              _card([
                _tile(
                  icon: Icons.system_update_rounded,
                  title: tr('check_updates'),
                  subtitle: tr('check_updates_sub'),
                  onTap: _checkUpdates,
                ),
                _divider(),
                _tile(
                  icon: Icons.movie_rounded,
                  title: tr('app_name'),
                  subtitle: tr('about_sub'),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  /// Ручная проверка обновления: меню обновления или «последняя версия».
  Future<void> _checkUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
        content: Text(tr('checking_updates')),
        behavior: SnackBarBehavior.floating));
    final current = (await PackageInfo.fromPlatform()).version;
    try {
      final info = await UpdateService.checkForUpdate(current);
      if (!mounted) return;
      if (info == null) {
        messenger.showSnackBar(SnackBar(
            content: Text(tr('up_to_date')),
            behavior: SnackBarBehavior.floating));
      } else {
        await UpdateSheet.show(context, info, current);
      }
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(tr('update_check_failed')),
          behavior: SnackBarBehavior.floating));
    }
  }

  // --------------------------- строительные блоки ---------------------------

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 22, 12, 10),
        child: Text(
          title,
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  Widget _card(List<Widget> children) => Card(
        margin: EdgeInsets.zero,
        child: Column(children: children),
      );

  Widget _divider() => const Divider(height: 1, indent: 56);

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    return ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(title,
          style: const TextStyle(
              fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: trailing ??
          (onTap == null
              ? null
              : const Icon(Icons.chevron_right_rounded, size: 22)),
      onTap: onTap,
    );
  }

  Widget _paletteRow() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final c in _palettes)
            GestureDetector(
              onTap: () => _theme.setSeedColor(c),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _theme.seedColor.toARGB32() == c.toARGB32()
                        ? scheme.onSurface
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: _theme.seedColor.toARGB32() == c.toARGB32()
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 22)
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------- действия -------------------------------

  Future<void> _pickColor() async {
    final picked = await showColorPickerSheet(
      context,
      initial: _theme.seedColor,
      title: tr('theme_color'),
      resetTo: AppTheme.defaultSeed,
    );
    if (picked != null) _theme.setSeedColor(picked);
  }

  void _pickThemeMode() {
    _bottomSheet(
      title: tr('theme_mode'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in AppThemeMode.values)
            RadioListTile<AppThemeMode>(
              value: m,
              // ignore: deprecated_member_use
              groupValue: _theme.mode,
              // ignore: deprecated_member_use
              onChanged: (v) {
                if (v != null) _theme.setMode(v);
                Navigator.pop(context);
              },
              title: Text(_themeModeLabel(m)),
              secondary: Icon(_themeModeIcon(m)),
            ),
        ],
      ),
    );
  }

  void _pickLanguage() {
    _bottomSheet(
      title: tr('language'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in LocaleController.languages)
            ListTile(
              title: Text(l.nativeName,
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600)),
              trailing: _locale.code == l.code
                  ? Icon(Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                _locale.setCode(l.code);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  void _pickSource() {
    _bottomSheet(
      title: tr('movie_source'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in MovieSource.values)
            ListTile(
              leading: Icon(s == MovieSource.tmdb
                  ? Icons.public_rounded
                  : Icons.movie_rounded),
              title: Text(s.label,
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(s.note),
              trailing: _source.source == s
                  ? Icon(Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                _source.setSource(s);
                // Дотянуть необогащённые фильмы через новый источник.
                MovieRepository.instance.retryUnmatched();
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  void _pickStartScreen() {
    _bottomSheet(
      title: tr('start_screen'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in StartScreen.values)
            ListTile(
              leading: Icon(_startScreenIcon(s)),
              title: Text(_startScreenLabel(s),
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600)),
              trailing: _prefs.startScreen == s
                  ? Icon(Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                _prefs.setStartScreen(s);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  void _pickDateFormat() {
    final now = DateTime(2026, 6, 24);
    _bottomSheet(
      title: tr('date_format'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final numeric in [false, true])
            ListTile(
              leading: Icon(
                  numeric ? Icons.pin_rounded : Icons.calendar_month_rounded),
              title: Text(
                  numeric ? tr('date_format_numeric') : tr('date_format_long'),
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(numeric ? numericDate(now) : longDate(now)),
              trailing: _prefs.numericDates == numeric
                  ? Icon(Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                _prefs.setNumericDates(numeric);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  /// Подтверждение полной очистки личных данных (необратимо).
  void _confirmClearAll() {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, color: scheme.error, size: 32),
        title: Text(tr('clear_all_title'),
            style: const TextStyle(fontFamily: AppTheme.displayFont)),
        content: Text(tr('clear_all_body'),
            style: const TextStyle(fontFamily: AppTheme.bodyFont)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              await MovieRepository.instance.clearAll();
              messenger.showSnackBar(SnackBar(
                  content: Text(tr('clear_all_done')),
                  behavior: SnackBarBehavior.floating));
            },
            style: FilledButton.styleFrom(
                backgroundColor: scheme.error, foregroundColor: scheme.onError),
            child: Text(tr('clear')),
          ),
        ],
      ),
    );
  }

  void _backupSheet() {
    _bottomSheet(
      title: tr('sync_backup'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('backup_hint'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: Text(tr('create_backup')),
            subtitle: Text(tr('create_backup_sub')),
            onTap: () {
              Navigator.pop(context);
              BackupService.exportAndShare();
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_open_rounded),
            title: Text(tr('restore_backup')),
            subtitle: Text(tr('restore_backup_sub')),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              final ok = await BackupService.importFromFile();
              messenger.showSnackBar(SnackBar(
                content:
                    Text(tr(ok ? 'backup_import_ok' : 'backup_import_fail')),
              ));
            },
          ),
          ListTile(
            leading: const Icon(Icons.move_to_inbox_rounded),
            title: Text(tr('import_tracker')),
            subtitle: Text(tr('import_tracker_sub')),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              final res = await ImportService.pickAndImport();
              if (!res.ok) {
                messenger.showSnackBar(
                    SnackBar(content: Text(tr('import_tracker_fail'))));
                return;
              }
              messenger.showSnackBar(SnackBar(
                content: Text(trf('import_tracker_ok',
                    {'a': res.added, 'u': res.updated})),
              ));
            },
          ),
        ],
      ),
    );
  }

  /// Единый стиль нижней панели (скругление сверху, ручка, заголовок).
  void _bottomSheet({required String title, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            child,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ------------------------------- подписи -------------------------------

  String _themeModeLabel(AppThemeMode m) => switch (m) {
        AppThemeMode.light => tr('theme_light'),
        AppThemeMode.dark => tr('theme_dark'),
        AppThemeMode.system => tr('theme_system'),
        AppThemeMode.autoTime => tr('theme_auto'),
      };

  IconData _themeModeIcon(AppThemeMode m) => switch (m) {
        AppThemeMode.light => Icons.light_mode_rounded,
        AppThemeMode.dark => Icons.dark_mode_rounded,
        AppThemeMode.system => Icons.brightness_auto_rounded,
        AppThemeMode.autoTime => Icons.schedule_rounded,
      };

  String _currentLanguageName() {
    for (final l in LocaleController.languages) {
      if (l.code == _locale.code) return l.nativeName;
    }
    return _locale.code;
  }

  String _startScreenLabel(StartScreen s) => switch (s) {
        StartScreen.watchlist => tr('nav_watchlist'),
        StartScreen.watched => tr('nav_watched'),
        StartScreen.nowWatching => tr('now_watching'),
        StartScreen.discover => tr('nav_discover'),
        StartScreen.cinema => tr('nav_cinema'),
      };

  IconData _startScreenIcon(StartScreen s) => switch (s) {
        StartScreen.watchlist => Icons.bookmark_rounded,
        StartScreen.watched => Icons.check_circle_rounded,
        StartScreen.nowWatching => Icons.live_tv_rounded,
        StartScreen.discover => Icons.explore_rounded,
        StartScreen.cinema => Icons.local_movies_rounded,
      };

  String _dateFormatExample(bool numeric) {
    final now = DateTime(2026, 6, 24);
    return numeric ? numericDate(now) : longDate(now);
  }
}
