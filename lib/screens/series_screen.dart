import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../models/social.dart';
import '../services/movie_repository.dart';
import '../services/social/social_controller.dart';
import '../services/store.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../widgets/pop_icon.dart';
import '../widgets/poster.dart';
import '../widgets/poster_viewer.dart';
import '../widgets/rating_slider.dart';
import '../widgets/favorite_character.dart';
import '../widgets/reveal.dart';
import '../widgets/score_pad.dart';
import 'browse_screens.dart';
import 'delete_helpers.dart';
import 'social/friend_pick_sheet.dart';

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

  /// Последовательный режим: отметил серию → все до неё; снял → все после.
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

  /// Серии от (season, number) включительно до конца.
  List<List<int>> _orderedFrom(int season, int number) {
    final out = <List<int>>[];
    var started = false;
    for (final e in _orderedAll) {
      if (e[0] == season && e[1] == number) started = true;
      if (started) out.add(e);
    }
    return out;
  }

  // ---- действия с серией (учитывают последовательный режим) ----

  void _markEpisode(TmdbEpisode ep) {
    if (_sequential) {
      _repo.markEpisodesBulk(s.tvShowId, _orderedUpTo(ep.season, ep.number));
    } else {
      _repo.markEpisodeWatched(s.tvShowId, ep.season, ep.number,
          runtimeMin: ep.runtime);
    }
  }

  /// Снять просмотр серии целиком (в послед. режиме — и все следующие).
  void _unmarkEpisode(TmdbEpisode ep) {
    if (_sequential) {
      _repo.unmarkEpisodesBulk(s.tvShowId, _orderedFrom(ep.season, ep.number));
    } else {
      _repo.unmarkEpisode(s.tvShowId, ep.season, ep.number);
    }
  }

  /// Тап по галочке серии → всегда открываем меню «когда посмотрели?» (как у
  /// сезона), чтобы отметить просмотр/пересмотр с выбранной датой.
  void _tapCheck(TmdbEpisode ep) {
    final we = s.watchedEpisode(ep.season, ep.number);
    final firstWatch = we == null;
    if (firstWatch && !_aired(ep)) {
      _snack(tr('episode_not_aired'));
      return;
    }
    _showSeasonWhenSheet(
      title: firstWatch ? tr('episode_mark_when') : tr('episode_rewatch_when'),
      subtitle: ep.name,
      onDate: (date) async {
        if (firstWatch) {
          // Отмечаем (учитывая последовательный режим), затем ставим дату именно
          // этой серии (в т.ч. null = «неизвестно»).
          if (_sequential) {
            await _repo.markEpisodesBulk(
                s.tvShowId, _orderedUpTo(ep.season, ep.number));
          } else {
            await _repo.markEpisodeWatched(s.tvShowId, ep.season, ep.number,
                runtimeMin: ep.runtime);
          }
          await _repo.setEpisodeViewDate(
              s.tvShowId, ep.season, ep.number, 0, date);
        } else {
          // Пересмотр — отдельный просмотр с выбранной датой.
          await _repo.addEpisodeView(s.tvShowId, ep.season, ep.number,
              date: date, runtimeMin: ep.runtime);
        }
        HapticFeedback.selectionClick();
      },
    );
  }

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

  /// Полностью удалить сериал из базы (для мусорных/ненаходимых) → закрыть экран.
  Future<void> _deleteSeriesFromBase() async {
    await deleteSeriesFromBase(context, s);
    if (mounted && _repo.seriesById(s.tvShowId) == null) {
      Navigator.of(context).maybePop();
    }
  }

  /// «Убрать просмотр»: есть повторы → −1; иначе снять просмотр (с каскадом).
  void _removeOneWatch(TmdbEpisode ep) {
    final we = s.watchedEpisode(ep.season, ep.number);
    if (we == null) return;
    if (we.rewatchCount > 0) {
      _repo.removeEpisodeRewatch(s.tvShowId, ep.season, ep.number);
    } else {
      _unmarkEpisode(ep);
    }
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = false;
    });
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
    _season = _initialSeason();
    await _loadSeason(_season!);
    if (mounted) setState(() => _loading = false);
  }

  int _initialSeason() {
    int? best;
    DateTime? bestAt;
    for (final e in s.episodes) {
      if (e.season == null || e.watchedAt == null) continue;
      if (bestAt == null || e.watchedAt!.isAfter(bestAt)) {
        bestAt = e.watchedAt;
        best = e.season;
      }
    }
    if (best != null && _seasons.any((x) => x.number == best)) return best;
    return _seasons.first.number;
  }

  Future<void> _loadSeason(int n) async {
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
                  if (v == 'delete') _deleteSeriesFromBase();
                },
                itemBuilder: (context) => [
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
                // «Буду смотреть» — пока сериал не начат (нет просмотренных серий).
                if (s.episodes.isEmpty)
                  SliverToBoxAdapter(child: _watchlistButton(scheme)),
                SliverToBoxAdapter(child: _droppedButton(scheme)),
                SliverToBoxAdapter(child: _reviewTile(scheme)),
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
              itemBuilder: (c, i) => GestureDetector(
                onTap: cast[i].id > 0
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PersonScreen(
                            personId: cast[i].id, personName: cast[i].name)))
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
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Бэкдроп (или цветной градиент, если его нет) с затемнением снизу.
          if (_extra?.backdropUrl != null)
            CachedNetworkImage(
              imageUrl: _extra!.backdropUrl!,
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
                GestureDetector(
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

  /// Локальная замена постера сериала своим изображением (долгое нажатие).
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
              title: Text(tr('poster_change')),
              onTap: () => Navigator.pop(ctx, 'pick'),
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
    final epAvg = s.episodeScoreAvg;
    final fromEp = epAvg != null;
    final sc = epAvg ?? s.score;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: sc != null
                  ? scoreColor(sc)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: fromEp ? () => _snack(tr('series_avg_locked')) : _rateSeries,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(sc != null ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 20,
                          color: sc != null
                              ? onScoreColor(sc)
                              : scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        sc != null
                            ? '${sc.toStringAsFixed(1)} · ${fromEp ? tr('avg_of_episodes') : tr('series_rating')}'
                            : tr('rate_series'),
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: sc != null
                                ? onScoreColor(sc)
                                : scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: s.favorite ? scheme.primary : scheme.surfaceContainerHighest,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _repo.toggleSeriesFavorite(s.tvShowId);
              },
              child: SizedBox(
                width: 48,
                height: 48,
                child: PopIcon(
                  active: s.favorite,
                  activeIcon: Icons.favorite_rounded,
                  inactiveIcon: Icons.favorite_border_rounded,
                  activeColor: scheme.onPrimary,
                  inactiveColor: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Широкая кнопка «Буду смотреть» для сериала (активна — когда в списке).
  Widget _watchlistButton(ColorScheme scheme) {
    final active = s.watchlist;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: SizedBox(
        width: double.infinity,
        child: active
            ? FilledButton.icon(
                onPressed: () => _repo.toggleSeriesWatchlist(s.tvShowId),
                icon: const Icon(Icons.bookmark_rounded),
                label: Text(tr('in_watchlist')),
              )
            : FilledButton.tonalIcon(
                onPressed: () {
                  _repo.toggleSeriesWatchlist(s.tvShowId);
                  _snack(tr('added_to_watchlist'));
                },
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(tr('add_watchlist')),
              ),
      ),
    );
  }

  /// Широкая кнопка «Брошено» для сериала (мягкий красный, активна когда брошен).
  Widget _droppedButton(ColorScheme scheme) {
    final active = s.dropped;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: SizedBox(
        width: double.infinity,
        child: active
            ? FilledButton.icon(
                onPressed: () => _repo.toggleSeriesDropped(s.tvShowId),
                icon: const Icon(Icons.heart_broken_rounded),
                label: Text(tr('in_dropped')),
                style: FilledButton.styleFrom(
                    backgroundColor: kDroppedColor, foregroundColor: Colors.white),
              )
            : FilledButton.tonalIcon(
                onPressed: () => _repo.toggleSeriesDropped(s.tvShowId),
                icon: const Icon(Icons.heart_broken_outlined),
                label: Text(tr('mark_dropped')),
                style: FilledButton.styleFrom(
                    backgroundColor: kDroppedColor.withValues(alpha: 0.16),
                    foregroundColor: kDroppedColor),
              ),
      ),
    );
  }

  // ----------------------------- сезоны -----------------------------

  Widget _seasonBar(ColorScheme scheme) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          for (final se in _seasons)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(trf('season_n', {'n': se.number})),
                selected: _season == se.number,
                onSelected: (_) {
                  setState(() => _season = se.number);
                  _loadSeason(se.number);
                },
                labelStyle: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    color: _season == se.number
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant),
                selectedColor: scheme.secondaryContainer,
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }

  /// Панель сезона: прогресс + широкая кнопка «Отметить/Снять весь сезон».
  Widget _seasonToolbar(ColorScheme scheme) {
    final eps = _eps;
    if (eps == null || eps.isEmpty || _season == null) {
      return const SizedBox.shrink();
    }
    // «Отметить весь сезон» и прогресс считаем по ВЫШЕДШИМ сериям.
    final aired = eps.where(_aired).toList();
    final seenInSeason =
        aired.where((e) => s.isEpisodeWatched(e.season, e.number)).length;
    final allWatched = aired.isNotEmpty && seenInSeason == aired.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
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
            // Отметить весь сезон — тап открывает меню выбора даты первого
            // просмотра. Удержание — меню повторного просмотра сезона.
            child: GestureDetector(
              onLongPress: () => _seasonRewatchMenu(scheme),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  if (allWatched) {
                    _repo.unmarkSeason(s.tvShowId, _season!);
                  } else {
                    _seasonMarkSheet();
                  }
                },
                icon: Icon(allWatched
                    ? Icons.remove_done_rounded
                    : Icons.done_all_rounded),
                label: Text(tr(allWatched ? 'unmark_season' : 'mark_season')),
                style: allWatched
                    ? FilledButton.styleFrom(
                        backgroundColor: scheme.surfaceContainerHighest,
                        foregroundColor: scheme.onSurfaceVariant)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------- эпизод -----------------------------

  Widget _episodeTile(ColorScheme scheme, TmdbEpisode ep) {
    final watchedEp = s.watchedEpisode(ep.season, ep.number);
    final watched = watchedEp != null;
    final sc = watchedEp?.score;
    final watches = watchedEp?.watchCount ?? 0; // 0 если не смотрел
    final aired = _aired(ep);
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
              Expanded(
                child: InkWell(
                  onTap: () => _openEpisode(ep),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 120,
                            height: 74,
                            child: ep.stillUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: ep.stillUrl!,
                                    fit: BoxFit.cover,
                                    memCacheWidth: (120 *
                                            MediaQuery.devicePixelRatioOf(
                                                context))
                                        .round(),
                                    placeholder: (c, _) => Container(
                                        color: scheme.surfaceContainerHighest),
                                    errorWidget: (c, u, e) => Container(
                                        color: scheme.surfaceContainerHighest,
                                        child: Icon(Icons.tv_rounded,
                                            color: scheme.onSurfaceVariant)),
                                  )
                                : Container(
                                    color: scheme.surfaceContainerHighest,
                                    child: Icon(Icons.tv_rounded,
                                        color: scheme.onSurfaceVariant)),
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
                                  Text('S${ep.season} · E${ep.number}',
                                      style: TextStyle(
                                          fontFamily: AppTheme.displayFont,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          color: scheme.primary)),
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
              // Тап по галочке → +1 просмотр (×2, ×3…). Удержание: у отмеченной
              // серии — меню (снять / дата / «Неизвестно»); у неотмеченной —
              // отметить без даты («смотрел, но не знаю когда»).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapCheck(ep),
                onLongPress: watched
                    ? () => _checkmarkMenu(scheme, ep, watchedEp)
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

  /// Меню по удержанию галочки: снять просмотр целиком или вернуть один просмотр.
  void _checkmarkMenu(ColorScheme scheme, TmdbEpisode ep, Episode watchedEp) {
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
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('S${ep.season} · E${ep.number} · ${ep.name}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: scheme.onSurface)),
              ),
            ),
            _menuTile(scheme, Icons.event_rounded, tr('edit_watch_date'), () {
              Navigator.pop(sheetCtx);
              _editEpisodeDate(watchedEp);
            }),
            if (watchedEp.watchedAt != null)
              _menuTile(
                  scheme, Icons.help_outline_rounded, tr('set_unknown_date'),
                  () {
                Navigator.pop(sheetCtx);
                _repo.setEpisodeWatchedAt(s.tvShowId, watchedEp, null);
                _snack(tr('marked_unknown'));
              }),
            _menuTile(scheme, Icons.exposure_minus_1_rounded,
                tr('remove_one_watch'), () {
              Navigator.pop(sheetCtx);
              _removeOneWatch(ep);
            }),
            if (watchedEp.rewatchCount > 0)
              _menuTile(scheme, Icons.looks_one_rounded, tr('reset_to_one'),
                  () {
                Navigator.pop(sheetCtx);
                _repo.resetEpisodeToSingle(s.tvShowId, ep.season, ep.number);
              }),
            _menuTile(scheme, Icons.remove_done_rounded, tr('clear_all_checks'),
                () {
              Navigator.pop(sheetCtx);
              _unmarkEpisode(ep);
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Плитка «Моя рецензия» на сериал: текст (тап → правка) или кнопка написать.
  Widget _reviewTile(ColorScheme scheme) {
    final has = s.review != null && s.review!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: has
          ? GestureDetector(
              onTap: _editReview,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tr('my_review'),
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: scheme.primary)),
                        const Spacer(),
                        Icon(Icons.edit_rounded,
                            size: 16, color: scheme.onSurfaceVariant),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(s.review!,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 14,
                            height: 1.45,
                            color: scheme.onSurface)),
                  ],
                ),
              ),
            )
          : SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _editReview,
                icon: const Icon(Icons.rate_review_rounded),
                label: Text(tr('write_review')),
              ),
            ),
    );
  }

  /// Редактор рецензии на сериал — нижний лист с многострочным полем.
  void _editReview() {
    final ctl = TextEditingController(text: s.review ?? '');
    final scheme = Theme.of(context).colorScheme;
    final id = s.tvShowId;
    final had = s.review != null && s.review!.trim().isNotEmpty;
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
            const SizedBox(height: 14),
            Text(tr('my_review'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: scheme.onSurface)),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontFamily: AppTheme.bodyFont, height: 1.4),
              decoration: InputDecoration(
                hintText: tr('review_hint'),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (had)
                  TextButton(
                    onPressed: () {
                      _repo.setSeriesReview(id, null);
                      Navigator.pop(sheetCtx);
                    },
                    child: Text(tr('delete')),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    _repo.setSeriesReview(id, ctl.text);
                    Navigator.pop(sheetCtx);
                  },
                  child: Text(tr('save')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(trf('season_dated', {'n': n})),
        action: SnackBarAction(
          label: tr('undo'),
          onPressed: () => _repo.restoreFromSnapshot(const [], [snap]),
        ),
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

  /// Тап по «Отметить весь сезон»: меню выбора даты ПЕРВОГО просмотра (как
  /// «Когда вы посмотрели?» у фильма) — отмечает все вышедшие серии сезона с
  /// выбранной датой (null = «Неизвестная дата»).
  void _seasonMarkSheet() {
    if (_season == null) return;
    final eps = _eps;
    if (eps == null) return;
    final aired = eps
        .where((e) => _aired(e) && !s.isEpisodeWatched(e.season, e.number))
        .toList();
    if (aired.isEmpty) {
      _snack(tr('season_all_watched'));
      return;
    }
    _showSeasonWhenSheet(
      title: trf('season_mark_when', {'n': _season!}),
      subtitle: trf('season_mark_sub', {'n': aired.length}),
      coWatchEnabled: _hasFriends,
      onDate: (date) {
        final runtimes = {for (final e in aired) e.number: e.runtime};
        _repo.markSeason(s.tvShowId, _season!, [for (final e in aired) e.number],
            runtimes: runtimes, date: date);
        // Честно предупреждаем: без даты сезон не попадёт в ленту «Просмотрено»
        // (записи без даты туда намеренно не идут).
        _snack(date == null
            ? trf('season_done_undated', {'n': _season!})
            : trf('season_done', {'n': _season!}));
      },
      onCoWatch: (date, friends) async {
        final runtimes = {for (final e in aired) e.number: e.runtime};
        await _repo.markSeason(
            s.tvShowId, _season!, [for (final e in aired) e.number],
            runtimes: runtimes, date: date);
        final eps = [
          for (final e in aired) [_season!, e.number]
        ];
        for (final f in friends) {
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
        if (mounted) _snack(trf('cowatch_marked', {'n': friends.length}));
      },
    );
  }

  bool get _hasFriends =>
      SocialController.instance.friends.friends.isNotEmpty;

  /// Меню по удержанию кнопки сезона: отметить ВЕСЬ сезон просмотренным ещё раз
  /// с выбором даты + снять все просмотры.
  void _seasonRewatchMenu(ColorScheme scheme) {
    if (_season == null) return;
    final watchedInSeason = s.episodes.where((e) => e.season == _season).length;
    if (watchedInSeason == 0) {
      // Сезон ещё не смотрели — предлагаем обычную отметку с датой.
      _seasonMarkSheet();
      return;
    }
    _showSeasonWhenSheet(
      title: trf('season_rewatch_title', {'n': _season!}),
      subtitle: trf('season_rewatch_sub', {'n': watchedInSeason}),
      onDate: (date) async {
        final n = await _repo.rewatchSeason(s.tvShowId, _season!, date);
        if (!mounted) return;
        _snack(n > 0
            ? trf('season_rewatched', {'c': n})
            : tr('season_no_watched'));
      },
      extra: (sheetCtx) => _seasonMenuTile(
          Theme.of(sheetCtx).colorScheme,
          Icons.remove_done_rounded,
          tr('season_clear_all'), () {
        Navigator.pop(sheetCtx);
        _repo.unmarkSeason(s.tvShowId, _season!);
        _snack(tr('season_cleared'));
      }, danger: true),
    );
  }

  /// Общий лист «когда» для сезона (в стиле «Когда вы посмотрели?»). [onDate]
  /// получает выбранную дату (null = «Неизвестная дата»); [extra] — доп. плитка
  /// внизу (напр. «Снять все просмотры»). Если [coWatchEnabled] и есть друзья —
  /// показывается «Посмотрел с другом»: после выбора друзей дата уходит в
  /// [onCoWatch] вместо [onDate].
  void _showSeasonWhenSheet({
    required String title,
    required String subtitle,
    required void Function(DateTime?) onDate,
    Widget Function(BuildContext sheetCtx)? extra,
    bool coWatchEnabled = false,
    void Function(DateTime? date, List<SocialUser> friends)? onCoWatch,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    showModalBottomSheet<void>(
      context: context,
      // Прокручиваемый: лист может вырасти на всю высоту, и SafeArea поднимает
      // содержимое над системными кнопками — иначе нижний (красный) пункт и
      // заголовок обрезались на невысоком экране.
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) {
        List<SocialUser>? picked; // с кем смотрели (co-watch)
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            void choose(DateTime? d) {
              Navigator.pop(sheetCtx);
              if (picked != null && onCoWatch != null) {
                onCoWatch(d, picked!);
              } else {
                onDate(d);
              }
            }

            Future<void> pickDate() async {
              final date = await showDatePicker(
                context: sheetCtx,
                initialDate: now,
                firstDate: DateTime(1900),
                lastDate: now,
              );
              if (date == null || !sheetCtx.mounted) return;
              final time = await showTimePicker(
                context: sheetCtx,
                initialTime: TimeOfDay.now(),
              );
              final dt = time == null
                  ? DateTime(date.year, date.month, date.day)
                  : DateTime(
                      date.year, date.month, date.day, time.hour, time.minute);
              if (sheetCtx.mounted) choose(dt);
            }

            Future<void> pickFriends() async {
              final fr = await pickCoWatchFriends(sheetCtx);
              if (fr != null && fr.isNotEmpty) setSheet(() => picked = fr);
            }

            return SafeArea(
              child: SingleChildScrollView(
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
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(title,
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                color: scheme.primary)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(subtitle,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 13,
                                color: scheme.onSurfaceVariant)),
                      ),
                    ),
                    if (picked != null)
                      _seasonCoWatchBanner(scheme, picked!, pickFriends),
                    _seasonMenuTile(scheme, Icons.help_outline_rounded,
                        tr('when_unknown'), () => choose(null)),
                    _seasonMenuTile(scheme, Icons.flag_rounded,
                        tr('when_just_finished'), () => choose(now)),
                    _seasonMenuTile(scheme, Icons.today_rounded,
                        tr('when_today'), () => choose(now)),
                    _seasonMenuTile(scheme, Icons.history_rounded,
                        tr('when_yesterday'),
                        () => choose(now.subtract(const Duration(days: 1)))),
                    _seasonMenuTile(scheme, Icons.event_rounded,
                        tr('when_pick_date'), pickDate),
                    if (coWatchEnabled && picked == null && _hasFriends) ...[
                      Divider(
                          height: 18,
                          indent: 24,
                          endIndent: 24,
                          color: scheme.outlineVariant),
                      _seasonMenuTile(scheme, Icons.group_rounded,
                          tr('cowatch_with_friend'), pickFriends),
                    ],
                    if (extra != null) ...[
                      Divider(
                          height: 20,
                          indent: 24,
                          endIndent: 24,
                          color: scheme.outlineVariant),
                      extra(sheetCtx),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Плашка «С: имена» + «Изменить» на листе сезона (co-watch выбран).
  Widget _seasonCoWatchBanner(
      ColorScheme scheme, List<SocialUser> friends, VoidCallback onChange) {
    final names = friends.map((f) => f.displayName).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(Icons.group_rounded,
                size: 20, color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(trf('cowatch_with', {'names': names}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: scheme.onPrimaryContainer)),
            ),
            TextButton(onPressed: onChange, child: Text(tr('cowatch_change'))),
          ],
        ),
      ),
    );
  }

  /// Плитка меню сезона в стиле «Когда вы посмотрели?» (крупный круглый значок).
  Widget _seasonMenuTile(
      ColorScheme scheme, IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final bg = danger ? kDroppedColor.withValues(alpha: 0.16) : scheme.primaryContainer;
    final fg = danger ? kDroppedColor : scheme.onPrimaryContainer;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: fg, size: 24),
            ),
            const SizedBox(width: 16),
            Text(label,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: danger ? kDroppedColor : scheme.onSurface)),
          ],
        ),
      ),
    );
  }

  /// Ставит одну оценку всем УЖЕ ПРОСМОТРЕННЫМ сериям сезона (не отмечает новые
  /// и не трогает невышедшие).
  Future<void> _rateSeason() async {
    if (_season == null) return;
    final r = await showScorePad(context, initial: null);
    if (r == null) return;
    final n = await _repo.setSeasonScore(s.tvShowId, _season!, r);
    if (mounted) {
      _snack(n > 0
          ? trf('season_rated', {'n': n, 'v': r.toStringAsFixed(1)})
          : tr('season_no_watched'));
    }
  }

  /// Правка даты и времени просмотра серии из меню списка (дата → время).
  Future<void> _editEpisodeDate(Episode we) async {
    final now = DateTime.now();
    final initial = we.watchedAt ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    final dt = time == null
        ? DateTime(picked.year, picked.month, picked.day)
        : DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
    await _repo.setEpisodeWatchedAt(s.tvShowId, we, dt);
  }

  Widget _menuTile(
          ColorScheme scheme, IconData icon, String label, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(children: [
            Icon(icon, color: scheme.onSurfaceVariant),
            const SizedBox(width: 16),
            Text(label,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: scheme.onSurface)),
          ]),
        ),
      );

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

  /// Открывает полный экран серии (нижней панелью, как карточка фильма).
  void _openEpisode(TmdbEpisode ep) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _EpisodeSheet(
        seriesId: s.tvShowId,
        seriesTitle: s.displayTitle,
        ep: ep,
        canMark: _aired(ep),
        onMark: () => _markEpisode(ep),
        onRewatch: () => _repo.addEpisodeRewatch(
            s.tvShowId, ep.season, ep.number,
            runtimeMin: ep.runtime),
        onUnmark: () => _unmarkEpisode(ep),
      ),
    );
  }

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

