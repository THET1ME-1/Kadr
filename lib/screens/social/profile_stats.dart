import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/movie_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Компактная «важная» статистика профиля (своего или друга) — самое интересное
/// из экрана «Статистика»: часы просмотра, ключевые плитки и топ жанров. Считает
/// из переданного [repo] (для друга — его read-only MovieRepository.detached).
class ProfileStats extends StatelessWidget {
  final MovieRepository repo;

  /// Тап по hero-блоку «У экрана» (в своём профиле — открыть полную статистику).
  final VoidCallback? onHeroTap;
  const ProfileStats({super.key, required this.repo, this.onHeroTap});

  @override
  Widget build(BuildContext context) {
    final s = _Compact.of(repo);
    final scheme = Theme.of(context).colorScheme;
    if (!s.hasData) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(tr('stat_empty'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  color: scheme.onSurfaceVariant)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        onHeroTap != null
            ? GestureDetector(
                onTap: onHeroTap,
                behavior: HitTestBehavior.opaque,
                child: _hero(context, s, tappable: true))
            : _hero(context, s),
        const SizedBox(height: 12),
        _tiles(context, s),
        if (s.genres.isNotEmpty) ...[
          const SizedBox(height: 12),
          _genres(context, s),
        ],
      ],
    );
  }

  Widget _hero(BuildContext context, _Compact s, {bool tappable = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tr('stat_screen_time'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      letterSpacing: 2,
                      color: Colors.white.withValues(alpha: 0.85))),
              if (tappable) ...[
                const Spacer(),
                Icon(Icons.arrow_forward_rounded,
                    size: 18, color: Colors.white.withValues(alpha: 0.85)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${s.hours}',
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 48,
                        height: 1,
                        color: Colors.white)),
                const SizedBox(width: 8),
                Text(tr('stat_hours_unit'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
              trf('stat_summary_sub', {
                'f': '${s.watchedMovies}',
                's': '${s.seriesCount}',
                'e': '${s.episodes}'
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _tiles(BuildContext context, _Compact s) {
    final tiles = <(IconData, String, String)>[
      (Icons.movie_rounded, '${s.watchedMovies}', tr('stat_movies')),
      (Icons.live_tv_rounded, '${s.seriesCount}', tr('stat_series')),
      (
        Icons.star_rounded,
        s.avgScore == 0 ? '—' : s.avgScore.toStringAsFixed(1),
        tr('stat_avg')
      ),
      (Icons.favorite_rounded, '${s.favorites}', tr('stat_favorites')),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _tile(context, tiles[i], i)),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, (IconData, String, String) t, int i) {
    final scheme = Theme.of(context).colorScheme;
    final bg = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ][i % 3];
    final fg = [
      scheme.onPrimaryContainer,
      scheme.onSecondaryContainer,
      scheme.onTertiaryContainer,
    ][i % 3];
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(t.$1, color: fg, size: 20),
          const SizedBox(height: 8),
          SizedBox(
            height: 28,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(t.$2,
                  maxLines: 1,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      height: 1,
                      color: fg)),
            ),
          ),
          const SizedBox(height: 2),
          Text(t.$3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 11,
                  color: fg.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _genres(BuildContext context, _Compact s) {
    final scheme = Theme.of(context).colorScheme;
    final top = s.genres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final shown = top.take(6).toList();
    final maxV = shown.first.value;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('stat_genres'),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: scheme.onSurface)),
          const SizedBox(height: 12),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(capitalize(shown[i].key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                          color: scheme.onSurface)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 18,
                      color: scheme.surfaceContainerHighest,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (shown[i].value / maxV).clamp(0.04, 1.0),
                        child: DecoratedBox(
                            decoration: BoxDecoration(color: scheme.primary)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${shown[i].value}',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: scheme.primary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Компактный срез метрик (без графиков) — быстро считается из репозитория.
class _Compact {
  final int watchedMovies;
  final int seriesCount;
  final int episodes;
  final int hours;
  final double avgScore;
  final int favorites;
  final Map<String, int> genres;

  _Compact({
    required this.watchedMovies,
    required this.seriesCount,
    required this.episodes,
    required this.hours,
    required this.avgScore,
    required this.favorites,
    required this.genres,
  });

  bool get hasData => watchedMovies > 0 || episodes > 0 || seriesCount > 0;

  static _Compact of(MovieRepository repo) {
    final watched = repo.watched;
    var minutes = 0, scoreN = 0;
    var scoreSum = 0.0;
    final genres = <String, int>{};
    for (final m in watched) {
      final rt = m.runtimeMin;
      final sane = (rt != null && rt > 0 && rt <= 600) ? rt : 0;
      final vc = m.viewings.isEmpty ? 1 : m.viewings.length;
      minutes += sane * vc;
      final sc = m.currentScore;
      if (sc != null) {
        scoreSum += sc;
        scoreN++;
      }
      for (final g in m.genres) {
        genres[g] = (genres[g] ?? 0) + 1;
      }
    }
    var episodes = 0;
    for (final s in repo.series) {
      for (final e in s.episodes) {
        episodes++;
        final ert = e.runtimeMin;
        if (ert != null && ert > 0 && ert <= 600) {
          minutes += ert * e.watchCount.clamp(1, 100);
        }
      }
    }
    return _Compact(
      watchedMovies: watched.length,
      seriesCount: repo.seriesCount,
      episodes: episodes,
      hours: minutes ~/ 60,
      avgScore: scoreN == 0 ? 0 : scoreSum / scoreN,
      favorites: repo.favorites.length + repo.favoriteSeries.length,
      genres: genres,
    );
  }
}
