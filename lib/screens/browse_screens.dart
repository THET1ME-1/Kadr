import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/app_prefs.dart';
import '../services/facts_service.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
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

/// Фильмография персоны (актёр/режиссёр). Список всех фильмов, где участвовал:
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
  TmdbPerson? _person;
  bool _error = false;
  bool _bioExpanded = false;

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
    // Карточка и фильмография грузятся разом: биография не должна ждать список.
    final results = await Future.wait([
      TmdbService.personDetails(widget.personId),
      TmdbService.personMovieCredits(widget.personId),
    ]);
    if (!mounted) return;
    final list = results[1] as List<TmdbMovie>;
    setState(() {
      _person = results[0] as TmdbPerson?;
      _movies = list;
      _error = list.isEmpty && _person == null;
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
            final repo = MovieRepository.instance;
            final seen = movies
                .where((m) =>
                    repo.findMovieForTmdb(m)?.status == LibraryStatus.watched)
                .length;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _hero(scheme, movies.length, seen)),
                if (_person?.biography != null)
                  SliverToBoxAdapter(child: _bio(scheme)),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Text(
                      trf('movies_count', {'n': movies.length}),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => TmdbMovieRow(movie: movies[i]),
                      childCount: movies.length,
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

  /// Шапка-афиша: фото во всю ширину, имя и чипы поверх затемнения.
  Widget _hero(ColorScheme scheme, int total, int seen) {
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
                    if (total > 0) _chip(trf('movies_count', {'n': total})),
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

  /// Биография: четыре строки, дальше — по кнопке.
  Widget _bio(ColorScheme scheme) {
    final text = _person!.biography!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: AppTheme.emphasized,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('copied'))));
                  },
                  child: Text(
                    text,
                    maxLines: _bioExpanded ? null : 4,
                    overflow: _bioExpanded
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 14,
                        height: 1.5,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              TextButton(
                onPressed: () => setState(() => _bioExpanded = !_bioExpanded),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(_bioExpanded ? tr('read_less') : tr('read_more')),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
