import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/strings.dart';
import '../services/movie_repository.dart';
import '../services/notification_service.dart';
import '../services/store.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/update_sheet.dart';
import 'about_screen.dart';
import 'discover_tab.dart';
import 'dropped_screen.dart';
import 'library_tab.dart';
import 'lists_screen.dart';
import 'now_watching_screen.dart';
import 'series_screen.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';

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

  /// Мгновенный запрос — для локальной фильтрации библиотеки.
  String _query = '';

  /// Дебаунс-запрос — для сетевого поиска TMDB (Обзор/В кино); иначе набор
  /// текста на вкладках библиотеки дёргает поиск в скрытых лентах IndexedStack.
  String _netQuery = '';
  final _searchCtl = TextEditingController();
  Timer? _searchDebounce;
  LibraryViewMode _libMode = LibraryViewMode.list;

  @override
  void initState() {
    super.initState();
    _loadViewMode();
    // Фоновая дозагрузка русских названий и постеров + проверка новых серий.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      MovieRepository.instance.startEnrichSweep();
      await NotificationService.instance.init();
      await NotificationService.instance.requestPermission();
      // Не блокируем первый кадр — проверяем серии чуть позже.
      await Future<void>.delayed(const Duration(seconds: 2));
      await NotificationService.instance.checkNewEpisodes();
      _checkForUpdate();
    });
  }

  /// Тихая проверка обновления на GitHub при запуске: если версия новее —
  /// показываем нижнее меню обновления (как в ScoreMaster).
  Future<void> _checkForUpdate() async {
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final info = await UpdateService.checkForUpdate(current);
      if (!mounted || info == null) return;
      UpdateSheet.show(context, info, current);
    } catch (_) {/* молча */}
  }

  Future<void> _loadViewMode() async {
    final raw = await Store.instance.getString('libViewMode');
    LibraryViewMode? m;
    for (final e in LibraryViewMode.values) {
      if (e.name == raw) {
        m = e;
        break;
      }
    }
    if (m != null && mounted) setState(() => _libMode = m!);
  }

  void _setViewMode(LibraryViewMode m) {
    setState(() => _libMode = m);
    Store.instance.setString('libViewMode', m.name);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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
        onChanged: (v) {
          setState(() => _query = v);
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 350), () {
            if (mounted) setState(() => _netQuery = v);
          });
        },
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontFamily: AppTheme.bodyFont),
        decoration: InputDecoration(
          hintText: _index >= 2 ? tr('search_all_hint') : tr('search_hint'),
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchCtl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchCtl.clear();
                    setState(() {
                      _query = '';
                      _netQuery = '';
                    });
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

  IconData _viewModeIcon(LibraryViewMode m) => switch (m) {
        LibraryViewMode.list => Icons.view_agenda_rounded,
        LibraryViewMode.posters => Icons.grid_view_rounded,
        LibraryViewMode.banners => Icons.view_carousel_rounded,
      };

  Widget _viewModeButton(BuildContext context) {
    return PopupMenuButton<LibraryViewMode>(
      icon: Icon(_viewModeIcon(_libMode)),
      tooltip: tr('view_mode'),
      onSelected: _setViewMode,
      itemBuilder: (context) => [
        for (final m in LibraryViewMode.values)
          PopupMenuItem(
            value: m,
            child: Row(
              children: [
                Icon(_viewModeIcon(m),
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Text(tr(switch (m) {
                  LibraryViewMode.list => 'view_list',
                  LibraryViewMode.posters => 'view_posters',
                  LibraryViewMode.banners => 'view_banners',
                })),
                if (_libMode == m) ...[
                  const Spacer(),
                  Icon(Icons.check_rounded,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          ),
      ],
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
          if (onLibrary) _viewModeButton(context),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _KadrDrawer(
        onSelectTab: (i) => setState(() => _index = i),
      ),
      body: Column(
        children: [
          const _NewEpisodesBanner(),
          _searchField(context),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                LibraryTab(
                    mode: LibraryMode.watchlist,
                    query: _query,
                    viewMode: _libMode),
                LibraryTab(
                    mode: LibraryMode.watched,
                    query: _query,
                    viewMode: _libMode),
                DiscoverTab(mode: DiscoverMode.trending, query: _netQuery),
                DiscoverTab(mode: DiscoverMode.nowPlaying, query: _netQuery),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: onLibrary
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _index = 2),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('add')),
            )
          : null,
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

/// Красивый in-app баннер о новой серии: иконка, название, «×» для закрытия,
/// тап — открыть сериал. Появляется/уходит с плавной анимацией высоты.
class _NewEpisodesBanner extends StatelessWidget {
  const _NewEpisodesBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: NotificationService.instance,
      builder: (context, _) {
        final inbox = NotificationService.instance.inbox;
        return AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: inbox.isEmpty
              ? const SizedBox(width: double.infinity)
              : _card(context, scheme, inbox),
        );
      },
    );
  }

  Widget _card(
      BuildContext context, ColorScheme scheme, List<NewEpisode> inbox) {
    final e = inbox.first;
    final more = inbox.length - 1;
    return Padding(
      key: ValueKey(e.key),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final s = MovieRepository.instance.seriesById(e.tvShowId);
            NotificationService.instance.dismiss(e);
            if (s != null) {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SeriesScreen(series: s)));
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: scheme.tertiary, shape: BoxShape.circle),
                  child: Icon(Icons.live_tv_rounded,
                      color: scheme.onTertiary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        more > 0
                            ? trf('new_episodes_n', {'n': inbox.length})
                            : tr('notif_new_ep_title'),
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 14.5,
                            color: scheme.onTertiaryContainer),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${e.title} · ${e.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: scheme.onTertiaryContainer
                                .withValues(alpha: 0.85)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: scheme.onTertiaryContainer,
                  tooltip: tr('close'),
                  onPressed: () => NotificationService.instance.dismiss(e),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
              Expanded(
                child: Column(
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _drawerTile(context, Icons.home_rounded, tr('drawer_home'), () {
          Navigator.pop(context);
          onSelectTab(0);
        }),
        _drawerTile(context, Icons.search_rounded, tr('drawer_search'), () {
          Navigator.pop(context);
          onSelectTab(2);
        }),
        _drawerTile(context, Icons.live_tv_rounded, tr('now_watching'), () {
          Navigator.pop(context);
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NowWatchingScreen()));
        }),
        _drawerTile(context, Icons.insights_rounded, tr('drawer_stats'), () {
          Navigator.pop(context);
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const StatisticsScreen()));
        }),
        _drawerTile(context, Icons.list_alt_rounded, tr('drawer_lists'), () {
          Navigator.pop(context);
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ListsScreen()));
        }),
        _drawerTile(context, Icons.heart_broken_rounded, tr('drawer_dropped'),
            () {
          Navigator.pop(context);
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const DroppedScreen()));
        }),
        const Divider(indent: 28, endIndent: 28, height: 24),
        _drawerTile(context, Icons.settings_rounded, tr('drawer_settings'), () {
          Navigator.pop(context);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        }),
        _drawerTile(context, Icons.info_rounded, tr('drawer_about'), () {
          Navigator.pop(context);
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AboutScreen()));
        }),
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
