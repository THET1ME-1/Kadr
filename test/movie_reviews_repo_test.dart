import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/utils/movie_reviews.dart';

/// Рецензии на отдельные просмотры фильма и на просмотры сезонов.
void main() {
  final v1 = Viewing(date: DateTime(2026, 4, 15), score: 8.8);
  final v2 = Viewing(date: DateTime(2026, 5, 16), score: 8.5);
  final v3 = Viewing(date: DateTime(2026, 8, 16), score: 8.0);

  MovieRepository repo() => MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'm',
            title: 'Легенда об Аанге',
            status: LibraryStatus.watched,
            viewings: [for (final v in [v1, v2, v3]) Viewing.fromAny(v.toJson())],
          ).toJson(),
        ],
        'series': [
          LibrarySeries(tvShowId: 's', title: 'Аркейн', episodes: [
            Episode(
              season: 1,
              number: 1,
              watchedAt: DateTime(2023, 5, 29),
              rewatchViews: [Viewing(date: DateTime(2026, 8, 18))],
            ),
          ]).toJson(),
        ],
      });

  ReviewMeta meta(String title) =>
      ReviewMeta(title: title, criteria: {'story': 8.0});

  group('фильм', () {
    test('первая рецензия ложится в старые поля с привязкой к просмотру',
        () async {
      final r = repo();
      await r.saveMovieReview('m',
          viewId: v3.id, text: 'третий', meta: meta('Третий'));
      final m = r.byUuid('m')!;
      expect(m.review, 'третий');
      expect(m.reviewMeta!.viewId, v3.id);
      expect(m.moreReviews, isEmpty);
    });

    test('рецензия на другой просмотр идёт в дополнительные', () async {
      final r = repo();
      await r.saveMovieReview('m',
          viewId: v3.id, text: 'третий', meta: meta('Третий'));
      await r.saveMovieReview('m',
          viewId: v1.id, text: 'первый', meta: meta('Первый'));
      final m = r.byUuid('m')!;
      expect(m.review, 'третий');
      expect(m.moreReviews.single.review, 'первый');
      expect(m.moreReviews.single.reviewMeta!.viewId, v1.id);
      expect([for (final ref in movieReviews(m)) ref.ordinal], [1, 3]);
    });

    test('повторная запись на тот же просмотр обновляет ту же рецензию',
        () async {
      final r = repo();
      await r.saveMovieReview('m', viewId: v1.id, text: 'а', meta: meta('А'));
      await r.saveMovieReview('m', viewId: v3.id, text: 'б', meta: meta('Б'));
      await r.saveMovieReview('m', viewId: v3.id, text: 'в', meta: meta('В'));
      final m = r.byUuid('m')!;
      expect(m.allReviews.length, 2);
      expect(m.moreReviews.single.review, 'в');
    });

    test('удаляется рецензия именно этого просмотра', () async {
      final r = repo();
      await r.saveMovieReview('m', viewId: v1.id, text: 'а', meta: meta('А'));
      await r.saveMovieReview('m', viewId: v3.id, text: 'б', meta: meta('Б'));
      await r.deleteMovieReview('m', viewId: v1.id);
      final m = r.byUuid('m')!;
      expect(m.review, isNull);
      expect(m.reviewMeta, isNull);
      expect(m.allReviews.single.review, 'б');
      await r.deleteMovieReview('m', viewId: v3.id);
      expect(m.allReviews, isEmpty);
      expect(m.moreReviews, isEmpty);
    });

    test('рецензия переезжает на свободный просмотр и не лезет на занятый',
        () async {
      final r = repo();
      await r.saveMovieReview('m', viewId: v1.id, text: 'а', meta: meta('А'));
      await r.saveMovieReview('m', viewId: v3.id, text: 'б', meta: meta('Б'));
      expect(await r.moveMovieReview('m', from: v1.id, to: v3.id), isFalse);
      expect(await r.moveMovieReview('m', from: v1.id, to: v2.id), isTrue);
      final m = r.byUuid('m')!;
      expect([for (final ref in movieReviews(m)) ref.ordinal], [2, 3]);
      expect(reviewOfViewing(m, v2.id)!.review, 'а');
    });

    test('старая рецензия без привязки получает её при переносе', () async {
      final r = MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'm',
            title: 'Фильм',
            status: LibraryStatus.watched,
            viewings: [v1, v2],
            review: 'Старый текст без разбора',
          ).toJson(),
        ],
      });
      final m = r.byUuid('m')!;
      expect(reviewViewing(m, m)!.id, v2.id);
      expect(await r.moveMovieReview('m', from: v2.id, to: v1.id), isTrue);
      expect(m.reviewMeta!.viewId, v1.id);
      expect(m.reviewIsPublic, isFalse,
          reason: 'старая приватная рецензия не становится открытой');
    });

    test('фильм без просмотров: рецензия пишется и удаляется как раньше',
        () async {
      final r = MovieRepository.detached({
        'movies': [LibraryMovie(uuid: 'm', title: 'Фильм').toJson()],
      });
      await r.saveMovieReview('m', text: 'текст', meta: meta('Без просмотра'));
      expect(r.byUuid('m')!.review, 'текст');
      await r.deleteMovieReview('m');
      expect(r.byUuid('m')!.hasReview, isFalse);
    });
  });

  group('сезоны', () {
    test('рецензия на пересмотр сезона пишется рядом с первой', () async {
      final r = repo();
      final a = await r.saveSeasonReview('s',
          from: 1, to: 1, text: 'первый', meta: meta('Первый'));
      final clash = await r.saveSeasonReview('s',
          from: 1, to: 1, text: 'ещё', meta: meta('Ещё'));
      final b = await r.saveSeasonReview('s',
          from: 1, to: 1, pass: 2, text: 'второй', meta: meta('Второй'));
      expect(a, isNotNull);
      expect(clash, isNull);
      expect(b, isNotNull);
      final parts = r.seriesById('s')!.seasonReviews;
      expect([for (final p in parts) p.pass], [1, 2]);
    });

    test('просмотр рецензии меняется вместе с охватом', () async {
      final r = repo();
      final a = await r.saveSeasonReview('s',
          from: 1, to: 1, text: 'первый', meta: meta('Первый'));
      final res =
          await r.moveReview('s', partId: a, from: 1, to: 1, pass: 2);
      expect(res.ok, isTrue);
      expect(r.seriesById('s')!.seasonReviews.single.pass, 2);
    });
  });
}
