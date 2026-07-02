import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../widgets/poster.dart';
import '../widgets/pressable.dart';
import '../widgets/reveal.dart';

enum DiscoverMode { trending, nowPlaying }

/// Лента «Обзор» (популярное) / «В кино» (сейчас в прокате) из TMDB. Тап по
/// фильму → добавить в библиотеку («Буду смотреть» / «Просмотрено»).
class DiscoverTab extends StatefulWidget {
  final DiscoverMode mode;
  const DiscoverTab({super.key, required this.mode});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab>
    with AutomaticKeepAliveClientMixin {
  List<TmdbMovie>? _movies;
  bool _error = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _movies = null;
      _error = false;
    });
    final list = widget.mode == DiscoverMode.trending
        ? await TmdbService.trending()
        : await TmdbService.nowPlaying();
    if (!mounted) return;
    setState(() {
      _movies = list;
      _error = list.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_movies == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error || _movies!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(tr('discover_error'),
                style: const TextStyle(
                    fontFamily: AppTheme.bodyFont, fontSize: 15)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: Text(tr('retry'))),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      const spacing = 12.0;
      final cols = c.maxWidth ~/ 130;
      final n = cols < 2 ? 2 : cols;
      final w = (c.maxWidth - 32 - spacing * (n - 1)) / n;
      return RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
          child: Wrap(
            spacing: spacing,
            runSpacing: 18,
            children: [
              for (var i = 0; i < _movies!.length; i++)
                Reveal(
                  delay: Duration(milliseconds: (i % n) * 40),
                  child: _card(_movies![i], w),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _card(TmdbMovie m, double w) {
    final scheme = Theme.of(context).colorScheme;
    final lib = MovieRepository.instance.movieByTmdb(m.id);
    return SizedBox(
      width: w,
      child: Pressable(
        onTap: () => _addSheet(m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Poster(title: m.title, url: m.posterUrl, width: w, radius: 16),
                if (lib != null)
                  Positioned(top: 6, right: 6, child: _statusBadge(scheme, lib)),
              ],
            ),
            const SizedBox(height: 6),
            Text(m.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.1,
                    color: scheme.onSurface)),
            const SizedBox(height: 2),
            Row(
              children: [
                if (m.rating != null && m.rating! > 0) ...[
                  Icon(Icons.star_rounded, size: 13, color: scheme.primary),
                  const SizedBox(width: 2),
                  Text(m.rating!.toStringAsFixed(1),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 6),
                ],
                if (m.year != null)
                  Text('${m.year}',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Значок статуса в ленте: просмотрено → галочка + моя оценка; в списке →
  /// закладка.
  Widget _statusBadge(ColorScheme scheme, LibraryMovie lib) {
    if (lib.status == LibraryStatus.watched) {
      final sc = lib.currentScore;
      return Container(
        padding: EdgeInsets.symmetric(horizontal: sc != null ? 8 : 5, vertical: 4),
        decoration: BoxDecoration(
            color: scheme.primary, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary),
            if (sc != null) ...[
              const SizedBox(width: 3),
              Text(sc.toStringAsFixed(1),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: scheme.onPrimary)),
            ],
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(5),
      decoration:
          BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
      child: Icon(Icons.bookmark_rounded,
          size: 14, color: scheme.onSecondaryContainer),
    );
  }

  void _addSheet(TmdbMovie m) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Poster(title: m.title, url: m.posterUrl, width: 84, radius: 14),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.title,
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                                height: 1.1,
                                color: scheme.onSurface)),
                        const SizedBox(height: 4),
                        Text(
                            [
                              if (m.year != null) '${m.year}',
                              if (m.rating != null && m.rating! > 0)
                                '★ ${m.rating!.toStringAsFixed(1)}',
                            ].join(' · '),
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 13,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              if (m.overview != null && m.overview!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(m.overview!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _add(sheetCtx, m, LibraryStatus.watchlist),
                      icon: const Icon(Icons.bookmark_add_rounded),
                      label: Text(tr('nav_watchlist')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          _add(sheetCtx, m, LibraryStatus.watched),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(tr('act_watched')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _add(BuildContext sheetCtx, TmdbMovie m, LibraryStatus status) {
    final messenger = ScaffoldMessenger.of(context);
    MovieRepository.instance.addFromTmdb(m, status);
    Navigator.pop(sheetCtx);
    setState(() {}); // обновить галочку «в библиотеке»
    messenger.showSnackBar(SnackBar(
      content: Text(tr(status == LibraryStatus.watched
          ? 'added_to_watched'
          : 'added_to_watchlist')),
      behavior: SnackBarBehavior.floating,
    ));
  }
}
