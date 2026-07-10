import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../services/trakt/trakt_controller.dart';
import '../theme/app_theme.dart';

/// Экран интеграции с Trakt: вход по коду устройства, синхронизация фильмов
/// (Kadr — источник правды), предупреждение о лимитах/VIP.
class TraktScreen extends StatefulWidget {
  const TraktScreen({super.key});

  @override
  State<TraktScreen> createState() => _TraktScreenState();
}

class _TraktScreenState extends State<TraktScreen> {
  final _t = TraktController.instance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Trakt')),
      body: ListenableBuilder(
        listenable: _t,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _card(scheme.primaryContainer, scheme.onPrimaryContainer,
                Icons.sync_rounded, tr('trakt_intro')),
            const SizedBox(height: 12),
            // Предупреждение о лимитах бесплатного аккаунта и Trakt VIP.
            _card(scheme.tertiaryContainer, scheme.onTertiaryContainer,
                Icons.info_outline_rounded, tr('trakt_limits_note')),
            const SizedBox(height: 20),
            if (_t.state == TraktState.waitingForUser && _t.deviceCode != null)
              _activate(scheme)
            else if (!_t.connected)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _t.connect,
                  icon: const Icon(Icons.link_rounded),
                  label: Text(tr('trakt_connect')),
                ),
              )
            else
              _connected(scheme),
            if (_t.statusKey != null) ...[
              const SizedBox(height: 14),
              Center(
                child: Text(
                  _statusText(_t),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            const SizedBox(height: 28),
            Center(
              child: Text(tr('trakt_powered'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7))),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(TraktController t) {
    final base = tr(t.statusKey!);
    if (t.statusKey == 'trakt_done') {
      return '$base · ↑${t.lastPushed} ↓${t.lastPulled}';
    }
    return base;
  }

  // Экран ввода кода (device flow).
  Widget _activate(ColorScheme scheme) {
    final code = _t.deviceCode!;
    return Column(
      children: [
        Text(tr('trakt_activate'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                height: 1.4,
                color: scheme.onSurface)),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => Clipboard.setData(ClipboardData(text: code.userCode)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18)),
            child: Text(code.userCode,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 34,
                    letterSpacing: 4,
                    color: scheme.primary)),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(code.verificationUrl),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(tr('trakt_open_activate')),
          ),
        ),
        const SizedBox(height: 10),
        const Center(child: SizedBox(
            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))),
        const SizedBox(height: 10),
        TextButton(onPressed: _t.cancelLogin, child: Text(tr('cancel'))),
      ],
    );
  }

  // Экран подключённого состояния: кнопки синка.
  Widget _connected(ColorScheme scheme) {
    final busy = _t.busy;
    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(tr('trakt_connected'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: busy ? null : _t.pushToTrakt,
            icon: const Icon(Icons.upload_rounded, size: 18),
            label: Text(tr('trakt_push')),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: busy ? null : _t.pullFromTrakt,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(tr('trakt_pull')),
          ),
        ),
        if (busy) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _t.syncRatings,
          onChanged: busy ? null : _t.setSyncRatings,
          title: Text(tr('trakt_sync_ratings')),
          subtitle: Text(tr('trakt_ratings_note'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : _t.disconnect,
            icon: const Icon(Icons.link_off_rounded, size: 18),
            label: Text(tr('trakt_disconnect')),
          ),
        ),
      ],
    );
  }

  Widget _card(Color bg, Color fg, IconData icon, String text) => Container(
        padding: const EdgeInsets.all(16),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13.5,
                      height: 1.4,
                      color: fg)),
            ),
          ],
        ),
      );
}
