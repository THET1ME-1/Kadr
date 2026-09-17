import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../l10n/strings.dart';
import '../../services/app_prefs.dart';
import '../../services/backup_service.dart';
import '../../services/import_service.dart';
import '../../services/movie_repository.dart';
import '../../services/movie_source.dart';
import '../../services/store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/settings_kit.dart';
import '../auto_backup_screen.dart';
import '../scrobble_screen.dart';
import '../sync_screen.dart';
import '../tmdb_key_screen.dart';
import '../trakt_screen.dart';
import '../tvtime_import_screen.dart';
import 'settings_sheets.dart';

void _push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

/// Раздел «База фильмов»: источник данных и ключи доступа.
class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  static IconData _sourceIcon(MovieSource s) => switch (s) {
    MovieSource.tmdb => Icons.public_rounded,
    MovieSource.kinopoisk => Icons.movie_rounded,
    MovieSource.tvdb => Icons.live_tv_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final source = SourceController.instance;
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) => SettingsPage(
        title: tr('set_group_catalog'),
        children: [
          SettingsGroup([
            SettingsRow(
              icon: Icons.travel_explore_rounded,
              title: tr('movie_source'),
              subtitle: '${source.source.label} · ${source.source.note}',
              trailing: const SettingsChevron(),
              onTap: () => showChoiceSheet<MovieSource>(
                context,
                title: tr('movie_source'),
                selected: source.source,
                options: [
                  for (final s in MovieSource.values)
                    ChoiceOption(
                      value: s,
                      label: s.label,
                      subtitle: s.note,
                      icon: _sourceIcon(s),
                    ),
                ],
                onPick: (s) {
                  source.setSource(s);
                  // Дотянуть необогащённые фильмы через новый источник.
                  MovieRepository.instance.retryUnmatched();
                },
              ),
            ),
            SettingsRow(
              icon: Icons.vpn_key_rounded,
              title: tr('api_keys_title'),
              subtitle: tr('api_keys_sub'),
              trailing: const SettingsChevron(),
              onTap: () => _push(context, const TmdbKeyScreen()),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Раздел «Отметки просмотра»: серии по порядку, невышедшие серии, дневник.
class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  bool _sequential = true;
  bool _restrictUnaired = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = await Store.instance.getBool('sequentialEpisodes', def: true);
    final unaired = await Store.instance.getBool('restrictUnaired', def: true);
    if (mounted) {
      setState(() {
        _sequential = seq;
        _restrictUnaired = unaired;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPrefs.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => SettingsPage(
        title: tr('set_group_tracking'),
        children: [
          SettingsGroup([
            SettingsSwitchRow(
              icon: Icons.playlist_add_check_rounded,
              title: tr('seq_mode'),
              subtitle: tr('seq_mode_sub'),
              value: _sequential,
              onChanged: (v) {
                setState(() => _sequential = v);
                Store.instance.setBool('sequentialEpisodes', v);
              },
            ),
            SettingsSwitchRow(
              icon: Icons.event_busy_rounded,
              title: tr('restrict_unaired'),
              subtitle: tr('restrict_unaired_sub'),
              value: _restrictUnaired,
              onChanged: (v) {
                setState(() => _restrictUnaired = v);
                Store.instance.setBool('restrictUnaired', v);
              },
            ),
            SettingsSwitchRow(
              icon: Icons.auto_stories_rounded,
              title: tr('diary_settings_title'),
              subtitle: tr('diary_settings_sub'),
              value: prefs.diaryEnabled,
              onChanged: prefs.setDiaryEnabled,
            ),
          ]),
        ],
      ),
    );
  }
}

/// Раздел «Бэкап и синхронизация»: автобэкап, WebDAV, Trakt и копия в файл.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsPage(
      title: tr('set_group_sync'),
      children: [
        SettingsGroup([
          SettingsRow(
            icon: Icons.folder_zip_rounded,
            title: tr('auto_backup'),
            subtitle: tr('auto_backup_sub'),
            trailing: const SettingsChevron(),
            onTap: () => _push(context, const AutoBackupScreen()),
          ),
          SettingsRow(
            icon: Icons.cloud_sync_rounded,
            title: tr('sync_webdav'),
            subtitle: tr('sync_webdav_sub'),
            trailing: const SettingsChevron(),
            onTap: () => _push(context, const SyncScreen()),
          ),
          SettingsRow(
            icon: Icons.sync_rounded,
            title: 'Trakt',
            subtitle: tr('trakt_sub'),
            trailing: const SettingsChevron(),
            onTap: () => _push(context, const TraktScreen()),
          ),
        ]),
        SettingsSection(tr('set_backup_file'), icon: Icons.backup_rounded),
        SettingsGroup([
          SettingsRow(
            icon: Icons.ios_share_rounded,
            title: tr('create_backup'),
            subtitle: tr('create_backup_sub'),
            trailing: const SettingsChevron(),
            onTap: BackupService.exportAndShare,
          ),
          SettingsRow(
            icon: Icons.file_open_rounded,
            title: tr('restore_backup'),
            subtitle: tr('restore_backup_sub'),
            trailing: const SettingsChevron(),
            onTap: () => _restore(context),
          ),
          SettingsRow(
            icon: Icons.move_to_inbox_rounded,
            title: tr('import_tracker'),
            subtitle: tr('import_tracker_sub'),
            trailing: const SettingsChevron(),
            onTap: () => _importCsv(context),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
          child: Text(
            tr('backup_hint'),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _restore(BuildContext context) async {
    final ok = await BackupService.importFromFile();
    if (context.mounted) {
      showSettingsSnack(
        context,
        tr(ok ? 'backup_import_ok' : 'backup_import_fail'),
      );
    }
  }

  Future<void> _importCsv(BuildContext context) async {
    final res = await ImportService.pickAndImport();
    if (!context.mounted) return;
    showSettingsSnack(
      context,
      res.ok
          ? trf('import_tracker_ok', {'a': res.added, 'u': res.updated})
          : tr('import_tracker_fail'),
    );
  }
}

/// Раздел «Импорт и автоотметки»: TV Time и плееры.
class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  /// Фирменный жёлтый TV Time: «беженцы» оттуда узнают строку сразу.
  static const Color _tvTimeGold = Color(0xFFFFD403);

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: tr('set_group_import'),
      children: [
        SettingsGroup([
          SettingsRow(
            icon: Icons.move_to_inbox_rounded,
            title: tr('tvtime_title'),
            subtitle: tr('tvtime_settings_sub'),
            iconBg: _tvTimeGold,
            iconFg: const Color(0xFF1B1B1B),
            trailing: const SettingsChevron(),
            onTap: () => _push(context, const TvTimeImportScreen()),
          ),
          SettingsRow(
            icon: Icons.sensors_rounded,
            title: tr('set_scrobble'),
            subtitle: tr('set_scrobble_sub'),
            trailing: const SettingsChevron(),
            onTap: () => _push(context, const ScrobbleScreen()),
          ),
        ]),
      ],
    );
  }
}

/// Раздел «Память и сброс»: кэш картинок и полное удаление данных.
class StoragePage extends StatelessWidget {
  const StoragePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SettingsPage(
      title: tr('set_group_storage'),
      children: [
        SettingsGroup([
          SettingsRow(
            icon: Icons.cleaning_services_rounded,
            title: tr('clear_image_cache'),
            subtitle: tr('clear_image_cache_sub'),
            trailing: const SettingsChevron(),
            onTap: () => _clearImageCache(context),
          ),
        ]),
        const SizedBox(height: 24),
        SettingsGroup([
          SettingsRow(
            icon: Icons.delete_forever_rounded,
            title: tr('clear_all_data'),
            subtitle: tr('clear_all_data_sub'),
            iconBg: scheme.errorContainer,
            iconFg: scheme.onErrorContainer,
            titleColor: scheme.error,
            onTap: () => _confirmClearAll(context),
          ),
        ]),
      ],
    );
  }

  /// Скачанные постеры, кадры и аватары перекачаются при следующем показе.
  Future<void> _clearImageCache(BuildContext context) async {
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (context.mounted) showSettingsSnack(context, tr('cache_cleared'));
  }

  /// Полная очистка личных данных, без возврата.
  void _confirmClearAll(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, color: scheme.error, size: 32),
        title: Text(
          tr('clear_all_title'),
          style: const TextStyle(fontFamily: AppTheme.displayFont),
        ),
        content: Text(
          tr('clear_all_body'),
          style: const TextStyle(fontFamily: AppTheme.bodyFont),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              await MovieRepository.instance.clearAll();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(tr('clear_all_done')),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: Text(tr('clear')),
          ),
        ],
      ),
    );
  }
}
