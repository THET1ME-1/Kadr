import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/app_prefs.dart';
import '../services/movie_repository.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../widgets/empty_state.dart';
import '../widgets/movie_cards.dart' show droppedBadge;
import '../widgets/poster.dart';
import '../widgets/rating_slider.dart';
import '../widgets/reveal.dart';
import '../widgets/score_pad.dart';
import 'movie_sheet.dart';
import 'series_screen.dart';

enum LibraryMode { watched, watchlist }

/// Режим отображения галереи: список / постеры (сетка) / баннеры (широкие).
enum LibraryViewMode { list, posters, banners }

enum _WatchedFilter { all, movies, series }

enum _LibSort { dateNew, dateOld, ratingHigh, titleAz, yearNew }

/// Вкладка библиотеки: «Просмотрено» (карточка на каждый просмотр + сериалы, по
/// месяцам) или «Буду смотреть» (по дате добавления). Поддерживает три режима
/// галереи и сортировку.
class LibraryTab extends StatefulWidget {
  final LibraryMode mode;
  final String query;
  final LibraryViewMode viewMode;

  /// Вызывается по кнопке «Искать по всей базе» из пустого результата поиска.
  final VoidCallback? onSearchEverywhere;
  const LibraryTab({
    super.key,
    required this.mode,
    this.query = '',
    this.viewMode = LibraryViewMode.list,
    this.onSearchEverywhere,
  });

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  _WatchedFilter _filter = _WatchedFilter.all;
  _LibSort _sort = _LibSort.dateNew;

  /// Фильтр по жанрам (OR) и диапазону года выхода. Метаданные — только у
  /// фильмов, поэтому при активном фильтре сериалы скрываются.
  final Set<String> _genreFilter = {};
  RangeValues? _yearFilter;
  bool get _hasMetaFilter => _genreFilter.isNotEmpty || _yearFilter != null;

  /// Режим множественного выделения (по долгому нажатию на карточку).
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Ключ → элемент текущего рендера: нужен, чтобы при удалении знать, какой
  /// именно просмотр/сессию убирать (перезаполняется на каждый build).
  final Map<String, _LibEntry> _entryByKey = {};

  /// id элементов, чья анимация появления уже проигралась. Живёт всё время
  /// жизни вкладки, чтобы при возврате карточки в зону видимости на скролле она
  /// не анимировалась заново (именно это давало лаги прокрутки). См. [Reveal].
  final Set<Object> _revealed = {};

  @override
  void initState() {
    super.initState();
    _loadSort();
  }

  /// Стабильный ключ элемента для выделения/удаления.
  String _keyOf(_LibEntry e) {
    if (e.session != null) {
      final s = e.session!;
      return 's:${s.series.tvShowId}:${s.start?.microsecondsSinceEpoch ?? 0}:${s.count}';
    }
    final m = e.movie!;
    if (widget.mode == LibraryMode.watchlist) return 'wl:${m.uuid}';
    return 'mv:${m.uuid}:${identityHashCode(e.viewing)}';
  }

  void _indexEntries(Iterable<_LibEntry> entries) {
    _entryByKey.clear();
    for (final e in entries) {
      _entryByKey[_keyOf(e)] = e;
    }
    // Выделения, которых больше нет в рендере (например, после сортировки/
    // фильтра), отбрасываем, чтобы счётчик не врал.
    _selected.removeWhere((k) => !_entryByKey.containsKey(k));
    if (_selected.isEmpty) _selecting = false;
  }

  void _onSelect(String key) {
    setState(() {
      if (_selected.remove(key)) {
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(key);
        _selecting = true;
      }
    });
  }

  void _exitSelect() => setState(() {
        _selected.clear();
        _selecting = false;
      });

