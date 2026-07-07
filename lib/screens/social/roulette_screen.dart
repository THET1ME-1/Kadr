import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/movie_repository.dart';
import '../../services/social/social_controller.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/poster.dart';
import '../movie_sheet.dart';

/// Кандидат рулетки: постер + название + (для открытия) фильм библиотеки либо
/// tmdbId (для рекомендаций друзей).
class _Cand {
  final String title;
  final String? poster;
  final int? year;
  final LibraryMovie? movie;
  final int? tmdbId;
  _Cand(this.title, this.poster, this.year, {this.movie, this.tmdbId});
}

enum _Source { watchlist, friends }

/// Кинорулетка: случайный фильм из твоего вишлиста или из советов друзей.
/// Барабан быстро прокручивает постеры и останавливается на выбранном.
class RouletteScreen extends StatefulWidget {
  const RouletteScreen({super.key});

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
  _Cand? _shown; // текущий кадр (во время кручения) / итог
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _watchlist = [
      for (final m in MovieRepository.instance.watchlist)
        _Cand(m.displayTitle, m.posterUrl, m.year, movie: m),
    ];
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
        '${(m.ruTitle ?? m.title).toLowerCase().trim()}|${m.year ?? 0}'
    };
    final byKey = <String, _Cand>{};
    for (final lib in libs) {
      for (final m in lib.repo.watched) {
        final sc = m.currentScore;
        final k = '${m.displayTitle.toLowerCase().trim()}|${m.year ?? 0}';
        if (sc != null && sc >= 8 && !mineWatched.contains(k)) {
          byKey.putIfAbsent(
              k, () => _Cand(m.displayTitle, m.posterUrl, m.year, tmdbId: m.tmdbId));
        }
      }
    }
    if (mounted) {
      setState(() {
        _friendCands = byKey.values.toList();
        _loadingFriends = false;
      });
    }
  }

  void _spin() {
    final pool = _pool;
    if (pool.isEmpty || _spinning) return;
    setState(() {
      _spinning = true;
      _settled = false;
    });
    final finalPick = pool[_rnd.nextInt(pool.length)];
    var ticks = 0;
    // Кол-во кадров зависит от размера пула (но не слишком много).
    final total = 16 + _rnd.nextInt(8);
    void schedule(int delay) {
      _spinTimer = Timer(Duration(milliseconds: delay), () {
        if (!mounted) return;
        ticks++;
        if (ticks >= total) {
          setState(() {
            _shown = finalPick;
            _spinning = false;
            _settled = true;
          });
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
    } else if (c.tmdbId != null) {
      // Совет друга — открываем полную карточку через TMDB.
      final t = TmdbMovie(
          id: c.tmdbId!, title: c.title, posterUrl: c.poster, year: c.year);
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
            child: Center(
              child: _loadingFriends
                  ? const CircularProgressIndicator()
                  : pool.isEmpty
                      ? _emptyPool(scheme)
                      : _reel(scheme),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (pool.isEmpty || _spinning) ? null : _spin,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                icon: Icon(_spinning
                    ? Icons.hourglass_top_rounded
                    : Icons.casino_rounded),
                label: Text(_spinning ? tr('roulette_spinning') : tr('roulette_spin'),
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
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
          onTap: () {
            setState(() {
              _source = s;
              _settled = false;
              _shown = null;
            });
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
            child: Text(label,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: sel
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20)),
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
            Icon(Icons.casino_outlined,
                size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
                _source == _Source.watchlist
                    ? tr('roulette_empty_watchlist')
                    : tr('roulette_empty_friends'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      );

  Widget _reel(ColorScheme scheme) {
    final c = _shown ?? _pool.first;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: _settled ? 1.0 : 0.94,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: Poster(title: c.title, url: c.poster, width: 190, radius: 20),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(c.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  height: 1.15,
                  color: scheme.onSurface)),
        ),
        if (c.year != null) ...[
          const SizedBox(height: 4),
          Text('${c.year}',
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 13,
                  color: scheme.onSurfaceVariant)),
        ],
        if (_settled) ...[
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
