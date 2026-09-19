import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';

void main() {
  group('ReviewMeta — JSON', () {
    test('туда и обратно без потерь', () {
      final meta = ReviewMeta(
        title: 'Маяк, который светит внутрь',
        criteria: {'story': 9.0, 'sound': 8.8},
        verdict: Verdict.must,
        pros: ['Финальный твист'],
        cons: ['Провисает середина'],
        spoilers: true,
        shared: false,
        draft: true,
        createdAt: DateTime(2026, 9, 19, 10),
        updatedAt: DateTime(2026, 9, 19, 11),
        publishedAt: DateTime(2026, 9, 19, 12),
      );
      final back = ReviewMeta.fromJson(meta.toJson());
      expect(back.title, meta.title);
      expect(back.criteria, {'story': 9.0, 'sound': 8.8});
      expect(back.verdict, Verdict.must);
      expect(back.pros, ['Финальный твист']);
      expect(back.cons, ['Провисает середина']);
      expect(back.spoilers, isTrue);
      expect(back.shared, isFalse);
      expect(back.draft, isTrue);
      expect(back.createdAt, DateTime(2026, 9, 19, 10));
      expect(back.updatedAt, DateTime(2026, 9, 19, 11));
      expect(back.publishedAt, DateTime(2026, 9, 19, 12));
    });

    test('незнакомый вердикт и мусор в пунктах не роняют разбор', () {
      final back = ReviewMeta.fromJson({
        'verdict': 'legendary',
        'criteria': {'story': 'x', 'acting': 12, 'pace': 0.2, 'sound': 7.46},
      });
      expect(back.verdict, isNull);
      // Строку выбрасываем, числа зажимаем в 1..10 и округляем до 0.1.
      expect(back.criteria, {'acting': 10.0, 'pace': 1.0, 'sound': 7.5});
    });
  });

  group('рецензия в модели фильма', () {
    test('старый JSON: строка review без меты читается как текст', () {
      final m = LibraryMovie.fromJson({
        'uuid': 'a',
        'title': 'Prison Break: The Final Break',
        'review': 'Легендарный конец легендарной истории.',
      });
      expect(m.review, 'Легендарный конец легендарной истории.');
      expect(m.reviewMeta, isNull);
      expect(m.hasReview, isTrue);
      // Старые рецензии были приватными и такими остаются.
      expect(m.reviewIsPublic, isFalse);
    });

    test('мета переживает toJson/fromJson у фильма и сериала', () {
      final meta = ReviewMeta(verdict: Verdict.worth, shared: true);
      final m = LibraryMovie(uuid: 'a', title: 'A', reviewMeta: meta);
      final s = LibrarySeries(tvShowId: 's', title: 'S', reviewMeta: meta);
      expect(LibraryMovie.fromJson(m.toJson()).reviewMeta?.verdict,
          Verdict.worth);
      expect(LibrarySeries.fromJson(s.toJson()).reviewMeta?.verdict,
          Verdict.worth);
    });

    test('рецензия без текста, но с вердиктом, считается рецензией', () {
      final m = LibraryMovie(
          uuid: 'a', title: 'A', reviewMeta: ReviewMeta(verdict: Verdict.miss));
      expect(m.hasReview, isTrue);
      expect(LibraryMovie(uuid: 'b', title: 'B').hasReview, isFalse);
      expect(
          LibraryMovie(uuid: 'c', title: 'C', reviewMeta: ReviewMeta())
              .hasReview,
          isFalse);
    });

    test('публичная только опубликованная и открытая друзьям', () {
      LibraryMovie mk(ReviewMeta meta) =>
          LibraryMovie(uuid: 'a', title: 'A', review: 'текст', reviewMeta: meta);
      expect(mk(ReviewMeta(shared: true, draft: false)).reviewIsPublic, isTrue);
      expect(mk(ReviewMeta(shared: true, draft: true)).reviewIsPublic, isFalse);
      expect(mk(ReviewMeta(shared: false, draft: false)).reviewIsPublic, isFalse);
    });
  });

  group('подсказки', () {
    test('вердикт по оценке', () {
      expect(suggestVerdict(9.4), Verdict.masterpiece);
      expect(suggestVerdict(9.0), Verdict.masterpiece);
      expect(suggestVerdict(8.9), Verdict.must);
      expect(suggestVerdict(8.0), Verdict.must);
      expect(suggestVerdict(6.5), Verdict.worth);
      expect(suggestVerdict(6.4), Verdict.niche);
      expect(suggestVerdict(5.0), Verdict.niche);
      expect(suggestVerdict(4.9), Verdict.miss);
    });

    test('среднее по пунктам округляется до десятых', () {
      expect(criteriaAverage({'story': 9.0, 'direction': 9.3, 'acting': 9.1,
          'visuals': 8.6, 'sound': 8.8, 'pace': 6.8}), 8.6);
      expect(criteriaAverage({}), isNull);
    });

    test('каталог пунктов содержит пункты по умолчанию', () {
      expect(kDefaultCriteria,
          ['story', 'direction', 'acting', 'visuals', 'sound', 'pace']);
      for (final id in kDefaultCriteria) {
        expect(kCriteria, contains(id));
      }
    });
  });
}