/// Полный экран одной серии (нижней панелью) — как карточка фильма, но данные
/// текущей серии: кадр, описание, оценка серии, управление просмотром.
class _EpisodeSheet extends StatefulWidget {
  final String seriesId;
  final String seriesTitle;
  final TmdbEpisode ep;
  final bool canMark;
  final VoidCallback onMark;
  final VoidCallback onRewatch;
  final VoidCallback onUnmark;
  const _EpisodeSheet({
    required this.seriesId,
    required this.seriesTitle,
    required this.ep,
    required this.canMark,
    required this.onMark,
    required this.onRewatch,
    required this.onUnmark,
  });

  @override
  State<_EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<_EpisodeSheet> {
  final _repo = MovieRepository.instance;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  double? _dragging;

  TmdbEpisode get ep => widget.ep;

  Episode? get _we =>
      _repo.seriesById(widget.seriesId)?.watchedEpisode(ep.season, ep.number);

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _messenger.currentState?.showSnackBar(SnackBar(
        content: Text(tr('copied')), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, controller) => ScaffoldMessenger(
            key: _messenger,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: _content(Theme.of(context).colorScheme),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _content(ColorScheme scheme) {
    final we = _we;
    final watched = we != null;
    final meta = [
      if (ep.airDate != null && DateTime.tryParse(ep.airDate!) != null)
        numericDate(DateTime.parse(ep.airDate!)),
      if (ep.runtime != null && ep.runtime! > 0)
        humanDuration(Duration(minutes: ep.runtime!)),
    ].join(' · ');
    return [
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
      // Кадр серии → фулскрин по тапу.
      GestureDetector(
        onTap: ep.stillUrl != null
            ? () => openPosterViewer(context,
                title: ep.name,
                url: ep.stillUrl,
                heroTag: 'ep-${widget.seriesId}-${ep.season}-${ep.number}')
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ep.stillUrl != null
                ? Hero(
                    tag: 'ep-${widget.seriesId}-${ep.season}-${ep.number}',
                    child: CachedNetworkImage(
                      imageUrl: ep.stillUrl!,
                      fit: BoxFit.cover,
                      placeholder: (c, _) =>
                          Container(color: scheme.surfaceContainerHighest),
                      errorWidget: (c, u, e) =>
                          Container(color: scheme.surfaceContainerHighest),
                    ),
                  )
                : Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.tv_rounded,
                        size: 44, color: scheme.onSurfaceVariant)),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text('${widget.seriesTitle}  ·  S${ep.season}·E${ep.number}',
          style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: scheme.primary)),
      const SizedBox(height: 4),
      GestureDetector(
        onLongPress: () => _copy(ep.name),
        child: Text(ep.name,
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                height: 1.1,
                color: scheme.onSurface)),
      ),
      if (meta.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(meta,
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                color: scheme.onSurfaceVariant)),
      ],
      // Несколько просмотров → список «Оценки по просмотрам»: у КАЖДОГО своя
      // дата и оценка, каждый редактируется/удаляется (как у фильмов). Один
      // просмотр → обычная карточка оценки + дата.
      if (we != null && we.watchCount > 1) ...[
        const SizedBox(height: 20),
        Text(tr('per_viewing_scores'),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: scheme.primary)),
        const SizedBox(height: 8),
        ..._episodeViewRows(scheme, we),
      ] else ...[
        // Дата и время просмотра — редактируемые (как у фильмов).
        if (we != null) ...[
          const SizedBox(height: 14),
          _watchedAtTile(scheme, we),
        ],
        const SizedBox(height: 18),
        _scoreCard(scheme, we),
        if (we?.score != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () {
                _repo.setEpisodeScore(widget.seriesId, we!, null);
                setState(() => _dragging = null);
              },
              icon: const Icon(Icons.star_outline_rounded),
              label: Text(tr('remove_score')),
              style: FilledButton.styleFrom(
                  backgroundColor: kDroppedColor.withValues(alpha: 0.16),
                  foregroundColor: kDroppedColor),
            ),
          ),
        ],
      ],
      const SizedBox(height: 16),
      ..._watchButtons(scheme, watched),
      if (ep.overview != null && ep.overview!.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(tr('overview'),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: scheme.primary)),
        const SizedBox(height: 6),
        GestureDetector(
          onLongPress: () => _copy(ep.overview!),
          child: Text(ep.overview!,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  height: 1.45,
                  color: scheme.onSurface)),
        ),
      ],
    ];
  }

  /// Список «Оценки по просмотрам» серии: каждый просмотр (первый + повторы) со
  /// своей датой и оценкой; тап → редактор (как у фильмов).
  List<Widget> _episodeViewRows(ColorScheme scheme, Episode we) {
    final list = we.views;
    final rows = <Widget>[];
    for (var i = list.length - 1; i >= 0; i--) {
      final v = list[i];
      final isRewatch = i > 0;
      final sc = we.scoreOfView(v);
      rows.add(Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editEpisodeView(context, we, i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Icon(isRewatch ? Icons.repeat_rounded : Icons.event_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          v.hasDate
                              ? dateExactWithTime(v.date!)
                              : tr('when_unknown'),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 14,
                              color: scheme.onSurface)),
                      if (isRewatch)
                        Text(trf('viewing_n', {'n': i + 1}),
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sc != null
                        ? scoreColor(sc)
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          sc != null
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 16,
                          color: sc != null
                              ? onScoreColor(sc)
                              : scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(sc != null ? sc.toStringAsFixed(1) : tr('not_rated'),
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: sc != null
                                  ? onScoreColor(sc)
                                  : scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.edit_rounded,
                    size: 17,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ));
    }
    return rows;
  }

  /// Редактор одного просмотра серии: дата + оценка + удаление (как у фильмов).
  void _editEpisodeView(BuildContext context, Episode we, int viewIndex) {
    final v = we.views[viewIndex];
    DateTime? date = v.date;
    bool rated = we.scoreOfView(v) != null;
    double val = we.scoreOfView(v) ?? 1.0;
    final scheme = Theme.of(context).colorScheme;
    final sid = widget.seriesId;
    final season = ep.season, number = ep.number;

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
            padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      viewIndex > 0
                          ? trf('viewing_n', {'n': viewIndex + 1})
                          : tr('edit_viewing'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: scheme.onSurface)),
                ),
                const SizedBox(height: 12),
                Material(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: sheetCtx,
                        initialDate: date ?? now,
                        firstDate: DateTime(1900),
                        lastDate: now,
                      );
                      if (picked == null || !sheetCtx.mounted) return;
                      final time = await showTimePicker(
                        context: sheetCtx,
                        initialTime: TimeOfDay.fromDateTime(date ?? now),
                      );
                      setSheet(() => date = time == null
                          ? DateTime(picked.year, picked.month, picked.day)
                          : DateTime(picked.year, picked.month, picked.day,
                              time.hour, time.minute));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.event_rounded, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('date_time'),
                                    style: TextStyle(
                                        fontFamily: AppTheme.bodyFont,
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant)),
                                Text(
                                    date == null
                                        ? tr('when_unknown')
                                        : dateExactWithTime(date!),
                                    style: TextStyle(
                                        fontFamily: AppTheme.bodyFont,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: scheme.onSurface)),
                              ],
                            ),
                          ),
                          if (date != null)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              tooltip: tr('clear_date'),
                              onPressed: () => setSheet(() => date = null),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    final r =
                        await showScorePad(sheetCtx, initial: rated ? val : null);
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
                Text(tr('rate_this_viewing'),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant)),
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
                    IconButton.filledTonal(
                      onPressed: () {
                        _repo.removeEpisodeView(sid, season, number, viewIndex);
                        Navigator.pop(sheetCtx);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      style: IconButton.styleFrom(
                          backgroundColor: scheme.errorContainer,
                          foregroundColor: scheme.onErrorContainer),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextButton(
                        onPressed: () => setSheet(() => rated = false),
                        child: Text(tr('remove_score')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          _repo.setEpisodeViewDate(
                              sid, season, number, viewIndex, date);
                          _repo.setEpisodeViewScore(
                              sid, season, number, viewIndex, rated ? val : null);
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

  List<Widget> _watchButtons(ColorScheme scheme, bool watched) {
    if (!watched) {
      // Невышедшую серию отметить нельзя — показываем подсказку.
      if (!widget.canMark) {
        return [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(tr('episode_not_aired'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ];
      }
      return [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.onMark,
            icon: const Icon(Icons.check_rounded),
            label: Text(tr('mark_watched')),
          ),
        ),
      ];
    }
    final watches = _we?.watchCount ?? 1;
    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.onRewatch,
          icon: const Icon(Icons.repeat_rounded),
          label: Text('${tr('watch_again')}  ·  ×$watches'),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: () {
            widget.onUnmark();
            Navigator.of(context).maybePop();
          },
          icon: const Icon(Icons.remove_done_rounded),
          label: Text(tr('undo_watch')),
          style: FilledButton.styleFrom(
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundColor: scheme.onSurfaceVariant),
        ),
      ),
    ];
  }

  /// Плитка «Дата и время просмотра» с правкой (дата+время) и очисткой.
  Widget _watchedAtTile(ColorScheme scheme, Episode we) {
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _editWatchedAt(we),
        // Удержание — быстро пометить дату как «Неизвестно».
        onLongPress: we.watchedAt == null
            ? null
            : () {
                _repo.setEpisodeWatchedAt(widget.seriesId, we, null);
                _messenger.currentState?.showSnackBar(SnackBar(
                    content: Text(tr('marked_unknown')),
                    behavior: SnackBarBehavior.floating));
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.event_rounded, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('date_time'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 12,
                            color: scheme.onSurfaceVariant)),
                    Text(
                        we.watchedAt == null
                            ? tr('when_unknown')
                            : dateExactWithTime(we.watchedAt!),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: scheme.onSurface)),
                  ],
                ),
              ),
              if (we.watchedAt != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: tr('clear_date'),
                  onPressed: () =>
                      _repo.setEpisodeWatchedAt(widget.seriesId, we, null),
                )
              else
                Icon(Icons.edit_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Диалоги выбора даты, затем времени просмотра серии.
  Future<void> _editWatchedAt(Episode we) async {
    final now = DateTime.now();
    final initial = we.watchedAt ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    final dt = time == null
        ? DateTime(picked.year, picked.month, picked.day)
        : DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
    await _repo.setEpisodeWatchedAt(widget.seriesId, we, dt);
  }

  Widget _scoreCard(ColorScheme scheme, Episode? we) {
    if (we == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24)),
        child: Column(children: [
          Icon(Icons.star_border_rounded,
              size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(tr('rate_after_watch_ep'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: scheme.onSurfaceVariant)),
        ]),
      );
    }
    final rated = _dragging != null || we.score != null;
    final val = _dragging ?? we.score ?? 1.0;
    final accent = scoreColor(val);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(24)),
      child: Column(children: [
        Text(tr('episode_score'),
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
        const SizedBox(height: 2),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final r = await showScorePad(context, initial: we.score);
            if (r != null) {
              _repo.setEpisodeScore(widget.seriesId, we, r);
              if (mounted) setState(() => _dragging = null);
            }
          },
          child: TweenAnimationBuilder<Color?>(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            tween: ColorTween(
                end: rated
                    ? accent
                    : scheme.onPrimaryContainer.withValues(alpha: 0.55)),
            builder: (context, color, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Icon(rated ? Icons.star_rounded : Icons.star_border_rounded,
                    color: color, size: 30),
                const SizedBox(width: 6),
                Text(rated ? val.toStringAsFixed(1) : '—',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 44,
                        height: 1,
                        color: color)),
                Text(' / 10',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color:
                            scheme.onPrimaryContainer.withValues(alpha: 0.7))),
                const SizedBox(width: 8),
                Icon(Icons.dialpad_rounded,
                    size: 18,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.55)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        RatingSlider(
          value: val,
          onChanged: (v) => setState(() => _dragging = v),
          onChangeEnd: (v) {
            _repo.setEpisodeScore(widget.seriesId, we, v);
            setState(() => _dragging = null);
          },
        ),
      ]),
    );
  }
}
