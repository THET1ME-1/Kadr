import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/app_prefs.dart';
import '../services/facts_service.dart';
import '../services/movie_repository.dart';
import '../services/social/social_controller.dart';
import '../services/store.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../utils/season_pass.dart';
import '../utils/season_pick.dart';
import '../utils/season_progress.dart';
import '../utils/series_finale.dart';
import '../services/youtube_service.dart';
import '../widgets/action_group.dart';
import '../widgets/series_progress.dart';
import '../widgets/youtube_parts.dart';
import '../widgets/facts_section.dart';
import '../widgets/pop_icon.dart';
import '../widgets/poster.dart';
import '../widgets/poster_viewer.dart';
import '../widgets/pressable.dart';
import '../widgets/rating_slider.dart';
import '../widgets/favorite_character.dart';
import '../widgets/reveal.dart';
import '../widgets/score_pad.dart';
import '../widgets/season_pill.dart';
import '../widgets/undo_snack.dart';
import '../widgets/viewing/pass_strip.dart';
import 'browse_screens.dart';
import 'delete_helpers.dart';
import 'episode_grid_sheet.dart';
import 'series_stats_screen.dart';
import 'social/media_image_picker.dart';
import 'review/series_reviews_section.dart';
import 'viewing/episode_sheet.dart';
import 'viewing/mark_sheet.dart';
import 'viewing/viewing_delete.dart';
import 'viewing/viewing_host.dart';
import 'viewing/viewing_sheet.dart';

/// Экран сериала (M3 Expressive): крупная шапка с бэкдропом, оценка всего
/// сериала, выбор сезона, отметка «весь сезон разом», а у каждой серии —
/// галочка просмотра, повторные просмотры и своя оценка. Серии тянутся из TMDB,
/// поэтому можно отмечать даже те, которых ещё нет в библиотеке.
class SeriesScreen extends StatefulWidget {
  final LibrarySeries series;
  final String? heroTag;
  const SeriesScreen({super.key, required this.series, this.heroTag});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  final _repo = MovieRepository.instance;
  int? _tmdbId;
  List<TmdbSeason> _seasons = [];
  int? _season;
  List<TmdbEpisode>? _eps;
  TmdbTvExtra? _extra;
  bool _loading = true;
  bool _error = false;

  /// Последовательный режим: отметил серию → отмечаются и все до неё. Снятие
  /// по порядку настраивается отдельно, см. [AppPrefs.sequentialUnmark].
  bool _sequential = true;

  /// Запрет отмечать/оценивать невышедшие серии.
  bool _restrictUnaired = true;

  LibrarySeries get s =>
      _repo.seriesById(widget.series.tvShowId) ?? widget.series;

  @override
  void initState() {
    super.initState();
    Store.instance.getBool('sequentialEpisodes', def: true).then((v) {
      if (mounted) setState(() => _sequential = v);
    });
    Store.instance.getBool('restrictUnaired', def: true).then((v) {
      if (mounted) setState(() => _restrictUnaired = v);
    });
    _init();
  }

  /// Вышла ли серия (или запрет выключен). Неизвестная/непарсимая дата — не
  /// блокируем.
  bool _aired(TmdbEpisode ep) {
    if (!_restrictUnaired) return true;
    final d = ep.airDate;
    if (d == null || d.isEmpty) return true;
    final parsed = DateTime.tryParse(d);
    if (parsed == null) return true;
    return !parsed.isAfter(DateTime.now());
  }

  // ---- порядок серий (для последовательного режима) ----

  /// Все серии сериала по порядку: [[сезон, номер], …] из списка сезонов.
  List<List<int>> get _orderedAll => [
        for (final se in _seasons)
          for (var n = 1; n <= se.episodeCount; n++) [se.number, n]
      ];

  /// Серии от начала до (season, number) включительно.
  List<List<int>> _orderedUpTo(int season, int number) {
    final out = <List<int>>[];
    for (final e in _orderedAll) {
      out.add(e);
      if (e[0] == season && e[1] == number) break;
    }
    return out;
  }

  // ---- действия с серией (учитывают последовательный режим) ----

  EpisodeViewingHost _hostOf(TmdbEpisode ep) => EpisodeViewingHost(
      s.tvShowId, ep.season, ep.number,
      runtimeMin: ep.runtime, repo: _repo);

  /// Тап по галочке серии и «Смотрел ещё раз» в окне серии: окно отметки с
  /// номером будущего просмотра, затем запись с выбранной датой.
  Future<void> _tapCheck(TmdbEpisode ep) async {
    final we = s.watchedEpisode(ep.season, ep.number);
    if (we == null && !_aired(ep)) {
      _snack(tr('episode_not_aired'));
      return;
    }
    final choice = await showMarkSheet(
      context,
      title: tr('mark_q'),
      subject: 'S${ep.season} · E${ep.number} · ${ep.name}',
      ordinal: (we?.watchCount ?? 0) + 1,
    );
    if (choice == null || !mounted) return;
    await _addEpisodeView(ep, choice.date);
  }

  /// Записывает просмотр серии с датой [date] (null — «не помню»). Первый
  /// просмотр в последовательном режиме отмечает и все серии до неё, с той
  /// же датой; у уже отмеченной серии это пересмотр.
  Future<void> _addEpisodeView(TmdbEpisode ep, DateTime? date) async {
    if (s.isEpisodeWatched(ep.season, ep.number)) {
      await _repo.addEpisodeView(s.tvShowId, ep.season, ep.number,
          date: date, runtimeMin: ep.runtime);
    } else if (_sequential) {
      await _repo.markEpisodesBulk(
          s.tvShowId, _orderedUpTo(ep.season, ep.number),
          at: date, undated: date == null);
    } else {
      await _repo.markEpisodeWatched(s.tvShowId, ep.season, ep.number,
          runtimeMin: ep.runtime, at: date, undated: date == null);
    }
    HapticFeedback.selectionClick();
  }

  /// Удержание галочки отмеченной серии: окно её последнего просмотра.
  void _openViewing(TmdbEpisode ep, Episode watched) => showViewingSheet(
      context, _hostOf(ep),
      viewId: watched.orderedViews.last.id);

