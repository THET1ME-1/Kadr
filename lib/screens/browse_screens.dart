import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/app_prefs.dart';
import '../services/facts_service.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/biography_block.dart';
import '../widgets/facts_section.dart';
import '../widgets/infinite_grid.dart';
import '../widgets/movie_cards.dart';

/// Подборка фильмов по жанру (открывается тапом на жанр в карточке фильма).
/// Бесконечная лента: чем дальше листаешь — тем больше подгружается.
class GenreScreen extends StatelessWidget {
  final int genreId;
  final String genreName;
  const GenreScreen(
      {super.key, required this.genreId, required this.genreName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(genreName)),
      body: ListenableBuilder(
        listenable: MovieRepository.instance,
        builder: (context, _) => InfiniteGrid<TmdbMovie>(
          loader: (page) =>
              TmdbService.discoverMovies(page: page, genreId: genreId),
          itemBuilder: (context, m, w) =>
              DiscoverMovieCard(movie: m, width: w),
        ),
      ),
    );
  }
}

/// Фильмография персоны (актёр/режиссёр). Фильмы и сериалы, где участвовал:
/// просмотренные помечены галочкой, остальные можно добавить в «Буду смотреть».
class PersonScreen extends StatefulWidget {
  final int personId;
  final String personName;

  /// Фото актёра (если открыт из каста) — сохраняется в «любимых актёрах».
  final String? personPhoto;
  const PersonScreen(
      {super.key,
      required this.personId,
      required this.personName,
      this.personPhoto});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  List<TmdbMovie>? _movies;
  List<TmdbSeries> _series = const [];
  TmdbPerson? _person;
  bool _error = false;

