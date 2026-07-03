import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/store.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../widgets/poster.dart';
import '../widgets/poster_viewer.dart';
import '../widgets/rating_slider.dart';
import '../widgets/reveal.dart';

/// Экран сериала (M3 Expressive): крупная шапка с бэкдропом, оценка всего
/// сериала, выбор сезона, отметка «весь сезон разом», а у каждой серии —
/// галочка просмотра, повторные просмотры и своя оценка. Серии тянутся из TMDB,
/// поэтому можно отмечать даже те, которых ещё нет в библиотеке.
class SeriesScreen extends StatefulWidget {
  final LibrarySeries series;
  const SeriesScreen({super.key, required this.series});

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

  LibrarySeries get s =>
      _repo.seriesById(widget.series.tvShowId) ?? widget.series;

  @override
  void initState() {
    super.initState();
    Store.instance.getBool('sequentialEpisodes', def: true).then((v) {
      if (mounted) setState(() => _sequential = v);
    });
    _init();
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

  /// Тап по галочке: не смотрел → отметить; смотрел → +1 просмотр (×2, ×3…).
  void _tapCheck(TmdbEpisode ep) {
    final we = s.watchedEpisode(ep.season, ep.number);
    if (we == null) {
      _markEpisode(ep);
    } else {
      _repo.addEpisodeRewatch(s.tvShowId, ep.season, ep.number,
          runtimeMin: ep.runtime);
    }
    HapticFeedback.selectionClick();
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
    _seasons = await TmdbService.seasons(id);
    _extra = await TmdbService.tvExtra(id);
    if (_seasons.isEmpty) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }
    // Запоминаем общее число серий (для «Сейчас смотрю» — только незавершённые).
    final total = _seasons.fold<int>(0, (a, b) => a + b.episodeCount);
    await _repo.setSeriesTotal(s.tvShowId, total);
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
    if (mounted) setState(() => _eps = eps);
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
                SliverToBoxAdapter(child: _droppedButton(scheme)),
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
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ],
          );
        },
      ),
    );
  }

  // ------------------------------ шапка ------------------------------

  Widget _hero(ColorScheme scheme) {
    final total = _seasons.fold<int>(0, (a, b) => a + b.episodeCount);
    final seen = s.episodes.length;
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
                      url: s.posterUrl,
                      heroTag: 'sposter-${s.tvShowId}'),
                  child: Hero(
                    tag: 'sposter-${s.tvShowId}',
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      shadowColor: Colors.black54,
                      child: Poster(
                          title: s.displayTitle,
                          url: s.posterUrl,
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
                      Text(
                          total > 0
                              ? trf('seen_of', {'n': seen, 'm': total})
                              : trf('episodes_n', {'n': seen}),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.85))),
                      if (total > 0) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            tween: Tween<double>(end: progress),
                            builder: (context, v, _) => LinearProgressIndicator(
                              value: v,
                              minHeight: 8,
                              backgroundColor: Colors.white24,
                              color: Colors.white,
                            ),
                          ),
                        ),
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

  Widget _actions(ColorScheme scheme) {
    final sc = s.score;
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
                onTap: _rateSeries,
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
                            ? '${sc.toStringAsFixed(1)} · ${tr('series_rating')}'
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
              onTap: () => _repo.toggleSeriesFavorite(s.tvShowId),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                    s.favorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: s.favorite ? scheme.onPrimary : scheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
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
    final seenInSeason =
        eps.where((e) => s.isEpisodeWatched(e.season, e.number)).length;
    final allWatched = seenInSeason == eps.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              trf('season_progress',
                  {'s': _season!, 'n': seenInSeason, 'm': eps.length}),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: () {
              if (allWatched) {
                _repo.unmarkSeason(s.tvShowId, _season!);
              } else {
                final runtimes = {for (final e in eps) e.number: e.runtime};
                _repo.markSeason(
                    s.tvShowId, _season!, [for (final e in eps) e.number],
                    runtimes: runtimes);
                _snack(trf('season_done', {'n': _season!}));
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
                              Text('S${ep.season} · E${ep.number}',
                                  style: TextStyle(
                                      fontFamily: AppTheme.displayFont,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                      color: scheme.primary)),
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
              // Тап по галочке → +1 просмотр (×2, ×3…). Удержание → меню снятия.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapCheck(ep),
                onLongPress:
                    watched ? () => _checkmarkMenu(scheme, ep, watchedEp) : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
                  child: _checkCircle(scheme, watched, watches),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Кружок отметки: пусто → галочка → число просмотров (×2, ×3…) ВМЕСТО
  /// галочки. Смена состояния — плавно (масштаб+прозрачность).
  Widget _checkCircle(ColorScheme scheme, bool watched, int watches) {
    Widget child;
    if (!watched) {
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
            final r = await TmdbService.searchTvShows(q);
            setSheet(() {
              results = r;
              loading = false;
            });
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
    double val = initial ?? 6.5;
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
                Text(rated ? val.toStringAsFixed(1) : '—',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 46,
                        color:
                            rated ? scoreColor(val) : scheme.onSurfaceVariant)),
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
  final VoidCallback onMark;
  final VoidCallback onRewatch;
  final VoidCallback onUnmark;
  const _EpisodeSheet({
    required this.seriesId,
    required this.seriesTitle,
    required this.ep,
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

  List<Widget> _watchButtons(ColorScheme scheme, bool watched) {
    if (!watched) {
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
    final val = _dragging ?? we.score ?? 6.5;
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
        TweenAnimationBuilder<Color?>(
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
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
            ],
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
