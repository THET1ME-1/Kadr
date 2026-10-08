import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/utils/season_reviews.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReviewMeta _meta(double avg, {bool draft = false}) =>
    ReviewMeta(criteria: {'story': avg}, draft: draft);

SeasonReview _part(String id, int from, int to, double avg,
        {bool draft = false}) =>
    SeasonReview(id: id, from: from, to: to, reviewMeta: _meta(avg, draft: draft));

/// «Атака титанов» из макета: по сериям S1 8.8, S2 9.0, S3 9.1, S4 9.3.
LibrarySeries _aot({List<SeasonReview>? parts}) {
  Episode ep(int s, int n, double sc) =>
      Episode(season: s, number: n, watchedAt: DateTime(2026, s, n), score: sc);
  return LibrarySeries(
    tvShowId: 'aot',
    title: 'Атака титанов',
    episodes: [
      ep(1, 1, 8.8), ep(1, 2, 8.8),
      ep(2, 1, 9.0), ep(2, 2, 9.0),
      ep(3, 1, 9.1), ep(3, 2, 9.1),
      ep(4, 1, 9.3), ep(4, 2, 9.3),
    ],
    seasonReviews: parts ??
        [
          _part('a', 1, 1, 8.6),
          _part('b', 2, 3, 9.2),
          _part('c', 4, 4, 8.1),
        ],
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LocaleController.instance.setCode('ru');
  });

  group('свод по рецензиям', () {
    test('вес по числу сезонов, как в макете: 8.8', () {
      expect(reviewsAverage(_aot()), 8.8);
    });

    test('черновики и рецензии без оценок по пунктам в свод не входят', () {
      final s = _aot(parts: [
        _part('a', 1, 1, 6.0, draft: true),
        SeasonReview(id: 'b', from: 2, to: 2, reviewMeta: ReviewMeta()),
        _part('c', 3, 4, 9.0),
      ]);
      expect(reviewsAverage(s), 9.0);
    });

    test('рецензия на весь сериал в свод не входит', () {
      final s = _aot(parts: [_part('a', 1, 1, 7.0)])
        ..reviewMeta = _meta(10);
      expect(reviewsAverage(s), 7.0);
    });

    test('без рецензий на сезоны свода нет', () {
      expect(reviewsAverage(_aot(parts: [])), isNull);
    });
  });

  group('оценка сериала по источнику', () {
    test('по умолчанию средняя по сериям', () {
      expect(_aot().displayScore, 9.1);
    });

    test('выставлен свод', () {
      final s = _aot()..scoreSource = SeriesScoreSource.reviews;
      expect(s.displayScore, 8.8);
    });

    test('выставлена рецензия на весь сериал', () {
      final s = _aot()
        ..reviewMeta = _meta(9.0)
        ..scoreSource = SeriesScoreSource.review;
      expect(s.displayScore, 9.0);
    });

    test('источник пропал: снова средняя по сериям', () {
      final s = _aot(parts: [])..scoreSource = SeriesScoreSource.reviews;
      expect(s.displayScore, 9.1);
    });
  });

  group('сравнение по сезонам', () {
    test('по строке на сезон: серии и рецензия', () {
      final rows = compareSeasons(_aot());
      expect([for (final r in rows) r.season], [1, 2, 3, 4]);
      expect(rows[0].episodes, 8.8);
      expect(rows[0].review, 8.6);
      expect(rows[2].review, 9.2, reason: 'S3 в рецензии на S2–S3');
      expect(rows[3].review, 8.1);
    });

    test('строка вывода: строже и сильнее всего разошёлся сезон', () {
      expect(
        reviewsDeltaLine(_aot()),
        'Рецензии строже серий на 0.3. Сильнее всего разошёлся 4-й сезон.',
      );
    });
  });

  group('охват', () {
    test('сезон занят только одной рецензией', () {
      final s = _aot();
      expect(takenBy(s, 3)?.id, 'b');
      expect(canCover(s, 2, 2), isFalse);
      expect(canCover(s, 2, 3, exceptId: 'b'), isTrue);
      expect(canCover(s, 3, 4, exceptId: 'b'), isFalse);
      expect(canCover(_aot(parts: []), 1, 4), isTrue);
    });

    test('подписи охвата', () {
      expect(scopeShort(1, 1), 'S1');
      expect(scopeShort(2, 3), 'S2–S3');
      expect(scopeShort(null, null), 'Весь сериал');
      expect(scopeLong(1, 1), 'Сезон 1');
      expect(scopeLong(2, 3), 'Сезоны 2–3');
    });
  });

  test('части, источник и дата источника переживают сохранение', () {
    final s = _aot()
      ..scoreSource = SeriesScoreSource.reviews
      ..scoreSourceAt = DateTime(2026, 10, 8);
    final back = LibrarySeries.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
    );
    expect(back.seasonReviews.map((p) => '${p.id}:${p.from}-${p.to}'),
        ['a:1-1', 'b:2-3', 'c:4-4']);
    expect(back.seasonReviews[1].reviewMeta!.average, 9.2);
    expect(back.scoreSource, SeriesScoreSource.reviews);
    expect(back.scoreSourceAt, DateTime(2026, 10, 8));
  });
}
