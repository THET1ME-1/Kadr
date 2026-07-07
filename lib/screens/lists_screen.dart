import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../models/social.dart';
import '../services/movie_repository.dart';
import '../services/social/social_api.dart';
import '../services/social/social_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster.dart';
import '../widgets/reveal.dart';
import 'delete_helpers.dart';
import 'movie_sheet.dart';
import 'series_screen.dart';
import 'social/shared_list_screen.dart';

/// Экран «Списки»: избранное, «Буду смотреть», «Просмотрено» + свои списки
/// (импортированные из TV Time). Тап → содержимое списка.
class ListsScreen extends StatelessWidget {
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final special = <_ListData>[
          _ListData(tr('act_favorite'), Icons.favorite_rounded, repo.favorites,
              series: repo.favoriteSeries),
          _ListData(tr('nav_watchlist'), Icons.bookmark_rounded, repo.watchlist,
              series: repo.watchlistSeries),
          _ListData(tr('watched_movies'), Icons.movie_rounded, repo.watched),
          _ListData(tr('watched_series'), Icons.live_tv_rounded, const [],
              series: repo.watchedSeries),
        ];
        final custom = [
          for (final l in repo.lists)
            _ListData(
              l.name,
              Icons.list_alt_rounded,
              l.movieUuids
                  .map(repo.byUuid)
                  .whereType<LibraryMovie>()
                  .toList(),
              deletable: true,
            ),
        ];
        return Scaffold(
          appBar: AppBar(title: Text(tr('drawer_lists'))),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _createSheet(context, repo),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('create_list')),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              for (var i = 0; i < special.length; i++)
                Reveal(
                    delay: Duration(milliseconds: i * 50),
                    child: _listCard(context, special[i])),
              const _SharedListsSection(),
              if (custom.isNotEmpty) ...[
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(tr('my_lists'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurface)),
                ),
                for (var i = 0; i < custom.length; i++)
                  Reveal(
                    delay: Duration(milliseconds: i * 50),
                    child: Dismissible(
                      key: ValueKey('list-${custom[i].name}'),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => repo.deleteList(custom[i].name),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 28, bottom: 12),
                        decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(24)),
                        child: Icon(Icons.delete_rounded,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                      ),
                      child: _listCard(context, custom[i]),
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _listCard(BuildContext context, _ListData data) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _ListDetail(
                  title: data.name,
                  movies: data.movies,
                  series: data.series))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _collage(data),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(data.icon, size: 18, color: scheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(data.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: AppTheme.displayFont,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
                                    color: scheme.onSurface)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(_countLabel(data),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 13,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _createSheet(BuildContext context, MovieRepository repo) {
    final ctl = TextEditingController();
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Text(tr('create_list'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: scheme.onSurface)),
            const SizedBox(height: 14),
            TextField(
              controller: ctl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: tr('list_name')),
              onSubmitted: (v) {
                repo.createList(v);
                Navigator.pop(sheetCtx);
              },
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () {
                  repo.createList(ctl.text);
                  Navigator.pop(sheetCtx);
                },
                child: Text(tr('create')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _countLabel(_ListData data) {
    final parts = <String>[
      if (data.movies.isNotEmpty) trf('movies_count', {'n': data.movies.length}),
      if (data.series.isNotEmpty) trf('series_count', {'n': data.series.length}),
    ];
    return parts.isEmpty ? trf('movies_count', {'n': 0}) : parts.join(' · ');
  }

  Widget _collage(_ListData data) {
    final items = <({String title, String? url})>[
      for (final m in data.movies) (title: m.displayTitle, url: m.posterUrl),
      for (final s in data.series) (title: s.displayTitle, url: s.posterUrl),
    ];
    final shown = items.take(3).toList();
    if (shown.isEmpty) {
      return const SizedBox(width: 56, height: 56);
    }
    return SizedBox(
      width: 56,
      height: 78,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: i * 10.0,
              child: Poster(
                  title: shown[i].title,
                  url: shown[i].url,
                  width: 40,
                  radius: 8),
            ),
        ],
      ),
    );
  }
}

/// Секция «Совместные списки» на экране «Списки»: списки, которые редактируют
/// несколько друзей. Живёт на бэкенде соц-слоя; показывается только если вошёл.
class _SharedListsSection extends StatefulWidget {
  const _SharedListsSection();