  /// Что показывает список: фильмы или сериалы.
  bool _showSeries = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _movies = null;
      _series = const [];
      _error = false;
    });
    // Карточка и фильмография грузятся разом: биография не должна ждать список.
    final results = await Future.wait([
      TmdbService.personDetails(widget.personId),
      TmdbService.personMovieCredits(widget.personId),
      TmdbService.personTvCredits(widget.personId),
    ]);
    if (!mounted) return;
    final list = results[1] as List<TmdbMovie>;
    final series = results[2] as List<TmdbSeries>;
    setState(() {
      _person = results[0] as TmdbPerson?;
      _movies = list;
      _series = series;
      // У ведущих и актёров сериалов фильмов может не быть вовсе — тогда
      // открываем сразу то, что есть.
      _showSeries = list.isEmpty && series.isNotEmpty;
      _error = list.isEmpty && series.isEmpty && _person == null;
    });
  }

  /// Фото для шапки: крупное из карточки персоны, иначе то, с которым открыли.
  String? get _photo => _person?.largePhotoUrl ?? widget.personPhoto;

  /// Род занятий словами. Незнакомые отделы TMDB (Camera, Sound, …) прячем —
  /// подпись «Crew» пользователю ничего не говорит.
  String? get _role => switch (_person?.department) {
        'Acting' => tr('person_acting'),
        'Directing' => tr('director'),
        'Writing' => tr('person_writing'),
        'Production' => tr('person_producing'),
        _ => null,
      };

  /// Годы жизни и место рождения: «20 мая 1990 · Челтнем, Англия».
  String get _lifeLine {
    final p = _person;
    if (p == null) return '';
    final parts = <String>[];
    if (p.birthday != null) {
      parts.add(p.deathday != null
          ? '${p.birthday!.year} — ${p.deathday!.year}'
          : longDate(p.birthday!));
    }
    if (p.placeOfBirth != null) parts.add(p.placeOfBirth!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Кружок под иконками: они лежат поверх фото, а при прокрутке — поверх
        // списка фильмов.
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
              child: ListenableBuilder(
                listenable: AppPrefs.instance,
                builder: (context, _) {
                  final fav =
                      AppPrefs.instance.isFavoriteActor(widget.personId);
                  return IconButton(
                    tooltip: fav ? tr('fav_actor_remove') : tr('fav_actor_add'),
                    icon: Icon(
                        fav
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: fav ? scheme.primary : Colors.white),
                    onPressed: () => AppPrefs.instance.toggleFavoriteActor(
                        FavoriteActor(
                            id: widget.personId,
                            name: _person?.name ?? widget.personName,
                            photoUrl: _person?.photoUrl ?? widget.personPhoto)),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: Builder(builder: (context) {
        if (_movies == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_error) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_off_rounded,
                    size: 52, color: scheme.onSurfaceVariant),
                const SizedBox(height: 10),
                Text(tr('nothing_found'),
                    style: const TextStyle(
                        fontFamily: AppTheme.bodyFont, fontSize: 15)),
                const SizedBox(height: 12),
                FilledButton.tonal(
                    onPressed: _load, child: Text(tr('retry'))),
              ],
            ),
          );
        }
        return ListenableBuilder(
          listenable: MovieRepository.instance,
          builder: (context, _) {
            final movies = _movies!;
            final series = _series;
            final repo = MovieRepository.instance;
            // Просмотренным считаем фильм с отметкой и сериал, у которого есть
            // хотя бы одна отмеченная серия.
            final seen = movies
                    .where((m) =>
                        repo.findMovieForTmdb(m)?.status ==
                        LibraryStatus.watched)
                    .length +
                series
                    .where((s) =>
                        repo.seriesByTmdb(s.id)?.episodes.isNotEmpty ?? false)
                    .length;
            final bothKinds = movies.isNotEmpty && series.isNotEmpty;
            final showSeries = _showSeries && series.isNotEmpty;
            final count = showSeries ? series.length : movies.length;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                    child: _hero(scheme, movies.length, series.length, seen)),
                if (_person?.biography != null)
                  SliverToBoxAdapter(
                      child: BiographyBlock(biography: _person!.biography!)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FactsSection(
                      key: ValueKey('facts-person-${widget.personId}'),
                      loader: () => FactsService.forPerson(
                        name: _person?.name ?? widget.personName,
                        aliases: _person?.aliases ?? const [],
                      ),
                    ),
                  ),
                ),
                if (bothKinds)
                  SliverToBoxAdapter(child: _kindSwitch(scheme))
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                      child: Text(
                        trf(showSeries ? 'series_count' : 'movies_count',
                            {'n': count}),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => showSeries
                          ? TmdbSeriesRow(series: series[i])
                          : TmdbMovieRow(movie: movies[i]),
                      childCount: count,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  /// Переключатель «Фильмы / Сериалы» — тот же вид, что на «Просмотрено»:
  /// подложка без обводки, выбранная вкладка залита активным цветом темы.
  Widget _kindSwitch(ColorScheme scheme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _kindChip(scheme,
                    label: '${tr('filter_movies')} · ${_movies!.length}',
                    selected: !_showSeries,
                    onTap: () => setState(() => _showSeries = false)),
                _kindChip(scheme,
                    label: '${tr('filter_series')} · ${_series.length}',
                    selected: _showSeries,
                    onTap: () => setState(() => _showSeries = true)),
              ],
            ),
          ),
        ),
      );

  Widget _kindChip(ColorScheme scheme,
          {required String label,
          required bool selected,
          required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: selected
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );

  /// Шапка-афиша: фото во всю ширину, имя и чипы поверх затемнения.
  Widget _hero(ColorScheme scheme, int movieCount, int seriesCount, int seen) {
    final photo = _photo;
    final life = _lifeLine;
    return SizedBox(
      height: 380,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            CachedNetworkImage(
              imageUrl: photo,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholder: (c, _) =>
                  Container(color: scheme.surfaceContainerHighest),
              errorWidget: (c, u, e) => _noPhoto(scheme),
            )
          else
            _noPhoto(scheme),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_person?.name ?? widget.personName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        height: 1.05,
                        color: Colors.white)),
                if (life.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(life,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.85))),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (seen > 0)
                      _chip(trf('person_watched_n', {'n': seen}),
                          bg: scheme.primaryContainer,
                          fg: scheme.onPrimaryContainer),
                    if (_role != null) _chip(_role!),
                    if (movieCount > 0)
                      _chip(trf('movies_count', {'n': movieCount})),
                    if (seriesCount > 0)
                      _chip(trf('series_count', {'n': seriesCount})),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {Color? bg, Color? fg}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: bg ?? Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: fg ?? Colors.white)),
      );

  /// Заглушка вместо фото: инициалы на приглушённом фоне.
  Widget _noPhoto(ColorScheme scheme) {
    final name = _person?.name ?? widget.personName;
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(initials,
          style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 64,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5))),
    );
  }
}
