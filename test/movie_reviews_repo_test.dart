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

    // Рецензия старой версии без дат при каждом чтении вставала к последнему
    // просмотру: пересмотр уводил её за собой, а его удаление стирало текст.
    group('рецензия, написанная до привязки', () {
      MovieRepository legacy({ReviewMeta? meta}) => MovieRepository.detached({
            'movies': [
              LibraryMovie(
                uuid: 'm',
                title: 'Очень страшное кино',
                status: LibraryStatus.watched,
                viewings: [Viewing.fromAny(v1.toJson())],
                review: 'Старый текст без разбора',
                reviewMeta: meta,
              ).toJson(),
            ],
          });

      test('получает просмотр один раз, при загрузке', () {
        final m = legacy().byUuid('m')!;
        expect(m.reviewMeta!.viewId, v1.id);
        expect(m.reviewIsPublic, isFalse,
            reason: 'старая приватная рецензия не становится открытой');
        expect(m.reviewMeta!.updatedAt, isNull,
            reason: 'привязка не правка: дата не появляется');
      });

      test('не переезжает на новый пересмотр и не пропадает с ним', () async {
        final r = legacy();
        await r.addViewing('m', DateTime(2026, 9, 1));
        final m = r.byUuid('m')!;
        final rewatch = m.currentViewing!;
        expect(reviewViewing(m, m)!.id, v1.id);
        expect(reviewOfViewing(m, rewatch.id), isNull);
        await r.removeViewing('m', rewatch);
        expect(r.byUuid('m')!.review, 'Старый текст без разбора');
      });

      test('привязка переживает сохранение и загрузку', () async {
        final r = legacy();
        await r.addViewing('m', DateTime(2026, 9, 1));
        final again = MovieRepository.detached(r.toJson()).byUuid('m')!;
        expect(reviewViewing(again, again)!.id, v1.id);
      });

      test('с датой встаёт к просмотру, который был раньше неё', () {
        final r = MovieRepository.detached({
          'movies': [
            LibraryMovie(
              uuid: 'm',
              title: 'Фильм',
              status: LibraryStatus.watched,
              viewings: [
                for (final v in [v1, v2, v3]) Viewing.fromAny(v.toJson()),
              ],
              review: 'После второго просмотра',
              reviewMeta: ReviewMeta(createdAt: DateTime(2026, 6, 1)),
            ).toJson(),
          ],
        });
        expect(r.byUuid('m')!.reviewMeta!.viewId, v2.id);
      });
    });

    // Две рецензии выводятся к одному просмотру: вторая остаётся без него.
    // Такую пару оставляла синхронизация, когда рецензию переносили.
    test('рецензия без просмотра находится по своему id, а не по фильму',
        () async {
      final r = MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'm',
            title: 'Фильм',
            status: LibraryStatus.watched,
            viewings: [Viewing.fromAny(v1.toJson())],
            review: 'главная',
            reviewMeta: ReviewMeta(viewId: v1.id),
            moreReviews: [
              ExtraReview(
                id: 'mr-1',
                review: 'лишняя',
                reviewMeta: ReviewMeta(viewId: v1.id),
              ),
            ],
          ).toJson(),
        ],
      });
      final loose = movieReviews(r.byUuid('m')!).last;
      expect(loose.viewing, isNull);
      expect(loose.extraId, 'mr-1');
      await r.saveMovieReview('m',
          extraId: 'mr-1', text: 'лишняя, правка', meta: meta('Правка'));
      expect(r.byUuid('m')!.review, 'главная');
      expect(r.byUuid('m')!.moreReviews.single.review, 'лишняя, правка');
      await r.deleteMovieReview('m', extraId: 'mr-1');
      final m = r.byUuid('m')!;
      expect(m.review, 'главная', reason: 'главная рецензия на месте');
      expect(m.moreReviews, isEmpty);
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
