import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/auto_backup_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Настройки локальных автобекапов: папка, частота, «создать сейчас».
class AutoBackupScreen extends StatelessWidget {
  const AutoBackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = AutoBackupService.instance;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('auto_backup'))),
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) {
          final last = svc.lastBackup;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(tr('auto_backup_hint'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13,
                      height: 1.4,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              _card(scheme, [
                SwitchListTile(
                  value: svc.enabled,
                  onChanged: (v) async {
                    final ok = await svc.setEnabled(v);
                    if (!context.mounted) return;
                    if (v && !ok) {
                      _snack(context, tr('auto_backup_need_folder'));
                    }
                  },
                  title: Text(tr('auto_backup_enable'),
                      style: const TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600)),
                  secondary: Icon(Icons.folder_zip_rounded,
                      color: scheme.primary),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      Icon(Icons.folder_rounded, color: scheme.onSurfaceVariant),
                  title: Text(tr('auto_backup_folder'),
                      style: const TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    svc.folder ?? tr('auto_backup_no_folder'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final f = await svc.chooseFolder();
                      if (!context.mounted) return;
                      if (f == null && svc.lastError == 'not_writable') {
                        _snack(context, tr('auto_backup_not_writable'));
                      }
                    },
                    child: Text(tr('choose')),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              Text(tr('auto_backup_when'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: scheme.primary)),
              const SizedBox(height: 6),
              _card(scheme, [
                _modeTile(scheme, svc, AutoBackupMode.onChange,
                    tr('auto_backup_on_change'), tr('auto_backup_on_change_sub')),
                const Divider(height: 1),
                _modeTile(scheme, svc, AutoBackupMode.daily,
                    tr('auto_backup_daily'), tr('auto_backup_daily_sub')),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: svc.folder == null
                      ? null
                      : () async {
                          final ok = await svc.backupNow();
                          if (!context.mounted) return;
                          _snack(
                              context,
                              ok
                                  ? tr('auto_backup_done')
                                  : tr('auto_backup_failed'));
                        },
                  icon: const Icon(Icons.save_rounded),
                  label: Text(tr('auto_backup_now')),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  last == null
                      ? tr('auto_backup_never')
                      : trf('auto_backup_last', {'when': dateExactWithTime(last)}),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _modeTile(ColorScheme scheme, AutoBackupService svc,
      AutoBackupMode mode, String title, String sub) {
    final selected = svc.mode == mode;
    return ListTile(
      leading: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          color: selected ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(title,
          style: const TextStyle(
              fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
      subtitle: Text(sub),
      onTap: () => svc.setMode(mode),
    );
  }

  Widget _card(ColorScheme scheme, List<Widget> children) => Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating, content: Text(msg)));
  }
}
