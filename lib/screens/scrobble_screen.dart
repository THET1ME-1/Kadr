import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../services/scrobble_service.dart';
import '../services/social/social_controller.dart';
import '../theme/app_theme.dart';
import 'social/auth_screen.dart';

/// Скробблинг Plex/Jellyfin/Kodi (Material 3): смотри в своём медиасервере —
/// Kadr сам отмечает просмотры. Показывает персональный URL вебхука + инструкцию.
class ScrobbleScreen extends StatefulWidget {
  const ScrobbleScreen({super.key});

  @override
  State<ScrobbleScreen> createState() => _ScrobbleScreenState();
}

class _ScrobbleScreenState extends State<ScrobbleScreen> {
  String? _url;
  bool _loadingUrl = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    if (!SocialController.instance.isLoggedIn) return;
    setState(() => _loadingUrl = true);
    try {
      final u = await ScrobbleService.instance.webhookUrl();
      if (mounted) setState(() => _url = u);
    } catch (_) {
      // оставим null — покажем ошибку загрузки в UI
    } finally {
      if (mounted) setState(() => _loadingUrl = false);
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
        SnackBar(content: Text(s), behavior: SnackBarBehavior.floating));

  Future<void> _copy() async {
    if (_url == null) return;
    await Clipboard.setData(ClipboardData(text: _url!));
    if (mounted) _snack(tr('scrobble_copied'));
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    try {
      final n = await ScrobbleService.instance.drain();
      if (mounted) _snack(trf('scrobble_checked', {'n': n}));
    } catch (_) {
      if (mounted) _snack(tr('scrobble_check_fail'));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('scrobble_title'))),
      body: ListenableBuilder(
        listenable: SocialController.instance,
        builder: (context, _) => SocialController.instance.isLoggedIn
            ? _content(context)
            : _loggedOut(context),
      ),
    );
  }

  Widget _loggedOut(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sensors_rounded,
                  color: scheme.onPrimaryContainer, size: 34),
              const SizedBox(height: 12),
              Text(tr('scrobble_need_account'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: scheme.onPrimaryContainer)),
              const SizedBox(height: 8),
              Text(tr('scrobble_need_account_sub'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13.5,
                      height: 1.4,
                      color: scheme.onPrimaryContainer
                          .withValues(alpha: 0.9))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuthScreen())),
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15)),
          icon: const Icon(Icons.login_rounded),
          label: Text(tr('profile_login_cta')),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // Интро.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sensors_rounded, color: scheme.primary, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Text(tr('scrobble_intro'),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 14,
                        height: 1.45,
                        color: scheme.onSurface)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Включатель.
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
          ),
          child: SwitchListTile(
            value: ScrobbleService.instance.enabled,
            onChanged: (v) {
              ScrobbleService.instance.setEnabled(v);
              setState(() {});
            },
            secondary: Icon(Icons.sync_rounded, color: scheme.onSurfaceVariant),
            title: Text(tr('scrobble_enable'),
                style: const TextStyle(
                    fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
            subtitle: Text(tr('scrobble_enable_sub'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12,
                    color: scheme.onSurfaceVariant)),
          ),
        ),
        const SizedBox(height: 16),
        // URL вебхука.
        Text(tr('scrobble_url_label'),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: scheme.onSurface)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: _loadingUrl
                    ? const SizedBox(
                        height: 20,
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))))
                    : SelectableText(
                        _url ?? tr('scrobble_url_error'),
                        maxLines: 3,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 12.5,
                            color: _url == null
                                ? scheme.error
                                : scheme.onSurface),
                      ),
              ),
              IconButton(
                tooltip: tr('scrobble_copy'),
                onPressed: _url == null ? null : _copy,
                icon: Icon(Icons.copy_rounded, color: scheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Инструкции.
        _guideCard(scheme, 'Plex', Icons.play_circle_outline_rounded,
            tr('scrobble_plex_steps')),
        const SizedBox(height: 12),
        _guideCard(scheme, 'Jellyfin', Icons.play_circle_outline_rounded,
            tr('scrobble_jellyfin_steps')),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: _checking ? null : _checkNow,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            label: Text(tr('scrobble_check_now')),
          ),
        ),
      ],
    );
  }

  Widget _guideCard(
      ColorScheme scheme, String name, IconData icon, String steps) {
    return Container(
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
              Icon(icon, color: scheme.primary, size: 22),
              const SizedBox(width: 10),
              Text(name,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 10),
          Text(steps,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
