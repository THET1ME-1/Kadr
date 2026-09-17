import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/movie_repository.dart';
import '../../services/social/social_controller.dart';
import '../../services/store.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/poster.dart';
import '../../utils/roulette.dart';
import '../movie_sheet.dart';
import '../series_screen.dart';

/// Кандидат рулетки: постер + название + (для открытия) запись библиотеки либо
/// tmdbId (для рекомендаций друзей).
class _Cand {
  final String title;
  final String? poster;
  final int? year;
  final LibraryMovie? movie;
  final LibrarySeries? series;
  final int? tmdbId;
  _Cand(
    this.title,
    this.poster,
    this.year, {
    this.movie,
    this.series,
    this.tmdbId,
  });

  /// Стабильный ключ, по которому выпавший фильм узнаётся при следующем входе.
  String get key {
    if (movie != null) return 'm:${movie!.uuid}';
    if (series != null) return 's:${series!.tvShowId}';
    if (tmdbId != null) return 't:$tmdbId';
    return 'k:${title.toLowerCase().trim()}|${year ?? 0}';
  }
}

/// Запись, переданная извне: уже отобранный список «Буду смотреть» с экрана
/// библиотеки — с его фильтром, поиском и сегментом «Фильмы/Сериалы».
class RoulettePick {
  final LibraryMovie? movie;
  final LibrarySeries? series;
  const RoulettePick.movie(LibraryMovie this.movie) : series = null;
  const RoulettePick.series(LibrarySeries this.series) : movie = null;
}

enum _Source { watchlist, friends }

/// Кинорулетка: случайный фильм из твоего вишлиста или из советов друзей.
/// Барабан быстро прокручивает постеры и останавливается на выбранном.
class RouletteScreen extends StatefulWidget {
  /// Откуда брать «Мой вишлист». null — вся библиотека; список — то, что человек
  /// видел на вкладке (фильтр и поиск уже применены).
  final List<RoulettePick>? pool;
  const RouletteScreen({super.key, this.pool});

  @override
  State<RouletteScreen> createState() => _RouletteScreenState();
}

class _RouletteScreenState extends State<RouletteScreen> {
  _Source _source = _Source.watchlist;
  final _rnd = Random();

  List<_Cand> _watchlist = const [];
  List<_Cand>? _friendCands; // ленивая загрузка
  bool _loadingFriends = false;

  Timer? _spinTimer;
  bool _spinning = false;
  _Cand? _shown; // кадр, мелькающий во время кручения

  /// Что выпало, у каждого источника своё. Переключение источника итог не
  /// стирает, а последний итог лежит в [Store] и ждёт следующего входа.
  final Map<_Source, _Cand> _picked = {};

  static String _storeKey(_Source s) => 'roulettePick.${s.name}';

  _Cand? get _result => _picked[_source];

  @override
  void initState() {
    super.initState();
    final outer = widget.pool;
    _watchlist = outer != null
        ? [
            for (final p in outer)
              if (p.movie != null)
                _Cand(
                  p.movie!.displayTitle,
                  p.movie!.displayPoster,
                  p.movie!.year,
                  movie: p.movie,
                )
              else
                _Cand(
                  p.series!.displayTitle,
                  p.series!.displayPoster,
                  p.series!.year,
                  series: p.series,
                ),
          ]
        : [
            for (final m in MovieRepository.instance.watchlist)
              // displayPoster, а не posterUrl: свой постер должен побеждать.
              _Cand(m.displayTitle, m.displayPoster, m.year, movie: m),
          ];
    _restorePick(_Source.watchlist, _watchlist);
  }

  /// Возвращает прошлый итог, если фильм всё ещё в этом списке.
  Future<void> _restorePick(_Source source, List<_Cand> pool) async {
    final key = await Store.instance.getString(_storeKey(source));
    if (key == null || !mounted || _picked[source] != null) return;
    for (final c in pool) {
      if (c.key == key) {
        setState(() => _picked[source] = c);
        return;
      }
    }
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    super.dispose();
  }

  List<_Cand> get _pool =>
      _source == _Source.watchlist ? _watchlist : (_friendCands ?? const []);

  Future<void> _ensureFriends() async {
    if (_friendCands != null || _loadingFriends) return;
    setState(() => _loadingFriends = true);
    final libs = await SocialController.instance.allFriendLibraries();
    final mineWatched = {
      for (final m in MovieRepository.instance.watched)
        '${(m.ruTitle ?? m.title).toLowerCase().trim()}|${m.year ?? 0}',
    };
    final byKey = <String, _Cand>{};
    for (final lib in libs) {
      for (final m in lib.repo.watched) {
        final sc = m.currentScore;
        final k = '${m.displayTitle.toLowerCase().trim()}|${m.year ?? 0}';
        if (sc != null && sc >= 8 && !mineWatched.contains(k)) {
          byKey.putIfAbsent(
            k,
            () => _Cand(m.displayTitle, m.posterUrl, m.year, tmdbId: m.tmdbId),
          );
        }
      }
    }
    if (mounted) {
      setState(() {
        _friendCands = byKey.values.toList();
        _loadingFriends = false;
      });
      _restorePick(_Source.friends, _friendCands!);
    }
  }

