import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/app_prefs.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../widgets/infinite_grid.dart';
import '../widgets/movie_cards.dart';

enum DiscoverMode { forYou, trending, nowPlaying }

enum _DiscSort { popular, topRated, newest }

/// Жанр TMDB для фильтра (id стабильны, названия локализуем сами).
class _Genre {
  final int id;
  final String ru;
  final String en;
  const _Genre(this.id, this.ru, this.en);
  String get label => LocaleController.instance.code == 'en' ? en : ru;
}

const List<_Genre> _movieGenres = [
  _Genre(28, 'Боевик', 'Action'),
  _Genre(12, 'Приключения', 'Adventure'),
  _Genre(16, 'Мультфильм', 'Animation'),
  _Genre(35, 'Комедия', 'Comedy'),
  _Genre(80, 'Криминал', 'Crime'),
  _Genre(99, 'Документальный', 'Documentary'),
  _Genre(18, 'Драма', 'Drama'),
  _Genre(10751, 'Семейный', 'Family'),
  _Genre(14, 'Фэнтези', 'Fantasy'),
  _Genre(36, 'История', 'History'),
  _Genre(27, 'Ужасы', 'Horror'),
  _Genre(10402, 'Музыка', 'Music'),
  _Genre(9648, 'Детектив', 'Mystery'),
  _Genre(10749, 'Мелодрама', 'Romance'),
  _Genre(878, 'Фантастика', 'Science Fiction'),
  _Genre(53, 'Триллер', 'Thriller'),
  _Genre(10752, 'Военный', 'War'),
  _Genre(37, 'Вестерн', 'Western'),
];

const List<_Genre> _tvGenres = [
  _Genre(10759, 'Боевик и приключения', 'Action & Adventure'),
  _Genre(16, 'Мультфильм', 'Animation'),
  _Genre(35, 'Комедия', 'Comedy'),
  _Genre(80, 'Криминал', 'Crime'),
  _Genre(99, 'Документальный', 'Documentary'),
  _Genre(18, 'Драма', 'Drama'),
  _Genre(10751, 'Семейный', 'Family'),
  _Genre(10762, 'Детский', 'Kids'),
  _Genre(9648, 'Детектив', 'Mystery'),
  _Genre(10764, 'Реалити-шоу', 'Reality'),
  _Genre(10765, 'НФ и фэнтези', 'Sci-Fi & Fantasy'),
  _Genre(10766, 'Мыльная опера', 'Soap'),
  _Genre(10768, 'Война и политика', 'War & Politics'),
  _Genre(37, 'Вестерн', 'Western'),
];

/// Лента «Обзор»: популярное и «В кино» (сейчас в прокате) из TMDB одним
/// экраном — режим переключается сегментом вверху. Внутри — подвкладки Фильмы и
/// Сериалы. Общий поиск по всей базе (когда задан [query]), фильтры по
/// жанру/году и сортировка. Бесконечная ленивая подгрузка. Тап по фильму →
/// карточка, по сериалу → экран серий.
class DiscoverTab extends StatefulWidget {
  final String query;
  const DiscoverTab({super.key, this.query = ''});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  /// Плавное скрытие шапки (переключатель режима + вкладки + фильтры) при
  /// прокрутке ленты вниз и её возврат при прокрутке вверх. 1 — показана, 0 —
  /// скрыта; порог срабатывания — накопленные 50px.
  late final AnimationController _headerCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final Animation<double> _headerAnim =
      CurvedAnimation(parent: _headerCtl, curve: Curves.easeInOut);
  bool _headerHidden = false;
  double _scrollAccum = 0;

  /// Режим ленты: популярное («Обзор») или сейчас в прокате («В кино»).
  DiscoverMode _mode = DiscoverMode.trending;