  @override
  State<_SharedListsSection> createState() => _SharedListsSectionState();
}

class _SharedListsSectionState extends State<_SharedListsSection> {
  List<SharedListSummary> _lists = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = SocialController.instance.token;
    if (t == null) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final lists = await SocialApi.instance.sharedLists(t);
      if (mounted) {
        setState(() {
          _lists = lists;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _create() async {
    final scheme = Theme.of(context).colorScheme;
    final c = TextEditingController();
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('sl_create'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: scheme.onSurface)),
            const SizedBox(height: 6),
            Text(tr('sl_create_hint'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              decoration: InputDecoration(hintText: tr('list_name')),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, c.text.trim()),
                  child: Text(tr('create'))),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty) return;
    final t = SocialController.instance.token;
    if (t == null) return;
    try {
      final id = await SocialApi.instance.createList(t, name);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SharedListScreen(listId: id, initialName: name)));
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // До входа в профиль — секцию не показываем (нечего синхронизировать).
    return ListenableBuilder(
      listenable: SocialController.instance,
      builder: (context, _) {
        if (!SocialController.instance.isLoggedIn) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  Text(tr('sl_section'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: scheme.onSurface)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(tr('create')),
                  ),
                ],
              ),
            ),
            if (_loaded && _lists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text(tr('sl_none'),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13,
                        color: scheme.onSurfaceVariant)),
              ),
            for (final l in _lists) _sharedCard(context, l),
          ],
        );
      },
    );
  }

  Widget _sharedCard(BuildContext context, SharedListSummary l) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    SharedListScreen(listId: l.id, initialName: l.name)));
            _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.groups_rounded,
                      color: scheme.onTertiaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: scheme.onSurface)),
                      const SizedBox(height: 4),
                      Text(
                          '${trf('sl_members_n', {'n': l.members})} · ${trf('movies_count', {'n': l.items})}',
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 13,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListData {
  final String name;
  final IconData icon;
  final List<LibraryMovie> movies;
  final List<LibrarySeries> series;
  final bool deletable;
  _ListData(this.name, this.icon, this.movies,
      {this.series = const [], this.deletable = false});
  int get count => movies.length + series.length;
}

class _ListDetail extends StatelessWidget {
  final String title;
  final List<LibraryMovie> movies;
  final List<LibrarySeries> series;
  const _ListDetail(
      {required this.title, required this.movies, this.series = const []});

  @override
  Widget build(BuildContext context) {
    final empty = movies.isEmpty && series.isEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: empty
          ? EmptyState(
              icon: Icons.list_alt_rounded,
              title: title,
              subtitle: tr('list_empty'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: [
                for (final m in movies) _movieTile(context, m),
                for (final s in series) _seriesTile(context, s),
              ],
            ),
    );
  }

  Widget _movieTile(BuildContext context, LibraryMovie m) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [if (m.year != null) '${m.year}'].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showMovieSheet(context, m),
          onLongPress: () => deleteMovieFromBase(context, m),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Poster(title: m.displayTitle, url: m.posterUrl, width: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              height: 1.1,
                              color: scheme.onSurface)),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(meta,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                if (m.currentScore != null) _scoreDot(scheme, m.currentScore!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seriesTile(BuildContext context, LibrarySeries s) {
    final scheme = Theme.of(context).colorScheme;
    final sc = s.displayScore;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s))),
          onLongPress: () => deleteSeriesFromBase(context, s),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Stack(
                  children: [
                    Poster(title: s.displayTitle, url: s.posterUrl, width: 52),
                    Positioned(
                      left: 3,
                      top: 3,
                      child: Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                            color: scheme.tertiary,
                            borderRadius: BorderRadius.circular(7)),
                        child: Icon(Icons.live_tv_rounded,
                            size: 11, color: scheme.onTertiary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              height: 1.1,
                              color: scheme.onSurface)),
                      const SizedBox(height: 3),
                      Text(trf('episodes_n', {'n': s.episodesSeen}),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (sc != null) _scoreDot(scheme, sc),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scoreDot(ColorScheme scheme, double score) => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
        child: Text(score.toStringAsFixed(1),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: scheme.onPrimaryContainer)),
      );
}
