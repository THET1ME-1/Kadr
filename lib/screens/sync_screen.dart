import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/sync/webdav_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Экран синхронизации между устройствами через WebDAV (Nextcloud / Яндекс.Диск
/// / ownCloud). Двусторонний синк с умным слиянием — данные на сервере
/// пользователя, ничего добавленного не теряется.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _wd = WebdavService.instance;
  final _urlCtl = TextEditingController();
  final _userCtl = TextEditingController();
  final _passCtl = TextEditingController();

  bool _loading = true;
  bool _configured = false;
  bool _auto = true;
  bool _busy = false;
  DateTime? _lastAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configured = await _wd.isConfigured();
    _urlCtl.text = (await _wd.url()) ?? '';
    _userCtl.text = (await _wd.user()) ?? '';
    _auto = await _wd.autoEnabled();
    _lastAt = await _wd.lastSyncAt();
    if (mounted) {
      setState(() {
        _configured = configured;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    _userCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _connect() async {
    if (_urlCtl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    await _wd.saveConfig(
      url: _urlCtl.text,
      user: _userCtl.text,
      password: _passCtl.text,
    );
    try {
      await _wd.testConnection();
      if (!mounted) return;
      setState(() {
        _configured = true;
        _busy = false;
      });
      _snack(tr('sync_connected'));
      _syncNow();
    } catch (e) {
      await _wd.forget();
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(tr('sync_connect_failed'));
    }
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final stats = await _wd.sync();
      _lastAt = await _wd.lastSyncAt();
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(stats.changed
          ? trf('sync_done', {
              'a': stats.addedMovies + stats.addedSeries,
              'm': stats.mergedMovies + stats.mergedSeries
            })
          : tr('sync_no_changes'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(tr('sync_error'));
    }
  }

  Future<void> _forget() async {
    await _wd.forget();
    if (!mounted) return;
    _passCtl.clear();
    setState(() {
      _configured = false;
      _lastAt = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('sync_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _intro(scheme),
                const SizedBox(height: 16),
                if (_configured) ..._connectedView(scheme) else _form(scheme),
              ],
            ),
    );
  }

  Widget _intro(ColorScheme scheme) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_sync_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Text(tr('sync_intro'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSecondaryContainer)),
            ),
          ],
        ),
      );

  Widget _form(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(_urlCtl, tr('sync_url'), tr('sync_url_hint'),
            keyboard: TextInputType.url),
        const SizedBox(height: 12),
        _field(_userCtl, tr('sync_user'), ''),
        const SizedBox(height: 12),
        _field(_passCtl, tr('sync_pass'), '', obscure: true),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Icon(Icons.link_rounded),
          label: Text(tr('sync_connect')),
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctl, String label, String hint,
      {bool obscure = false, TextInputType? keyboard}) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: ctl,
      obscureText: obscure,
      keyboardType: keyboard,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontFamily: AppTheme.bodyFont),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint.isEmpty ? null : hint,
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  List<Widget> _connectedView(ColorScheme scheme) {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_urlCtl.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: scheme.onSurface)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _lastAt == null
                  ? tr('sync_never')
                  : trf('sync_last', {'t': dateTimeShort(_lastAt!)}),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _syncNow,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5))
            : const Icon(Icons.sync_rounded),
        label: Text(tr('sync_now')),
        style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16)),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        value: _auto,
        onChanged: (v) {
          setState(() => _auto = v);
          _wd.setAutoEnabled(v);
        },
        title: Text(tr('sync_auto'),
            style: const TextStyle(
                fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
        subtitle: Text(tr('sync_auto_sub')),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _busy ? null : _forget,
        icon: Icon(Icons.link_off_rounded, color: scheme.error),
        label: Text(tr('sync_forget'),
            style: TextStyle(color: scheme.error)),
      ),
    ];
  }
}
