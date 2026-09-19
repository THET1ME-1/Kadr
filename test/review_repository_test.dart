import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/sync/sync_merge.dart';

/// Рецензии в репозитории: запись, удаление, публичная проекция и слияние.
void main() {
  MovieRepository repoWith({ReviewMeta? movieMeta, ReviewMeta? seriesMeta}) =>
      MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'm1',
            title: 'Shutter Island',
            status: LibraryStatus.watched,
            viewings: [Viewing(date: DateTime(2024, 3, 12), score: 8.5)],
            review: movieMeta == null ? null : 'Текст **рецензии**',
            reviewMeta: movieMeta,
          ).toJson(),
        ],
        'series': [
          LibrarySeries(
            tvShowId: 's1',
            title: 'Dark',
            episodes: [
              Episode(season: 1, number: 1, watchedAt: DateTime(2024, 5, 1)),
            ],
            review: seriesMeta == null ? null : 'Про сериал',
            reviewMeta: seriesMeta,
          ).toJson(),
        ],
      });

  group('запись', () {
    test('saveMovieReview пишет текст и мету, ставит даты', () async {
      final repo = repoWith();
      await repo.saveMovieReview('m1',
          text: '  Первый абзац.  ',
          meta: ReviewMeta(verdict: Verdict.must, draft: true));
      final m = repo.byUuid('m1')!;
      expect(m.review, 'Первый абзац.');
      expect(m.reviewMeta!.verdict, Verdict.must);
      expect(m.reviewMeta!.createdAt, isNotNull);
      expect(m.reviewMeta!.updatedAt, isNotNull);
      expect(m.reviewMeta!.publishedAt, isNull); // черновик ещё не публиковали
    });

    test('публикация ставит дату один раз', () async {
      final repo = repoWith();
      await repo.saveMovieReview('m1',
          text: 'a', meta: ReviewMeta(draft: false));
      final first = repo.byUuid('m1')!.reviewMeta!.publishedAt;
      expect(first, isNotNull);
      await repo.saveMovieReview('m1',
          text: 'b', meta: repo.byUuid('m1')!.reviewMeta!.copy());
      expect(repo.byUuid('m1')!.reviewMeta!.publishedAt, first);
    });

    test('пустой текст убирает поле, мета остаётся', () async {
      final repo = repoWith();
      await repo.saveMovieReview('m1',
          text: '   ', meta: ReviewMeta(verdict: Verdict.miss));
      final m = repo.byUuid('m1')!;
      expect(m.review, isNull);
      expect(m.hasReview, isTrue);
    });

    test('сериал пишется так же', () async {
      final repo = repoWith();
      await repo.saveSeriesReview('s1',
          text: 'Про сериал', meta: ReviewMeta(pros: ['Музыка']));
      final s = repo.seriesById('s1')!;
      expect(s.review, 'Про сериал');
      expect(s.reviewMeta!.pros, ['Музыка']);
    });

    test('удаление чистит и текст, и мету', () async {
      final repo = repoWith(
          movieMeta: ReviewMeta(verdict: Verdict.must),
          seriesMeta: ReviewMeta(verdict: Verdict.worth));
      await repo.deleteMovieReview('m1');
      await repo.deleteSeriesReview('s1');
      expect(repo.byUuid('m1')!.hasReview, isFalse);
      expect(repo.byUuid('m1')!.reviewMeta, isNull);
      expect(repo.seriesById('s1')!.hasReview, isFalse);
    });

    test('setCurrentScore пишет в текущий просмотр', () async {
      final repo = repoWith();
      await repo.setCurrentScore('m1', 9.1);
      final m = repo.byUuid('m1')!;
      expect(m.currentScore, 9.1);
      expect(m.viewings.single.score, 9.1);
    });
  });

  group('что видят друзья', () {
    Map<String, dynamic> pubMovie(MovieRepository r,
            {bool hideRatings = false}) =>
        (r.buildPublicProfile(hideRatings: hideRatings)['movies'] as List)
            .cast<Map<String, dynamic>>()
            .single;

    test('опубликованная и открытая рецензия уезжает целиком', () {
      final r = repoWith(
          movieMeta: ReviewMeta(
              shared: true, criteria: {'story': 9.0}, verdict: Verdict.must));
      final m = pubMovie(r);
      expect(m['review'], 'Текст **рецензии**');
      expect((m['reviewMeta'] as Map)['verdict'], 'must');
      final friend = MovieRepository.detached(r.buildPublicProfile());
      expect(friend.watched.single.reviewIsPublic, isTrue);
    });

    test('черновик не уезжает', () {
      final m = pubMovie(repoWith(movieMeta: ReviewMeta(draft: true)));
      expect(m['review'], isNull);
      expect(m.containsKey('reviewMeta'), isFalse);
    });

    test('закрытая от друзей не уезжает', () {
      final m = pubMovie(repoWith(movieMeta: ReviewMeta(shared: false)));
      expect(m['review'], isNull);
      expect(m.containsKey('reviewMeta'), isFalse);
    });

    test('сериал: закрытая рецензия режется', () {
      final r = repoWith(seriesMeta: ReviewMeta(shared: false));
      final s = (r.buildPublicProfile()['series'] as List).single as Map;
      expect(s['review'], isNull);
      expect(s.containsKey('reviewMeta'), isFalse);
    });

    test('скрытые даты огрубляют и даты рецензии', () {
      final r = repoWith(
          movieMeta: ReviewMeta(
              createdAt: DateTime(2026, 9, 14, 10, 30),
              updatedAt: DateTime(2026, 9, 19, 11, 45),
              publishedAt: DateTime(2026, 9, 17, 22, 5)));
      final meta = (r.buildPublicProfile(hideDates: true)['movies'] as List)
          .cast<Map<String, dynamic>>()
          .single['reviewMeta'] as Map;
      for (final k in ['createdAt', 'updatedAt', 'publishedAt']) {
        expect(DateTime.parse(meta[k] as String), DateTime(2026, 9),
            reason: k);
      }
    });

    test('скрытые оценки прячут и оценки по пунктам', () {
      final m = pubMovie(
          repoWith(movieMeta: ReviewMeta(criteria: {'story': 9.0})),
          hideRatings: true);
      expect(m['review'], isNotNull); // сам текст остаётся
      expect((m['reviewMeta'] as Map).containsKey('criteria'), isFalse);
    });
  });

  group('синхронизация', () {
    Map<String, dynamic> snap(String? text, ReviewMeta? meta) => {
          'movies': [
            LibraryMovie(
                    uuid: 'm1',
                    title: 'A',
                    status: LibraryStatus.watched,
                    review: text,
                    reviewMeta: meta)
                .toJson(),
          ],
          'series': [],
          'lists': [],
        };

    test('берётся более свежая рецензия вместе с её текстом', () {
      final old = ReviewMeta(
          verdict: Verdict.worth, updatedAt: DateTime(2026, 9, 1));
      final fresh = ReviewMeta(
          verdict: Verdict.must, updatedAt: DateTime(2026, 9, 10));
      final merged = mergeSnapshots(snap('старый', old), snap('новый', fresh), SyncStats());
      final m = (merged['movies'] as List).single as Map<String, dynamic>;
      expect(m['review'], 'новый');
      expect((m['reviewMeta'] as Map)['verdict'], 'must');

      final back = mergeSnapshots(snap('новый', fresh), snap('старый', old), SyncStats());
      final m2 = (back['movies'] as List).single as Map<String, dynamic>;
      expect(m2['review'], 'новый');
    });

    test('рецензия со старой версии без меты не затирает новую', () {
      final fresh = ReviewMeta(
          verdict: Verdict.must, updatedAt: DateTime(2026, 9, 10));
      final merged = mergeSnapshots(snap('новый', fresh), snap('старый', null), SyncStats());
      final m = (merged['movies'] as List).single as Map<String, dynamic>;
      expect(m['review'], 'новый');
      expect(m['reviewMeta'], isNotNull);
    });
  });
}
