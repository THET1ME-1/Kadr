import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api_keys.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';
import 'tmdb_key_screen.dart';
import 'tvtime_import_screen.dart';

/// Онбординг первого запуска (Material 3 Expressive): страницы с крупными
/// иконками, пружинные переходы, живой индикатор.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctl = PageController();
  int _page = 0;

  List<_Page> get _pages => [
        _Page(Icons.local_movies_rounded, tr('ob1_title'), tr('ob1_sub')),
        _Page(Icons.star_rounded, tr('ob2_title'), tr('ob2_sub')),
        _Page(Icons.translate_rounded, tr('ob3_title'), tr('ob3_sub')),
        _Page(Icons.insights_rounded, tr('ob4_title'), tr('ob4_sub')),
        _Page(Icons.move_to_inbox_rounded, tr('ob5_title'), tr('ob5_sub'),
            tvtime: true),
      ];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await Store.instance.setBool('onboardingDone', true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => ApiKeys.canEnter
              ? const HomeShell()
              : const TmdbKeyScreen(gate: true)),
      (r) => false,
    );
  }

  /// Открыть перенос из TV Time. После импорта «Продолжить» ведёт дальше по
  /// онбордингу (к вводу ключа TMDB) через [_finish].
  void _openImport() {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => TvTimeImportScreen(onContinue: _finish)),
    );
  }

  void _nextOrFinish() {
    if (_page == _pages.length - 1) {
      _finish();
    } else {
      _ctl.nextPage(
          duration: const Duration(milliseconds: 420),
          curve: AppTheme.emphasized);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = _pages;
    final last = _page == pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                child: TextButton(
                  onPressed: last ? null : _finish,
                  child: Text(tr('skip')),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: pages.length,
                itemBuilder: (context, i) => pages[i].tvtime
                    ? _migratePage(scheme, pages[i])
                    : _pageView(scheme, pages[i]),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: AppTheme.emphasized,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? scheme.primary
                          : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _nextOrFinish,
                  child: Text(tr(last ? 'start' : 'next')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageView(ColorScheme scheme, _Page p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(p.title),
            tween: Tween(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: AppTheme.emphasizedDecelerate,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(52),
              ),
              child: Icon(p.icon, size: 84, color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            p.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            p.sub,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 16,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Страница-перенос из TV Time: логотип TV Time и кнопка импорта.
  Widget _migratePage(ColorScheme scheme, _Page p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 168,
            height: 168,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(52),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1B1B1B),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Image.asset('assets/tvtime_logo.png', width: 96),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            p.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              letterSpacing: -0.5,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            p.sub,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 16,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.tonalIcon(
            onPressed: _openImport,
            style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
            icon: const Icon(Icons.move_to_inbox_rounded, size: 20),
            label: Text(tr('tvtime_pick'),
                style: const TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _Page {
  final IconData icon;
  final String title;
  final String sub;
  final bool tvtime;
  _Page(this.icon, this.title, this.sub, {this.tvtime = false});
}