  void _spin() {
    final pool = _pool;
    final source = _source;
    if (pool.isEmpty || _spinning) return;
    setState(() => _spinning = true);
    // avoid: крутить дважды и получить то же самое — выглядит как поломка.
    final finalPick = pickRandom(pool, avoid: _picked[source], rng: _rnd)!;
    var ticks = 0;
    // Кол-во кадров зависит от размера пула (но не слишком много).
    final total = 16 + _rnd.nextInt(8);
    void schedule(int delay) {
      _spinTimer = Timer(Duration(milliseconds: delay), () {
        if (!mounted) return;
        ticks++;
        if (ticks >= total) {
          setState(() {
            _shown = null;
            _picked[source] = finalPick;
            _spinning = false;
          });
          Store.instance.setString(_storeKey(source), finalPick.key);
          return;
        }
        setState(() => _shown = pool[_rnd.nextInt(pool.length)]);
        // Замедление к концу (ease-out).
        final progress = ticks / total;
        schedule((60 + progress * progress * 260).round());
      });
    }

    schedule(60);
  }

  void _open(_Cand c) {
    if (c.movie != null) {
      showMovieSheet(context, c.movie!);
    } else if (c.series != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SeriesScreen(series: c.series!)),
      );
    } else if (c.tmdbId != null) {
      // Совет друга — открываем полную карточку через TMDB.
      final t = TmdbMovie(
        id: c.tmdbId!,
        title: c.title,
        posterUrl: c.poster,
        year: c.year,
      );
      showMovieSheet(context, MovieRepository.instance.ensureFromTmdb(t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pool = _pool;
    return Scaffold(
      appBar: AppBar(title: Text(tr('roulette_title'))),
      body: Column(
        children: [
          const SizedBox(height: 12),
          _sourceToggle(scheme),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Center(
                child: _loadingFriends
                    ? const CircularProgressIndicator()
                    : pool.isEmpty
                    ? _emptyPool(scheme)
                    : _reel(scheme, box.maxHeight),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (pool.isEmpty || _spinning) ? null : _spin,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: Icon(
                  _spinning
                      ? Icons.hourglass_top_rounded
                      : Icons.casino_rounded,
                ),
                label: Text(
                  _spinning ? tr('roulette_spinning') : tr('roulette_spin'),
                  style: const TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceToggle(ColorScheme scheme) {
    Widget seg(_Source s, String label) {
      final sel = _source == s;
      return Expanded(
        child: GestureDetector(
          // Пока барабан крутится, источник не меняем: итог уже выбран из
          // текущего списка.
          onTap: _spinning
              ? null
              : () {
                  setState(() => _source = s);
                  if (s == _Source.friends) _ensureFriends();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel ? scheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: sel
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          seg(_Source.watchlist, tr('roulette_src_watchlist')),
          seg(_Source.friends, tr('roulette_src_friends')),
        ],
      ),
    );
  }

  Widget _emptyPool(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.casino_outlined, size: 56, color: scheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Text(
          _source == _Source.watchlist
              ? tr('roulette_empty_watchlist')
              : tr('roulette_empty_friends'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  /// Высота под названием, годом и кнопкой «Открыть».
  static const double _reelTextHeight = 170;

  /// [height] — место под барабан. На телефоне постер 190 dp в ширину, на
  /// низком экране (телевизор, горизонталь) он ужимается, чтобы итог
  /// с кнопкой поместился целиком.
  Widget _reel(ColorScheme scheme, double height) {
    final posterWidth = ((height - _reelTextHeight) * 2 / 3).clamp(80.0, 190.0);
    final result = _spinning ? null : _result;
    // До первого вращения виден первый фильм списка, но без «Открыть»: это
    // заставка, а не итог.
    final c = (_spinning ? _shown : result) ?? _pool.first;
    final settled = result != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: settled ? 1.0 : 0.94,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: Poster(
            title: c.title,
            url: c.poster,
            width: posterWidth,
            radius: 20,
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            c.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              height: 1.15,
              color: scheme.onSurface,
            ),
          ),
        ),
        if (c.year != null) ...[
          const SizedBox(height: 4),
          Text(
            '${c.year}',
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (settled) ...[
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => _open(c),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(tr('roulette_open')),
          ),
        ],
      ],
    );
  }
}
