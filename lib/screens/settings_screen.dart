import 'package:flutter/material.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../services/backup_service.dart';
import '../services/movie_repository.dart';
import '../services/movie_source.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/color_picker_sheet.dart';
import 'about_screen.dart';

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
      listenable: Listenable.merge([_theme, _locale, _source]),
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
              _section(tr('movies_section')),
              _card([
                _tile(
                  icon: Icons.movie_filter_rounded,
                  title: tr('movie_source'),
                  subtitle: '${_source.source.label} · ${_source.source.note}',
                  onTap: _pickSource,
                ),
              ]),
              _section(tr('data')),
              _card([
                _tile(
                  icon: Icons.cloud_sync_rounded,
                  title: tr('sync_backup'),
                  subtitle: tr('sync_backup_sub'),
                  onTap: _backupSheet,
                ),
              ]),
              _section(tr('about')),
              _card([
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
}
