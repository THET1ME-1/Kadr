import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/movie_repository.dart';

/// Проверяет публичную проекцию соц-слоя: что уезжает друзьям и что режется,
/// а также что read-only detached-репозиторий корректно отдаёт ленты.
void main() {
  Map<String, dynamic> sample() {
    final watched = LibraryMovie(
      uuid: 'm1',
      title: 'Watched One',
      status: LibraryStatus.watched,
      score: 8.0,
      review: 'моя личная рецензия',
      genres: ['драма'],
      viewings: [Viewing(date: DateTime(2024, 1, 1), score: 8.0)],
    );
    final wish = LibraryMovie(
      uuid: 'm2',
      title: 'Wishlist One',
      status: LibraryStatus.watchlist,
      review: 'секрет',
    );
    final plain = LibraryMovie(
      uuid: 'm3',
      title: 'Just In Library',
      status: LibraryStatus.library, // без активности — НЕ должен уехать
    );
    final series = LibrarySeries(
      tvShowId: 's1',
      title: 'Some Show',
      review: 'приватно',
      episodes: [Episode(season: 1, number: 1, watchedAt: DateTime(2024, 2, 2))],
    );
    return {
      'movies': [watched.toJson(), wish.toJson(), plain.toJson()],
      'series': [series.toJson()],
    };
  }

  test('detached-репозиторий не пишет на диск и отдаёт ленты', () {
    final repo = MovieRepository.detached(sample());
    expect(repo.isDetached, isTrue);
    expect(repo.watched.length, 1);
    expect(repo.watched.first.uuid, 'm1');
    expect(repo.watchlist.length, 1);
    expect(repo.watchlist.first.uuid, 'm2');
    expect(repo.series.length, 1);
  });

  test('buildPublicProfile режет приватное и лишнее', () {
    final repo = MovieRepository.detached(sample());
    final pub = repo.buildPublicProfile();
    final movies = (pub['movies'] as List).cast<Map<String, dynamic>>();
    final series = (pub['series'] as List).cast<Map<String, dynamic>>();

    // Фильм «просто в библиотеке» (без просмотра/желания/избранного) не уезжает.
    expect(movies.map((m) => m['uuid']), containsAll(['m1', 'm2']));
    expect(movies.map((m) => m['uuid']), isNot(contains('m3')));

    // Рецензии вырезаны и у фильмов, и у сериалов.
    for (final m in movies) {
      expect(m.containsKey('review') && m['review'] != null, isFalse);
    }
    for (final s in series) {
      expect(s.containsKey('review') && s['review'] != null, isFalse);
    }

    // Оценки/просмотры/жанры при этом сохранены (нужны для ленты и статистики).
    final m1 = movies.firstWhere((m) => m['uuid'] == 'm1');
    expect(m1['score'], 8.0);
    expect((m1['viewings'] as List), isNotEmpty);
    expect((m1['genres'] as List), contains('драма'));
  });

  test('проекция переживает круг: build → detached → те же ленты', () {
    final origin = MovieRepository.detached(sample());
    final projection = origin.buildPublicProfile();
    final friend = MovieRepository.detached(projection);
    expect(friend.watched.length, 1);
    expect(friend.watchlist.length, 1);
    expect(friend.series.first.episodes.length, 1);
  });

  test('hideRatings вырезает оценки, записи остаются', () {
    final repo = MovieRepository.detached(sample());
    final pub = repo.buildPublicProfile(hideRatings: true);
    final friend = MovieRepository.detached(pub);
    expect(friend.watched.length, 1); // фильм на месте
    expect(friend.watched.first.currentScore, isNull); // оценки нет
    // Дата просмотра сохранена (скрывали только оценки).
    expect(friend.watched.first.viewings.first.date, isNotNull);
  });

  test('hideDates огрубляет даты до начала месяца (лента не пустеет)', () {
    final repo = MovieRepository.detached(sample());
    final pub = repo.buildPublicProfile(hideDates: true);
    final friend = MovieRepository.detached(pub);
    final d = friend.watched.first.viewings.first.date;
    expect(d, isNotNull); // дата есть → попадёт в ленту «Просмотрено»
    expect(d!.day, 1); // но огрублена до 1-го числа
    // Оценка при этом сохранена (скрывали только даты).
    expect(friend.watched.first.currentScore, 8.0);
  });
}