  // Фильтры — свои у каждой подвкладки (жанры фильмов и сериалов различаются).
  _Genre? _mGenre, _tGenre;
  int? _mYear, _tYear;
  _DiscSort _mSort = _DiscSort.popular, _tSort = _DiscSort.popular;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // По умолчанию — «Для вас», если есть по чему персонализировать (просмотрено
    // хотя бы что-то с известным жанром).
    if (_topMovieGenreId() != null) _mode = DiscoverMode.forYou;
  }

  @override
  void dispose() {
    _tab.dispose();
    _headerCtl.dispose();
    super.dispose();
  }

  String get _q => widget.query.trim();

  /// Топ-жанр пользователя (id TMDB) по ПРОСМОТРЕННЫМ фильмам (любимые весомее),
  /// или null, если данных нет. Жанры хранятся именами → маппим на id.
  int? _topMovieGenreId() {
    final counts = <String, double>{};
    for (final m in MovieRepository.instance.movies) {
      if (m.status != LibraryStatus.watched) continue;
      final w = (m.currentScore ?? 6) >= 7 ? 2.0 : 1.0;
      for (final g in m.genres) {
        final k = g.toLowerCase().trim();
        if (k.isEmpty) continue;
        counts[k] = (counts[k] ?? 0) + w;
      }
    }
    if (counts.isEmpty) return null;
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    for (final g in _movieGenres) {
      if (g.ru.toLowerCase() == top || g.en.toLowerCase() == top) return g.id;
    }
    return null;
  }

  /// Прячет из ленты «Обзор» тайтлы, чьи статус+тип отключены в настройках
  /// (просмотрено/брошено/«буду смотреть» — отдельно для фильмов и сериалов).
  List<TmdbMovie> _hideWatchedM(List<TmdbMovie> list) {
    final repo = MovieRepository.instance;
    final p = AppPrefs.instance;
    return [
      for (final m in list)
        if (!_movieHidden(repo.movieByTmdb(m.id), p)) m
    ];
  }

  static bool _movieHidden(LibraryMovie? lib, AppPrefs p) {
    if (lib == null) return false;
    return switch (lib.status) {
      LibraryStatus.watched => p.discoverHidden(DiscoverHide.watchedMovies),
      LibraryStatus.dropped => p.discoverHidden(DiscoverHide.droppedMovies),
      LibraryStatus.watchlist => p.discoverHidden(DiscoverHide.watchlistMovies),
      LibraryStatus.library => false,
    };
  }

  List<TmdbSeries> _hideWatchedS(List<TmdbSeries> list) {
    final repo = MovieRepository.instance;
    final p = AppPrefs.instance;
    return [
      for (final s in list)
        if (!_seriesHidden(repo.seriesByTmdb(s.id), p)) s
    ];
  }

  static bool _seriesHidden(LibrarySeries? lib, AppPrefs p) {
    if (lib == null) return false;
    if (lib.dropped) return p.discoverHidden(DiscoverHide.droppedSeries);
    if (lib.watchlist && lib.episodes.isEmpty) {
      return p.discoverHidden(DiscoverHide.watchlistSeries);
    }
    if (lib.episodes.isNotEmpty) {
      return p.discoverHidden(DiscoverHide.watchedSeries);
    }
    return false;
  }

  bool get _mActive =>
      _mGenre != null || _mYear != null || _mSort != _DiscSort.popular;
  bool get _tActive =>
      _tGenre != null || _tYear != null || _tSort != _DiscSort.popular;

  String get _mSortBy => switch (_mSort) {
        _DiscSort.popular => 'popularity.desc',
        _DiscSort.topRated => 'vote_average.desc',
        _DiscSort.newest => 'primary_release_date.desc',
      };
  String get _tSortBy => switch (_tSort) {
        _DiscSort.popular => 'popularity.desc',
        _DiscSort.topRated => 'vote_average.desc',
        _DiscSort.newest => 'first_air_date.desc',
      };

  Future<List<TmdbMovie>> _movieLoader(int page) async {
    if (_q.isNotEmpty) return TmdbService.searchMovies(_q, page: page);
    List<TmdbMovie> list;
    if (_mActive) {
      list = await TmdbService.discoverMovies(
        page: page,
        genreId: _mGenre?.id,
        year: _mYear,
        sortBy: _mSortBy,
        nowPlayingWindow: _mode == DiscoverMode.nowPlaying,
      );
    } else if (_mode == DiscoverMode.forYou) {
      final g = _topMovieGenreId();
      list = g != null
          ? await TmdbService.discoverMovies(
              page: page, genreId: g, sortBy: 'popularity.desc')
          : await TmdbService.trending(page: page);
    } else if (_mode == DiscoverMode.nowPlaying) {
      list = await TmdbService.nowPlaying(page: page);
    } else {
      list = await TmdbService.trending(page: page);
    }
    return _hideWatchedM(list);
  }

  Future<List<TmdbSeries>> _seriesLoader(int page) async {
    if (_q.isNotEmpty) return TmdbService.searchTvShows(_q, page: page);
    List<TmdbSeries> list;
    if (_tActive) {
      list = await TmdbService.discoverTv(
        page: page,
        genreId: _tGenre?.id,
        year: _tYear,
        sortBy: _tSortBy,
      );
    } else if (_mode == DiscoverMode.nowPlaying) {
      list = await TmdbService.onAirTv(page: page);
    } else {
      // «Для вас» и «Обзор» → популярные сериалы (жанров сериалов в библиотеке нет)
      list = await TmdbService.trendingTv(page: page);
    }
    return _hideWatchedS(list);
  }

  /// Реакция на прокрутку ленты: копим смещение и на ±50px прячем/показываем
  /// шапку. Реагируем только на вертикаль сетки (горизонтальную прокрутку
  /// фильтров игнорируем). setState не зовём — анимируют сами Size/Fade, сетки
  /// не перестраиваются.
  bool _onGridScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification) return false;
    // У самого верха ленты шапка всегда видна.
    if (n.metrics.pixels <= 4) {
      _scrollAccum = 0;
      if (_headerHidden) _setHeader(hidden: false);
      return false;
    }
    final d = n.scrollDelta ?? 0;
    if (d == 0) return false;
    // Смена направления прокрутки — сбрасываем накопитель.
    if ((d > 0) != (_scrollAccum >= 0)) _scrollAccum = 0;
    _scrollAccum += d;
    if (_scrollAccum >= 50 && !_headerHidden) {
      _scrollAccum = 0;
      _setHeader(hidden: true);
    } else if (_scrollAccum <= -50 && _headerHidden) {
      _scrollAccum = 0;
      _setHeader(hidden: false);
    }
    return false;
  }

  void _setHeader({required bool hidden}) {
    _headerHidden = hidden;
    hidden ? _headerCtl.reverse() : _headerCtl.forward();
  }

  /// Обёртка для плавного сворачивания части шапки (высота + прозрачность).
  Widget _collapsible(Widget child) => SizeTransition(
        sizeFactor: _headerAnim,
        axisAlignment: -1,
        child: FadeTransition(opacity: _headerAnim, child: child),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final mKey =
        'm|$_mode|$_q|${_mGenre?.id}|$_mYear|$_mSort|${_topMovieGenreId()}';
    final tKey = 's|$_mode|$_q|${_tGenre?.id}|$_tYear|$_tSort';
    // Прокрутка ленты вниз плавно прячет шапку (переключатель + вкладки +
    // фильтры) — на «Обзоре» она занимала пол-экрана; вверх — возвращает.
    return NotificationListener<ScrollNotification>(
      onNotification: _onGridScroll,
      child: Column(
        children: [
          _collapsible(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_q.isEmpty) _modeToggle(scheme),
                TabBar(
                  controller: _tab,
                  labelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  indicatorColor: scheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                  unselectedLabelStyle: const TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                  tabs: [
                    Tab(text: tr('filter_movies')),
                    Tab(text: tr('filter_series')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                Column(
                  children: [
                    // Фильтры действуют на ленту; при поиске идёт глобальный
                    // поиск по базе — панель скрываем.
                    if (_q.isEmpty) _collapsible(_filterBar(movies: true)),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: MovieRepository.instance,
                        builder: (context, _) => InfiniteGrid<TmdbMovie>(
                          reloadKey: mKey,
                          loader: _movieLoader,
                          itemBuilder: (context, m, w) =>
                              DiscoverMovieCard(movie: m, width: w),
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    if (_q.isEmpty) _collapsible(_filterBar(movies: false)),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: MovieRepository.instance,
                        builder: (context, _) => InfiniteGrid<TmdbSeries>(
                          reloadKey: tKey,
                          loader: _seriesLoader,
                          itemBuilder: (context, s, w) =>
                              DiscoverSeriesCard(series: s, width: w),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Переключатель режима ленты: «Обзор» (популярное) ↔ «В кино» (в прокате).
  Widget _modeToggle(ColorScheme scheme) {
    Widget seg(DiscoverMode m, String label, IconData icon) {
      final selected = _mode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _mode = m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          seg(DiscoverMode.forYou, tr('disc_for_you'),
              Icons.auto_awesome_rounded),
          seg(DiscoverMode.trending, tr('nav_discover'), Icons.explore_rounded),
          seg(DiscoverMode.nowPlaying, tr('nav_cinema'),
              Icons.local_movies_rounded),
        ],
      ),
    );
  }

  // ----------------------------- фильтры -----------------------------

  Widget _filterBar({required bool movies}) {
    final genre = movies ? _mGenre : _tGenre;
    final year = movies ? _mYear : _tYear;
    final sort = movies ? _mSort : _tSort;
    final active = movies ? _mActive : _tActive;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        children: [
          _chip(
            label: genre?.label ?? tr('filter_genre'),
            selected: genre != null,
            icon: Icons.theater_comedy_rounded,
            onTap: () => _pickGenre(movies),
          ),
          const SizedBox(width: 8),
          _chip(
            label: year?.toString() ?? tr('filter_year'),
            selected: year != null,
            icon: Icons.calendar_month_rounded,
            onTap: () => _pickYear(movies),
          ),
          const SizedBox(width: 8),
          _chip(
            label: _sortLabel(sort),
            selected: sort != _DiscSort.popular,
            icon: Icons.sort_rounded,
            onTap: () => _pickSort(movies),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            _chip(
              label: tr('reset'),
              selected: false,
              icon: Icons.filter_alt_off_rounded,
              onTap: () => setState(() {
                if (movies) {
                  _mGenre = null;
                  _mYear = null;
                  _mSort = _DiscSort.popular;
                } else {
                  _tGenre = null;
                  _tYear = null;
                  _tSort = _DiscSort.popular;
                }
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primary,
      avatar: Icon(icon,
          size: 17,
          color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
      label: Text(label),
      labelStyle: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
      onSelected: (_) {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }

  String _sortLabel(_DiscSort s) => switch (s) {
        _DiscSort.popular => tr('sort_popular'),
        _DiscSort.topRated => tr('sort_top_rated'),
        _DiscSort.newest => tr('sort_new_release'),
      };

  void _pickGenre(bool movies) {
    final genres = movies ? _movieGenres : _tvGenres;
    final current = movies ? _mGenre : _tGenre;
    _sheet(
      title: tr('filter_genre'),
      children: [
        _sheetTile(tr('all_genres'), current == null, () {
          setState(() => movies ? _mGenre = null : _tGenre = null);
          Navigator.pop(context);
        }),
        for (final g in genres)
          _sheetTile(g.label, current?.id == g.id, () {
            setState(() => movies ? _mGenre = g : _tGenre = g);
            Navigator.pop(context);
          }),
      ],
    );
  }

  void _pickYear(bool movies) {
    final now = DateTime.now().year;
    final current = movies ? _mYear : _tYear;
    _sheet(
      title: tr('filter_year'),
      children: [
        _sheetTile(tr('all_years'), current == null, () {
          setState(() => movies ? _mYear = null : _tYear = null);
          Navigator.pop(context);
        }),
        for (var y = now; y >= 1950; y--)
          _sheetTile('$y', current == y, () {
            setState(() => movies ? _mYear = y : _tYear = y);
            Navigator.pop(context);
          }),
      ],
    );
  }

  void _pickSort(bool movies) {
    final current = movies ? _mSort : _tSort;
    _sheet(
      title: tr('sort'),
      children: [
        for (final s in _DiscSort.values)
          _sheetTile(_sortLabel(s), current == s, () {
            setState(() => movies ? _mSort = s : _tSort = s);
            Navigator.pop(context);
          }),
      ],
    );
  }

  Widget _sheetTile(String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(label,
          style: const TextStyle(
              fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w600)),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: scheme.primary)
          : null,
      onTap: onTap,
    );
  }

  void _sheet({required String title, required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: scheme.onSurface)),
              ),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: children),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
