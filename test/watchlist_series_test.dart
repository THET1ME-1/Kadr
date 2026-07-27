import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/movie_repository.dart';

/// «Буду смотреть» для сериалов: список ведёт флаг [LibrarySeries.watchlist],
/// поставленный пользователем. Начатый сериал из списка не выпадает — иначе
/// отметка на экране сериала горит, а во вкладке пусто.
void main() {
  MovieRepository repoWith(List<LibrarySeries> series) =>
      MovieRepository.detached({
        'movies': const [],
        'series': [for (final s in series) s.toJson()],
      });

  test('сериал без просмотренных серий попадает в «Буду смотреть»', () {
    final repo = repoWith([
      LibrarySeries(tvShowId: 's1', title: 'Новый сериал', watchlist: true),
    ]);
    expect(repo.watchlistSeries.map((s) => s.tvShowId), ['s1']);
  });

  test('начатый сериал остаётся в «Буду смотреть»', () {
    final repo = repoWith([
      LibrarySeries(
        tvShowId: 's2',
        title: 'Начатый сериал',
        watchlist: true,
        episodes: [Episode(season: 1, number: 1, watchedAt: DateTime(2026, 5, 1))],
      ),
    ]);
    expect(repo.watchlistSeries.map((s) => s.tvShowId), ['s2']);
  });

  test('брошенный сериал в списке не показывается', () {
    final repo = repoWith([
      LibrarySeries(
          tvShowId: 's3', title: 'Брошенный', watchlist: true, dropped: true),
    ]);
    expect(repo.watchlistSeries, isEmpty);
  });

  test('сериал без отметки в списке не показывается', () {
    final repo = repoWith([
      LibrarySeries(tvShowId: 's4', title: 'Просто в базе'),
    ]);
    expect(repo.watchlistSeries, isEmpty);
  });
}
