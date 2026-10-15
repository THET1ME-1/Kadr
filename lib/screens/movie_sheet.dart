import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../models/social.dart';
import '../services/facts_service.dart';
import '../services/movie_repository.dart';
import '../services/social/social_controller.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/movie_reviews.dart';
import '../utils/score.dart';
import '../widgets/action_group.dart';
import '../widgets/movie_cards.dart' show statusBadges;
import '../widgets/pop_icon.dart';
import '../widgets/favorite_character.dart';
import '../widgets/poster.dart';
import '../widgets/poster_viewer.dart';
import '../widgets/pressable.dart';
import '../widgets/facts_section.dart';
import '../widgets/reveal.dart';
import '../widgets/user_avatar.dart';
import '../widgets/viewing/drop_parts.dart';
import '../widgets/youtube_parts.dart';
import '../widgets/viewing/score_card.dart';
import 'browse_screens.dart';
import 'social/auth_screen.dart';
import 'social/media_image_picker.dart';
import 'share_card_sheet.dart';
import 'when_watched_sheet.dart';
import 'review/movie_reviews_section.dart';
import 'viewing/drop_sheet.dart';
import 'viewing/viewing_delete.dart';
import 'viewing/viewing_host.dart';
import 'viewing/viewing_sheet.dart';
import 'viewing/viewings_section.dart';

/// Открывает полноэкранную карточку фильма (как экран сериала — отдельная
/// страница, а не выезжающая панель).
Future<void> showMovieSheet(
  BuildContext context,
  LibraryMovie movie, {
  String? heroTag,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MovieScreen(movie: movie, heroTag: heroTag),
    ),
  );
}

/// Полноэкранная карточка фильма (M3 Expressive): крупная шапка с бэкдропом и
/// постером, оценка КАЖДОГО просмотра со сравнением, детали TMDB (описание,
/// актёры, факты, ссылки). Обновляется на лету.
class MovieScreen extends StatefulWidget {
  final LibraryMovie movie;
  final String? heroTag;
  const MovieScreen({super.key, required this.movie, this.heroTag});

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  final _repo = MovieRepository.instance;

  TmdbDetails? _details;

  /// Части коллекции/франшизы (если фильм входит в серию).
  List<TmdbMovie>? _collection;
  String? _collectionName;

