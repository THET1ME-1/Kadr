import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/app_icon_service.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_icon_preview.dart';
import '../../widgets/appearance_card.dart';
import '../../widgets/settings_kit.dart';
import '../custom_icon_screen.dart';
import 'settings_sheets.dart';

/// Раздел «Внешний вид»: режим темы и цвет первым блоком, под ними цвета из
/// обоев, чёрный фон и иконка приложения.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance;
    final icons = AppIconService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([theme, icons]),
      builder: (context, _) => SettingsPage(
        title: tr('appearance'),
        children: [
          SettingsGroup([
            // Своя заливка у карточки та же, что у блока, поэтому форму
            // задаёт группа.
            const AppearanceCard(),
            SettingsSwitchRow(
              icon: Icons.auto_awesome_rounded,
              title: tr('dynamic_color'),
              subtitle: tr('dynamic_color_sub'),
              value: theme.useDynamicColor,
              onChanged: theme.setUseDynamicColor,
            ),
            if (theme.isDark)
              SettingsSwitchRow(
                icon: Icons.contrast_rounded,
                title: tr('amoled'),
                subtitle: tr('amoled_sub'),
                value: theme.amoled,
                onChanged: theme.setAmoled,
              ),
          ]),
          if (icons.isSupported) ...[
            SettingsSection(tr('app_icon'), icon: Icons.apps_rounded),
            SettingsGroup([
              SettingsRow(
                leading: AppIconPreview(option: icons.currentOption, size: 44),
                title: tr('app_icon'),
                subtitle: tr(icons.currentOption.nameKey),
                trailing: const SettingsChevron(),
                onTap: () => _pickAppIcon(context),
              ),
              SettingsRow(
                icon: Icons.color_lens_rounded,
                title: tr('custom_icon'),
                subtitle: tr('custom_icon_sub'),
                trailing: const SettingsChevron(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CustomIconScreen()),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// mipmap-ассеты лаунчера из Flutter не видны: плоские превью рисуются
  /// кодом, основное лого берётся из `assets/icon/`. Оба пути дают ровно то,
  /// что встанет на стол.
  void _pickAppIcon(BuildContext context) {
    final icons = AppIconService.instance;
    final messenger = ScaffoldMessenger.of(context);
    showChoiceSheet<String>(
      context,
      title: tr('app_icon'),
      hint: tr('app_icon_hint'),
      selected: icons.current,
      options: [
        for (final o in AppIconService.options)
          ChoiceOption(
            value: o.id,
            label: tr(o.nameKey),
            leading: AppIconPreview(option: o, size: 48),
          ),
      ],
      onPick: (id) async {
        if (icons.current == id) return;
        final ok = await icons.setIcon(id);
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                ok ? tr('app_icon_changed') : tr('app_icon_failed'),
              ),
            ),
          );
      },
    );
  }
}
