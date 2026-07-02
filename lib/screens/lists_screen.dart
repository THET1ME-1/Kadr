import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster.dart';
import '../widgets/reveal.dart';
import 'movie_sheet.dart';

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
          _ListData(tr('act_favorite'), Icons.favorite_rounded, repo.favorites),
          _ListData(tr('nav_watchlist'), Icons.bookmark_rounded, repo.watchlist),
          _ListData(
              tr('nav_watched'), Icons.check_circle_rounded, repo.watched),
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
              builder: (_) => _ListDetail(title: data.name, movies: data.movies))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _collage(data.movies),
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
                      Text(trf('movies_count', {'n': data.movies.length}),
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

  Widget _collage(List<LibraryMovie> movies) {
    final shown = movies.take(3).toList();
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
                  title: shown[i].displayTitle,
                  url: shown[i].posterUrl,
                  width: 40,
                  radius: 8),
            ),
        ],
      ),
    );
  }
}

class _ListData {
  final String name;
  final IconData icon;
  final List<LibraryMovie> movies;
  final bool deletable;
  _ListData(this.name, this.icon, this.movies, {this.deletable = false});
}

class _ListDetail extends StatelessWidget {
  final String title;
  final List<LibraryMovie> movies;
  const _ListDetail({required this.title, required this.movies});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: movies.isEmpty
          ? EmptyState(
              icon: Icons.list_alt_rounded,
              title: title,
              subtitle: tr('list_empty'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              itemCount: movies.length,
              itemBuilder: (context, i) {
                final m = movies[i];
                final meta = [
                  if (m.year != null) '${m.year}',
                ].join(' · ');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Material(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => showMovieSheet(context, m),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Poster(
                                title: m.displayTitle,
                                url: m.posterUrl,
                                width: 52),
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
                            if (m.currentScore != null)
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    shape: BoxShape.circle),
                                child: Text(m.currentScore!.toStringAsFixed(1),
                                    style: TextStyle(
                                        fontFamily: AppTheme.displayFont,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: scheme.onPrimaryContainer)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
