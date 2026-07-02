import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import 'library_tab.dart';
import 'settings_screen.dart';

/// Главная оболочка: четыре вкладки снизу (как в референсе — Буду смотреть /
/// Просмотрено / Обзор / В кино) + выезжающее меню. Содержимое вкладок пока
/// заглушки: экраны наполняются на этапе интеграции TMDB (см. PLAN.md).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  String _query = '';
  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Фоновая дозагрузка русских названий и постеров.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MovieRepository.instance.startEnrichSweep();
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// Поле поиска под шапкой — на всю ширину, со скруглёнными краями.
  Widget _searchField(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: TextField(
        controller: _searchCtl,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontFamily: AppTheme.bodyFont),
        decoration: InputDecoration(
          hintText: tr('search_hint'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchCtl.clear();
                    setState(() => _query = '');
                    FocusScope.of(context).unfocus();
                  },
                ),
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
        ),
      ),
    );
  }

  List<_Tab> get _tabs => [
        _Tab(tr('nav_watchlist'), Icons.bookmark_border_rounded,
            Icons.bookmark_rounded, Icons.playlist_add_rounded),
        _Tab(tr('nav_watched'), Icons.check_circle_outline_rounded,
            Icons.check_circle_rounded, Icons.visibility_rounded),
        _Tab(tr('nav_discover'), Icons.explore_outlined, Icons.explore_rounded,
            Icons.travel_explore_rounded),
        _Tab(tr('nav_cinema'), Icons.local_movies_outlined,
            Icons.local_movies_rounded, Icons.theaters_rounded),
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final onLibrary = _index == 0 || _index == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(tabs[_index].title),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_agenda_outlined),
            tooltip: 'Стиль',
            onPressed: () {},
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _KadrDrawer(
        onSelectTab: (i) => setState(() => _index = i),
      ),
      body: Column(
        children: [
          if (onLibrary) _searchField(context),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                LibraryTab(mode: LibraryMode.watchlist, query: _query),
                LibraryTab(mode: LibraryMode.watched, query: _query),
                EmptyState(
                    icon: tabs[2].emptyIcon,
                    title: tabs[2].title,
                    subtitle: tr('soon_sub')),
                EmptyState(
                    icon: tabs[3].emptyIcon,
                    title: tabs[3].title,
                    subtitle: tr('soon_sub')),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('add')),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.title,
            ),
        ],
      ),
    );
  }
}

class _Tab {
  final String title;
  final IconData icon;
  final IconData selectedIcon;
  final IconData emptyIcon;
  const _Tab(this.title, this.icon, this.selectedIcon, this.emptyIcon);
}

/// Выезжающее меню в духе референса: шапка с именем приложения, разделы и
/// настройки.
class _KadrDrawer extends StatelessWidget {
  final ValueChanged<int> onSelectTab;
  const _KadrDrawer({required this.onSelectTab});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationDrawer(
      onDestinationSelected: (_) {},
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.local_movies_rounded,
                    color: scheme.onPrimaryContainer, size: 30),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('app_name'),
                    style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    tr('about_sub'),
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _drawerTile(context, Icons.home_rounded, tr('drawer_home'), () {
          Navigator.pop(context);
          onSelectTab(0);
        }),
        _drawerTile(context, Icons.search_rounded, tr('drawer_search'),
            () => Navigator.pop(context)),
        _drawerTile(context, Icons.insights_rounded, tr('drawer_stats'),
            () => Navigator.pop(context)),
        _drawerTile(context, Icons.list_alt_rounded, tr('drawer_lists'),
            () => Navigator.pop(context)),
        const Divider(indent: 28, endIndent: 28, height: 24),
        _drawerTile(context, Icons.settings_rounded, tr('drawer_settings'), () {
          Navigator.pop(context);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        }),
        _drawerTile(context, Icons.info_rounded, tr('drawer_about'),
            () => Navigator.pop(context)),
      ],
    );
  }

  Widget _drawerTile(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label,
            style: const TextStyle(
                fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        onTap: onTap,
      ),
    );
  }
}
