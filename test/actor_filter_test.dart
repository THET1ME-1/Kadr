import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/utils/actor_filter.dart';

/// Фильтр библиотеки по актёру. Работает не по кэшу каста, а по фильмографии
/// TMDB: совпадение ищется по `tmdbId`, поэтому запись без него не проходит.
void main() {
  const filter = ActorFilter(
    personId: 9,
    name: 'Киллиан Мёрфи',
    movieIds: {1, 2},
    seriesIds: {7},
  );

  test('фильм из фильмографии проходит', () {
    expect(filter.matchesMovie(2), isTrue);
  });

  test('чужой фильм не проходит', () {
    expect(filter.matchesMovie(3), isFalse);
  });

  test('фильм без tmdbId не проходит — сопоставлять нечем', () {
    expect(filter.matchesMovie(null), isFalse);
  });

  test('сериал сверяется со своим списком, а не с фильмами', () {
    expect(filter.matchesSeries(7), isTrue);
    expect(filter.matchesSeries(1), isFalse);
  });

  test('актёр без единой роли в базе TMDB считается пустым фильтром', () {
    const empty = ActorFilter(personId: 1, name: 'Никто');
    expect(empty.isEmpty, isTrue);
    expect(filter.isEmpty, isFalse);
  });
}
