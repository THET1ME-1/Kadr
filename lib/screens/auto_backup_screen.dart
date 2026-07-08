import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/auto_backup_service.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Настройки локальных автобекапов: папка, частота, «создать сейчас» и
/// восстановление из копии (в т.ч. подсказка на свежей установке).
class AutoBackupScreen extends StatefulWidget {
  const AutoBackupScreen({super.key});

  @override
  State<AutoBackupScreen> createState() => _AutoBackupScreenState();
}

class _AutoBackupScreenState extends State<AutoBackupScreen> {
  final _svc = AutoBackupService.instance;
  List<BackupFile> _backups = const [];
  bool _promptedRestore = false;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    final list = await _svc.listBackups();
    if (!mounted) return;
    setState(() => _backups = list);
    // Свежая установка (пустая библиотека) + есть копии в папке → предлагаем
    // восстановить последнюю.
    if (!_promptedRestore &&
        list.isNotEmpty &&
        MovieRepository.instance.movies.isEmpty) {
      _promptedRestore = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _offerRestoreLatest(list);
      });
    }
  }

  Future<void> _chooseFolder() async {
    final f = await _svc.chooseFolder();
    if (!mounted) return;
    if (f == null) {
      if (_svc.lastError == 'not_writable') {
        _snack(tr('auto_backup_not_writable'));
      }
      return;
    }
    _promptedRestore = false;
    await _loadBackups();
  }

  Future<void> _offerRestoreLatest(List<BackupFile> list) async {
    final latest = list.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('restore_found_title')),
        content: Text(trf('restore_found_body',
            {'n': list.length, 'when': dateExactWithTime(latest.date)})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('restore_btn'))),
        ],
      ),
    );
    if (ok == true) await _doRestore(latest);
  }

  Future<void> _confirmRestore(BackupFile b) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('restore_confirm_title')),
        content: Text(trf(
            'restore_confirm_body', {'when': dateExactWithTime(b.date)})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary),
            child: Text(tr('restore_btn')),
          ),
        ],
      ),
    );
    if (ok == true) await _doRestore(b);
  }

  Future<void> _doRestore(BackupFile b) async {
    final done = await _svc.restore(b.file);
    if (!mounted) return;
    _snack(done ? tr('restore_done') : tr('restore_failed'));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('auto_backup'))),
      body: ListenableBuilder(
        listenable: _svc,
        builder: (context, _) {
          final last = _svc.lastBackup;
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
                  value: _svc.enabled,
                  onChanged: (v) async {
                    final ok = await _svc.setEnabled(v);
                    if (!context.mounted) return;
                    if (v && !ok) {
                      _snack(tr('auto_backup_need_folder'));
                    } else if (v && ok) {
                      _loadBackups();
                    }
                  },
                  title: Text(tr('auto_backup_enable'),
                      style: const TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600)),
                  secondary:
                      Icon(Icons.folder_zip_rounded, color: scheme.primary),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.folder_rounded,
                      color: scheme.onSurfaceVariant),
                  title: Text(tr('auto_backup_folder'),
                      style: const TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _svc.folder ?? tr('auto_backup_no_folder'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  trailing: TextButton(
                      onPressed: _chooseFolder, child: Text(tr('choose'))),
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
                _modeTile(scheme, AutoBackupMode.onChange,
                    tr('auto_backup_on_change'), tr('auto_backup_on_change_sub')),
                const Divider(height: 1),
                _modeTile(scheme, AutoBackupMode.daily, tr('auto_backup_daily'),
                    tr('auto_backup_daily_sub')),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _svc.folder == null
                      ? null
                      : () async {
                          final ok = await _svc.backupNow();
                          if (!context.mounted) return;
                          _snack(ok
                              ? tr('auto_backup_done')
                              : tr('auto_backup_failed'));
                          _loadBackups();
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
                      : trf('auto_backup_last',
                          {'when': dateExactWithTime(last)}),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant),
                ),
              ),
              // ------------------------- восстановление -------------------------
              if (_svc.folder != null) ...[
                const SizedBox(height: 24),
                Text(tr('restore_title'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: scheme.primary)),
                const SizedBox(height: 4),
                Text(tr('restore_hint'),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                if (_backups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(tr('restore_none'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: scheme.onSurfaceVariant)),
                  )
                else
                  _card(
                    scheme,
                    [
                      for (var i = 0; i < _backups.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.restore_rounded,
                              color: scheme.onSurfaceVariant),
                          title: Text(dateExactWithTime(_backups[i].date),
                              style: const TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${(_backups[i].size / 1024).round()} КБ',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                          trailing: TextButton(
                            onPressed: () => _confirmRestore(_backups[i]),
                            child: Text(tr('restore_btn')),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _modeTile(ColorScheme scheme, AutoBackupMode mode, String title,
      String sub) {
    final selected = _svc.mode == mode;
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
      onTap: () => _svc.setMode(mode),
    );
  }

  Widget _card(ColorScheme scheme, List<Widget> children) => Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating, content: Text(msg)));
  }
}
