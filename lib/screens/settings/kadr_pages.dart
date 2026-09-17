import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/settings_kit.dart';
import '../about_screen.dart';
import 'settings_sheets.dart';

/// Раздел «Поддержать проект»: короткий текст и три кнопки доната.
class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  static const _labelStyle = TextStyle(
    fontFamily: AppTheme.displayFont,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsPage(
      title: tr('set_group_support'),
      children: [
        SettingsGroup([
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SettingsIconChip(
                      Icons.volunteer_activism_rounded,
                      bg: scheme.primary,
                      fg: scheme.onPrimary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        tr('support_authors'),
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  tr('support_intro'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: openSupportAuthors,
                  icon: const Icon(Icons.favorite_rounded, size: 19),
                  label: const Text('Boosty', style: _labelStyle),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: openDonationAlerts,
                  icon: const Icon(Icons.card_giftcard_rounded, size: 19),
                  label: const Text('DonationAlerts', style: _labelStyle),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: openLavaDonate,
                  icon: const Icon(Icons.bolt_rounded, size: 19),
                  label: const Text('Lava.top', style: _labelStyle),
                ),
              ],
            ),
          ),
        ]),
      ],
    );
  }
}

/// Раздел «О приложении»: обновления, версия и авторы, исходный код, связь.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: tr('about'),
      children: [
        SettingsGroup([
          SettingsRow(
            icon: Icons.system_update_rounded,
            title: tr('check_updates'),
            subtitle: tr('check_updates_sub'),
            trailing: const SettingsChevron(),
            onTap: () => checkForUpdates(context),
          ),
          SettingsRow(
            icon: Icons.info_rounded,
            title: tr('set_about_kadr'),
            subtitle: tr('set_about_kadr_sub'),
            trailing: const SettingsChevron(),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          SettingsRow(
            icon: Icons.code_rounded,
            title: tr('source_code'),
            subtitle: 'github.com/THET1ME-1/Kadr',
            trailing: const SettingsChevron(),
            onTap: openRepo,
          ),
          SettingsRow(
            icon: Icons.mail_outline_rounded,
            title: tr('contact_support'),
            subtitle: kSupportEmail,
            trailing: const SettingsChevron(),
            onTap: openSupportEmail,
          ),
        ]),
      ],
    );
  }
}