  Future<void> _confirmDeleteSelected() async {
    final n = _selected.length;
    if (n == 0) return;
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('delete_selected_title')),
        content: Text(trf(
            widget.mode == LibraryMode.watchlist
                ? 'delete_selected_watchlist'
                : 'delete_selected_watched',
            {'n': n})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: kDroppedColor, foregroundColor: Colors.white),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _deleteSelected();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(trf('removed_n', {'n': n})),
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest,
    ));
  }

  Future<void> _deleteSelected() async {
    final repo = MovieRepository.instance;
    final entries = [
      for (final k in _selected)
        if (_entryByKey[k] != null) _entryByKey[k]!
    ];
    for (final e in entries) {
      if (e.session != null) {
        final s = e.session!;
        await repo.removeEpisodes(s.series.tvShowId, s.episodes);
      } else if (widget.mode == LibraryMode.watchlist) {
        // Сброс статуса «Буду смотреть» (из базы не удаляем).
        await repo.toggleWatchlist(e.movie!.uuid);
      } else if (e.viewing != null) {
        await repo.removeViewing(e.movie!.uuid, e.viewing!);
      }
    }
    if (mounted) {
      setState(() {
        _selected.clear();
        _selecting = false;
      });
    }
  }

  /// Сортировка персистится отдельно на каждую вкладку.
  Future<void> _loadSort() async {
    final raw = await Store.instance.getString('libSort.${widget.mode.name}');
    for (final s in _LibSort.values) {
      if (s.name == raw) {
        if (mounted) setState(() => _sort = s);
        return;
      }
    }
  }

  void _setSort(_LibSort s) {
    setState(() => _sort = s);
    Store.instance.setString('libSort.${widget.mode.name}', s.name);
  }

  String get _q => widget.query.toLowerCase().trim();
  bool _matchMovie(LibraryMovie m) {
    if (!(_q.isEmpty ||
        m.displayTitle.toLowerCase().contains(_q) ||
        m.title.toLowerCase().contains(_q))) {
      return false;
    }
    if (_genreFilter.isNotEmpty && !m.genres.any(_genreFilter.contains)) {
      return false;
    }
    if (_yearFilter != null) {
      final y = m.year;
      if (y == null ||
          y < _yearFilter!.start.round() ||
          y > _yearFilter!.end.round()) {
        return false;
      }
    }
    return true;
  }

  bool _matchSeries(LibrarySeries s) {
    if (_hasMetaFilter) return false; // жанр/год — метаданные фильмов
    return _q.isEmpty ||
        s.displayTitle.toLowerCase().contains(_q) ||
        s.title.toLowerCase().contains(_q);
  }
  bool _matchEntry(WatchedEntry e) =>
      e.isSeries ? _matchSeries(e.session!.series) : _matchMovie(e.movie!);

  @override
  Widget build(BuildContext context) {
    final repo = MovieRepository.instance;
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelect();
      },
      child: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final body = widget.mode == LibraryMode.watchlist
              ? _watchlist(repo)
              : _watched(repo);
          // Панель выделения живёт в стабильном слоте (высота анимируется), а
          // список всегда остаётся тем же Expanded — иначе при входе в режим
          // выбора CustomScrollView пересоздавался и «прыгал» к последнему
          // фильму. Теперь позиция прокрутки сохраняется.
          return Column(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _selecting
                    ? _selectionBar(context)
                    : const SizedBox(width: double.infinity),
              ),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }

  /// Контекстная панель режима выделения: закрыть · счётчик · удалить.
  Widget _selectionBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = _selected.isEmpty;
    final actionColor = empty ? scheme.onSurfaceVariant : kDroppedColor;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: tr('cancel'),
              onPressed: _exitSelect,
            ),
            Text(
              trf('n_selected', {'n': _selected.length}),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: scheme.onSurface),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: empty ? null : _confirmDeleteSelected,
              icon: Icon(Icons.delete_outline_rounded, color: actionColor),
              label: Text(tr('delete'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w700,
                      color: actionColor)),
            ),
          ],
        ),
      ),
    );
  }

  /// Пустой результат: если это ПОИСК (query не пуст) — предлагаем искать по
  /// всей базе (TMDB); иначе обычная заглушка раздела.
  Widget _emptyView(Widget fallback) {
    if (_q.isEmpty || widget.onSearchEverywhere == null) return fallback;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore_rounded,
                size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(trf('search_local_empty', {'q': widget.query.trim()}),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    height: 1.35,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: widget.onSearchEverywhere,
              icon: const Icon(Icons.search_rounded),
              label: Text(tr('search_all_db')),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------- «Буду смотреть» ---------------------------

  Widget _watchlist(MovieRepository repo) {
    var items = repo.watchlist.where(_matchMovie).toList();
    items = _sortMovies(items);
    if (items.isEmpty) {
      return _emptyView(EmptyState(
          icon: Icons.bookmark_rounded,
          title: tr('nav_watchlist'),
          subtitle: tr('lib_empty_watchlist')));
    }
    final entries = [for (final m in items) _LibEntry.movie(m)];
    _indexEntries(entries);
    return LayoutBuilder(builder: (context, c) {
      final g = _grid(c.maxWidth);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(context, items.length)),
          ..._entrySlivers(entries, g),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      );
    });
  }

  List<LibraryMovie> _sortMovies(List<LibraryMovie> list) {
    final l = [...list];
    switch (_sort) {
      case _LibSort.dateNew:
        l.sort((a, b) =>
            (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0)));
      case _LibSort.dateOld:
        l.sort((a, b) =>
            (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0)));
      case _LibSort.ratingHigh:
        l.sort((a, b) => (b.kpRating ?? -1).compareTo(a.kpRating ?? -1));
      case _LibSort.titleAz:
        l.sort((a, b) => a.displayTitle
            .toLowerCase()
            .compareTo(b.displayTitle.toLowerCase()));
      case _LibSort.yearNew:
        l.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    }
    return l;
  }

  // ----------------------------- «Просмотрено» -----------------------------

  Widget _watched(MovieRepository repo) {
    final groups = [
      for (final g in repo.watchedEntriesByMonth(
        movies: _filter != _WatchedFilter.series,
        series: _filter != _WatchedFilter.movies,
      ))
        if (g.value.any(_matchEntry))
          MapEntry(g.key, g.value.where(_matchEntry).toList()),
    ];
    final total = groups.fold<int>(0, (s, g) => s + g.value.length);

    // По дате — оставляем помесячную разбивку; иначе — плоский отсортированный
    // список без заголовков месяцев.
    final grouped = _sort == _LibSort.dateNew || _sort == _LibSort.dateOld;
    final List<MapEntry<DateTime?, List<_LibEntry>>> render;
    if (grouped) {
      final gs = [
        for (final g in groups)
          MapEntry<DateTime?, List<_LibEntry>>(
              g.key, [for (final e in g.value) _entry(e)])
      ];
      render = _sort == _LibSort.dateOld ? gs.reversed.toList() : gs;
      if (_sort == _LibSort.dateOld) {
        for (final g in render) {
          g.value.sort((a, b) => (a.date ?? DateTime(0))
              .compareTo(b.date ?? DateTime(0)));
        }
      }
    } else {
      final flat = <_LibEntry>[
        for (final g in groups)
          for (final e in g.value) _entry(e)
      ];
      _sortEntries(flat);
      render = [MapEntry<DateTime?, List<_LibEntry>>(null, flat)];
    }
    _indexEntries([for (final grp in render) ...grp.value]);

    return LayoutBuilder(builder: (context, c) {
      final g = _grid(c.maxWidth);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _filterBar()),
          if (groups.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyView(EmptyState(
                  icon: Icons.check_circle_rounded,
                  title: tr('nav_watched'),
                  subtitle: tr('lib_empty_watched'))),
            )
          else ...[
            SliverToBoxAdapter(child: _countHeader(context, total)),
            for (final grp in render)
              if (grp.key != null) ...[
                SliverToBoxAdapter(child: _monthHeader(context, grp.key!)),
                // Внутри месяца — мини-разделители по дням («24 июня 2026»).
                for (final day in _groupByDay(grp.value)) ...[
                  SliverToBoxAdapter(child: _dayDivider(context, day.key)),
                  ..._entrySlivers(day.value, g),
                ],
              ] else
                ..._entrySlivers(grp.value, g),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ],
      );
    });
  }

  _LibEntry _entry(WatchedEntry e) {
    if (e.isSeries) return _LibEntry.session(e.session!);
    final movie = e.movie!;
    final viewing = e.viewing!;
    // Номер просмотра — по порядку добавления (стабилен, не зависит от даты).
    final ordinal = movie.viewings.indexOf(viewing) + 1;
    final rewatchNum =
        (movie.viewings.length > 1 && ordinal > 1) ? ordinal : null;
    return _LibEntry.movie(movie, viewing: viewing, rewatchNumber: rewatchNum);
  }

  void _sortEntries(List<_LibEntry> l) {
    switch (_sort) {
      case _LibSort.ratingHigh:
        l.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
      case _LibSort.titleAz:
        l.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _LibSort.yearNew:
        l.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      default:
        break;
    }
  }

  // ------------------------------- элементы -------------------------------

  ({int cols, double w, double tileH}) _grid(double maxWidth) {
    const spacing = 12.0;
    const pad = 24.0; // 12 слева + 12 справа
    final avail = maxWidth - pad;
    final cols = (avail / 128).floor().clamp(2, 6);
    final w = (avail - spacing * (cols - 1)) / cols;
    final tileH = w * 1.5 + 52;
    return (cols: cols, w: w, tileH: tileH);
  }

  List<Widget> _entrySlivers(
      List<_LibEntry> entries, ({int cols, double w, double tileH}) g) {
    switch (widget.viewMode) {
      case LibraryViewMode.list:
        return [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _rowFor(entries[i]),
                childCount: entries.length,
              ),
            ),
          ),
        ];
      case LibraryViewMode.banners:
        return [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Reveal(
                  group: _revealed,
                  id: _keyOf(entries[i]),
                  child: _bannerFor(entries[i]),
                ),
                childCount: entries.length,
              ),
            ),
          ),
        ];
      case LibraryViewMode.posters:
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: g.cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
                mainAxisExtent: g.tileH,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => Reveal(
                  group: _revealed,
                  id: _keyOf(entries[i]),
                  delay: Duration(milliseconds: (i % g.cols) * 40),
                  child: _posterFor(entries[i], g.w),
                ),
                childCount: entries.length,
              ),
            ),
          ),
        ];
    }
  }

  Widget _rowFor(_LibEntry e) {
    final key = _keyOf(e);
    final sel = _selected.contains(key);
    if (e.session != null) {
      return _SeriesSessionCard(
        session: e.session!,
        selecting: _selecting,
        selected: sel,
        onSelect: () => _onSelect(key),
        revealGroup: _revealed,
        revealId: key,
      );
    }
    return _MovieRow(
      movie: e.movie!,
      viewing: e.viewing,
      rewatchNumber: e.rewatchNumber,
      selecting: _selecting,
      selected: sel,
      onSelect: () => _onSelect(key),
      revealGroup: _revealed,
      revealId: key,
    );
  }

  Widget _posterFor(_LibEntry e, double w) {
    final key = _keyOf(e);
    final sel = _selected.contains(key);
    if (e.session != null) {
      final s = e.session!.series;
      return _PosterCell(
        title: s.displayTitle,
        posterUrl: s.posterUrl,
        width: w,
        score: e.session!.avgScore ?? e.session!.series.displayScore,
        favorite: s.favorite,
        series: true,
        dropped: s.dropped,
        selecting: _selecting,
        selected: sel,
        onSelect: () => _onSelect(key),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s))),
      );
    }
    final m = e.movie!;
    return _PosterCell(
      title: m.displayTitle,
      posterUrl: m.posterUrl,
      width: w,
      score: e.viewing != null ? m.scoreOf(e.viewing!) : null,
      favorite: m.favorite,
      selecting: _selecting,
      selected: sel,
      onSelect: () => _onSelect(key),
      onTap: () => showMovieSheet(context, m),
    );
  }

  Widget _bannerFor(_LibEntry e) {
    final key = _keyOf(e);
    final sel = _selected.contains(key);
    if (e.session != null) {
      final s = e.session!.series;
      return _BannerCell(
        title: s.displayTitle,
        posterUrl: s.posterUrl,
        subtitle: '${e.session!.rangeLabel} · ${e.session!.count} сер.',
        score: e.session!.avgScore ?? e.session!.series.displayScore,
        favorite: s.favorite,
        series: true,
        dropped: s.dropped,
        selecting: _selecting,
        selected: sel,
        onSelect: () => _onSelect(key),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s))),
      );
    }
    final m = e.movie!;
    final date = e.viewing?.date;
    return _BannerCell(
      title: m.displayTitle,
      posterUrl: m.posterUrl,
      subtitle: [
        if (m.year != null) '${m.year}',
        if (date != null) dateExactWithTime(date),
      ].join(' · '),
      score: e.viewing != null ? m.scoreOf(e.viewing!) : null,
      favorite: m.favorite,
      selecting: _selecting,
      selected: sel,
      onSelect: () => _onSelect(key),
      onTap: () => showMovieSheet(context, m),
    );
  }

  // ------------------------------- шапки -------------------------------

  Widget _filterBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Подложка без обводки — как у поля поиска; выбранная вкладка
              // залита активным цветом темы (как кнопка «Добавить»).
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _segChip(scheme, _WatchedFilter.all, tr('filter_all')),
                    _segChip(scheme, _WatchedFilter.movies, tr('filter_movies')),
                    _segChip(scheme, _WatchedFilter.series, tr('filter_series')),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _filterButton(),
          _sortButton(),
        ],
      ),
    );
  }

  Widget _segChip(ColorScheme scheme, _WatchedFilter val, String label) {
    final selected = _filter == val;
    return GestureDetector(
      onTap: () => setState(() => _filter = val),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          // Тот же цвет, что у primary-действий приложения (FAB «Добавить»).
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color:
                selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _sortButton() => PopupMenuButton<_LibSort>(
        icon: const Icon(Icons.sort_rounded),
        tooltip: tr('sort'),
        onSelected: _setSort,
        itemBuilder: (context) => [
          for (final s in _LibSort.values)
            PopupMenuItem(
              value: s,
              child: Row(
                children: [
                  Text(_sortLabel(s)),
                  if (_sort == s) ...[
                    const Spacer(),
                    Icon(Icons.check_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
                  ],
                ],
              ),
            ),
        ],
      );

  String _sortLabel(_LibSort s) => switch (s) {
        _LibSort.dateNew => tr('sort_date_new'),
        _LibSort.dateOld => tr('sort_date_old'),
        _LibSort.ratingHigh => tr('sort_rating'),
        _LibSort.titleAz => tr('sort_title'),
        _LibSort.yearNew => tr('sort_year'),
      };

  Widget _header(BuildContext context, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 2),
        child: Row(
          children: [
            Text(
              trf('lib_count', {'n': n}),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            _filterButton(),
            _sortButton(),
          ],
        ),
      );

  /// Кнопка фильтров с точкой-индикатором, когда фильтр активен.
  Widget _filterButton() {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          tooltip: tr('filters'),
          onPressed: _openFilterSheet,
        ),
        if (_hasMetaFilter)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }

  /// Нижний лист фильтров: жанры (мультивыбор) + диапазон года выхода.
  void _openFilterSheet() {
    final repo = MovieRepository.instance;
    final scheme = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    int? minY, maxY;
    for (final m in repo.movies) {
      for (final g in m.genres) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
      final y = m.year;
      if (y != null && y > 1000) {
        minY = (minY == null || y < minY) ? y : minY;
        maxY = (maxY == null || y > maxY) ? y : maxY;
      }
    }
    final genres = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final hasYears = minY != null && maxY != null && maxY > minY;
    final loY = (minY ?? 1950).toDouble();
    final hiY = (maxY ?? DateTime.now().year).toDouble();

    final sel = {..._genreFilter};
    var range = _yearFilter ?? RangeValues(loY, hiY);
    // На случай, если сохранённый диапазон вышел за границы новой библиотеки.
    range = RangeValues(
        range.start.clamp(loY, hiY), range.end.clamp(loY, hiY));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                Text(tr('filters'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: scheme.onSurface)),
                const SizedBox(height: 16),
                Text(tr('filter_genres'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: scheme.primary)),
                const SizedBox(height: 8),
                if (genres.isEmpty)
                  Text(tr('filter_genres_loading'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          color: scheme.onSurfaceVariant))
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(sheetCtx).size.height * 0.35),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final g in genres)
                            FilterChip(
                              label: Text('${capitalize(g)} · ${counts[g]}'),
                              selected: sel.contains(g),
                              onSelected: (v) => setSheet(
                                  () => v ? sel.add(g) : sel.remove(g)),
                              showCheckmark: false,
                              labelStyle: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                  color: sel.contains(g)
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurfaceVariant),
                              selectedColor: scheme.secondaryContainer,
                              backgroundColor: scheme.surfaceContainerHigh,
                              side: BorderSide.none,
                            ),
                        ],
                      ),
                    ),
                  ),
                if (hasYears) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(tr('filter_year'),
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: scheme.primary)),
                      const Spacer(),
                      Text('${range.start.round()} – ${range.end.round()}',
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: scheme.onSurface)),
                    ],
                  ),
                  RangeSlider(
                    min: loY,
                    max: hiY,
                    divisions: (hiY - loY).round().clamp(1, 200),
                    values: range,
                    labels: RangeLabels(
                        '${range.start.round()}', '${range.end.round()}'),
                    onChanged: (v) => setSheet(() => range = v),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          setState(() {
                            _genreFilter.clear();
                            _yearFilter = null;
                          });
                        },
                        child: Text(tr('reset')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(sheetCtx);
                          setState(() {
                            _genreFilter
                              ..clear()
                              ..addAll(sel);
                            // Полный диапазон = без фильтра по году.
                            _yearFilter = (!hasYears ||
                                    (range.start <= loY && range.end >= hiY))
                                ? null
                                : range;
                          });
                        },
                        child: Text(tr('apply')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _countHeader(BuildContext context, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          trf('lib_count', {'n': n}),
          style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  Widget _monthHeader(BuildContext context, DateTime month) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text(
          month.year <= 1
              ? tr('when_unknown')
              : trf('watched_month',
                  {'month': monthName(month.month), 'year': month.year}),
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: 21,
            letterSpacing: -0.4,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );

  /// Разбивает элементы месяца на дни (сохраняя их порядок) — для дневных
  /// разделителей. Элементы уже отсортированы по дате, поэтому первое появление
  /// ключа задаёт порядок дней.
  List<MapEntry<DateTime, List<_LibEntry>>> _groupByDay(List<_LibEntry> es) {
    final map = <String, List<_LibEntry>>{};
    final days = <String, DateTime>{};
    for (final e in es) {
      final d = e.date;
      final key = d == null ? 'x' : '${d.year}-${d.month}-${d.day}';
      map.putIfAbsent(key, () => []).add(e);
      days[key] = d == null ? DateTime(1) : DateTime(d.year, d.month, d.day);
    }
    return [for (final k in map.keys) MapEntry(days[k]!, map[k]!)];
  }

  /// Мини-разделитель дня: дата («24 июня 2026» либо «24.06.2026») + линия.
  Widget _dayDivider(BuildContext context, DateTime day) {
    final scheme = Theme.of(context).colorScheme;
    final label = day.year <= 1
        ? tr('when_unknown')
        : (AppPrefs.instance.numericDates ? numericDate(day) : longDate(day));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.2,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
                height: 1, thickness: 1, color: scheme.surfaceContainerHighest),
          ),
        ],
      ),
    );
  }
}

