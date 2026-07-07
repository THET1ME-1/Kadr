import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/movie_repository.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/movie_cards.dart';

/// «Похоже на твой вкус»: рекомендации TMDB, построенные из фильмов, которые ты
/// оценил высоко. Фильмы, что уже смотрел, отсеиваются; чаще советуемые — выше.
class ForYouScreen extends StatefulWidget {
  const ForYouScreen({super.key});

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  List<TmdbMovie> _results = const [];
  bool _loading = true;
  bool _noSeeds = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _key(String title, int? year) =>
      '${title.toLowerCase().trim()}|${year ?? 0}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _noSeeds = false;
    });
    final repo = MovieRepository.instance;

    // Семена: высоко оценённые просмотренные фильмы с tmdbId.
    final seeds = repo.watched
        .where((m) => m.tmdbId != null && (m.currentScore ?? 0) >= 7)
        .toList()
      ..sort((a, b) => (b.currentScore ?? 0).compareTo(a.currentScore ?? 0));
    final topSeeds = seeds.take(10).toList();
    if (topSeeds.isEmpty) {
      setState(() {
        _loading = false;
        _noSeeds = true;
      });
      return;
    }

    // Что я уже смотрел — не советовать.
    final watchedKeys = {
      for (final m in repo.watched) _key(m.ruTitle ?? m.title, m.year)
    };

    // Параллельно тянем рекомендации по каждому семени, копим частоту.
    final lists = await Future.wait(
        topSeeds.map((m) => TmdbService.recommendations(m.tmdbId!)));

    final count = <String, int>{};
    final byKey = <String, TmdbMovie>{};
    for (final list in lists) {
      for (final rec in list) {
        final k = _key(rec.title, rec.year);
        if (watchedKeys.contains(k)) continue;
        count[k] = (count[k] ?? 0) + 1;
        byKey.putIfAbsent(k, () => rec);
      }
    }

    final ranked = byKey.keys.toList()
      ..sort((a, b) {
        final c = (count[b] ?? 0).compareTo(count[a] ?? 0);
        if (c != 0) return c;
        return (byKey[b]!.rating ?? 0).compareTo(byKey[a]!.rating ?? 0);
      });

    if (!mounted) return;
    setState(() {
      _results = [for (final k in ranked) byKey[k]!];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('for_you_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _noSeeds
              ? _empty(tr('for_you_no_seeds'))
              : _results.isEmpty
                  ? _empty(tr('for_you_empty'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                            sliver: SliverToBoxAdapter(
                              child: Text(tr('for_you_sub'),
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 13,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 130,
                                mainAxisExtent: 250,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, i) => DiscoverMovieCard(
                                    movie: _results[i], width: 120),
                                childCount: _results.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: AppTheme.bodyFont)),
            ],
          ),
        ),
      );
}
