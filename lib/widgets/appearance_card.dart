import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'color_picker_sheet.dart';
import 'seed_swatch.dart';

/// Пресеты акцентного цвета для карточки «Внешний вид».
const List<Color> kAccentPalette = [
  Color(0xFF00B5C7),
  Color(0xFF7C4DFF),
  Color(0xFFE53935),
  Color(0xFFFF7043),
  Color(0xFFFFB300),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFFEC407A),
];

/// Карточка «Внешний вид»: сегментный переключатель режима темы + палитра
/// акцентов + «свой цвет» (живой пикер). Слушает [ThemeController]. Общий виджет
/// для профиля и настроек, чтобы блок выглядел одинаково.
class AppearanceCard extends StatelessWidget {
  const AppearanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) => _card(context),
    );
  }

  Widget _card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = ThemeController.instance;
    return Container(
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AppThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: AppThemeMode.light,
                    icon: Icon(Icons.light_mode_rounded)),
                ButtonSegment(
                    value: AppThemeMode.dark,
                    icon: Icon(Icons.dark_mode_rounded)),
                ButtonSegment(
                    value: AppThemeMode.system,
                    icon: Icon(Icons.brightness_auto_rounded)),
                ButtonSegment(
                    value: AppThemeMode.autoTime,
                    icon: Icon(Icons.schedule_rounded)),
              ],
              selected: {theme.mode},
              onSelectionChanged: (s) {
                HapticFeedback.selectionClick();
                theme.setMode(s.first);
              },
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(_modeLabel(theme.mode),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    color: scheme.onSurfaceVariant)),
          ),
          // Акцентный цвет прячем в Material You — там цвет из обоев.
          if (!theme.useDynamicColor) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in kAccentPalette)
                  SeedSwatch(
                    seed: c,
                    vibrant: theme.vibrantScheme,
                    selected: theme.seedColor.toARGB32() == c.toARGB32(),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      theme.setSeedColor(c);
                    },
                  ),
                _customColorButton(context, scheme, theme),
              ],
            ),
            const SizedBox(height: 16),
            Text(tr('theme_intensity'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(tr('theme_vibrant'))),
                  ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                      label: Text(tr('theme_faithful'))),
                ],
                selected: {theme.vibrantScheme},
                onSelectionChanged: (s) {
                  HapticFeedback.selectionClick();
                  theme.setVibrantScheme(s.first);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _modeLabel(AppThemeMode m) => switch (m) {
        AppThemeMode.light => tr('theme_light'),
        AppThemeMode.dark => tr('theme_dark'),
        AppThemeMode.system => tr('theme_system'),
        AppThemeMode.autoTime => tr('theme_auto'),
      };

  Widget _customColorButton(
      BuildContext context, ColorScheme scheme, ThemeController theme) {
    final custom = !kAccentPalette
        .any((c) => c.toARGB32() == theme.seedColor.toARGB32());
    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        final picked = await showColorPickerSheet(
          context,
          initial: theme.seedColor,
          title: tr('theme_color'),
          resetTo: AppTheme.defaultSeed,
        );
        if (picked != null) theme.setSeedColor(picked);
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
          border: Border.all(
            color: custom ? scheme.onSurface : scheme.outlineVariant,
            width: custom ? 3 : 1,
          ),
        ),
        child: Icon(Icons.colorize_rounded,
            size: 20, color: custom ? theme.seedColor : scheme.onSurfaceVariant),
      ),
    );
  }
}