/// Внутренняя обёртка для элемента библиотеки (фильм-просмотр / сериал-сессия).
class _LibEntry {
  final LibraryMovie? movie;
  final Viewing? viewing;
  final int? rewatchNumber;
  final EpisodeSession? session;
  _LibEntry.movie(this.movie, {this.viewing, this.rewatchNumber})
      : session = null;
  _LibEntry.session(this.session)
      : movie = null,
        viewing = null,
        rewatchNumber = null;

  DateTime? get date =>
      session != null ? session!.start : viewing?.date;
  double? get score => session != null
      ? (session!.avgScore ?? session!.series.displayScore)
      : (viewing != null ? movie!.scoreOf(viewing!) : movie?.currentScore);
  String get title =>
      session != null ? session!.series.displayTitle : movie!.displayTitle;
  int? get year => session != null ? null : movie!.year;
}

/// Карточка-постер для сетки (режим «Постеры»).
class _PosterCell extends StatelessWidget {
  final String title;
  final String? posterUrl;
  final double width;
  final double? score;
  final bool favorite;
  final bool series;
  final bool dropped;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback onTap;
  const _PosterCell({
    required this.title,
    required this.posterUrl,
    required this.width,
    required this.onTap,
    this.score,
    this.favorite = false,
    this.series = false,
    this.dropped = false,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: selecting ? onSelect : onTap,
      onLongPress: onSelect,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Poster(title: title, url: posterUrl, width: width, radius: 16),
              if (favorite || dropped)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (favorite)
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                              color: scheme.primary, shape: BoxShape.circle),
                          child: Icon(Icons.favorite_rounded,
                              size: 13, color: scheme.onPrimary),
                        ),
                      if (favorite && dropped) const SizedBox(width: 4),
                      if (dropped) droppedBadge(),
                    ],
                  ),
                ),
              if (series)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: scheme.tertiary,
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.live_tv_rounded,
                        size: 13, color: scheme.onTertiary),
                  ),
                ),
              if (score != null)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: _scorePill(score!),
                ),
              if (selecting) _selectOverlay(scheme, selected, 16),
            ],
          ),
          const SizedBox(height: 6),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.1,
                  color: scheme.onSurface)),
        ],
      ),
    );
  }
}

