import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../services/api_keys.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

/// Экран ввода ПЕРСОНАЛЬНОГО ключа TMDB (и опционально kinopoisk.dev).
/// [gate] = true — первый запуск (после сохранения ведёт в приложение, назад
/// нельзя); false — правка из настроек (сохраняет и закрывается).
class TmdbKeyScreen extends StatefulWidget {
  final bool gate;
  const TmdbKeyScreen({super.key, this.gate = false});

  @override
  State<TmdbKeyScreen> createState() => _TmdbKeyScreenState();
}

class _TmdbKeyScreenState extends State<TmdbKeyScreen> {
  late final TextEditingController _tmdb =
      TextEditingController(text: ApiKeys.tmdbToken);
  late final TextEditingController _kp =
      TextEditingController(text: ApiKeys.kinopoiskKey);
  bool _busy = false;

  static final Uri _tmdbApiUrl =
      Uri.parse('https://www.themoviedb.org/settings/api');

  @override
  void dispose() {
    _tmdb.dispose();
    _kp.dispose();
    super.dispose();
  }

  Future<void> _openTmdb() async {
    if (!await launchUrl(_tmdbApiUrl, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(trf('open_link_fail', {'url': '$_tmdbApiUrl'}))));
      }
    }
  }

  void _snack(String s) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(s), behavior: SnackBarBehavior.floating));

  Future<void> _save() async {
    final token = _tmdb.text.trim();
    if (token.isEmpty) {
      _snack(tr('tmdb_key_empty'));
      return;
    }
    setState(() => _busy = true);
    final ok = await TmdbService.tokenWorks(token);
    if (!mounted) return;
    if (ok == false) {
      setState(() => _busy = false);
      _snack(tr('tmdb_key_invalid'));
      return;
    }
    // ok == true (валиден) или null (не проверили — офлайн): сохраняем.
    await ApiKeys.setTmdbToken(token);
    await ApiKeys.setKinopoiskKey(_kp.text.trim());
    if (!mounted) return;
    if (widget.gate) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeShell()));
    } else {
      Navigator.of(context).pop();
      _snack(ok == null ? tr('tmdb_key_offline') : tr('tmdb_key_saved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // На первом запуске уйти без ключа нельзя (без него приложение не работает).
      canPop: !widget.gate,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.gate,
          title: Text(tr('tmdb_key_title')),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.vpn_key_rounded,
                      color: Colors.white.withValues(alpha: 0.95), size: 36),
                  const SizedBox(height: 12),
                  Text(tr('tmdb_key_intro_title'),
                      style: const TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(tr('tmdb_key_intro'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13.5,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.92))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _step(scheme, '1', tr('tmdb_key_step1')),
            _step(scheme, '2', tr('tmdb_key_step2')),
            _step(scheme, '3', tr('tmdb_key_step3')),
            _step(scheme, '4', tr('tmdb_key_step4')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openTmdb,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(tr('tmdb_key_open')),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _tmdb,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(
                  fontFamily: AppTheme.bodyFont, fontSize: 13, height: 1.3),
              decoration: InputDecoration(
                labelText: tr('tmdb_key_field'),
                hintText: tr('tmdb_key_hint'),
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  tooltip: tr('paste'),
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null) _tmdb.text = d!.text!.trim();
                  },
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _kp,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 13),
              decoration: InputDecoration(
                labelText: tr('kinopoisk_key_field'),
                hintText: tr('kinopoisk_key_hint'),
                prefixIcon: const Icon(Icons.tune_rounded),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2))
                    : Text(
                        widget.gate
                            ? tr('tmdb_key_save_go')
                            : tr('save'),
                        style: const TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(ColorScheme scheme, String n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Text(n,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: scheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(text,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 14,
                        height: 1.35,
                        color: scheme.onSurface)),
              ),
            ),
          ],
        ),
      );
}
