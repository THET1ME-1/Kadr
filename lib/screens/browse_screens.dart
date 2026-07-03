import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
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
  const PersonScreen(
      {super.key, required this.personId, required this.personName});

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  List<TmdbMovie>? _movies;
  bool _error = false;

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
    final list = await TmdbService.personMovieCredits(widget.personId);
    if (!mounted) return;
    setState(() {
      _movies = list;
      _error = list.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.personName)),
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
          builder: (context, _) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
            itemCount: _movies!.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  child: Text(
                    trf('movies_count', {'n': _movies!.length}),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13,
                        color: scheme.onSurfaceVariant),
                  ),
                );
              }
              return TmdbMovieRow(movie: _movies![i - 1]);
            },
          ),
        );
      }),
    );
  }
}