/// Широкая карточка-баннер (режим «Баннеры»): постер во всю ширину + оверлей.
class _BannerCell extends StatelessWidget {
  final String title;
  final String? posterUrl;
  final String? subtitle;
  final double? score;
  final bool favorite;
  final bool series;
  final bool dropped;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback onTap;
  const _BannerCell({
    required this.title,
    required this.posterUrl,
    required this.onTap,
    this.subtitle,
    this.score,
    this.favorite = false,
    this.series = false,
    this.dropped = false,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selecting ? onSelect : onTap,
          onLongPress: onSelect,
          child: SizedBox(
            height: 168,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _cover(context, scheme),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.05),
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              height: 1.05,
                              color: Colors.white)),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12.5,
                                color: Colors.white.withValues(alpha: 0.85))),
                      ],
                    ],
                  ),
                ),
                if (favorite || series || dropped)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (series) ...[
                          const Icon(Icons.live_tv_rounded,
                              size: 20, color: Colors.white),
                          const SizedBox(width: 8),
                        ],
                        if (favorite) ...[
                          const Icon(Icons.favorite_rounded,
                              size: 20, color: Colors.white),
                          const SizedBox(width: 8),
                        ],
                        if (dropped)
                          const Icon(Icons.heart_broken_rounded,
                              size: 20, color: kDroppedColor),
                      ],
                    ),
                  ),
                if (score != null)
                  Positioned(top: 12, right: 12, child: _scorePill(score!)),
                if (selecting) _selectOverlay(scheme, selected, 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, ColorScheme scheme) {
    if (posterUrl != null && posterUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: posterUrl!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        memCacheWidth: (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round(),
        placeholder: (c, _) => Container(color: scheme.surfaceContainerHighest),
        errorWidget: (c, u, e) =>
            Container(color: scheme.surfaceContainerHighest),
      );
    }
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.movie_rounded,
          size: 44, color: scheme.onSurfaceVariant),
    );
  }
}

