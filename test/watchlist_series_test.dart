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

  test('сериал в списке получает дату добавления — иначе тонет в сортировке',
      () async {
    final repo = repoWith([LibrarySeries(tvShowId: 's5', title: 'Свежий')]);
    await repo.toggleSeriesWatchlist('s5');
    expect(repo.seriesById('s5')!.addedAt, isNotNull);
  });

  test('старый сериал из списка получает дату при загрузке базы', () {
    // Импорт TV Time и версии до 0.20 дату не писали: без неё сортировка
    // «новые сверху» уводила сериал под все фильмы списка.
    final repo = repoWith([
      LibrarySeries(tvShowId: 's7', title: 'Из импорта', watchlist: true),
      LibrarySeries(tvShowId: 's8', title: 'Не в списке'),
    ]);
    expect(repo.seriesById('s7')!.addedAt, isNotNull);
    expect(repo.seriesById('s8')!.addedAt, isNull);
  });

  test('дата добавления переживает сохранение и чтение', () {
    final s = LibrarySeries(
        tvShowId: 's6', title: 'С датой', addedAt: DateTime(2026, 8, 5));
    expect(LibrarySeries.fromJson(s.toJson()).addedAt, DateTime(2026, 8, 5));
  });
}