  /// id элементов, чья анимация появления уже проигралась — чтобы при
  /// горизонтальной прокрутке актёров/франшизы карточки не анимировались заново
  /// (это давало дропы кадров). См. [Reveal].
  final Set<Object> _revealed = {};

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final m = widget.movie;
    // Ролик YouTube в TMDB не ищется: по названию выпуска нашёлся бы чужой
    // фильм.
    if (m.isYouTube) return;
    var id = m.tmdbId;
    if (id == null) {
      // Нет tmdbId (напр. сопоставлен через KinoPoisk) — ищем по названию+году.
      final match = await TmdbService.search(m.title, year: m.year);
      id = match?.tmdbId;
      if (id != null) _repo.setTmdbId(m.uuid, id);
    }
    if (id == null) return;
    final d = await TmdbService.details(id);
    // Постер берём из ТЕХ ЖЕ деталей, что и бэкдроп (по верному tmdbId) — иначе
    // закэшированный ранее постер мог быть от другого фильма («чужой постер»).
    if (d?.posterUrl != null && d!.posterUrl != m.posterUrl) {
      _repo.setPoster(m.uuid, posterUrl: d.posterUrl);
    }
    if (mounted && d != null) setState(() => _details = d);
    // Кэшируем жанры/страны/длительность в фильм (для фильтров и статистики).
    if (d != null) {
      _repo.applyDetails(
        m.uuid,
        genres: [for (final g in d.genres) g.name],
        countries: d.countries,
        runtimeMin: d.runtime,
      );
    }
    // Части франшизы (несколько фильмов) — грузим отдельно.
    if (d?.collectionId != null) {
      final parts = await TmdbService.collection(d!.collectionId!);
      if (mounted && parts.length > 1) {
        setState(() {
          _collection = parts;
          _collectionName = d.collectionName;
        });
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
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
              child: IconButton(
                icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
                tooltip: tr('share'),
                onPressed: () => showShareCardSheet(
                  context,
                  _repo.byUuid(widget.movie.uuid) ?? widget.movie,
                  backdropUrl: _details?.backdropUrl,
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          final m = _repo.byUuid(widget.movie.uuid) ?? widget.movie;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _hero(scheme, m)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(_content(context, m)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------ шапка ------------------------------

  Widget _hero(ColorScheme scheme, LibraryMovie m) {
    final meta = [
      if (m.year != null) '${m.year}',
      if (m.runtimeMin != null) humanDuration(Duration(minutes: m.runtimeMin!)),
    ].join(' · ');
    final yt = m.youtube;
    // У ролика YouTube вместо бэкдропа его кадр.
    final backdrop = yt != null ? ytCover(yt.videoId) : _details?.backdropUrl;
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Бэкдроп (или цветной градиент) с затемнением снизу.
          if (backdrop != null)
            CachedNetworkImage(
              imageUrl: backdrop,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              // Декод под ширину экрана, а не под исходные ~1280px.
              memCacheWidth:
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
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
                  onTap: () => openPosterViewer(
                    context,
                    title: m.displayTitle,
                    url: m.displayPoster,
                    heroTag: widget.heroTag ?? 'poster-${m.uuid}',
                  ),
                  onLongPress: () => _editMoviePoster(m),
                  child: Hero(
                    tag: widget.heroTag ?? 'poster-${m.uuid}',
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      shadowColor: Colors.black54,
                      child: Poster(
                        title: m.displayTitle,
                        url: m.displayPoster,
                        width: 104,
                        radius: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onLongPress: () => _copy(m.displayTitle),
                        child: Text(
                          m.displayTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 24,
                            height: 1.05,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          meta,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                      if (yt != null) ...[
                        const SizedBox(height: 8),
                        YtChannelLine(name: yt.channelName, avatar: yt.avatar),
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

  List<Widget> _content(BuildContext context, LibraryMovie m) {
    final scheme = Theme.of(context).colorScheme;
    return [
      // Чипы статуса под шапкой: статус, повторы, рейтинг КП.
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          _statusChip(scheme, m),
          if (m.isRewatched)
            _chip(
              scheme,
              Icons.repeat_rounded,
              trn('views_n', m.viewCount),
              tone: true,
            ),
          if (m.kpRating != null && m.kpRating! > 0)
            _chip(scheme, Icons.star_rounded, m.kpRating!.toStringAsFixed(1)),
        ],
      ),
      // Начатый фильм: когда начал и на какой минуте остановился.
      if (m.pausedViewing != null) ...[
        const SizedBox(height: 16),
        PausedBlock(
          viewing: m.pausedViewing!,
          runtimeMin: m.runtimeMin,
          onTap: () => showViewingSheet(
            context,
            MovieViewingHost(m.uuid, repo: _repo),
            viewId: m.pausedViewing!.id,
          ),
        ),
      ],
      // Брошенный фильм: наверху когда, на какой минуте и почему.
      if (m.isDropped && m.lastDropped != null) ...[
        const SizedBox(height: 16),
        DroppedBlock(
          viewing: m.lastDropped!,
          runtimeMin: m.runtimeMin,
          onTap: () => showViewingSheet(
            context,
            MovieViewingHost(m.uuid, repo: _repo),
            viewId: m.lastDropped!.id,
          ),
        ),
      ],
      const SizedBox(height: 16),
      // «Убрать оценку» стоит внутри карточки оценки, как в окне просмотра.
      _scoreCard(scheme, m),
      // Рецензии стоят сразу под оценкой, как на экране сериала. Без
      // рецензий блока нет: «Рецензия» живёт в группе под главной кнопкой.
      if (movieReviews(m).isNotEmpty) ...[
        const SizedBox(height: 12),
        MovieReviewsSection(movie: m, repo: _repo),
      ],
      // Ролик YouTube открывается в приложении YouTube.
      if (m.youtube != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () => openYouTube(m.youtube!.url),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(tr('yt_watch')),
          ),
        ),
      ],
      // Вариант Б макета «Кнопки карточки»: одна главная кнопка с меню и
      // связанная группа. Семь широких кнопок подряд не возвращать.
      const SizedBox(height: 12),
      _mainActions(m),
      const SizedBox(height: 8),
      _actionGroup(scheme, m),
      // Фильм, брошенный старой версией статусом без даты: снять отметку.
      if (m.status == LibraryStatus.dropped) ...[
        const SizedBox(height: 12),
        _legacyDroppedButton(m),
      ],
      if (m.viewings.isNotEmpty) ...[
        const SizedBox(height: 12),
        ViewingsSection(host: MovieViewingHost(m.uuid, repo: _repo)),
      ],
      ..._collectionSection(scheme, m),
      ..._detailsWidgets(scheme, m),
      if (m.emotions.isNotEmpty) ...[
        const SizedBox(height: 18),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in m.emotions)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text('${e.emoji} ${e.label}'),
                backgroundColor: scheme.secondaryContainer,
                side: BorderSide.none,
              ),
          ],
        ),
      ],
    ];
  }

  // ------------------------ детали TMDB ------------------------
  /// Секция «части франшизы»: постеры всех фильмов серии по порядку выхода со
  /// статусом (просмотрено/буду смотреть/брошено/без списка). Тап → карточка.
  List<Widget> _collectionSection(ColorScheme scheme, LibraryMovie m) {
    final parts = _collection;
    if (parts == null || parts.length < 2) return const [];
    return [
      const SizedBox(height: 22),
      _sectionTitle(scheme, _collectionName ?? tr('collection')),
      const SizedBox(height: 12),
      SizedBox(
        height: 218,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: parts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (c, i) => Reveal(
            group: _revealed,
            id: 'part:$i',
            delay: Duration(milliseconds: i * 45),
            beginOffset: const Offset(0.15, 0),
            child: _partCard(scheme, parts[i], i + 1, m.tmdbId),
          ),
        ),
      ),
    ];
  }

  Widget _partCard(
    ColorScheme scheme,
    TmdbMovie part,
    int order,
    int? currentTmdbId,
  ) {
    // Матчим и по названию+году: у импортированных просмотренных фильмов часто
    // ещё нет tmdbId — иначе статус (галочка) не показывался бы до открытия.
    final lib = _repo.findMovieForTmdb(part);
    final isCurrent = currentTmdbId != null && part.id == currentTmdbId;
    return SizedBox(
      width: 120,
      child: GestureDetector(
        onTap: isCurrent
            ? null
            : () => showMovieSheet(context, _repo.ensureFromTmdb(part)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Poster(
                  title: part.title,
                  url: part.posterUrl,
                  width: 120,
                  radius: 14,
                ),
                // Порядковый номер части.
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$order',
                      style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned(top: 6, right: 6, child: statusBadges(scheme, lib)),
                if (isCurrent)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.primary, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              part.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.1,
                color: scheme.onSurface,
              ),
            ),
            if (part.year != null)
              Text(
                '${part.year}',
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _detailsWidgets(ColorScheme scheme, LibraryMovie m) {
    final d = _details;
    final links = _links(m);
    if (d == null) {
      return links.isEmpty ? [] : [const SizedBox(height: 16), ...links];
    }
    final facts = <Widget>[
      if (d.director != null && d.director!.isNotEmpty)
        _personFact(
          scheme,
          Icons.movie_creation_rounded,
          tr('director'),
          d.director!,
          d.directorId,
        ),
      if (d.budget != null && d.budget! > 0)
        _fact(scheme, Icons.payments_rounded, tr('budget'), _money(d.budget!)),
      if (d.revenue != null && d.revenue! > 0)
        _fact(
          scheme,
          Icons.trending_up_rounded,
          tr('revenue'),
          _money(d.revenue!),
        ),
    ];
    return [
      if (d.tagline != null) ...[
        const SizedBox(height: 18),
        Text(
          '«${d.tagline!.replaceAll(RegExp(r'^[«»"\s]+|[«»"\s]+$'), '')}»',
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (d.overview != null && d.overview!.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionTitle(scheme, tr('overview')),
        const SizedBox(height: 6),
        GestureDetector(
          onLongPress: () => _copy(d.overview!),
          child: Text(
            d.overview!,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 14,
              height: 1.45,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
      if (d.genres.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final g in d.genres)
              Material(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GenreScreen(
                        genreId: g.id,
                        genreName: capitalize(g.name),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      capitalize(g.name),
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
      if (d.cast.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionTitle(scheme, tr('cast')),
        const SizedBox(height: 12),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: d.cast.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (c, i) => Reveal(
              group: _revealed,
              id: 'cast:$i',
              delay: Duration(milliseconds: i * 45),
              beginOffset: const Offset(0.15, 0),
              child: Pressable(
                scale: 1,
                haptic: false,
                onTap: d.cast[i].id > 0
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PersonScreen(
                            personId: d.cast[i].id,
                            personName: d.cast[i].name,
                            personPhoto: d.cast[i].photoUrl,
                          ),
                        ),
                      )
                    : null,
                onLongPress: () =>
                    promptFavoriteCharacter(context, d.cast[i], m.displayTitle),
                child: _castCard(scheme, d.cast[i]),
              ),
            ),
          ),
        ),
      ],
      if (facts.isNotEmpty) ...[const SizedBox(height: 16), ...facts],
      FactsSection(
        key: ValueKey('facts-${m.uuid}'),
        loader: () => FactsService.forMovie(
          kinopoiskId: m.kinopoiskId,
          imdbId: m.imdbId ?? d.imdbId,
          title: m.displayTitle,
          year: m.year,
        ),
      ),
      if (links.isNotEmpty) ...[const SizedBox(height: 16), ...links],
    ];
  }

  /// Ряд внешних ссылок (Кинопоиск / IMDb / TMDb).
  List<Widget> _links(LibraryMovie m) {
    // Ролик YouTube на Кинопоиске и в IMDb не ищется.
    if (m.isYouTube) return const [];
    final items = <Widget>[];
    void add(String label, Color color, String url) {
      items.add(
        Material(
          color: color,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Кинопоиск: если есть точный id — прямая ссылка на страницу фильма; иначе
    // (id не подтянулся: источник TMDB / латинское имя из импорта не совпало /
    // лимит API) — открываем поиск Кинопоиска по названию+году, чтобы ссылка
    // была ВСЕГДА, ведь сам фильм на КП обычно есть.
    if (m.kinopoiskId != null) {
      add(
        'ПоискКино',
        const Color(0xFFFF6600),
        'https://www.kinopoisk.ru/film/${m.kinopoiskId}/',
      );
    } else {
      final q = [m.displayTitle, if (m.year != null) '${m.year}'].join(' ');
      add(
        'ПоискКино',
        const Color(0xFFFF6600),
        'https://www.kinopoisk.ru/index.php?kp_query=${Uri.encodeQueryComponent(q)}',
      );
    }
    if (_details?.imdbId != null) {
      add(
        'IMDb',
        const Color(0xFFD8A800),
        'https://www.imdb.com/title/${_details!.imdbId}/',
      );
    }
    if (m.tmdbId != null) {
      add(
        'TMDb',
        const Color(0xFF01B4E4),
        'https://www.themoviedb.org/movie/${m.tmdbId}',
      );
    }
    if (items.isEmpty) return [];
    return [Wrap(spacing: 8, runSpacing: 8, children: items)];
  }

  Widget _sectionTitle(ColorScheme scheme, String title) => Text(
    title,
    style: TextStyle(
      fontFamily: AppTheme.displayFont,
      fontWeight: FontWeight.w700,
      fontSize: 15,
      color: scheme.primary,
    ),
  );

  Widget _castCard(ColorScheme scheme, TmdbCast c) {
    return SizedBox(
      width: 84,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: c.photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: c.photoUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: (72 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    errorWidget: (ctx, u, e) => Icon(
                      Icons.person_rounded,
                      color: scheme.onSurfaceVariant,
                      size: 34,
                    ),
                  )
                : Icon(
                    Icons.person_rounded,
                    color: scheme.onSurfaceVariant,
                    size: 34,
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            c.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              height: 1.1,
              color: scheme.onSurface,
            ),
          ),
          if (c.character != null && c.character!.isNotEmpty)
            Text(
              c.character!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 10.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _fact(ColorScheme scheme, IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              '$label: ',
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      );

  /// Факт-ссылка на персону (режиссёр): имя-ссылка ведёт в фильмографию.
  Widget _personFact(
    ColorScheme scheme,
    IconData icon,
    String label,
    String name,
    int? personId,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontSize: 14,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: personId != null && personId > 0
                ? () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PersonScreen(personId: personId, personName: name),
                    ),
                  )
                : null,
            child: Text(
              name,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                decoration: personId != null && personId > 0
                    ? TextDecoration.underline
                    : null,
                decorationColor: scheme.primary,
                color: personId != null && personId > 0
                    ? scheme.primary
                    : scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// Замена постера фильма: выбор из галереи, из официальных постеров TMDB или
  /// сброс к оригиналу (долгое нажатие на постер). Меняется в одном месте —
  /// отображается везде.
  Future<void> _editMoviePoster(LibraryMovie m) async {
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
            if (m.posterFile != null)
              ListTile(
                leading: Icon(
                  Icons.restore_rounded,
                  color: scheme.onSurfaceVariant,
                ),
                title: Text(tr('poster_reset')),
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'reset') {
      await _repo.clearMoviePosterLocal(m.uuid);
      if (mounted) setState(() {});
      return;
    }
    if (action == 'tmdb') {
      final url = await showMediaImagePicker(
        context,
        backdrop: false,
        initialTmdbId: m.tmdbId,
        initialIsTv: false,
        initialTitle: m.title,
      );
      if (!mounted || url == null) return;
      final ok = await _repo.setMoviePosterFromUrl(m.uuid, url);
      if (!mounted) return;
      if (ok) {
        setState(() {});
      } else {
        _snack(tr('poster_load_failed'));
      }
      return;
    }
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final raw =
          f.bytes ??
          (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (raw == null) return;
      final ok = await _repo.setMoviePosterLocal(m.uuid, raw);
      if (mounted && ok) setState(() {});
    } catch (_) {
      /* отмена/ошибка выбора файла — игнорируем */
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack(tr('copied'));
  }

  String _money(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '$buf \$';
  }

  // ------------------ управление списками ------------------
  /// Посоветовать фильм другу: выбрать друга + необязательная заметка.
  void _recommendToFriend(LibraryMovie m) {
    final scheme = Theme.of(context).colorScheme;
    final noteCtl = TextEditingController();
    final friends = SocialController.instance.friends.friends;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trf('recommend_title', {'title': m.displayTitle}),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtl,
                  maxLength: 200,
                  style: const TextStyle(fontFamily: AppTheme.bodyFont),
                  decoration: InputDecoration(
                    hintText: tr('recommend_note_hint'),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr('recommend_pick_friend'),
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in friends)
                        ListTile(
                          leading: UserAvatar(user: f.user, size: 40),
                          title: Text(
                            f.user.displayName,
                            style: const TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: const Icon(Icons.send_rounded),
                          onTap: () {
                            Navigator.pop(ctx);
                            _sendRecommendation(m, f.user, noteCtl.text.trim());
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendRecommendation(
    LibraryMovie m,
    SocialUser to,
    String note,
  ) async {
    try {
      await SocialController.instance.recommend(
        toUserId: to.id,
        title: m.displayTitle,
        year: m.year,
        posterUrl: m.posterUrl,
        tmdbId: m.tmdbId,
        note: note.isEmpty ? null : note,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trf('recommend_sent', {'name': to.displayName})),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    }
  }

  void _manageListsSheet(LibraryMovie m) {
    final scheme = Theme.of(context).colorScheme;
    final ctl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          final lists = _repo.lists;
          final inLists = _repo.listsForMovie(m.uuid).toSet();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr('manage_lists'),
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (lists.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                            child: Text(
                              tr('no_lists_yet'),
                              style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        for (final l in lists)
                          CheckboxListTile(
                            value: inLists.contains(l.name),
                            title: Text(
                              l.name,
                              style: const TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onChanged: (_) {
                              _repo.toggleInList(l.name, m.uuid);
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctl,
                            decoration: InputDecoration(
                              hintText: tr('new_list'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: () {
                            _repo.createList(ctl.text, withMovieUuid: m.uuid);
                            ctl.clear();
                            setSheet(() {});
                          },
                          child: Text(tr('create')),
                        ),
                      ],
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

  Widget _statusChip(ColorScheme scheme, LibraryMovie m) {
    // Брошенный фильм лежит в «Просмотрено» попыткой, но статус у него свой.
    if (m.isDropped) {
      return _chip(scheme, Icons.heart_broken_rounded, tr('dropped'),
          dropped: true);
    }
    // Начат и ещё ни разу не досмотрен.
    if (!m.hasFullViewing && m.pausedViewing != null) {
      return _chip(scheme, Icons.play_circle_rounded, tr('pause_chip'),
          primary: true);
    }
    final (icon, label) = switch (m.status) {
      LibraryStatus.watched => (Icons.check_circle_rounded, tr('act_watched')),
      LibraryStatus.watchlist => (Icons.bookmark_rounded, tr('in_watchlist')),
      LibraryStatus.dropped => (Icons.heart_broken_rounded, tr('dropped')),
      LibraryStatus.library => (Icons.movie_rounded, tr('app_name')),
    };
    return _chip(scheme, icon, label, primary: true);
  }

  Widget _chip(
    ColorScheme scheme,
    IconData icon,
    String label, {
    bool primary = false,
    bool tone = false,
    bool dropped = false,
  }) {
    final bg = dropped
        ? dropTint(scheme, base: scheme.surface, alpha: 0.18)
        : primary
            ? scheme.primaryContainer
            : (tone
                ? scheme.tertiaryContainer
                : scheme.surfaceContainerHighest);
    final fg = dropped
        ? kDroppedColor
        : primary
            ? scheme.onPrimaryContainer
            : (tone ? scheme.onTertiaryContainer : scheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  /// Оценка в карточке: у последнего просмотра, а пока просмотров нет —
  /// общая. У неоценённого пересмотра карточка пустая, даже если прошлые
  /// просмотры оценены.
  double? _shownScore(LibraryMovie m) {
    final cv = m.currentViewing;
    return cv != null ? cv.score : m.score;
  }

  Widget _scoreCard(ColorScheme scheme, LibraryMovie m) {
    // Оценка доступна только просмотренным фильмам. Начатый просмотр
    // оценивают, когда досмотрят.
    final paused = m.currentViewing?.isPaused ?? false;
    final canRate =
        m.currentViewing != null || m.status == LibraryStatus.watched;
    if (!canRate || paused) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Icon(
              Icons.star_border_rounded,
              size: 34,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              tr(paused ? 'rate_after_finish' : 'rate_after_watch'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Карточка показывает последний просмотр: его номер в подписи, его дату
    // и прошлую оценку под слайдером.
    final cv = m.currentViewing;
    final score = _shownScore(m);
    final host = MovieViewingHost(m.uuid, repo: _repo);
    final prev = cv == null ? null : host.previousRated(cv);
    final prevText = prev?.score.toStringAsFixed(1);
    final footer = [
      if (cv?.date != null) numericDate(cv!.date!),
      if (prevText != null) trf('view_last_time', {'v': prevText}),
    ].join(' · ');
    final full = cv == null ? 0 : m.fullOrdinalOf(cv);
    return ScoreCard(
      key: ValueKey('score-${cv?.id}'),
      label: cv?.drop != null
          ? tr('drop_score_label')
          : m.isRewatched && full > 0
              ? trf('score_of_view', {
                  'view': trf('viewing_n', {'n': full}),
                })
              : tr('current_viewing_score'),
      value: score,
      onChanged: (v) => _repo.setCurrentScore(m.uuid, v),
      onClear: () => _repo.setCurrentScore(m.uuid, null),
      footer: footer.isNotEmpty
          ? footer
          : tr(score != null ? 'your_rating' : 'no_rating_yet'),
      sameAs: prev?.score,
      sameLabel: prevText == null
          ? null
          : trf(prev!.ordinal == 1 ? 'view_same_first' : 'view_same_last',
              {'v': prevText}),
    );
  }

  /// Главная кнопка, разделённая на две (вариант Б макета «Кнопки карточки»):
  /// слева отметка просмотра, стрелка справа открывает «Досмотрю потом»,
  /// «Бросить» (у просмотренного «Бросить пересмотр») и «Отменить
  /// просмотр». У начатого фильма слева «Досмотрел» (макет «Фильм в
  /// несколько заходов»).
  Widget _mainActions(LibraryMovie m) {
    final paused = m.pausedViewing;
    final items = <Widget>[
      // Брошенному старой версией статусом бросать нечего: снять отметку
      // можно кнопкой под группой.
      if (m.status != LibraryStatus.dropped) ...[
        MenuItemButton(
          leadingIcon: Icon(Icons.pause_circle_rounded,
              color: Theme.of(context).colorScheme.primary),
          onPressed: () => _pause(m),
          child: Text(tr('pause_later')),
        ),
        MenuItemButton(
          leadingIcon:
              const Icon(Icons.heart_broken_rounded, color: kDroppedColor),
          onPressed: () => paused != null ? _dropPaused(m, paused) : _drop(m),
          child: Text(tr(m.isWatched ? 'drop_rewatch' : 'mark_dropped')),
        ),
      ],
      if (m.status == LibraryStatus.watched)
        MenuItemButton(
          leadingIcon: const Icon(Icons.remove_done_rounded),
          onPressed: () => _undoWatch(m),
          child: Text(tr('undo_watch')),
        ),
    ];
    const outer = Radius.circular(28), inner = Radius.circular(8);
    final main = FilledButton.icon(
      onPressed: () => paused != null
          ? showFinishSheet(context, m, paused, repo: _repo)
          : showWhenWatchedSheet(context, m),
      icon: Icon(
          paused != null ? Icons.task_alt_rounded : Icons.add_task_rounded),
      // Брошенный фильм ещё не досмотрен: «Отметить просмотр».
      label: Text(tr(paused != null
          ? 'drop_finished'
          : (m.isWatched ? 'watch_again' : 'mark_watched'))),
      style: items.isEmpty
          ? null
          : FilledButton.styleFrom(
              shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.horizontal(left: outer, right: inner),
              ),
            ),
    );
    if (items.isEmpty) return SizedBox(width: double.infinity, child: main);
    return Row(
      spacing: 2,
      children: [
        Expanded(child: main),
        MenuAnchor(
          alignmentOffset: const Offset(0, 4),
          style: MenuStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          menuChildren: items,
          builder: (context, menu, _) => Tooltip(
            message: tr('more_actions'),
            child: FilledButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                menu.isOpen ? menu.close() : menu.open();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(56, 56),
                padding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.horizontal(left: inner, right: outer),
                ),
              ),
              child: AnimatedRotation(
                turns: menu.isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Связанная группа под главной кнопкой: любимое, рецензия, списки, совет
  /// другу. У фильма без просмотров вместо рецензии «Буду смотреть», а
  /// «Списки» сжимаются до значка: подпись «Буду смотреть» длинная.
  Widget _actionGroup(ColorScheme scheme, LibraryMovie m) {
    final seen = m.viewings.isNotEmpty || m.status == LibraryStatus.watched;
    final inList = m.status == LibraryStatus.watchlist;
    return ActionGroup([
      ActionGroupButton.icon(
        tooltip: tr('act_favorite'),
        active: m.favorite,
        onPressed: () {
          HapticFeedback.lightImpact();
          _repo.toggleFavorite(m.uuid);
        },
        child: PopIcon(
          active: m.favorite,
          activeIcon: Icons.favorite_rounded,
          inactiveIcon: Icons.favorite_border_rounded,
          activeColor: scheme.onPrimary,
          inactiveColor: scheme.onSecondaryContainer,
          size: 24,
        ),
      ),
      if (seen)
        ActionGroupButton.label(
          icon: Icons.rate_review_rounded,
          label: tr('view_review'),
          onPressed: () => startMovieReview(context, m, repo: _repo),
        )
      else
        ActionGroupButton.label(
          icon: inList ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          label: tr(inList ? 'in_watchlist' : 'add_watchlist'),
          active: inList,
          onPressed: () => _repo.toggleWatchlist(m.uuid),
        ),
      if (seen)
        ActionGroupButton.label(
          icon: Icons.playlist_add_rounded,
          label: tr('manage_lists'),
          onPressed: () => _manageListsSheet(m),
        )
      else
        ActionGroupButton.icon(
          tooltip: tr('manage_lists'),
          onPressed: () => _manageListsSheet(m),
          child: const Icon(Icons.playlist_add_rounded),
        ),
      // Советовать фильм другу (только если есть друзья в соц-слое).
      if (SocialController.instance.friends.friends.isNotEmpty)
        ActionGroupButton.icon(
          tooltip: tr('recommend_to_friend'),
          onPressed: () => _recommendToFriend(m),
          child: const Icon(Icons.recommend_rounded),
        ),
    ]);
  }

  /// «Отменить просмотр» из меню: убирает последний просмотр. С оценкой,
  /// дневником или рецензией сначала спрашивает, после удаления висит
  /// «Вернуть».
  Future<void> _undoWatch(LibraryMovie m) async {
    final cv = m.currentViewing;
    if (cv != null) {
      await deleteViewingFlow(
          context, MovieViewingHost(m.uuid, repo: _repo), cv);
      return;
    }
    // Старая запись «просмотрено» без единого просмотра.
    await _repo.undoLastViewing(m.uuid);
    if (mounted) _snack(tr('unwatched'));
  }

  /// Залитая «Брошено» у фильма, брошенного старой версией статусом без
  /// даты: тап снимает отметку.
  Widget _legacyDroppedButton(LibraryMovie m) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => _repo.toggleDropped(m.uuid),
          icon: const Icon(Icons.heart_broken_rounded),
          label: Text(tr('in_dropped')),
          style: FilledButton.styleFrom(
            backgroundColor: kDroppedColor,
            foregroundColor: Colors.white,
          ),
        ),
      );

  /// «Досмотрю потом»: окно «Где остановились?», потом пауза. Если фильм
  /// уже начат, это следующий заход, минута стоит с прошлого раза.
  Future<void> _pause(LibraryMovie m) async {
    final paused = m.pausedViewing;
    final choice = await showPauseSheet(
      context,
      subject: m.displayTitle,
      runtimeMin: m.runtimeMin,
      initialMin: paused?.pause?.atMin,
      first: paused == null,
    );
    if (choice == null || !mounted) return;
    await _repo.pauseViewing(m.uuid, atMin: choice.atMin, date: choice.date);
    if (mounted) _snack(tr('pause_saved'));
  }

  /// «Бросить» у начатого фильма: та же попытка становится брошенной, минута
  /// стоит с паузы, день остаётся прежним.
  Future<void> _dropPaused(LibraryMovie m, Viewing paused) async {
    final choice = await showDropSheet(
      context,
      subject: m.displayTitle,
      runtimeMin: m.runtimeMin,
      startMin: paused.pause?.atMin,
      withDate: false,
      repo: _repo,
    );
    if (choice == null || !mounted) return;
    await _repo.setViewingDrop(m.uuid, paused, choice.drop);
    if (mounted) _snack(tr('drop_added'));
  }

  /// Записывает брошенную попытку из окна «Где бросили?».
  Future<void> _drop(LibraryMovie m) async {
    final choice = await showDropSheet(
      context,
      subject: m.displayTitle,
      runtimeMin: m.runtimeMin,
      repo: _repo,
    );
    if (choice == null || !mounted) return;
    await _repo.addViewing(m.uuid, choice.date, drop: choice.drop);
    if (mounted) {
      _snack(tr(choice.date == null ? 'drop_added_undated' : 'drop_added'));
    }
  }

}