/// Индикатор выбора (режим выделения): заполненный кружок с галочкой, когда
/// выбрано, иначе полупрозрачное кольцо-подсказка.
Widget _selectCheck(ColorScheme scheme, bool selected, {double size = 30}) {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: selected ? scheme.primary : Colors.black.withValues(alpha: 0.35),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: selected
        ? Icon(Icons.check_rounded, size: size * 0.6, color: scheme.onPrimary)
        : null,
  );
}

/// Оверлей выбора поверх постера/баннера: затемнение + рамка + галочка по центру.
Widget _selectOverlay(ColorScheme scheme, bool selected, double radius) {
  return Positioned.fill(
    child: IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                color: selected
                    ? scheme.primary.withValues(alpha: 0.30)
                    : Colors.black.withValues(alpha: 0.12),
                border: selected
                    ? Border.all(color: scheme.primary, width: 3)
                    : null,
              ),
            ),
          ),
          Center(child: _selectCheck(scheme, selected)),
        ],
      ),
    ),
  );
}

/// Пилюля оценки в цвете балла (красный→золото).
Widget _scorePill(double score) {
  final c = scoreColor(score);
  final on = onScoreColor(score);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: 13, color: on),
        const SizedBox(width: 2),
        Text(score.toStringAsFixed(1),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: on)),
      ],
    ),
  );
}

