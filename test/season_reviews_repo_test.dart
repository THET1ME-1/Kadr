import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/sync/sync_merge.dart';

/// Рецензии на сезоны в хранилище: запись, охват, удаление, источник оценки,
/// что уходит друзьям и как сливаются при синке.
void main() {
  MovieRepository repo({List<SeasonReview>? parts, ReviewMeta? whole}) =>
      MovieRepository.detached({
        'series': [
          LibrarySeries(
            tvShowId: 's1',
            title: 'Атака титанов',
            episodes: [
              Episode(season: 1, number: 1, watchedAt: DateTime(2024, 5, 1), score: 9),
            ],
            review: whole == null ? null : 'Про весь сериал',
            reviewMeta: whole,
            seasonReviews: parts,
          ).toJson(),
        ],
      });

  ReviewMeta meta(double v, {bool draft = false, bool shared = true}) =>
      ReviewMeta(criteria: {'story': v}, draft: draft, shared: shared);

  group('запись', () {
    test('новая рецензия на сезоны получает id и даты', () async {
      final r = repo();
      final id = await r.saveSeasonReview('s1',
          from: 2, to: 3, text: '  Текст  ', meta: meta(9.2));
      final p = r.seriesById('s1')!.seasonReviews.single;
      expect(p.id, id);
      expect((p.from, p.to), (2, 3));
      expect(p.review, 'Текст');
      expect(p.reviewMeta!.createdAt, isNotNull);
    });

    test('повторная запись по id обновляет ту же рецензию', () async {
      final r = repo();
      final id = await r.saveSeasonReview('s1', from: 1, to: 1, meta: meta(8));
      await r.saveSeasonReview('s1', id: id, from: 1, to: 1, meta: meta(9));
      final parts = r.seriesById('s1')!.seasonReviews;
      expect(parts, hasLength(1));
      expect(parts.single.reviewMeta!.average, 9);
    });

    test('занятый сезон второй рецензии не достаётся', () async {
      final r = repo(parts: [SeasonReview(id: 'a', from: 1, to: 2)]);
      final id = await r.saveSeasonReview('s1', from: 2, to: 3, meta: meta(8));
      expect(id, isNull);
      expect(r.seriesById('s1')!.seasonReviews, hasLength(1));
    });

    test('удаление убирает только эту рецензию', () async {
      final r = repo(parts: [
        SeasonReview(id: 'a', from: 1, to: 1),
        SeasonReview(id: 'b', from: 2, to: 2),
      ]);
      await r.deleteSeasonReview('s1', 'a');
      expect(r.seriesById('s1')!.seasonReviews.map((p) => p.id), ['b']);
    });
  });

  group('смена охвата', () {
    test('диапазон меняется у той же рецензии', () async {
      final r = repo(parts: [SeasonReview(id: 'a', from: 1, to: 1, reviewMeta: meta(8))]);
      final res = await r.moveReview('s1', partId: 'a', from: 1, to: 3);
      expect(res.ok, isTrue);
      expect(res.partId, 'a');
      final p = r.seriesById('s1')!.seasonReviews.single;
      expect((p.from, p.to), (1, 3));
    });

    test('рецензия на весь сериал переезжает на сезоны вместе с текстом', () async {
      final r = repo(whole: meta(9));
      final res = await r.moveReview('s1', from: 2, to: 2);
      final s = r.seriesById('s1')!;
      expect(res.ok, isTrue);
      expect(s.hasReview, isFalse);
      final p = s.seasonReviews.single;
      expect(p.id, res.partId);
      expect(p.review, 'Про весь сериал');
      expect(p.reviewMeta!.average, 9);
    });

    test('рецензия на сезоны становится рецензией на весь сериал', () async {
      final r = repo(parts: [
        SeasonReview(id: 'a', from: 1, to: 1, review: 'Про S1', reviewMeta: meta(8)),
      ]);
      final res = await r.moveReview('s1', partId: 'a');
      final s = r.seriesById('s1')!;
      expect(res.ok, isTrue);
      expect(res.partId, isNull);
      expect(s.seasonReviews, isEmpty);
      expect(s.review, 'Про S1');
    });

    test('на весь сериал нельзя, если такая рецензия уже есть', () async {
      final r = repo(
        whole: meta(9),
        parts: [SeasonReview(id: 'a', from: 1, to: 1, reviewMeta: meta(8))],
      );
      final res = await r.moveReview('s1', partId: 'a');
      expect(res.ok, isFalse);
      expect(r.seriesById('s1')!.seasonReviews, hasLength(1));
    });

    test('на занятые сезоны нельзя', () async {
      final r = repo(parts: [
        SeasonReview(id: 'a', from: 1, to: 1),
        SeasonReview(id: 'b', from: 2, to: 2),
      ]);
      final res = await r.moveReview('s1', partId: 'a', from: 1, to: 2);
      expect(res.ok, isFalse);
    });
  });

  test('источник оценки ставится с датой', () async {
    final r = repo(parts: [SeasonReview(id: 'a', from: 1, to: 1, reviewMeta: meta(7))]);
    await r.setSeriesScoreSource('s1', SeriesScoreSource.reviews);
    final s = r.seriesById('s1')!;
    expect(s.scoreSource, SeriesScoreSource.reviews);
    expect(s.scoreSourceAt, isNotNull);
    expect(s.displayScore, 7);
  });

  group('друзьям', () {
    test('уходят только открытые опубликованные рецензии на сезоны', () {
      final r = repo(parts: [
        SeasonReview(id: 'open', from: 1, to: 1, review: 'а', reviewMeta: meta(8)),
        SeasonReview(id: 'draft', from: 2, to: 2, review: 'б', reviewMeta: meta(8, draft: true)),
        SeasonReview(id: 'private', from: 3, to: 3, review: 'в', reviewMeta: meta(8, shared: false)),
      ]);
      final s = (r.buildPublicProfile()['series'] as List).single as Map;
      expect([for (final p in s['seasonReviews'] as List) (p as Map)['id']], ['open']);
    });

    test('скрытые оценки режут пункты и у рецензий на сезоны', () {
      final r = repo(parts: [
        SeasonReview(id: 'open', from: 1, to: 1, review: 'а', reviewMeta: meta(8)),
      ]);
      final s = (r.buildPublicProfile(hideRatings: true)['series'] as List).single as Map;
      final p = (s['seasonReviews'] as List).single as Map;
      expect((p['reviewMeta'] as Map).containsKey('criteria'), isFalse);
    });
  });

  group('синк', () {
    Map<String, dynamic> snap(List<SeasonReview> parts,
            {SeriesScoreSource src = SeriesScoreSource.episodes, DateTime? at}) =>
        {
          'series': [
            LibrarySeries(
              tvShowId: 's1',
              title: 'Атака титанов',
              seasonReviews: parts,
              scoreSource: src,
              scoreSourceAt: at,
            ).toJson(),
          ],
        };

    test('рецензии на сезоны объединяются по id, у общей свежая правка', () {
      final old = meta(7)..updatedAt = DateTime(2026, 1, 1);
      final fresh = meta(9)..updatedAt = DateTime(2026, 5, 1);
      final out = mergeSnapshots(
        snap([SeasonReview(id: 'a', from: 1, to: 1, reviewMeta: old)]),
        snap([
          SeasonReview(id: 'a', from: 1, to: 2, reviewMeta: fresh),
          SeasonReview(id: 'b', from: 3, to: 3, reviewMeta: meta(8)),
        ]),
        SyncStats(),
      );
      final parts = ((out['series'] as List).single as Map)['seasonReviews'] as List;
      expect([for (final p in parts) (p as Map)['id']], ['a', 'b']);
      final a = parts.first as Map;
      expect(a['to'], 2);
      expect(((a['reviewMeta'] as Map)['criteria'] as Map)['story'], 9);
    });

    test('источник оценки берётся с более поздней датой', () {
      final out = mergeSnapshots(
        snap([], src: SeriesScoreSource.reviews, at: DateTime(2026, 10, 1)),
        snap([], src: SeriesScoreSource.episodes, at: DateTime(2026, 10, 8)),
        SyncStats(),
      );
      final s = (out['series'] as List).single as Map;
      expect(s.containsKey('scoreSource'), isFalse, reason: 'episodes по умолчанию');
      expect(s['scoreSourceAt'], DateTime(2026, 10, 8).toIso8601String());
    });
  });
}
