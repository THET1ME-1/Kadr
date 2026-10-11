import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';

Map<String, dynamic> _movieJson(List<Map<String, dynamic>> viewings,
        {double? score, int? rewatchCount}) =>
    {
      'uuid': 'm',
      'title': 'Фильм',
      'status': 'watched',
      'viewings': viewings,
      'score': score,
      'rewatchCount': ?rewatchCount,
    };

void main() {
  group('id просмотра', () {
    test('старым записям id выводится из даты и совпадает на двух устройствах',
        () {
      final json = _movieJson([
        {'date': '2026-04-15T11:22:31.000', 'score': 8.8},
        {'date': null, 'score': null},
        {'date': '2026-04-15T11:22:31.000', 'score': 8.8},
        {'date': null, 'score': 9.0},
      ]);
      final a = LibraryMovie.fromJson(json), b = LibraryMovie.fromJson(json);
      expect([for (final v in a.viewings) v.id],
          [for (final v in b.viewings) v.id]);
      expect({for (final v in a.viewings) v.id}.length, 4);
    });

    test('id переживает запись и чтение, даже если дату поправили', () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': '2026-04-15T11:22:31.000', 'score': 8.8},
      ]));
      final id = m.viewings.single.id;
      m.viewings.single.date = DateTime(2020, 1, 1);
      final back = LibraryMovie.fromJson(m.toJson());
      expect(back.viewings.single.id, id);
    });

    test('новый просмотр получает свой id', () {
      expect(Viewing().id, isNotEmpty);
      expect(Viewing().id, isNot(Viewing().id));
    });
  });

  group('порядок и номер просмотра', () {
    test('без даты идут первыми, дальше по дате', () {
      final late = Viewing(date: DateTime(2026, 8, 16), score: 8.0);
      final early = Viewing(date: DateTime(2026, 4, 15), score: 8.8);
      final unknown = Viewing(score: 9.0);
      final m = LibraryMovie(
        uuid: 'm',
        title: 'Фильм',
        status: LibraryStatus.watched,
        viewings: [late, unknown, early],
      );
      expect(m.orderedViewings, [unknown, early, late]);
      expect(m.ordinalOf(unknown), 1);
      expect(m.ordinalOf(early), 2);
      expect(m.ordinalOf(late), 3);
      expect(m.currentViewing, late);
    });

    test('просмотр, добавленный задним числом, получает ранний номер', () {
      final first = Viewing(date: DateTime(2026, 4, 15));
      final m = LibraryMovie(
        uuid: 'm',
        title: 'Фильм',
        status: LibraryStatus.watched,
        viewings: [first],
      );
      final older = Viewing(date: DateTime(2019, 1, 1));
      m.viewings.add(older);
      expect(m.ordinalOf(older), 1);
      expect(m.ordinalOf(first), 2);
    });
  });

  group('счётчик повторов', () {
    test('считается из списка просмотров', () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': '2026-04-15T11:22:31.000'},
        {'date': '2026-05-16T22:26:16.000'},
      ], rewatchCount: 0));
      expect(m.rewatchCount, 1);
      expect(m.viewCount, 2);
      expect(m.toJson()['rewatchCount'], 1);
    });

    test('старый счётчик, обогнавший список, достраивает просмотры без даты',
        () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': '2026-04-15T11:22:31.000'},
      ], rewatchCount: 2));
      expect(m.viewings.length, 3);
      expect(m.viewings.where((v) => v.date == null).length, 2);
      expect(m.rewatchCount, 2);
      // Второе чтение ничего не добавляет.
      expect(LibraryMovie.fromJson(m.toJson()).viewings.length, 3);
    });
  });

  group('оценка фильма', () {
    test('общая оценка один раз переезжает в последний просмотр', () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': '2024-01-01T10:00:00.000'},
        {'date': '2026-01-01T10:00:00.000'},
      ], score: 7.9));
      expect(m.currentViewing!.score, 7.9);
      expect(m.orderedViewings.first.score, isNull);
      expect(m.score, isNull);
      expect(m.currentScore, 7.9);
      // Новый просмотр после переезда остаётся без оценки.
      final back = LibraryMovie.fromJson(m.toJson());
      back.viewings.add(Viewing(date: DateTime(2026, 9, 1)));
      final again = LibraryMovie.fromJson(back.toJson());
      expect(again.currentViewing!.score, isNull);
    });

    test('своя оценка последнего просмотра не затирается общей', () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': '2026-04-15T11:22:31.000', 'score': 8.8},
        {'date': '2026-08-16T16:49:27.000', 'score': 8.0},
      ], score: 7.9));
      expect(m.currentViewing!.score, 8.0);
      expect(m.score, isNull);
    });

    test('оценка фильма — последний оценённый просмотр', () {
      final m = LibraryMovie(
        uuid: 'm',
        title: 'Фильм',
        status: LibraryStatus.watched,
        viewings: [
          Viewing(date: DateTime(2026, 4, 15), score: 8.8),
          Viewing(date: DateTime(2026, 8, 16)),
        ],
      );
      expect(m.currentScore, 8.8);
      expect(m.scoreOf(m.currentViewing!), isNull);
      expect(m.previousScore(m.currentViewing!), 8.8);
    });

    test('без просмотров остаётся общая оценка', () {
      final m = LibraryMovie(uuid: 'm', title: 'Фильм', score: 6.5);
      expect(m.score, 6.5);
      expect(m.currentScore, 6.5);
    });

    // В базе есть просмотры-дубли с одной датой до секунды: так отмечали
    // «видел раньше». Старая версия показывала оценку первого из них, а
    // общую держала запасной. Переезд общей оценки не должен её подменить.
    test('дубль с той же датой: общая оценка не перебивает оценку первого',
        () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': '2026-04-11T20:20:08.000', 'score': 7.0},
        {'date': '2026-04-11T20:20:08.000'},
      ], score: 6.5));
      expect(m.currentScore, 7.0);
      expect(m.currentViewing!.score, isNull);
      expect(m.score, isNull);
    });

    test('дубль после раннего просмотра: решает оценка дубля, не общая', () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': '2023-05-29T13:58:01.000'},
        {'date': '2025-10-04T21:35:11.000', 'score': 6.5},
        {'date': '2025-10-04T21:35:11.000'},
      ], score: 7.2));
      expect(m.currentScore, 6.5);
      expect(m.score, isNull);
    });

    test('два пустых дубля: общая оценка достаётся последнему', () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': '2026-04-11T20:20:08.000'},
        {'date': '2026-04-11T20:20:08.000'},
      ], score: 8.0));
      expect(m.currentScore, 8.0);
      expect(m.currentViewing!.score, 8.0);
      expect(m.orderedViewings.first.score, isNull);
    });

    test('просмотры без дат: общая оценка идёт последнему, как раньше', () {
      final m = LibraryMovie.fromJson(_movieJson([
        {'date': null, 'score': 8.0},
        {'date': null},
      ], score: 6.0));
      // Старая версия показывала у такого фильма общую оценку.
      expect(m.currentScore, 6.0);
    });
  });

  group('просмотры серии', () {
    test('список просмотров совпадает со счётчиком, id стабильны', () {
      final json = {
        'season': 1,
        'number': 3,
        'watchedAt': '2023-05-29T13:41:00.000',
        'score': 10.0,
        'rewatchCount': 2,
        'rewatchViews': [
          {'date': '2023-10-02T17:44:00.000'},
        ],
      };
      final a = Episode.fromJson(json), b = Episode.fromJson(json);
      expect(a.watchCount, 3);
      expect(a.rewatchCount, 2);
      expect(a.views.length, 3);
      expect([for (final v in a.views) v.id], [for (final v in b.views) v.id]);
      expect({for (final v in a.views) v.id}.length, 3);
      final back = Episode.fromJson(a.toJson());
      expect([for (final v in back.views) v.id], [for (final v in a.views) v.id]);
    });

    test('порядок по дате, оценка серии — последний оценённый просмотр', () {
      final e = Episode(
        season: 1,
        number: 1,
        watchedAt: DateTime(2023, 5, 29),
        score: 10.0,
        rewatchViews: [
          Viewing(date: DateTime(2026, 8, 18), score: 9.0),
          Viewing(date: DateTime(2023, 10, 2)),
        ],
      );
      final o = e.orderedViews;
      expect([for (final v in o) v.date!.year], [2023, 2023, 2026]);
      expect(o.first.id, e.vid);
      expect(e.currentScore, 9.0);
      expect(e.scoreOfView(o[1]), isNull);
    });

    test('событие ленты несёт id и оценку своего просмотра', () {
      final rewatch = Viewing(date: DateTime(2026, 8, 18));
      final s = LibrarySeries(tvShowId: 's', title: 'Сериал', episodes: [
        Episode(
          season: 1,
          number: 1,
          watchedAt: DateTime(2023, 5, 29),
          score: 10.0,
          rewatchViews: [rewatch],
        ),
      ]);
      final sessions = s.sessions();
      expect(sessions.length, 2);
      final ev = sessions.last.episodes.single;
      expect(ev.eventViewId, rewatch.id);
      expect(ev.rewatchOrdinal, 2);
      expect(ev.score, isNull);
      expect(sessions.first.episodes.single.eventViewId, s.episodes.single.vid);
    });

    test('средняя сериала берёт последнюю оценку серии', () {
      final s = LibrarySeries(tvShowId: 's', title: 'Сериал', episodes: [
        Episode(
          season: 1,
          number: 1,
          watchedAt: DateTime(2023, 5, 29),
          score: 10.0,
          rewatchViews: [Viewing(date: DateTime(2026, 8, 18), score: 8.0)],
        ),
        Episode(season: 1, number: 2, watchedAt: DateTime(2023, 5, 29), score: 9.0),
      ]);
      expect(s.episodeScoreAvg, 8.5);
    });
  });

  group('рецензии', () {
    test('просмотр рецензии и доп. рецензии переживают JSON', () {
      final v1 = Viewing(date: DateTime(2026, 4, 15), score: 8.8);
      final v2 = Viewing(date: DateTime(2026, 8, 16), score: 8.0);
      final m = LibraryMovie(
        uuid: 'm',
        title: 'Фильм',
        status: LibraryStatus.watched,
        viewings: [v1, v2],
        review: 'первая',
        reviewMeta: ReviewMeta(title: 'Первая', viewId: v1.id),
        moreReviews: [
          ExtraReview(
              id: 'x1',
              review: 'вторая',
              reviewMeta: ReviewMeta(title: 'Вторая', viewId: v2.id)),
        ],
      );
      final back = LibraryMovie.fromJson(m.toJson());
      expect(back.reviewMeta!.viewId, v1.id);
      expect(back.moreReviews.single.id, 'x1');
      expect(back.moreReviews.single.reviewMeta!.viewId, v2.id);
      expect(back.moreReviews.single.review, 'вторая');
    });

    test('у рецензии на сезоны есть номер просмотра, по умолчанию первый', () {
      final old = SeasonReview.fromJson({'id': 'a', 'from': 1, 'to': 1});
      expect(old.pass, 1);
      final p = SeasonReview(id: 'b', from: 1, to: 1, pass: 3);
      expect(SeasonReview.fromJson(p.toJson()).pass, 3);
      expect(old.toJson().containsKey('pass'), isFalse);
    });

    test('в свод идёт последняя рецензия каждого сезона', () {
      ReviewMeta meta(double v) => ReviewMeta(criteria: {'story': v});
      final s = LibrarySeries(tvShowId: 's', title: 'Сериал', seasonReviews: [
        SeasonReview(id: 'a', from: 1, to: 1, reviewMeta: meta(9.6)),
        SeasonReview(id: 'b', from: 1, to: 1, pass: 3, reviewMeta: meta(9.8)),
        SeasonReview(id: 'c', from: 2, to: 2, reviewMeta: meta(8.4)),
        SeasonReview(id: 'd', from: 2, to: 2, pass: 2, reviewMeta: meta(9.0)),
      ]);
      expect(s.seasonReviewsAverage, 9.4);
    });
  });
}
