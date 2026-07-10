import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/app_prefs.dart';

/// Иконка пункта меню (используется и в drawer, и в экране настройки).
IconData drawerItemIcon(DrawerItem i) => switch (i) {
      DrawerItem.search => Icons.search_rounded,
      DrawerItem.nowWatching => Icons.live_tv_rounded,
      DrawerItem.activity => Icons.dynamic_feed_rounded,
      DrawerItem.roulette => Icons.casino_rounded,
      DrawerItem.forYou => Icons.auto_awesome_rounded,
      DrawerItem.schedule => Icons.calendar_month_rounded,
      DrawerItem.news => Icons.newspaper_rounded,
      DrawerItem.stats => Icons.insights_rounded,
      DrawerItem.lists => Icons.list_alt_rounded,
      DrawerItem.dropped => Icons.heart_broken_rounded,
    };

/// Ключ локализованной подписи пункта меню.
String drawerItemLabelKey(DrawerItem i) => switch (i) {
      DrawerItem.search => 'drawer_search',
      DrawerItem.nowWatching => 'now_watching',
      DrawerItem.activity => 'activity_title',
      DrawerItem.roulette => 'roulette_title',
      DrawerItem.forYou => 'for_you_title',
      DrawerItem.schedule => 'drawer_schedule',
      DrawerItem.news => 'drawer_news',
      DrawerItem.stats => 'drawer_stats',
      DrawerItem.lists => 'drawer_lists',
      DrawerItem.dropped => 'drawer_dropped',
    };

/// Настройка бокового меню: перетаскивание для порядка + тумблер видимости.
class DrawerCustomizeScreen extends StatelessWidget {
  const DrawerCustomizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPrefs.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('drawer_customize'))),
      body: ListenableBuilder(
        listenable: p,
        builder: (context, _) {
          final order = p.drawerOrder;
          final scheme = Theme.of(context).colorScheme;
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            itemCount: order.length,
            onReorder: (oldI, newI) {
              final list = List.of(order);
              if (newI > oldI) newI -= 1;
              list.insert(newI, list.removeAt(oldI));
              p.setDrawerOrder(list);
            },
            itemBuilder: (context, i) {
              final item = order[i];
              final visible = !p.drawerHidden.contains(item);
              return Padding(
                key: ValueKey(item),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(drawerItemIcon(item),
                        color: visible
                            ? scheme.primary
                            : scheme.onSurfaceVariant),
                    title: Text(tr(drawerItemLabelKey(item))),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: visible,
                          onChanged: (v) => p.setDrawerHidden(item, !v),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.drag_handle_rounded,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
