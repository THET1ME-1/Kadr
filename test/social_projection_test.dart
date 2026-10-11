import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/utils/movie_reviews.dart';

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
    // Оценка фильма живёт в просмотре: общая переезжает в него и обнуляется.
    final m1 = movies.firstWhere((m) => m['uuid'] == 'm1');
    expect(m1['score'], isNull);
    expect(((m1['viewings'] as List).single as Map)['score'], 8.0);
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

  test('hideDates огрубляет и дату добавления сериала', () {
    final repo = MovieRepository.detached({
      'movies': const [],
      'series': [
        LibrarySeries(
                tvShowId: 's1',
                title: 'Сериал',
                watchlist: true,
                addedAt: DateTime(2026, 3, 17))
            .toJson(),
      ],
    });
    final friend =
        MovieRepository.detached(repo.buildPublicProfile(hideDates: true));
    expect(friend.watchlistSeries.single.addedAt, DateTime(2026, 3, 1));
  });

  // Id просмотра выводится из его даты или из момента отметки, id рецензии —
  // из момента создания. При скрытых датах по ним читалось бы точное время,
  // поэтому наружу уходят порядковые номера.
  group('id и служебные даты в проекции', () {
    final seen = DateTime(2024, 1, 17, 14, 24, 26);
    final rewatched = DateTime(2024, 3, 3, 21, 5, 7);
    final edited = DateTime(2026, 9, 9, 9, 9, 9);
    const marked = 'vk3x9q2m7a';
    const extraId = 'mr-1789677172710123';
    const seasonId = 'sr-1789677172710999';

    MovieRepository origin() => MovieRepository.detached({
          'movies': [
            LibraryMovie(
              uuid: 'm1',
              title: 'Фильм',
              status: LibraryStatus.watched,
              viewings: [
                Viewing(id: '', date: seen, score: 8.0),
                Viewing(
                    id: marked,
                    date: DateTime(2026, 5, 1, 10),
                    score: 9.0,
                    editedAt: edited),
              ],
              review: 'про первый',
              reviewMeta:
                  ReviewMeta(viewId: 'd${seen.millisecondsSinceEpoch}'),
              moreReviews: [
                ExtraReview(
                  id: extraId,
                  review: 'про второй',
                  reviewMeta: ReviewMeta(viewId: marked),
                ),
              ],
            ).toJson(),
          ],
          'series': [
            LibrarySeries(
              tvShowId: 's1',
              title: 'Сериал',
              episodes: [
                Episode(
                  season: 1,
                  number: 1,
                  watchedAt: seen,
                  vid: 'd${seen.millisecondsSinceEpoch}',
                  editedAt: edited,
                  rewatchViews: [Viewing(id: '', date: rewatched)],
                ),
              ],
              seasonReviews: [
                SeasonReview(
                  id: seasonId,
                  from: 1,
                  to: 1,
                  review: 'про сезон',
                  reviewMeta: ReviewMeta(criteria: {'story': 9.0}),
                ),
              ],
              caughtUpAt: [rewatched],
              scoreSource: SeriesScoreSource.reviews,
              scoreSourceAt: edited,
            ).toJson(),
          ],
        });

    final secrets = [
      '${seen.millisecondsSinceEpoch}',
      '${rewatched.millisecondsSinceEpoch}',
      marked,
      '1789677172710123',
      '1789677172710999',
    ];
    final exactDates = [
      seen.toIso8601String(),
      rewatched.toIso8601String(),
      edited.toIso8601String(),
    ];

    test('id не выдают время ни при каких настройках', () {
      for (final hide in [false, true]) {
        final text = jsonEncode(origin().buildPublicProfile(hideDates: hide));
        for (final s in secrets) {
          expect(text.contains(s), isFalse, reason: 'в проекции осталось $s');
        }
        expect(text.contains(edited.toIso8601String()), isFalse,
            reason: 'момент правки друзьям не нужен');
      }
    });

    test('при скрытых датах точного времени в проекции нет нигде', () {
      final text = jsonEncode(origin().buildPublicProfile(hideDates: true));
      for (final d in exactDates) {
        expect(text.contains(d), isFalse, reason: 'в проекции осталось $d');
      }
    });

    test('рецензии у друга остаются при своих просмотрах', () {
      for (final hide in [false, true]) {
        final friend = MovieRepository.detached(
            origin().buildPublicProfile(hideDates: hide));
        final m = friend.byUuid('m1')!;
        expect([
          for (final r in movieReviews(m)) (r.ordinal, r.item.review),
        ], [
          (1, 'про первый'),
          (2, 'про второй'),
        ]);
        final s = friend.seriesById('s1')!;
        expect(s.seasonReviews.single.review, 'про сезон');
        expect(s.episodes.single.watchCount, 2);
        expect(s.displayScore, 9.0, reason: 'источник оценки доехал');
      }
    });
  });
}