  /// Отмечает серию просмотренной с НЕИЗВЕСТНОЙ датой (удержание галочки у
  /// неотмеченной). Такая серия не попадает в ленту «Просмотрено».
  void _markUnknownDate(TmdbEpisode ep) {
    if (s.watchedEpisode(ep.season, ep.number) == null && !_aired(ep)) {
      _snack(tr('episode_not_aired'));
      return;
    }
    _repo.markEpisodeUnknown(s.tvShowId, ep.season, ep.number,
        runtimeMin: ep.runtime);
    HapticFeedback.selectionClick();
    _snack(tr('marked_unknown'));
  }

  /// Статистика сериала: время, даты и путь по сезонам.
  void _openStats() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeriesStatsScreen(
        series: s,
        seasons: List.of(_seasons),
        tmdbId: _tmdbId,
      ),
    ));
  }

  /// Картинка с оценками всех серий. Структура та же, что на экране: сезоны и
  /// число серий из TMDB, без спецвыпусков.
  void _shareGrid() {
    showEpisodeGridSheet(context, s, {
      for (final se in _seasons)
        if (se.number > 0) se.number: se.episodeCount,
    });
  }

  /// Полностью удалить сериал из базы (для мусорных/ненаходимых) → закрыть экран.
  Future<void> _deleteSeriesFromBase() async {
    await deleteSeriesFromBase(context, s);
    if (mounted && _repo.seriesById(s.tvShowId) == null) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    // Цикл с YouTube: выпуски уже в библиотеке, TMDB не спрашиваем.
    if (s.isYouTube) {
      setState(() {
        _applyYouTube();
        _loading = false;
      });
      unawaited(_refreshYouTube());
      return;
    }
    var id = widget.series.tmdbId;
    if (id == null) {
      final m = await TmdbService.searchTv(widget.series.title);
      id = m?.tmdbId;
      if (id != null) {
        widget.series.tmdbId = id;
        await _repo.enrichSeries(widget.series);
      }
    }
    _tmdbId = id;
    if (id == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    final tmdbSeasons = await TmdbService.seasons(id);
    _extra = await TmdbService.tvExtra(id);
    // Постер сериала — из тех же tv-деталей, что и бэкдроп (фикс «чужого постера»).
    if (_extra?.posterUrl != null && _extra!.posterUrl != s.posterUrl) {
      await _repo.setSeriesPoster(s.tvShowId, _extra!.posterUrl!);
    }
    // TMDB — источник истины структуры. Библиотечные сезоны берём лишь когда
    // TMDB ничего не отдал (сериал не найден).
    _seasons = _mergeLibrarySeasons(tmdbSeasons);
    if (_seasons.isEmpty) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    // НЕ удаляем серии автоматически по структуре TMDB: авто-совпадение шоу
    // часто НЕТОЧНОЕ, и такая чистка стирала реальные серии пользователя. Лишние
    // серии просто показываются как есть; структуру TMDB используем только для
    // отображения (галочки/счётчик), но данные не трогаем.
    // Запоминаем общее число серий (для «Сейчас смотрю» — только незавершённые).
    final total = _seasons.fold<int>(0, (a, b) => a + b.episodeCount);
    await _repo.setSeriesTotal(s.tvShowId, total);
    await _repo.setSeriesYear(s.tvShowId, _extra?.year);
    final air = await TmdbService.airOf(id);
    if (air != null) await _repo.setSeriesAir(s.tvShowId, air);
    // Импорт TV Time мог сохранить серии только датами (без сезона/номера) —
    // раскладываем их по сериям TMDB по порядку, чтобы галочки совпали со счётчиком.
    if (s.episodes.any((e) => e.season == null || e.number == null)) {
      final ordered = <List<int>>[];
      for (final se in _seasons) {
        for (var n = 1; n <= se.episodeCount; n++) {
          ordered.add([se.number, n]);
        }
      }
      await _repo.reconcileSeriesEpisodes(s.tvShowId, ordered);
    }
    _season = await pickInitialSeason(
      seasons: _seasons,
      watched: s.episodes,
      episodesOf: (n) => TmdbService.episodesOf(_tmdbId!, n),
    );
    if (!mounted) return;
    await _loadSeason(_season!);
    if (mounted) setState(() => _loading = false);
  }

  /// Цикл с YouTube (макет «Циклы с YouTube», Э1): один сезон, выпуск —
  /// серия с кадром, подзаголовком или днём выхода и длиной ролика.
  void _applyYouTube() {
    final yt = s.youtube!;
    _seasons = [
      TmdbSeason(
          number: 1, name: tr('yt_issues'), episodeCount: yt.videos.length),
    ];
    _season = 1;
    _eps = [
      for (var i = 0; i < yt.videos.length; i++)
        () {
          final v = yt.videos[i];
          final p = v.published;
          return TmdbEpisode(
            season: 1,
            number: i + 1,
            name: ytSubtitle(v.title) ??
                (p != null ? trf('yt_published', {'date': longDate(p)}) : ''),
            airDate: p?.toIso8601String(),
            stillUrl: v.still,
            runtime: v.runtimeMin,
          );
        }(),
    ];
  }

  /// Свежие выпуски цикла: лента канала и плейлист, новые встают в конец.
  /// Заодно дозаполняет даты выхода старым выпускам.
  Future<void> _refreshYouTube() async {
    final yt = s.youtube;
    if (yt == null) return;
    final fresh = await YouTubeService.newVideos(yt, s.title,
        fullEvery: const Duration(hours: 12));
    final missing = [
      for (final v in [...yt.videos, ...?fresh])
        if (v.published == null) v,
    ];
    final dated = missing.isEmpty
        ? 0
        : await YouTubeService.fillDates(missing, limit: 12);
    if (fresh != null || dated > 0) {
      await _repo.appendYouTubeVideos(s.tvShowId, fresh ?? const []);
    }
    if (mounted && s.isYouTube) setState(_applyYouTube);
  }

  /// Первый непросмотренный выпуск цикла; null — всё просмотрено.
  int? get _nextIssue {
    final yt = s.youtube;
    if (yt == null) return null;
    for (var n = 1; n <= yt.videos.length; n++) {
      if (!s.isEpisodeWatched(1, n)) return n;
    }
    return null;
  }

  Future<void> _loadSeason(int n) async {
    if (s.isYouTube) return;
    setState(() => _eps = null);
    final eps = await TmdbService.episodesOf(_tmdbId!, n);
    if (mounted) setState(() => _eps = _mergeLibraryEpisodes(n, eps));
  }

  /// Список сезонов. TMDB — источник истины: если он знает сезоны сериала,
  /// показываем ТОЛЬКО их (реальную структуру шоу). Библиотечные «хвосты» от
  /// неточного матча (лишние серии/сезоны, спецвыпуски) не подмешиваем.
  /// Библиотечные сезоны берём лишь когда TMDB ничего не отдал (сериал не
  /// найден) — чтобы не потерять просмотренные серии, исключая спецвыпуски.
  List<TmdbSeason> _mergeLibrarySeasons(List<TmdbSeason> tmdb) {
    if (tmdb.isNotEmpty) return tmdb;
    final libMax = <int, int>{}; // сезон → макс. номер серии
    final libCount = <int, int>{}; // сезон → сколько серий отмечено
    for (final e in s.episodes) {
      final se = e.season;
      if (se == null || se < 1) continue; // спецвыпуски (сезон 0) пропускаем
      libCount[se] = (libCount[se] ?? 0) + 1;
      final num = e.number;
      if (num != null && num >= 1) {
        libMax[se] = (libMax[se] == null || num > libMax[se]!) ? num : libMax[se]!;
      }
    }
    final nums = libCount.keys.toList()..sort();
    return [
      for (final n in nums)
        TmdbSeason(
          number: n,
          name: 'Сезон $n',
          episodeCount: [libMax[n] ?? 0, libCount[n] ?? 0]
              .reduce((a, b) => a > b ? a : b),
        ),
    ];
  }

  /// Серии сезона. Если TMDB знает серии — показываем только их (реальный набор,
  /// без библиотечных хвостов сверх числа серий и без спецвыпусков). Только
  /// когда TMDB не вернул серий, показываем просмотренные из библиотеки
  /// (исключая спецвыпуски number ≤ 0), чтобы их было видно и можно было снять.
  List<TmdbEpisode> _mergeLibraryEpisodes(int season, List<TmdbEpisode> tmdb) {
    if (tmdb.isNotEmpty) return tmdb;
    final extra = <TmdbEpisode>[];
    final seen = <int>{};
    for (final e in s.episodes) {
      final num = e.number;
      if (e.season != season || num == null || num < 1 || seen.contains(num)) {
        continue;
      }
      seen.add(num);
      extra.add(TmdbEpisode(season: season, number: num, name: 'Серия $num'));
    }
    extra.sort((a, b) => a.number.compareTo(b.number));
    return extra;
  }

  /// Сколько серий просмотрено В ПРЕДЕЛАХ показываемой структуры (сезоны/серии
  /// из [_seasons]). Библиотека могла накопить серии от неточного матча
  /// (напр. мультсериал, привязанный к 8-серийному ремейку) — их не считаем,
  /// иначе шапка показывает «45 из 8».
  int _seenInStructure() {
    final bounds = {for (final se in _seasons) se.number: se.episodeCount};
    var n = 0;
    for (final e in s.episodes) {
      final se = e.season, num = e.number;
      if (se == null || num == null || num < 1) continue;
      final cap = bounds[se];
      if (cap == null || num > cap) continue;
      n++;
    }
    return n;
  }

  // ------------------------------ build ------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Полупрозрачный кружок под стрелкой — читается и на бэкдропе, и когда
        // под шапку уезжает светлый контент списка.
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Material(
            color: Colors.black.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                onSelected: (v) {
                  if (v == 'stats') _openStats();
                  if (v == 'grid') _shareGrid();
                  if (v == 'delete') _deleteSeriesFromBase();
                  if (v == 'yt_list') openYouTube(s.youtube!.url);
                  if (v == 'yt_notify') {
                    _repo.setYouTubeNotify(s.tvShowId, !s.youtube!.notify);
                  }
                },
                itemBuilder: (context) => [
                  if (s.youtube != null) ...[
                    PopupMenuItem(
                      value: 'yt_list',
                      child: Row(
                        children: [
                          Icon(Icons.smart_display_rounded,
                              size: 20, color: scheme.primary),
                          const SizedBox(width: 10),
                          Text(tr('yt_open_playlist')),
                        ],
                      ),
                    ),
                    CheckedPopupMenuItem(
                      value: 'yt_notify',
                      checked: s.youtube!.notify,
                      child: Text(tr('yt_notify')),
                    ),
                  ],
                  PopupMenuItem(
                    value: 'stats',
                    child: Row(
                      children: [
                        Icon(Icons.insights_rounded,
                            size: 20, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text(tr('drawer_stats')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'grid',
                    child: Row(
                      children: [
                        Icon(Icons.grid_view_rounded,
                            size: 20, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text(tr('grid_share')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever_rounded,
                            size: 20, color: scheme.error),
                        const SizedBox(width: 10),
                        Text(tr('delete_from_base')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _hero(scheme)),
              if (_error)
                SliverToBoxAdapter(child: _errorCard(context))
              else ...[
                SliverToBoxAdapter(child: _actions(scheme)),
                // Без рецензий блока нет: «Рецензия» живёт в группе под
                // оценкой, как у карточки фильма.
                if (s.hasReview || s.seasonReviews.any((p) => p.hasReview))
                  SliverToBoxAdapter(
                      child: SeriesReviewsSection(
                          series: s, repo: _repo, seasons: _seasons)),
                if (_seasons.length > 1)
                  SliverToBoxAdapter(child: _seasonBar(scheme)),
                SliverToBoxAdapter(child: _seasonToolbar(scheme)),
                if (_eps == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Reveal(
                        delay: Duration(milliseconds: (i % 6) * 28),
                        child: _episodeTile(scheme, _eps![i]),
                      ),
                      childCount: _eps!.length,
                    ),
                  ),
                if (_extra?.cast.isNotEmpty ?? false)
                  SliverToBoxAdapter(child: _castSection(scheme)),
                // Факты ищутся по названию в Кинопоиске: циклу с YouTube
                // они чужие.
                if (!s.isYouTube)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FactsSection(
                      key: ValueKey('facts-series-${s.tvShowId}'),
                      loader: () => FactsService.forMovie(
                        kinopoiskId: s.kinopoiskId,
                        imdbId: s.imdbId,
                        title: s.displayTitle,
                        year: s.year,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ],
          );
        },
      ),
    );
  }

  /// Актёры сериала (как в карточке фильма). Тап → фильмография актёра,
  /// долгое нажатие → «сделать любимым персонажем».
  Widget _castSection(ColorScheme scheme) {
    final cast = _extra!.cast;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 12),
            child: Text(tr('cast'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: scheme.primary)),
          ),
          SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (c, i) => Pressable(
                scale: 1,
                haptic: false,
                onTap: cast[i].id > 0
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PersonScreen(
                            personId: cast[i].id,
                            personName: cast[i].name,
                            personPhoto: cast[i].photoUrl)))
                    : null,
                onLongPress: () =>
                    promptFavoriteCharacter(context, cast[i], s.displayTitle),
                child: _castCard(scheme, cast[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _castCard(ColorScheme scheme, TmdbCast c) {
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: scheme.surfaceContainerHighest),
            clipBehavior: Clip.antiAlias,
            child: c.photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: c.photoUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth:
                        (72 * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorWidget: (ctx, u, e) => Icon(Icons.person_rounded,
                        color: scheme.onSurfaceVariant, size: 34),
                  )
                : Icon(Icons.person_rounded,
                    color: scheme.onSurfaceVariant, size: 34),
          ),
          const SizedBox(height: 6),
          Text(c.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  height: 1.1,
                  color: scheme.onSurface)),
          if (c.character != null && c.character!.isNotEmpty)
            Text(c.character!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ------------------------------ шапка ------------------------------

  Widget _hero(ColorScheme scheme) {
    final total = _seasons.fold<int>(0, (a, b) => a + b.episodeCount);
    final seen = _seenInStructure();
    final progress = total > 0 ? (seen / total).clamp(0.0, 1.0) : 0.0;
    final yt = s.youtube;
    // У цикла с YouTube вместо бэкдропа кадр первого выпуска.
    final backdrop = yt != null && yt.videos.isNotEmpty
        ? yt.videos.first.cover
        : _extra?.backdropUrl;
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Бэкдроп (или цветной градиент, если его нет) с затемнением снизу.
          if (backdrop != null)
            CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (c, _) =>
                  Container(color: scheme.surfaceContainerHighest),
              errorWidget: (c, u, e) => _gradientBg(scheme),
            )
          else
            _gradientBg(scheme),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black45, Colors.transparent, Colors.black87],
                stops: [0, 0.32, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Pressable(
                  scale: 1,
                  haptic: false,
                  onTap: () => openPosterViewer(context,
                      title: s.displayTitle,
                      url: s.displayPoster,
                      heroTag: widget.heroTag ?? 'sposter-${s.tvShowId}'),
                  onLongPress: () => _editSeriesPoster(s),
                  child: Hero(
                    tag: widget.heroTag ?? 'sposter-${s.tvShowId}',
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      shadowColor: Colors.black54,
                      child: Poster(
                          title: s.displayTitle,
                          url: s.displayPoster,
                          width: 104,
                          radius: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.displayTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                              height: 1.05,
                              color: Colors.white)),
                      if (yt != null) ...[
                        const SizedBox(height: 8),
                        YtChannelLine(name: yt.channelName, avatar: yt.avatar),
                      ],
                      const SizedBox(height: 8),
                      // Счётчик «Просмотрено N из M» и полоса заполняются с
                      // анимацией при открытии: число быстро тикает 0→N, полоса
                      // едет слева направо. Ключ по «данные загружены» → анимация
                      // играет раз (когда появляются реальные числа) и не
                      // переигрывает при отметке серий.
                      TweenAnimationBuilder<double>(
                        key: ValueKey(total > 0),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        tween: Tween<double>(begin: 0, end: 1),
                        builder: (context, t, _) {
                          final shown = (seen * t).round();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  total > 0
                                      ? trf('seen_of', {'n': shown, 'm': total})
                                      : trf('episodes_n', {'n': shown}),
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 13,
                                      color:
                                          Colors.white.withValues(alpha: 0.85))),
                              if (total > 0) ...[
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: progress * t,
                                    minHeight: 8,
                                    backgroundColor: Colors.white24,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      // Досмотрел или догнал: таблетка с датой финала или с
                      // тем, чего ждём.
                      if (statusPill(s) != null) ...[
                        const SizedBox(height: 10),
                        SeriesStatusPill(series: s),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientBg(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
        ),
      );

  // ----------------------- действия (оценка/избранное) -----------------------

  /// Замена постера сериала: выбор из галереи, из официальных постеров TMDB
  /// или сброс к оригиналу (долгое нажатие на постер).
  Future<void> _editSeriesPoster(LibrarySeries s) async {
    final scheme = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.image_rounded, color: scheme.primary),
              title: Text(tr('banner_choose')),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            ListTile(
              leading: Icon(Icons.movie_filter_rounded, color: scheme.primary),
              title: Text(tr('pick_from_poster')),
              onTap: () => Navigator.pop(ctx, 'tmdb'),
            ),
            if (s.posterFile != null)
              ListTile(
                leading: Icon(Icons.restore_rounded,
                    color: scheme.onSurfaceVariant),
                title: Text(tr('poster_reset')),
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reset') {
      await _repo.clearSeriesPosterLocal(s.tvShowId);
      if (mounted) setState(() {});
      return;
    }
    if (action == 'tmdb') {
      final url = await showMediaImagePicker(
        context,
        backdrop: false,
        initialTmdbId: _tmdbId ?? s.tmdbId,
        initialIsTv: true,
        initialTitle: s.title,
      );
      if (!mounted || url == null) return;
      final ok = await _repo.setSeriesPosterFromUrl(s.tvShowId, url);
      if (!mounted) return;
      if (ok) {
        setState(() {});
      } else {
        _snack(tr('poster_load_failed'));
      }
      return;
    }
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final raw = f.bytes ??
          (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (raw == null) return;
      final ok = await _repo.setSeriesPosterLocal(s.tvShowId, raw);
      if (mounted && ok) setState(() {});
    } catch (_) {/* отмена/ошибка выбора файла — игнорируем */}
  }

  Widget _actions(ColorScheme scheme) {
    // Если у серий есть оценки — показываем их среднее (считается автоматически).
    // Ручная оценка сериала доступна ТОЛЬКО когда ни одна серия не оценена.
    // Оценку может давать свод рецензий или рецензия на весь сериал, если
    // человек нажал «Выставить сериалу»; тогда под кнопкой строка «Вернуть».
    final epAvg = s.episodeScoreAvg;
    final rvAvg = switch (s.scoreSource) {
      SeriesScoreSource.reviews => s.seasonReviewsAverage,
      SeriesScoreSource.review => s.reviewMeta?.average,
      SeriesScoreSource.episodes => null,
    };
    final fromReviews = rvAvg != null;
    final fromEp = !fromReviews && epAvg != null;
    final sc = rvAvg ?? epAvg ?? s.score;
    final own = epAvg ?? s.score;
    final label = fromReviews
        ? tr(s.scoreSource == SeriesScoreSource.reviews
            ? 'rvs_by_reviews'
            : 'rvs_by_review')
        : fromEp
            ? tr(s.isYouTube ? 'yt_avg' : 'avg_of_episodes')
            : tr('series_rating');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: sc != null ? scoreColor(sc) : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: fromReviews
                  ? () => _snack(tr('rvs_score_locked'))
                  : fromEp
                      ? () => _snack(tr('series_avg_locked'))
                      : _rateSeries,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        fromReviews
                            ? Icons.rate_review_rounded
                            : sc != null
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                        size: 20,
                        color: sc != null
                            ? onScoreColor(sc)
                            : scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    // Длинная подпись свода ужимается, а не вылезает за край.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          sc != null
                              ? '${sc.toStringAsFixed(1)} · $label'
                              : tr('rate_series'),
                          maxLines: 1,
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: sc != null
                                  ? onScoreColor(sc)
                                  : scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (fromReviews)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 6),
              child: Row(
                children: [
                  Icon(Icons.undo_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        own != null
                            ? trf('rvs_episodes_line',
                                {'v': own.toStringAsFixed(1)})
                            : tr('avg_of_episodes'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: scheme.onSurfaceVariant)),
                  ),
                  TextButton(
                    onPressed: () => _repo.setSeriesScoreSource(
                        s.tvShowId, SeriesScoreSource.episodes),
                    child: Text(tr('rvs_back')),
                  ),
                ],
              ),
            ),
          // Цикл с YouTube: главная кнопка ведёт на первый непросмотренный
          // выпуск (вариант Э1 макета «Циклы с YouTube»).
          if (_nextIssue != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () =>
                    openYouTube(s.youtube!.entryAt(_nextIssue!)!.url),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  trf('yt_watch_n', {'n': s.youtube!.labelOf(_nextIssue!)}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _actionGroup(scheme),
        ],
      ),
    );
  }

  /// Связанная группа под оценкой, как у карточки фильма (вариант Б макета
  /// «Кнопки карточки»): любимое, рецензия или «Буду смотреть», закладка и
  /// «Бросить». Широкие кнопки стопкой не возвращать. Списков и совета
  /// другу у сериала нет: они бывают только у фильмов.
  Widget _actionGroup(ColorScheme scheme) {
    final started = s.episodes.isNotEmpty;
    return ActionGroup([
      ActionGroupButton.icon(
        tooltip: tr('act_favorite'),
        active: s.favorite,
        onPressed: () {
          HapticFeedback.lightImpact();
          _repo.toggleSeriesFavorite(s.tvShowId);
        },
        child: PopIcon(
          active: s.favorite,
          activeIcon: Icons.favorite_rounded,
          inactiveIcon: Icons.favorite_border_rounded,
          activeColor: scheme.onPrimary,
          inactiveColor: scheme.onSecondaryContainer,
          size: 24,
        ),
      ),
      if (started)
        ActionGroupButton.label(
          icon: Icons.rate_review_rounded,
          label: tr('view_review'),
          onPressed: () =>
              startSeriesReview(context, s, seasons: _seasons, repo: _repo),
        )
      else
        ActionGroupButton.label(
          icon: s.watchlist
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          label: tr(s.watchlist ? 'in_watchlist' : 'add_watchlist'),
          active: s.watchlist,
          onPressed: _toggleWatchlist,
        ),
      // Начатый сериал из «Буду смотреть»: закладкой отметку можно снять.
      if (started && s.watchlist)
        ActionGroupButton.icon(
          tooltip: tr('in_watchlist'),
          active: true,
          onPressed: _toggleWatchlist,
          child: const Icon(Icons.bookmark_rounded),
        ),
      ActionGroupButton.icon(
        tooltip: tr(s.dropped ? 'in_dropped' : 'mark_dropped'),
        active: s.dropped,
        activeColor: kDroppedColor,
        tint: kDroppedColor,
        onPressed: () {
          HapticFeedback.lightImpact();
          _repo.toggleSeriesDropped(s.tvShowId);
        },
        child: Icon(s.dropped
            ? Icons.heart_broken_rounded
            : Icons.heart_broken_outlined),
      ),
    ]);
  }

  void _toggleWatchlist() {
    final adding = !s.watchlist;
    _repo.toggleSeriesWatchlist(s.tvShowId);
    if (adding) _snack(tr('added_to_watchlist'));
  }

  // ----------------------------- сезоны -----------------------------

  /// Таблетки сезонов: заполняются по ходу сезона, досмотренный с галочкой
  /// (вариант S3 макета). Доля считается по числу серий сезона из TMDB.
  Widget _seasonBar(ColorScheme scheme) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final se in _seasons)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Builder(builder: (context) {
                final p = seasonProgress(s, se.number, se.episodeCount);
                return SeasonPill(
                  label: trf('season_n', {'n': se.number}),
                  fraction: p.fraction,
                  done: p.done,
                  selected: _season == se.number,
                  onTap: () {
                    setState(() => _season = se.number);
                    _loadSeason(se.number);
                  },
                );
              }),
            ),
        ],
      ),
    );
  }

  /// Панель сезона: оценка и дата разом и широкая кнопка просмотра сезона.
  /// Под ней полоса пересмотра, когда сезон смотрят не в первый раз.
  Widget _seasonToolbar(ColorScheme scheme) {
    final eps = _eps;
    if (eps == null || eps.isEmpty || _season == null) {
      return const SizedBox.shrink();
    }
    // Просмотр сезона считаем по ВЫШЕДШИМ сериям.
    final aired = eps.where(_aired).toList();
    final st = seasonPass(s, _season!, [for (final e in aired) e.number]);
    // Кнопка называет следующий шаг: отметить сезон, досмотреть оставшиеся
    // серии идущего просмотра или начать пересмотр.
    final label = switch (st.action) {
      SeasonAction.rewatch => tr('rewatch_season'),
      SeasonAction.markRest => trf('mark_more_n', {'n': st.left}),
      SeasonAction.markAll => tr(s.isYouTube ? 'yt_mark_all' : 'mark_season'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          _seasonButtons(
              scheme, st, aired, label, st.action == SeasonAction.rewatch),
          if (st.showsStrip) PassStrip(state: st),
        ],
      ),
    );
  }

  Widget _seasonButtons(ColorScheme scheme, SeasonPassState st,
      List<TmdbEpisode> aired, String label, bool rewatch) {
    return Row(
      children: [
        // Разом поставить одну оценку всем просмотренным сериям сезона.
        IconButton.filledTonal(
          onPressed: _rateSeason,
          icon: const Icon(Icons.star_rounded),
          tooltip: tr('rate_season'),
        ),
        const SizedBox(width: 8),
        // Массово задать дату просмотра всем сериям сезона.
        IconButton.filledTonal(
          onPressed: _seasonDate,
          icon: const Icon(Icons.event_rounded),
          tooltip: tr('season_date'),
        ),
        const SizedBox(width: 8),
        Expanded(
          // Тап всегда открывает окно отметки; «Снять все просмотры
          // сезона» лежит внутри него.
          child: FilledButton.tonalIcon(
            onPressed: () => _seasonSheet(st, aired),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: Icon(rewatch ? Icons.repeat_rounded : Icons.done_all_rounded),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }

  // ----------------------------- эпизод -----------------------------

  Widget _episodeTile(ColorScheme scheme, TmdbEpisode ep) {
    final watchedEp = s.watchedEpisode(ep.season, ep.number);
    final watched = watchedEp != null;
    // Оценка серии — последняя: у пересмотренной её даёт пересмотр.
    final sc = watchedEp?.currentScore;
    final watches = watchedEp?.watchCount ?? 0; // 0 если не смотрел
    final aired = _aired(ep);
    // Выпуск цикла с YouTube: подпись «№4», длина на кадре, тап — в YouTube.
    final yt = s.youtube;
    final entry = yt?.entryAt(ep.number);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      // Плавная смена фона отмеченной серии.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: watched
              ? scheme.secondaryContainer.withValues(alpha: 0.45)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Тап по карточке серии → полный экран серии (как у фильма).
              // Выпуск цикла с YouTube открывается в YouTube.
              Expanded(
                child: InkWell(
                  onTap: () => entry != null
                      ? openYouTube(entry.url)
                      : _openEpisode(ep),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 120,
                            height: 74,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ep.stillUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: ep.stillUrl!,
                                        fit: BoxFit.cover,
                                        memCacheWidth: (120 *
                                                MediaQuery.devicePixelRatioOf(
                                                    context))
                                            .round(),
                                        placeholder: (c, _) => Container(
                                            color: scheme
                                                .surfaceContainerHighest),
                                        errorWidget: (c, u, e) => Container(
                                            color:
                                                scheme.surfaceContainerHighest,
                                            child: Icon(Icons.tv_rounded,
                                                color:
                                                    scheme.onSurfaceVariant)),
                                      )
                                    : Container(
                                        color: scheme.surfaceContainerHighest,
                                        child: Icon(Icons.tv_rounded,
                                            color: scheme.onSurfaceVariant)),
                                if (entry?.durSec != null)
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: YtDurationBadge(entry!.durSec!),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  // «S12 · E104» на 320 dp ужимается, а не
                                  // вылезает за край.
                                  Flexible(
                                    child: Text(
                                        yt != null
                                            ? yt.labelOf(ep.number)
                                            : 'S${ep.season} · E${ep.number}',
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontFamily: AppTheme.displayFont,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                            color: scheme.primary)),
                                  ),
                                  if (!aired) ...[
                                    const SizedBox(width: 6),
                                    _soonBadge(scheme, ep),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(ep.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                      height: 1.15,
                                      color: scheme.onSurface)),
                              if (sc != null) ...[
                                const SizedBox(height: 5),
                                _epScoreChip(scheme, sc),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Тап по галочке → окно отметки (первый просмотр или ещё один).
              // Удержание: у отмеченной серии — окно её просмотра (дата,
              // оценка, дневник, удаление); у неотмеченной — отметить без
              // даты («смотрел, но не знаю когда»).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapCheck(ep),
                onLongPress: watched
                    ? () => _openViewing(ep, watchedEp)
                    : () => _markUnknownDate(ep),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
                  child: _checkCircle(scheme, watched, watches, aired),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Мягко-красный бейдж «скоро» для невышедшей серии (с датой в подсказке).
  Widget _soonBadge(ColorScheme scheme, TmdbEpisode ep) {
    final d = ep.airDate != null ? DateTime.tryParse(ep.airDate!) : null;
    return Tooltip(
      message: d != null ? numericDate(d) : tr('not_aired_badge'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded,
                size: 11, color: scheme.onTertiaryContainer),
            const SizedBox(width: 3),
            Text(tr('not_aired_badge'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    color: scheme.onTertiaryContainer)),
          ],
        ),
      ),
    );
  }

  /// Кружок отметки: пусто → галочка → число просмотров (×2, ×3…) ВМЕСТО
  /// галочки. Невышедшая непросмотренная серия — часы (нельзя отметить).
  Widget _checkCircle(
      ColorScheme scheme, bool watched, int watches, bool aired) {
    Widget child;
    if (!watched && !aired) {
      child = Icon(Icons.schedule_rounded,
          key: const ValueKey('soon'),
          size: 19,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6));
    } else if (!watched) {
      child = Icon(Icons.check_rounded,
          key: const ValueKey('empty'), size: 20, color: scheme.outline);
    } else if (watches >= 2) {
      child = Text('×$watches',
          key: ValueKey('x$watches'),
          style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: scheme.onPrimary));
    } else {
      child = Icon(Icons.check_rounded,
          key: const ValueKey('check'), size: 20, color: scheme.onPrimary);
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: watched ? scheme.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
            color: watched ? scheme.primary : scheme.outline, width: 2),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (c, a) =>
            ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
        child: child,
      ),
    );
  }

  Widget _epScoreChip(ColorScheme scheme, double sc) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: scoreColor(sc), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.star_rounded, size: 14, color: onScoreColor(sc)),
          const SizedBox(width: 3),
          Text(sc.toStringAsFixed(1),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: onScoreColor(sc))),
        ]),
      );

  /// Массово задаёт дату/время просмотра всем просмотренным сериям сезона.
  /// Если серии смотрели в РАЗНЫЕ дни — спрашивает подтверждение перед тем как
  /// схлопнуть их даты в одну (иначе точная история терялась молча); снимок для
  /// «Отмены» кладём всегда.
  Future<void> _seasonDate() async {
    if (_season == null) return;
    final inSeason = s.episodes.where((e) => e.season == _season).toList();
    if (inSeason.isEmpty) {
      _snack(tr('season_no_watched'));
      return;
    }
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    final dt = time == null
        ? DateTime(picked.year, picked.month, picked.day)
        : DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
    if (!mounted) return;
    // Потеря данных: если серии смотрели в разные дни, схлопывание в одну дату
    // сотрёт историю — предупреждаем.
    final distinctDays = inSeason
        .map((e) => e.watchedAt)
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();
    if (distinctDays.length >= 2) {
      final ok = await _confirmDialog(
        tr('season_dates_replace_title'),
        trf('season_dates_replace_body', {'n': distinctDays.length}),
        tr('replace'),
      );
      if (ok != true || !mounted) return;
    }
    final snap = s.toJson(); // снимок до перезаписи — для «Отмены»
    final n = await _repo.setSeasonWatchedAt(s.tvShowId, _season!, dt);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(undoSnackBar(
        text: trf('season_dated', {'n': n}),
        label: tr('undo'),
        onUndo: () => _repo.restoreFromSnapshot(const [], [snap]),
      ));
  }

  /// Диалог подтверждения (destructive-акцент на кнопке).
  Future<bool?> _confirmDialog(String title, String body, String confirmLabel) {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: scheme.error, foregroundColor: scheme.onError),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Окно отметки сезона: одно на первый просмотр, досмотр оставшихся серий
  /// и пересмотр. Первый просмотр отмечает ещё не отмеченные вышедшие серии,
  /// пересмотр доводит все серии до одного числа просмотров. «Снять все
  /// просмотры сезона» лежит здесь же.
  Future<void> _seasonSheet(SeasonPassState st, List<TmdbEpisode> aired) async {
    final season = _season;
    if (season == null) return;
    final watched = s.episodes.where((e) => e.season == season).length;
    if (aired.isEmpty && watched == 0) {
      _snack(tr('season_no_watched'));
      return;
    }
    // Что осталось отметить: весь сезон или часть идущего просмотра.
    final subject = [
      trf('season_n', {'n': season}),
      if (aired.isNotEmpty)
        st.left == st.total
            ? trn('ss_episodes', st.total)
            : trn('mark_left', st.left, {'total': st.total}),
    ].join(' · ');
    final first = st.completed == 0;
    final choice = await showMarkSheet(
      context,
      title: tr('mark_season_q'),
      subject: subject,
      ordinal: st.current,
      coWatch: first,
      dangerLabel: watched > 0 ? tr('season_clear_all_season') : null,
    );
    if (choice == null || !mounted) return;
    if (choice.danger) {
      await _clearSeason(season, watched);
      return;
    }
    if (aired.isEmpty) return;
    final date = choice.date;
    if (!first) {
      final n = await _repo.completeSeasonPass(
          s.tvShowId, season, [for (final e in aired) e.number], date);
      if (mounted && n > 0) _snack(trf('season_rewatched', {'c': n}));
      return;
    }
    final fresh = [
      for (final e in aired)
        if (!s.isEpisodeWatched(e.season, e.number)) e,
    ];
    await _repo.markSeason(s.tvShowId, season, [for (final e in fresh) e.number],
        runtimes: {for (final e in fresh) e.number: e.runtime}, date: date);
    if (!mounted) return;
    if (choice.friends.isEmpty) {
      // Честно предупреждаем: без даты сезон не попадёт в ленту «Просмотрено»
      // (записи без даты туда намеренно не идут).
      _snack(date == null
          ? trf('season_done_undated', {'n': season})
          : trf('season_done', {'n': season}));
      return;
    }
    final eps = [
      for (final e in fresh) [season, e.number],
    ];
    for (final f in choice.friends) {
      try {
        await SocialController.instance.sendSeriesCoWatch(
          toUserId: f.id,
          title: s.displayTitle,
          origTitle: s.title,
          year: s.year,
          tmdbId: s.tmdbId,
          posterUrl: s.posterUrl,
          watchedAt: date,
          episodes: eps,
        );
      } catch (_) {/* пропускаем этого друга */}
    }
    if (mounted) _snack(trf('cowatch_marked', {'n': choice.friends.length}));
  }

  /// «Снять все просмотры сезона»: спрашивает, снимает и оставляет плашку
  /// «Вернуть» со снимком сериала. При настройке «Снимать серии по порядку»
  /// вместе с сезоном уходят сезоны после него, и вопрос это называет.
  Future<void> _clearSeason(int season, int watched) async {
    final after = AppPrefs.instance.sequentialUnmark
        ? _repo.watchedAfterSeason(s.tvShowId, season)
        : 0;
    if (!await _confirmUnmarkSeason(watched, after: after) || !mounted) return;
    final snap = s.toJson();
    if (after > 0) {
      await _repo.unmarkFrom(s.tvShowId, season);
    } else {
      await _repo.unmarkSeason(s.tvShowId, season);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(undoSnackBar(
        text: tr('season_cleared'),
        label: tr('view_restore'),
        onUndo: () => _repo.restoreFromSnapshot(const [], [snap]),
      ));
  }

  /// Подтверждение перед снятием всех просмотров сезона: вместе с отметками
  /// теряются даты и оценки серий. [after] — сколько серий уйдёт в сезонах
  /// после него при снятии по порядку.
  Future<bool> _confirmUnmarkSeason(int watched, {int after = 0}) async {
    final scheme = Theme.of(context).colorScheme;
    final body = [
      trf('unmark_season_confirm_body', {'c': watched}),
      if (after > 0) ...[
        trf('unmark_cascade_season', {'eps': trn('ss_episodes', after)}),
        unmarkCascadeHint(),
      ],
    ].join('\n\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 32),
        title: Text(trf('unmark_season_confirm', {'n': _season!})),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: scheme.error, foregroundColor: scheme.onError),
            child: Text(tr('unmark_season_action')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Ставит одну оценку всем УЖЕ ПРОСМОТРЕННЫМ сериям сезона (не отмечает новые
  /// и не трогает невышедшие).
  Future<void> _rateSeason() async {
    if (_season == null) return;
    final r = await showScorePad(context);
    if (r == null) return;
    final n = await _repo.setSeasonScore(s.tvShowId, _season!, r);
    if (mounted) {
      _snack(n > 0
          ? trf('season_rated', {'n': n, 'v': r.toStringAsFixed(1)})
          : tr('season_no_watched'));
    }
  }

  Widget _errorCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 52, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(tr('no_episodes'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: AppTheme.bodyFont)),
          const SizedBox(height: 6),
          Text(tr('link_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          // Ручная привязка: ввести название кириллицей и выбрать из TMDB.
          FilledButton.icon(
            onPressed: _manualLinkSheet,
            icon: const Icon(Icons.search_rounded),
            label: Text(tr('link_find')),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _init, child: Text(tr('retry'))),
        ],
      ),
    );
  }

  /// Лист ручной привязки сериала к TMDB (поиск кириллицей + выбор).
  void _manualLinkSheet() {
    final scheme = Theme.of(context).colorScheme;
    final ctl = TextEditingController(text: s.displayTitle);
    List<TmdbSeries> results = [];
    var loading = false;
    var didInit = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          Future<void> run(String q) async {
            q = q.trim();
            if (q.isEmpty) {
              setSheet(() => results = []);
              return;
            }
            setSheet(() => loading = true);
            try {
              final r = await TmdbService.searchTvShows(q);
              setSheet(() {
                results = r;
                loading = false;
              });
            } catch (_) {
              // Нет сети/сбой — не виснем на спиннере.
              setSheet(() {
                results = [];
                loading = false;
              });
            }
          }

          if (!didInit) {
            didInit = true;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => run(ctl.text));
          }
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(sheetCtx).size.height * 0.7,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctl,
                            autofocus: false,
                            textInputAction: TextInputAction.search,
                            onSubmitted: run,
                            style: const TextStyle(fontFamily: AppTheme.bodyFont),
                            decoration: InputDecoration(
                              hintText: tr('link_hint_field'),
                              prefixIcon: const Icon(Icons.search_rounded),
                              filled: true,
                              fillColor: scheme.surfaceContainerHigh,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                            onPressed: () => run(ctl.text),
                            child: Text(tr('link_find'))),
                      ],
                    ),
                  ),
                  if (loading)
                    const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator()),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                      itemCount: results.length,
                      itemBuilder: (c, i) {
                        final t = results[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Material(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () async {
                                await _repo.linkSeriesTmdb(s.tvShowId, t);
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                _init();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(children: [
                                  Poster(
                                      title: t.title,
                                      url: t.posterUrl,
                                      width: 44),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(t.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontFamily: AppTheme.displayFont,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                                color: scheme.onSurface)),
                                        if (t.year != null)
                                          Text('${t.year}',
                                              style: TextStyle(
                                                  fontFamily: AppTheme.bodyFont,
                                                  fontSize: 12.5,
                                                  color:
                                                      scheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.link_rounded,
                                      color: scheme.primary),
                                ]),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ----------------------------- оценки -----------------------------

  void _rateSeries() => _ratingSheet(
        title: s.displayTitle,
        initial: s.score,
        onCommit: (v) => _repo.setSeriesScore(s.tvShowId, v),
      );

  /// Открывает окно серии (нижней панелью, как карточка фильма).
  void _openEpisode(TmdbEpisode ep) => showEpisodeSheet(
        context,
        seriesId: s.tvShowId,
        seriesTitle: s.displayTitle,
        ep: ep,
        canMark: _aired(ep),
        onMark: () => _tapCheck(ep),
        repo: _repo,
      );

  /// Универсальный лист оценки (сериал / серия) со слайдером-линейкой.
  void _ratingSheet({
    required String title,
    required double? initial,
    required void Function(double?) onCommit,
  }) {
    final scheme = Theme.of(context).colorScheme;
    double val = initial ?? 1.0;
    bool rated = initial != null;
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
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: scheme.onSurface)),
                const SizedBox(height: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final r = await showScorePad(sheetCtx);
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
                              fontSize: 46,
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
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        onCommit(null);
                        Navigator.pop(sheetCtx);
                      },
                      child: Text(tr('remove_score')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        onCommit(rated ? val : null);
                        Navigator.pop(sheetCtx);
                      },
                      child: Text(tr('done')),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }
}