/// Блок сессии сериала во вкладке «Просмотрено»: серии, просмотренные подряд,
/// одной карточкой (как фильм) + список серий внутри, у каждой своя оценка.
class _SeriesSessionCard extends StatelessWidget {
  final EpisodeSession session;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final Set<Object>? revealGroup;
  final Object? revealId;
  const _SeriesSessionCard({
    required this.session,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    this.revealGroup,
    this.revealId,
  });

  LibrarySeries get s => session.series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = session.start;
    return Reveal(
      group: revealGroup,
      id: revealId,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Material(
          color:
              selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: selecting
                    ? onSelect
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SeriesScreen(series: s))),
                onLongPress: onSelect,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Poster(
                              title: s.displayTitle,
                              url: s.posterUrl,
                              width: 58),
                          Positioned(
                            left: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                  color: scheme.tertiary,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.live_tv_rounded,
                                  size: 12, color: scheme.onTertiary),
                            ),
                          ),
                          if (selecting) _selectOverlay(scheme, selected, 12),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(s.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontFamily: AppTheme.displayFont,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    height: 1.1,
                                    color: scheme.onSurface)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (s.favorite)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(Icons.favorite_rounded,
                                        size: 15, color: scheme.primary),
                                  ),
                                if (s.dropped)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(Icons.heart_broken_rounded,
                                        size: 15, color: kDroppedColor),
                                  ),
                                Flexible(
                                  child: Text(
                                      '${session.rangeLabel} · ${session.count} сер.',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontFamily: AppTheme.bodyFont,
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant)),
                                ),
                              ],
                            ),
                            if (start != null) ...[
                              const SizedBox(height: 3),
                              Text(dateExactWithTime(start),
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.85))),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _scoreBadge(scheme, session.avgScore ?? s.displayScore),
                    ],
                  ),
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: scheme.surfaceContainerHighest),
              // В режиме выделения гасим внутренние тапы серий (иначе тап
              // открыл бы диалог оценки), а по касанию — переключаем выбор.
              GestureDetector(
                onTap: selecting ? onSelect : null,
                onLongPress: selecting ? onSelect : null,
                behavior: HitTestBehavior.opaque,
                child: AbsorbPointer(
                  absorbing: selecting,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 10, 8),
                    child: Column(
                      children: [
                        // Серии от последней к первой (новые сверху).
                        for (final ep in session.episodes.reversed.take(12))
                          _EpisodeRow(seriesId: s.tvShowId, ep: ep),
                    if (session.episodes.length > 12)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SeriesScreen(series: s))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 4),
                          child: Row(
                            children: [
                              Icon(Icons.expand_more_rounded,
                                  size: 18, color: scheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                  trf('more_episodes',
                                      {'n': session.episodes.length - 12}),
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: scheme.primary)),
                            ],
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка одного эпизода в блоке сессии — с оценкой (тап → поставить).
class _EpisodeRow extends StatelessWidget {
  final String seriesId;
  final Episode ep;
  const _EpisodeRow({required this.seriesId, required this.ep});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sc = ep.score;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _rate(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline_rounded,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            SizedBox(
              width: 92,
              child: Text(ep.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: scheme.onSurface)),
            ),
            if (ep.watchedAt != null)
              Text(hhmm(ep.watchedAt!),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sc != null
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      sc != null
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 14,
                      color: sc != null
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant),
                  const SizedBox(width: 3),
                  Text(sc != null ? sc.toStringAsFixed(1) : '—',
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: sc != null
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _rate(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    double val = ep.score ?? 1.0;
    bool rated = ep.score != null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 14),
                Text(ep.label,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: scheme.onSurface)),
                const SizedBox(height: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final r = await showScorePad(sheetCtx,
                        initial: rated ? val : null);
                    if (r != null) {
                      setSheet(() {
                        val = r;
                        rated = true;
                      });
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(rated ? val.toStringAsFixed(1) : '—',
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 44,
                              color: rated
                                  ? scoreColor(val)
                                  : scheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      Icon(Icons.dialpad_rounded,
                          size: 18, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                RatingSlider(
                  value: val,
                  onChanged: (x) => setSheet(() {
                    val = x;
                    rated = true;
                  }),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          MovieRepository.instance
                              .setEpisodeScore(seriesId, ep, null);
                          Navigator.pop(sheetCtx);
                        },
                        child: Text(tr('remove_score')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          MovieRepository.instance
                              .setEpisodeScore(seriesId, ep, rated ? val : null);
                          Navigator.pop(sheetCtx);
                        },
                        child: Text(tr('done')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Бейдж оценки. Если оценки нет: в «Буду смотреть» ([addMode]) — «+»
/// (добавить просмотр), в «Просмотрено» — звезда (поставить оценку).
Widget _scoreBadge(ColorScheme scheme, double? score, {bool addMode = false}) {
  if (score == null) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
      child: Icon(addMode ? Icons.add_rounded : Icons.star_border_rounded,
          color: scheme.onSurfaceVariant, size: 24),
    );
  }
  return Container(
    width: 46,
    height: 46,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: scoreColor(score), shape: BoxShape.circle),
    child: Text(
      score.toStringAsFixed(1),
      style: TextStyle(
        fontFamily: AppTheme.displayFont,
        fontWeight: FontWeight.w800,
        fontSize: 15,
        color: onScoreColor(score),
      ),
    ),
  );
}

class _MovieRow extends StatelessWidget {
  final LibraryMovie movie;

  /// Конкретный просмотр (для вкладки «Просмотрено»). null во «Буду смотреть».
  final Viewing? viewing;

  /// Номер повторного просмотра (2, 3, …); null — если это первый просмотр.
  final int? rewatchNumber;

  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;
  final Set<Object>? revealGroup;
  final Object? revealId;

  const _MovieRow({
    required this.movie,
    this.viewing,
    this.rewatchNumber,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
    this.revealGroup,
    this.revealId,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (movie.year != null) '${movie.year}',
      if (movie.runtimeMin != null)
        humanDuration(Duration(minutes: movie.runtimeMin!)),
    ].join(' · ');
    final date = viewing?.date;
    final score = viewing != null ? movie.scoreOf(viewing!) : null;

    return Reveal(
      group: revealGroup,
      id: revealId,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Material(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: selecting ? onSelect : () => showMovieSheet(context, movie),
            onLongPress: onSelect,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      Poster(
                          title: movie.displayTitle,
                          url: movie.posterUrl,
                          width: 58),
                      if (selecting) _selectOverlay(scheme, selected, 12),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(movie.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                height: 1.1,
                                color: scheme.onSurface)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (movie.emotions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Text(movie.emotions.first.emoji,
                                    style: const TextStyle(fontSize: 15)),
                              ),
                            if (movie.favorite)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(Icons.favorite_rounded,
                                    size: 15, color: scheme.primary),
                              ),
                            Flexible(
                              child: Text(meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant)),
                            ),
                          ],
                        ),
                        if (date != null || rewatchNumber != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (date != null)
                                Text(
                                  dateExactWithTime(date),
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.85)),
                                ),
                              if (rewatchNumber != null) ...[
                                if (date != null) const SizedBox(width: 8),
                                _rewatchChip(scheme, rewatchNumber!),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _scoreBadge(scheme, score, addMode: viewing == null),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Бейдж повтора: «↻ N» — номер по счёту (2-й, 3-й… просмотр).
  Widget _rewatchChip(ColorScheme scheme, int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat_rounded,
                size: 13, color: scheme.onTertiaryContainer),
            const SizedBox(width: 3),
            Text('$n',
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: scheme.onTertiaryContainer)),
          ],
        ),
      );
}
