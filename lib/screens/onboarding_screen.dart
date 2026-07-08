import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api_keys.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';
import 'tmdb_key_screen.dart';

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
      ];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await Store.instance.setBool('onboardingDone', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
          builder: (_) => ApiKeys.hasTmdb
              ? const HomeShell()
              : const TmdbKeyScreen(gate: true)),
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
                itemBuilder: (context, i) => _pageView(scheme, pages[i]),
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
}

class _Page {
  final IconData icon;
  final String title;
  final String sub;
  _Page(this.icon, this.title, this.sub);
}
