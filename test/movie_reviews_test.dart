import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/utils/movie_reviews.dart';

ReviewMeta _meta(Map<String, double> criteria,
        {String? viewId, DateTime? at, bool draft = false, String? title}) =>
    ReviewMeta(
      title: title,
      criteria: criteria,
      viewId: viewId,
      createdAt: at,
      publishedAt: at,
      draft: draft,
    );

void main() {
  final v1 = Viewing(date: DateTime(2026, 9, 4, 16, 7), score: 9.5);
  final v2 = Viewing(date: DateTime(2026, 10, 10, 23, 32), score: 9.5);

  group('к какому просмотру относится рецензия', () {
    test('без привязки встаёт к последнему просмотру до своей даты', () {
      final m = LibraryMovie(
        uuid: 'spider',
        title: 'Человек-паук: Новый день',
        status: LibraryStatus.watched,
        viewings: [v1, v2],
        reviewMeta: _meta({'story': 9.0}, at: DateTime(2026, 10, 10, 23, 44)),
      );
      expect(reviewViewing(m, m), v2);
      final refs = movieReviews(m);
      expect(refs.single.ordinal, 2);
      expect(refs.single.viewing, v2);
    });

    test('рецензия между двумя просмотрами относится к первому', () {
      final m = LibraryMovie(
        uuid: 'm',
        title: 'Фильм',
        status: LibraryStatus.watched,
        viewings: [v1, v2],
        reviewMeta: _meta({'story': 9.0}, at: DateTime(2026, 9, 5)),
      );
      expect(reviewViewing(m, m), v1);
    });

    test('старая рецензия без дат относится к последнему просмотру', () {
      final m = LibraryMovie(
        uuid: 'm',
        title: 'Фильм',
        status: LibraryStatus.watched,
        viewings: [v1, v2],
        review: 'Текст без разбора',
      );
      expect(reviewViewing(m, m), v2);
    });

    test('привязка по id важнее даты', () {
      final m = LibraryMovie(
        uuid: 'm',
        title: 'Фильм',
        status: LibraryStatus.watched,
        viewings: [v1, v2],
        reviewMeta: _meta({'story': 9.0},
            viewId: v1.id, at: DateTime(2026, 10, 11)),
      );
      expect(reviewViewing(m, m), v1);
    });

    test('у фильма без просмотров рецензия без просмотра', () {
      final m = LibraryMovie(
          uuid: 'm', title: 'Фильм', reviewMeta: _meta({'story': 7.0}));
      expect(reviewViewing(m, m), isNull);
      expect(movieReviews(m).single.ordinal, 0);
    });
  });

  group('список и свод', () {
    final a = Viewing(date: DateTime(2026, 4, 15), score: 8.8);
    final b = Viewing(date: DateTime(2026, 5, 16), score: 8.5);
    final c = Viewing(date: DateTime(2026, 8, 16), score: 8.0);
    LibraryMovie aang({bool draftLast = false}) => LibraryMovie(
          uuid: 'aang',
          title: 'Легенда об Аанге',
          status: LibraryStatus.watched,
          viewings: [c, a, b],
          // Первая написанная лежит в полях фильма, хотя она про третий просмотр.
          review: 'третья',
          reviewMeta: _meta(
            {'story': 6.8, 'direction': 8.0, 'pace': 6.8},
            viewId: c.id,
            draft: draftLast,
            title: 'На третий раз видны швы',
          ),
          moreReviews: [
            ExtraReview(
              id: 'x',
              review: 'первая',
              reviewMeta: _meta(
                {'story': 8.4, 'direction': 8.8, 'pace': 8.0},
                viewId: a.id,
                title: 'Аанг вернулся, и это главное',
              ),
            ),
          ],
        );

    test('рецензии идут по порядку просмотров', () {
      final refs = movieReviews(aang());
      expect([for (final r in refs) r.ordinal], [1, 3]);
      expect(refs.first.extraId, 'x');
      expect(refs.last.extraId, isNull);
      expect(reviewOfViewing(aang(), a.id), isA<ExtraReview>());
      expect(reviewOfViewing(aang(), b.id), isNull);
    });

    test('просмотры без рецензии', () {
      expect(unreviewedViewings(aang()), [b]);
    });

    test('таблица свода: столбец на рецензию, разница первой и последней', () {
      final t = movieReviewsTable(aang())!;
      expect([for (final col in t.columns) col.ordinal], [1, 3]);
      expect([for (final col in t.columns) col.score], [8.8, 8.0]);
      expect(t.criteria, ['story', 'direction', 'pace']);
      expect(t.deltas['story'], closeTo(-1.6, 0.001));
      expect(t.deltas['direction'], closeTo(-0.8, 0.001));
      expect(t.strongest, 'story');
      expect(t.scoreDelta, closeTo(-0.8, 0.001));
    });

    test('черновик в свод не идёт, одной рецензии для свода мало', () {
      expect(movieReviewsTable(aang(draftLast: true)), isNull);
    });

    test('пять рецензий дают пять столбцов', () {
      final views = [
        for (var i = 1; i <= 5; i++)
          Viewing(date: DateTime(2020 + i), score: 7.0 + i * 0.4),
      ];
      final m = LibraryMovie(
        uuid: 'm',
        title: 'Фильм',
        status: LibraryStatus.watched,
        viewings: views,
        reviewMeta: _meta({'pace': 6.0}, viewId: views[0].id),
        moreReviews: [
          for (var i = 1; i < 5; i++)
            ExtraReview(
                id: 'x$i',
                reviewMeta: _meta({'pace': 6.0 + i}, viewId: views[i].id)),
        ],
      );
      final t = movieReviewsTable(m)!;
      expect(t.columns.length, 5);
      expect(t.deltas['pace'], closeTo(4.0, 0.001));
      expect(t.strongest, 'pace');
    });

    test('пункт, оценённый только в одной рецензии, остаётся без разницы', () {
      final m = aang();
      m.reviewMeta!.criteria['humor'] = 9.0;
      final t = movieReviewsTable(m)!;
      expect(t.criteria.contains('humor'), isTrue);
      expect(t.deltas.containsKey('humor'), isFalse);
      expect(t.columns.first.criteria['humor'], isNull);
    });
  });
}
