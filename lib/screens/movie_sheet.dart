import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../widgets/movie_cards.dart' show statusBadges;
import '../widgets/poster.dart';
import '../widgets/poster_viewer.dart';
import '../widgets/rating_slider.dart';
import '../widgets/score_pad.dart';
import 'browse_screens.dart';
import 'when_watched_sheet.dart';

/// Открывает полноэкранную карточку фильма (как экран сериала — отдельная
/// страница, а не выезжающая панель).
Future<void> showMovieSheet(BuildContext context, LibraryMovie movie) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => MovieScreen(movie: movie)),
  );
}

/// Полноэкранная карточка фильма (M3 Expressive): крупная шапка с бэкдропом и
/// постером, оценка КАЖДОГО просмотра со сравнением, детали TMDB (описание,
/// актёры, факты, ссылки). Обновляется на лету.
class MovieScreen extends StatefulWidget {
  final LibraryMovie movie;
  const MovieScreen({super.key, required this.movie});

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  final _repo = MovieRepository.instance;

  /// Значение слайдера во время перетаскивания (иначе берём из модели).
  double? _dragging;

  TmdbDetails? _details;

  /// Части коллекции/франшизы (если фильм входит в серию).
  List<TmdbMovie>? _collection;
  String? _collectionName;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final m = widget.movie;
    var id = m.tmdbId;
    if (id == null) {
      // Нет tmdbId (напр. сопоставлен через KinoPoisk) — ищем по названию+году.
      final match = await TmdbService.search(m.title, year: m.year);
      id = match?.tmdbId;
      if (id != null) _repo.setTmdbId(m.uuid, id);
    }
    if (id == null) return;
    final d = await TmdbService.details(id);
    if (mounted && d != null) setState(() => _details = d);
    // Кэшируем жанры/страны/длительность в фильм (для фильтров и статистики).
    if (d != null) {
      _repo.applyDetails(m.uuid,
          genres: [for (final g in d.genres) g.name],
          countries: d.countries,
          runtimeMin: d.runtime);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
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
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Бэкдроп (или цветной градиент) с затемнением снизу.
          if (_details?.backdropUrl != null)
            CachedNetworkImage(
              imageUrl: _details!.backdropUrl!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              // Декод под ширину экрана, а не под исходные ~1280px.
              memCacheWidth:
                  (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
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
                GestureDetector(
                  onTap: () => openPosterViewer(context,
                      title: m.displayTitle,
                      url: m.posterUrl,
                      heroTag: 'poster-${m.uuid}'),
                  child: Hero(
                    tag: 'poster-${m.uuid}',
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      shadowColor: Colors.black54,
                      child: Poster(
                          title: m.displayTitle,
                          url: m.posterUrl,
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
                      GestureDetector(
                        onLongPress: () => _copy(m.displayTitle),
                        child: Text(m.displayTitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                                height: 1.05,
                                color: Colors.white)),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(meta,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.85))),
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
            _chip(scheme, Icons.repeat_rounded,
                trf('rewatches_n', {'n': m.rewatchCount}),
                tone: true),
          if (m.kpRating != null && m.kpRating! > 0)
            _chip(scheme, Icons.star_rounded, m.kpRating!.toStringAsFixed(1)),
        ],
      ),
      const SizedBox(height: 16),
      _scoreCard(scheme, m),
      // Широкая мягко-красная кнопка сброса оценки — только если оценка есть.
      if (m.currentScore != null) ...[
        const SizedBox(height: 12),
        _clearScoreButton(scheme, m),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => showWhenWatchedSheet(context, m),
          icon: const Icon(Icons.add_task_rounded),
          label: Text(tr(m.status == LibraryStatus.watched
              ? 'watch_again'
              : 'mark_watched')),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          // Идеально круглая кнопка-сердечко (без надписи).
          _HeartButton(
            active: m.favorite,
            onTap: () => _repo.toggleFavorite(m.uuid),
          ),
          const SizedBox(width: 12),
          if (m.status != LibraryStatus.watched)
            Expanded(
              child: m.status == LibraryStatus.watchlist
                  // Активная — окрашена как «Отметить просмотр».
                  ? FilledButton.icon(
                      onPressed: () => _repo.toggleWatchlist(m.uuid),
                      icon: const Icon(Icons.bookmark_rounded),
                      label: Text(tr('in_watchlist')),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () => _repo.toggleWatchlist(m.uuid),
                      icon: const Icon(Icons.bookmark_border_rounded),
                      label: Text(tr('add_watchlist')),
                    ),
            )
          else
            // Просмотрено — широкая «Отменить просмотр» рядом с сердечком.
            Expanded(child: _undoWatchButton(scheme, m)),
        ],
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: () => _manageListsSheet(m),
          icon: const Icon(Icons.playlist_add_rounded),
          label: Text(tr('manage_lists')),
        ),
      ),
      // «Брошено» — для незавершённых (не для уже просмотренных фильмов).
      if (m.status != LibraryStatus.watched) ...[
        const SizedBox(height: 12),
        _droppedButton(scheme, m),
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
      if (m.hasScoreComparison) ...[
        const SizedBox(height: 22),
        _comparison(scheme, m),
      ],
      if (m.viewings.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text(tr('per_viewing_scores'),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: scheme.primary)),
        const SizedBox(height: 8),
        ..._viewingRows(scheme, m),
      ],
      const SizedBox(height: 18),
      ..._reviewSection(scheme, m),
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
          itemBuilder: (c, i) => _partCard(scheme, parts[i], i + 1, m.tmdbId),
        ),
      ),
    ];
  }

  Widget _partCard(
      ColorScheme scheme, TmdbMovie part, int order, int? currentTmdbId) {
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
                    radius: 14),
                // Порядковый номер части.
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: Text('$order',
                        style: const TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: Colors.white)),
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
            Text(part.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    height: 1.1,
                    color: scheme.onSurface)),
            if (part.year != null)
              Text('${part.year}',
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  List<Widget> _detailsWidgets(ColorScheme scheme, LibraryMovie m) {
    final d = _details;
    final links = _links(m);
    if (d == null) return links.isEmpty ? [] : [const SizedBox(height: 16), ...links];
    final facts = <Widget>[
      if (d.director != null && d.director!.isNotEmpty)
        _personFact(scheme, Icons.movie_creation_rounded, tr('director'),
            d.director!, d.directorId),
      if (d.budget != null && d.budget! > 0)
        _fact(scheme, Icons.payments_rounded, tr('budget'), _money(d.budget!)),
      if (d.revenue != null && d.revenue! > 0)
        _fact(scheme, Icons.trending_up_rounded, tr('revenue'),
            _money(d.revenue!)),
    ];
    return [
      if (d.tagline != null) ...[
        const SizedBox(height: 18),
        Text('«${d.tagline!.replaceAll(RegExp(r'^[«»"\s]+|[«»"\s]+$'), '')}»',
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant)),
      ],
      if (d.overview != null && d.overview!.isNotEmpty) ...[
        const SizedBox(height: 18),
        _sectionTitle(scheme, tr('overview')),
        const SizedBox(height: 6),
        GestureDetector(
          onLongPress: () => _copy(d.overview!),
          child: Text(d.overview!,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  height: 1.45,
                  color: scheme.onSurface)),
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
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GenreScreen(
                          genreId: g.id, genreName: capitalize(g.name)))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Text(capitalize(g.name),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: scheme.onSecondaryContainer)),
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
            itemBuilder: (c, i) => GestureDetector(
              onTap: d.cast[i].id > 0
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PersonScreen(
                          personId: d.cast[i].id, personName: d.cast[i].name)))
                  : null,
              child: _castCard(scheme, d.cast[i]),
            ),
          ),
        ),
      ],
      if (facts.isNotEmpty) ...[
        const SizedBox(height: 16),
        ...facts,
      ],
      if (links.isNotEmpty) ...[
        const SizedBox(height: 16),
        ...links,
      ],
    ];
  }

  /// Ряд внешних ссылок (Кинопоиск / IMDb / TMDb).
  List<Widget> _links(LibraryMovie m) {
    final items = <Widget>[];
    void add(String label, Color color, String url) {
      items.add(Material(
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
                Text(label,
                    style: const TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white)),
                const SizedBox(width: 5),
                const Icon(Icons.open_in_new_rounded,
                    size: 14, color: Colors.white),
              ],
            ),
          ),
        ),
      ));
    }

    // Кинопоиск: если есть точный id — прямая ссылка на страницу фильма; иначе
    // (id не подтянулся: источник TMDB / латинское имя из импорта не совпало /
    // лимит API) — открываем поиск Кинопоиска по названию+году, чтобы ссылка
    // была ВСЕГДА, ведь сам фильм на КП обычно есть.
    if (m.kinopoiskId != null) {
      add('Кинопоиск', const Color(0xFFFF6600),
          'https://www.kinopoisk.ru/film/${m.kinopoiskId}/');
    } else {
      final q = [m.displayTitle, if (m.year != null) '${m.year}'].join(' ');
      add('Кинопоиск', const Color(0xFFFF6600),
          'https://www.kinopoisk.ru/index.php?kp_query=${Uri.encodeQueryComponent(q)}');
    }
    if (_details?.imdbId != null) {
      add('IMDb', const Color(0xFFD8A800),
          'https://www.imdb.com/title/${_details!.imdbId}/');
    }
    if (m.tmdbId != null) {
      add('TMDb', const Color(0xFF01B4E4),
          'https://www.themoviedb.org/movie/${m.tmdbId}');
    }
    if (items.isEmpty) return [];
    return [Wrap(spacing: 8, runSpacing: 8, children: items)];
  }

  Widget _sectionTitle(ColorScheme scheme, String title) => Text(title,
      style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: scheme.primary));

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

  Widget _fact(ColorScheme scheme, IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text('$label: ',
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    color: scheme.onSurfaceVariant)),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: scheme.onSurface)),
            ),
          ],
        ),
      );

  /// Факт-ссылка на персону (режиссёр): имя-ссылка ведёт в фильмографию.
  Widget _personFact(ColorScheme scheme, IconData icon, String label,
          String name, int? personId) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Text('$label: ',
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    color: scheme.onSurfaceVariant)),
            Expanded(
              child: GestureDetector(
                onTap: personId != null && personId > 0
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            PersonScreen(personId: personId, personName: name)))
                    : null,
                child: Text(name,
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
                            : scheme.onSurface)),
              ),
            ),
          ],
        ),
      );

  /// Копирует текст в буфер обмена (по удержанию названия/описания).
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

  // ---- список просмотров: тап по строке = правка (дата+оценка+удаление) ----
  List<Widget> _viewingRows(ColorScheme scheme, LibraryMovie m) {
    // Порядок добавления (первый просмотр — внизу, последний — сверху),
    // НЕЗАВИСИМО от даты: «Неизвестно» не прыгает при правке дат.
    final list = m.viewings;
    final rows = <Widget>[];
    for (var i = list.length - 1; i >= 0; i--) {
      final v = list[i];
      final isRewatch = i > 0; // первый добавленный просмотр — не повтор
      // Эффективная оценка просмотра (с учётом общей) — согласуется с верхней.
      final sc = m.scoreOf(v);
      rows.add(Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _editViewing(context, m, v, i + 1),
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
                            color: scheme.onSurface),
                      ),
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
                      Text(
                        sc != null ? sc.toStringAsFixed(1) : tr('not_rated'),
                        style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: sc != null
                              ? onScoreColor(sc)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
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

  // ------------------ блок сравнения оценок ------------------
  Widget _comparison(ColorScheme scheme, LibraryMovie m) {
    // Эволюция оценки — в порядке добавления просмотров (как и список ниже).
    final rated = m.viewings.where((v) => v.score != null).toList();
    final delta = rated.last.score! - rated.first.score!;
    final verdict = delta.abs() < 0.05
        ? tr('cmp_same')
        : (delta > 0
            ? trf('cmp_improved', {'d': delta.toStringAsFixed(1)})
            : trf('cmp_dropped', {'d': (-delta).toStringAsFixed(1)}));
    final verdictColor = delta.abs() < 0.05
        ? scheme.onSurfaceVariant
        : (delta > 0 ? const Color(0xFF2E9B57) : const Color(0xFFD0433B));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('score_comparison'),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: scheme.onSurface)),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < rated.length; i++) ...[
                  if (i > 0) _arrow(scheme, rated[i].score! - rated[i - 1].score!),
                  _scorePill(scheme, rated[i], i),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                  delta.abs() < 0.05
                      ? Icons.drag_handle_rounded
                      : (delta > 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded),
                  size: 18,
                  color: verdictColor),
              const SizedBox(width: 6),
              Text(verdict,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: verdictColor)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scorePill(ColorScheme scheme, Viewing v, int i) => Column(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: scoreColor(v.score!), shape: BoxShape.circle),
            child: Text(v.score!.toStringAsFixed(1),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: onScoreColor(v.score!))),
          ),
          const SizedBox(height: 4),
          Text(
            v.hasDate ? numericDate(v.date!) : tr('when_unknown'),
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 10.5,
                color: scheme.onSurfaceVariant),
          ),
        ],
      );

  Widget _arrow(ColorScheme scheme, double d) {
    final up = d > 0.05, down = d < -0.05;
    final c = up
        ? const Color(0xFF2E9B57)
        : (down ? const Color(0xFFD0433B) : scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.arrow_forward_rounded, size: 18, color: c),
          Text(d == 0 ? '' : '${d > 0 ? '+' : ''}${d.toStringAsFixed(1)}',
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  color: c)),
        ],
      ),
    );
  }

  // ---- полный редактор просмотра: дата + оценка + удаление ----
  void _editViewing(
      BuildContext context, LibraryMovie m, Viewing v, int ordinal) {
    DateTime? date = v.date;
    bool rated = m.scoreOf(v) != null;
    double val = m.scoreOf(v) ?? 1.0;
    final scheme = Theme.of(context).colorScheme;

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
                      borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ordinal > 1 ? trf('viewing_n', {'n': ordinal}) : tr('edit_viewing'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: scheme.onSurface),
                  ),
                ),
                const SizedBox(height: 12),
                // дата и время
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
                // оценка — тап по числу/«—» открывает калькулятор ввода
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
                        _repo.removeViewing(m.uuid, v);
                        Navigator.pop(sheetCtx);
                        _snack(tr('viewing_deleted'));
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
                          _repo.setViewingDate(m.uuid, v, date);
                          _repo.setViewingScore(m.uuid, v, rated ? val : null);
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

  // ------------------ управление списками ------------------
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
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
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
                      child: Text(tr('manage_lists'),
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: scheme.onSurface)),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (lists.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                            child: Text(tr('no_lists_yet'),
                                style: TextStyle(
                                    fontFamily: AppTheme.bodyFont,
                                    color: scheme.onSurfaceVariant)),
                          ),
                        for (final l in lists)
                          CheckboxListTile(
                            value: inLists.contains(l.name),
                            title: Text(l.name,
                                style: const TextStyle(
                                    fontFamily: AppTheme.bodyFont,
                                    fontWeight: FontWeight.w600)),
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
                            decoration: InputDecoration(hintText: tr('new_list')),
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
    final (icon, label) = switch (m.status) {
      LibraryStatus.watched => (Icons.check_circle_rounded, tr('act_watched')),
      LibraryStatus.watchlist => (Icons.bookmark_rounded, tr('in_watchlist')),
      LibraryStatus.dropped => (Icons.heart_broken_rounded, tr('dropped')),
      LibraryStatus.library => (Icons.movie_rounded, tr('app_name')),
    };
    return _chip(scheme, icon, label, primary: true);
  }

  Widget _chip(ColorScheme scheme, IconData icon, String label,
      {bool primary = false, bool tone = false}) {
    final bg = primary
        ? scheme.primaryContainer
        : (tone ? scheme.tertiaryContainer : scheme.surfaceContainerHighest);
    final fg = primary
        ? scheme.onPrimaryContainer
        : (tone ? scheme.onTertiaryContainer : scheme.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: fg)),
        ],
      ),
    );
  }

  /// Открывает клавиатуру-калькулятор для ручного ввода оценки текущего фильма.
  Future<void> _openScorePad(LibraryMovie m) async {
    final v = await showScorePad(context, initial: m.currentScore);
    if (v != null) {
      _commitCurrentScore(m, v);
      if (mounted) setState(() => _dragging = null);
    }
  }

  /// Пишет оценку в текущий просмотр (или в общую, если просмотров ещё нет).
  void _commitCurrentScore(LibraryMovie m, double v) {
    final cv = m.currentViewing;
    if (cv != null) {
      _repo.setViewingScore(m.uuid, cv, v);
    } else {
      _repo.setScore(m.uuid, v);
    }
  }

  /// Убирает оценку текущего просмотра И общую: scoreOf() падает обратно на
  /// общий m.score (импорт TV Time), иначе кнопка выглядит сломанной.
  void _clearCurrentScore(LibraryMovie m) {
    final cv = m.currentViewing;
    if (cv != null) _repo.setViewingScore(m.uuid, cv, null);
    _repo.setScore(m.uuid, null);
    setState(() => _dragging = null);
  }

  Widget _scoreCard(ColorScheme scheme, LibraryMovie m) {
    // Оценка доступна только просмотренным фильмам.
    final canRate =
        m.currentViewing != null || m.status == LibraryStatus.watched;
    if (!canRate) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Icon(Icons.star_border_rounded,
                size: 34, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(tr('rate_after_watch'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    // Пока не оценено — слайдер стоит на нейтральной середине, но число
    // показываем как «—», а не как балл 7.0 (иначе выглядит будто оценка есть).
    final rated = _dragging != null || m.currentScore != null;
    final val = _dragging ?? m.currentScore ?? 1.0;
    final accent = scoreColor(val);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(tr('current_viewing_score'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
          const SizedBox(height: 2),
          // Тап по числу/«—» → калькулятор ручного ввода оценки.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openScorePad(m),
            child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // Плавно перетекающий цвет числа/звезды при изменении балла.
              TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                tween: ColorTween(
                    end: rated
                        ? accent
                        : scheme.onPrimaryContainer.withValues(alpha: 0.55)),
                builder: (context, color, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Icon(rated ? Icons.star_rounded : Icons.star_border_rounded,
                        color: color, size: 32),
                    const SizedBox(width: 6),
                    Text(
                      rated ? val.toStringAsFixed(1) : '—',
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 48,
                        height: 1,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              Text(' / 10',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
              const SizedBox(width: 8),
              Icon(Icons.dialpad_rounded,
                  size: 18,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.55)),
            ],
          ),
          ),
          const SizedBox(height: 6),
          RatingSlider(
            value: val,
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) {
              _commitCurrentScore(m, v);
              setState(() => _dragging = null);
            },
          ),
          const SizedBox(height: 4),
          Text(
            rated ? tr('your_rating') : tr('no_rating_yet'),
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  /// Широкая мягко-красная M3-кнопка «Убрать оценку» (как просил пользователь —
  /// одного размера с «Отметить просмотр», не мелкой ссылкой).
  Widget _clearScoreButton(ColorScheme scheme, LibraryMovie m) {
    // Мягкий красный: приглушённый, не кричащий (в тон палитре оценок).
    const soft = kDroppedColor;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: () => _clearCurrentScore(m),
        icon: const Icon(Icons.star_outline_rounded),
        label: Text(tr('remove_score')),
        style: FilledButton.styleFrom(
          backgroundColor: soft.withValues(alpha: 0.16),
          foregroundColor: soft,
        ),
      ),
    );
  }

  /// Кнопка «Отменить просмотр» — для уже просмотренного фильма (в Expanded).
  Widget _undoWatchButton(ColorScheme scheme, LibraryMovie m) {
    return FilledButton.tonalIcon(
      onPressed: () async {
        final removed = await _repo.undoLastViewing(m.uuid);
        _snack(tr(removed ? 'unwatched' : 'watch_undone'));
      },
      icon: const Icon(Icons.remove_done_rounded),
      label: Text(tr('undo_watch')),
      style: FilledButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurfaceVariant,
      ),
    );
  }

  /// Широкая кнопка «Брошено» (мягкий красный). Активна, когда фильм брошен.
  Widget _droppedButton(ColorScheme scheme, LibraryMovie m) {
    const soft = kDroppedColor;
    final active = m.status == LibraryStatus.dropped;
    return SizedBox(
      width: double.infinity,
      child: active
          ? FilledButton.icon(
              onPressed: () => _repo.toggleDropped(m.uuid),
              icon: const Icon(Icons.heart_broken_rounded),
              label: Text(tr('in_dropped')),
              style: FilledButton.styleFrom(
                  backgroundColor: soft, foregroundColor: Colors.white),
            )
          : FilledButton.tonalIcon(
              onPressed: () => _repo.toggleDropped(m.uuid),
              icon: const Icon(Icons.heart_broken_outlined),
              label: Text(tr('mark_dropped')),
              style: FilledButton.styleFrom(
                  backgroundColor: soft.withValues(alpha: 0.16),
                  foregroundColor: soft),
            ),
    );
  }

  /// Секция «Моя рецензия»: текст (тап → правка) или кнопка «Написать рецензию».
  List<Widget> _reviewSection(ColorScheme scheme, LibraryMovie m) {
    final has = m.review != null && m.review!.trim().isNotEmpty;
    return [
      Row(
        children: [
          _sectionTitle(scheme, tr('my_review')),
          const Spacer(),
          if (has)
            TextButton.icon(
              onPressed: () => _editReview(m),
              icon: const Icon(Icons.edit_rounded, size: 17),
              label: Text(tr('edit')),
            ),
        ],
      ),
      const SizedBox(height: 6),
      if (has)
        GestureDetector(
          onTap: () => _editReview(m),
          onLongPress: () => _copy(m.review!),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(m.review!,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    height: 1.45,
                    color: scheme.onSurface)),
          ),
        )
      else
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () => _editReview(m),
            icon: const Icon(Icons.rate_review_rounded),
            label: Text(tr('write_review')),
          ),
        ),
    ];
  }

  /// Редактор рецензии — нижний лист с многострочным полем.
  void _editReview(LibraryMovie m) {
    final ctl = TextEditingController(text: m.review ?? '');
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
                if (m.review != null && m.review!.trim().isNotEmpty)
                  TextButton(
                    onPressed: () {
                      _repo.setReview(m.uuid, null);
                      Navigator.pop(sheetCtx);
                    },
                    child: Text(tr('delete')),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    _repo.setReview(m.uuid, ctl.text);
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
}

/// Идеально круглая кнопка-сердечко (Избранное) — без надписи.
class _HeartButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _HeartButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.primary : scheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(
            active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: active ? scheme.onPrimary : scheme.onSurfaceVariant,
            size: 26,
          ),
        ),
      ),
    );
  }
}
