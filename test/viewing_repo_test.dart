import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/utils/movie_reviews.dart';

/// Просмотры в репозитории: фильм и серия по id, просмотр сезона, проекция.
void main() {
  final v1 = Viewing(date: DateTime(2026, 4, 15, 11, 22), score: 8.8);
  final v2 = Viewing(
    date: DateTime(2026, 5, 16, 22, 26),
    score: 8.5,
    diary: DiaryEntry(moods: ['🔥'], place: 'home', note: 'личное'),
  );

  MovieRepository movieRepo({double? score, List<Viewing>? viewings}) =>
      MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'm',
            title: 'Легенда об Аанге',
            status: viewings != null && viewings.isEmpty
                ? LibraryStatus.library
                : LibraryStatus.watched,
            viewings: viewings ??
                [
                  Viewing.fromAny(v1.toJson()),
                  Viewing.fromAny(v2.toJson()),
                ],
            score: score,
          ).toJson(),
        ],
      });

  Episode ep(int n, List<DateTime?> dates, {double? score}) => Episode(
        season: 1,
        number: n,
        watchedAt: dates.first,
        score: score,
        rewatchViews: [for (final d in dates.skip(1)) Viewing(date: d)],
      );

  MovieRepository seriesRepo(List<Episode> eps) => MovieRepository.detached({
        'series': [
          LibrarySeries(tvShowId: 's', title: 'Аркейн', episodes: eps).toJson(),
        ],
      });

  group('фильм', () {
    test('новый просмотр получает номер по дате и свой id', () async {
      final repo = movieRepo();
      final was = await repo.addViewing('m', DateTime(2020, 1, 1));
      final m = repo.byUuid('m')!;
      expect(was, isTrue);
      expect(m.viewings.length, 3);
      expect(m.rewatchCount, 2);
      final added = m.orderedViewings.first;
      expect(added.date, DateTime(2020, 1, 1));
      expect(added.id, isNot(anyOf(v1.id, v2.id)));
      // Оценка фильма остаётся от последнего по дате просмотра.
      expect(m.currentScore, 8.5);
    });

    test('первый просмотр забирает оценку, поставленную до него', () async {
      final repo = movieRepo(score: 7.0, viewings: []);
      expect(repo.byUuid('m')!.score, 7.0);
      await repo.addViewing('m', DateTime(2026, 1, 1));
      final m = repo.byUuid('m')!;
      expect(m.viewings.single.score, 7.0);
      expect(m.score, isNull);
    });

    test('оценка, дата и дневник меняются у своего просмотра', () async {
      final repo = movieRepo();
      final m = repo.byUuid('m')!;
      final first = m.viewingById(v1.id)!;
      await repo.setViewingScore('m', first, 9.9);
      await repo.setViewingDate('m', first, null);
      await repo.setViewingDiary('m', first, DiaryEntry(moods: ['😍']));
      expect(first.score, 9.9);
      expect(first.date, isNull);
      expect(first.diary!.moods, ['😍']);
      expect(m.viewingById(v2.id)!.score, 8.5);
      await repo.setViewingDiary('m', first, DiaryEntry());
      expect(first.diary, isNull);
    });

    // Синхронизация и «Вернуть» пересоздают объекты библиотеки. Экран, который
    // держал прежний просмотр, обязан писать в новый, а не в пустоту.
    test('оценка, дата и дневник пишутся и после подмены объектов', () async {
      final repo = movieRepo();
      final stale = repo.byUuid('m')!.viewingById(v2.id)!;
      await repo.mergeSyncSnapshot(const {});
      expect(identical(repo.byUuid('m')!.viewingById(v2.id), stale), isFalse);
      await repo.setViewingScore('m', stale, 9.5);
      await repo.setViewingDate('m', stale, DateTime(2026, 6, 1));
      await repo.setViewingDiary('m', stale, DiaryEntry(note: 'новое'));
      final live = repo.byUuid('m')!.viewingById(v2.id)!;
      expect(live.score, 9.5);
      expect(live.date, DateTime(2026, 6, 1));
      expect(live.diary!.note, 'новое');
      expect(await repo.removeViewing('m', stale), isNotNull);
      expect(repo.byUuid('m')!.viewingById(v2.id), isNull);
    });

    test('удалённый просмотр возвращается на место вместе с дневником',
        () async {
      final repo = movieRepo();
      final m = repo.byUuid('m')!;
      final removed = await repo.removeViewing('m', m.viewingById(v2.id)!);
      expect(repo.byUuid('m')!.viewings.length, 1);
      expect(removed, isNotNull);
      await repo.restoreViewing('m', removed!);
      final back = repo.byUuid('m')!;
      expect([for (final v in back.viewings) v.id], [v1.id, v2.id]);
      expect(back.viewingById(v2.id)!.diary!.note, 'личное');
      expect(back.viewingById(v2.id)!.score, 8.5);
    });

    // Плашка «Вернуть» может провисеть долго. Всё, что человек успел сделать
    // с фильмом после удаления, остаётся при нём.
    test('«Вернуть» не стирает сделанное после удаления', () async {
      final repo = movieRepo();
      final m = repo.byUuid('m')!;
      final removed = await repo.removeViewing('m', m.viewingById(v2.id)!);
      await repo.toggleFavorite('m');
      await repo.addViewing('m', DateTime(2026, 9, 1), score: 7.0);
      await repo.restoreViewing('m', removed!);
      final back = repo.byUuid('m')!;
      expect(back.favorite, isTrue);
      expect(back.viewings.length, 3);
      expect(back.currentScore, 7.0);
      // Повторное нажатие второй раз просмотр не добавляет.
      await repo.restoreViewing('m', removed);
      expect(repo.byUuid('m')!.viewings.length, 3);
    });

    test('вместе с просмотром возвращается его рецензия', () async {
      final repo = movieRepo();
      await repo.saveMovieReview('m',
          viewId: v1.id, text: 'про первый', meta: ReviewMeta());
      await repo.saveMovieReview('m',
          viewId: v2.id, text: 'про второй', meta: ReviewMeta());
      final removed = await repo.removeViewing(
          'm', repo.byUuid('m')!.viewingById(v2.id)!);
      expect(repo.byUuid('m')!.allReviews.single.review, 'про первый');
      await repo.restoreViewing('m', removed!);
      final m = repo.byUuid('m')!;
      expect(reviewOfViewing(m, v2.id)!.review, 'про второй');
      expect(reviewOfViewing(m, v1.id)!.review, 'про первый');
    });

    test('единственный просмотр возвращается вместе со статусом', () async {
      final repo = movieRepo(viewings: [Viewing.fromAny(v1.toJson())]);
      final removed = await repo.removeViewing(
          'm', repo.byUuid('m')!.viewingById(v1.id)!);
      expect(repo.byUuid('m')!.status, LibraryStatus.library);
      await repo.restoreViewing('m', removed!);
      expect(repo.byUuid('m')!.status, LibraryStatus.watched);
      expect(repo.byUuid('m')!.viewings.single.id, v1.id);
    });

    test('удаление просмотра убирает и его рецензию', () async {
      final repo = movieRepo();
      await repo.saveMovieReview('m',
          viewId: v2.id, text: 'про второй', meta: ReviewMeta());
      await repo.saveMovieReview('m',
          viewId: v1.id, text: 'про первый', meta: ReviewMeta());
      final m = repo.byUuid('m')!;
      await repo.removeViewing('m', m.viewingById(v2.id)!);
      expect(m.allReviews.length, 1);
      expect(m.allReviews.single.review, 'про первый');
    });

    test('«Отменить просмотр» убирает последний по дате', () async {
      final repo = movieRepo();
      expect(await repo.undoLastViewing('m'), isFalse);
      final m = repo.byUuid('m')!;
      expect(m.viewings.single.id, v1.id);
      expect(await repo.undoLastViewing('m'), isTrue);
      expect(m.viewings, isEmpty);
      expect(m.status, LibraryStatus.library);
    });
  });

  group('серия', () {
    final d1 = DateTime(2023, 5, 29), d2 = DateTime(2023, 10, 2);

    test('оценка и дата по id просмотра: первый и повтор', () async {
      final repo = seriesRepo([ep(1, [d1, d2], score: 10.0)]);
      final e = repo.seriesById('s')!.episodes.single;
      final rewatchId = e.rewatchViews.single.id;
      await repo.setEpisodeViewScoreById('s', 1, 1, rewatchId, 9.0);
      await repo.setEpisodeViewDateById('s', 1, 1, e.vid, null);
      expect(e.rewatchViews.single.score, 9.0);
      expect(e.score, 10.0);
      expect(e.watchedAt, isNull);
      expect(e.currentScore, 9.0);
    });

    test('дневник пишется в свой просмотр, а не в первый', () async {
      final repo = seriesRepo([ep(1, [d1, d2])]);
      final e = repo.seriesById('s')!.episodes.single;
      await repo.setEpisodeViewDiaryById(
          's', 1, 1, e.rewatchViews.single.id, DiaryEntry(moods: ['🔥']));
      expect(e.diary, isNull);
      expect(e.rewatchViews.single.diary!.moods, ['🔥']);
    });

    test('удаление первого просмотра поднимает повтор без чужой оценки',
        () async {
      final repo = seriesRepo([ep(1, [d1, d2], score: 10.0)]);
      final e = repo.seriesById('s')!.episodes.single;
      final rewatchId = e.rewatchViews.single.id;
      final firstId = e.vid;
      final removed = await repo.removeEpisodeViewById('s', 1, 1, e.vid);
      expect(e.watchCount, 1);
      expect(e.vid, rewatchId);
      expect(e.watchedAt, d2);
      expect(e.score, isNull);
      // «Вернуть» ставит просмотр обратно первым, повтор снова повтор.
      await repo.restoreEpisodeView('s', 1, 1, removed!);
      final back = repo.seriesById('s')!.episodes.single;
      expect(back.watchCount, 2);
      expect(back.vid, firstId);
      expect(back.watchedAt, d1);
      expect(back.score, 10.0);
      expect(back.rewatchViews.single.id, rewatchId);
      expect(back.rewatchViews.single.date, d2);
    });

    test('«Вернуть» просмотр серии не трогает остальные серии', () async {
      final repo = seriesRepo([ep(5, [d1, d2])]);
      final e = repo.seriesById('s')!.episodes.single;
      final removed =
          await repo.removeEpisodeViewById('s', 1, 5, e.rewatchViews.single.id);
      await repo.markEpisodesBulk('s', [
        [1, 6],
        [1, 7],
        [1, 8],
      ], at: DateTime(2026, 8, 1, 20));
      await repo.restoreEpisodeView('s', 1, 5, removed!);
      final s = repo.seriesById('s')!;
      expect(s.episodes.length, 4, reason: 'серии 6–8 остались');
      expect(s.watchedEpisode(1, 5)!.watchCount, 2);
    });

    test('единственный просмотр серии возвращается вместе с серией', () async {
      final repo = seriesRepo([
        Episode(season: 1, number: 1, watchedAt: d1, score: 9.0, runtimeMin: 42),
      ]);
      final e = repo.seriesById('s')!.episodes.single;
      final removed = await repo.removeEpisodeViewById('s', 1, 1, e.vid);
      expect(repo.seriesById('s')!.episodes, isEmpty);
      await repo.restoreEpisodeView('s', 1, 1, removed!);
      final back = repo.seriesById('s')!.episodes.single;
      expect(back.watchedAt, d1);
      expect(back.score, 9.0);
      expect(back.runtimeMin, 42);
    });

    test('удаление единственного просмотра снимает серию', () async {
      final repo = seriesRepo([ep(1, [d1]), ep(2, [d1])]);
      final e = repo.seriesById('s')!.watchedEpisode(1, 1)!;
      await repo.removeEpisodeViewById('s', 1, 1, e.vid);
      expect(repo.seriesById('s')!.isEpisodeWatched(1, 1), isFalse);
      expect(repo.seriesById('s')!.isEpisodeWatched(1, 2), isTrue);
    });

    // Настройка «Снимать серии по порядку»: снял серию, и все после неё
    // снимаются тоже. Так обещала настройка «по порядку», а на деле серии
    // после оставались отмеченными.
    group('снятие по порядку', () {
      Episode at(int season, int number) => Episode(
            season: season,
            number: number,
            watchedAt: DateTime(2026, season, number, 20),
            score: 8.0,
          );

      MovieRepository titans() => seriesRepo([
            at(1, 1),
            at(1, 2),
            at(1, 3),
            at(2, 1),
            at(2, 2),
            at(5, 1),
            Episode(watchedAt: DateTime(2020, 1, 1)),
          ]);

      List<String> marks(MovieRepository repo) => [
            for (final e in repo.seriesById('s')!.episodes)
              '${e.season}·${e.number}',
          ];

      test('после серии считаются отмеченные серии всех сезонов', () {
        final repo = titans();
        expect(repo.watchedAfter('s', 1, 2), 4);
        expect(repo.watchedAfter('s', 2, 2), 1);
        expect(repo.watchedAfter('s', 5, 1), 0);
        expect(repo.watchedAfterSeason('s', 1), 3);
        expect(repo.watchedAfterSeason('s', 5), 0);
      });

      test('серия снимается вместе со всеми после неё', () async {
        final repo = titans();
        final snap = await repo.unmarkFrom('s', 1, 2);
        // Серии до неё и серия без номера остаются.
        expect(marks(repo), ['1·1', 'null·null']);
        await repo.restoreFromSnapshot(const [], [snap!]);
        expect(marks(repo).length, 7);
        expect(repo.seriesById('s')!.watchedEpisode(5, 1)!.score, 8.0);
      });

      test('сезон снимается вместе со всеми сезонами после него', () async {
        final repo = titans();
        await repo.unmarkFrom('s', 2);
        expect(marks(repo), ['1·1', '1·2', '1·3', 'null·null']);
      });

      test('снимать нечего: снимка нет, библиотека как была', () async {
        final repo = titans();
        expect(await repo.unmarkFrom('s', 6), isNull);
        expect(marks(repo).length, 7);
      });
    });

    test('серии, отмеченные пачкой, получают выбранную дату', () async {
      final repo = seriesRepo([]);
      final at = DateTime(2026, 8, 1, 20);
      await repo.markEpisodesBulk('s', [
        [1, 1],
        [1, 2],
        [1, 3],
      ], at: at);
      final eps = repo.seriesById('s')!.episodes;
      expect(eps.length, 3);
      expect([for (final e in eps) e.watchedAt!.day], [1, 1, 1]);
      expect(eps[2].watchedAt!.isAfter(eps[0].watchedAt!), isTrue);
    });

    test('пачка без даты остаётся без даты', () async {
      final repo = seriesRepo([]);
      await repo.markEpisodesBulk('s', [
        [1, 1],
        [1, 2],
      ], undated: true);
      expect(
          repo.seriesById('s')!.episodes.every((e) => e.watchedAt == null),
          isTrue);
    });

    test('пересмотр сезона доводит все серии до одного числа', () async {
      final d3 = DateTime(2026, 8, 18);
      final repo = seriesRepo([
        ep(1, [d1, d2, d3]),
        ep(2, [d1, d2]),
        ep(3, [d1, d2]),
      ]);
      final n = await repo.completeSeasonPass(
          's', 1, [1, 2, 3], DateTime(2026, 8, 20));
      final eps = repo.seriesById('s')!.episodes;
      expect(n, 2);
      expect([for (final e in eps) e.watchCount], [3, 3, 3]);
      expect(eps[0].rewatchViews.last.date, d3,
          reason: 'серия, которая уже в этом просмотре, не трогается');
    });

    test('серию, которую смотрели чаще остальных, пересмотр не трогает',
        () async {
      final repo = seriesRepo([
        ep(1, [d1, d2, d2, d2, d2]),
        ep(2, [d1]),
      ]);
      await repo.completeSeasonPass('s', 1, [1, 2], null);
      final eps = repo.seriesById('s')!.episodes;
      expect([for (final e in eps) e.watchCount], [5, 2]);
      expect(eps[1].rewatchViews.single.date, isNull);
    });

    test('оценка сезона ставится последнему просмотру каждой серии',
        () async {
      final repo = seriesRepo([ep(1, [d1, d2], score: 7.0), ep(2, [d1])]);
      await repo.setSeasonScore('s', 1, 9.5);
      final eps = repo.seriesById('s')!.episodes;
      expect(eps[0].score, 7.0);
      expect(eps[0].rewatchViews.single.score, 9.5);
      expect(eps[1].score, 9.5);
      expect(repo.seriesById('s')!.episodeScoreAvg, 9.5);
    });
  });

  group('импорт из другого трекера', () {
    MovieRepository withDune(List<Viewing> viewings) =>
        MovieRepository.detached({
          'movies': [
            LibraryMovie(
              uuid: 'm',
              title: 'Дюна',
              year: 2021,
              status: LibraryStatus.watched,
              enrichTried: true,
              viewings: viewings,
            ).toJson(),
          ],
        });

    LibraryMovie incoming(List<Viewing> viewings, {double? score}) =>
        LibraryMovie(
          uuid: 'x',
          title: 'Дюна',
          year: 2021,
          status: LibraryStatus.watched,
          enrichTried: true,
          viewings: viewings,
          score: score,
        );

    test('оценка из файла ложится в просмотр с той же датой', () async {
      final d = DateTime(2024, 3, 1);
      final repo = withDune([Viewing(date: d)]);
      final (added, updated) =
          await repo.importMovies([incoming([Viewing(date: d)], score: 9.0)]);
      final m = repo.byUuid('m')!;
      expect((added, updated), (0, 1));
      expect(m.viewings.length, 1, reason: 'дубля просмотра нет');
      expect(m.currentScore, 9.0);
    });

    test('оценка из файла ложится в просмотр без даты', () async {
      final repo = withDune([Viewing()]);
      await repo.importMovies([incoming([Viewing()], score: 8.0)]);
      final m = repo.byUuid('m')!;
      expect(m.viewings.length, 1);
      expect(m.currentScore, 8.0);
    });

    test('своя оценка просмотра импортом не затирается', () async {
      final d = DateTime(2024, 3, 1);
      final repo = withDune([Viewing(date: d, score: 7.0)]);
      await repo.importMovies([incoming([Viewing(date: d)], score: 9.0)]);
      expect(repo.byUuid('m')!.currentScore, 7.0);
    });
  });

  group('что видят друзья', () {
    test('дневник просмотров не уезжает', () {
      final repo = MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'm',
            title: 'Фильм',
            status: LibraryStatus.watched,
            viewings: [Viewing.fromAny(v2.toJson())],
          ).toJson(),
        ],
        'series': [
          LibrarySeries(tvShowId: 's', title: 'Сериал', episodes: [
            Episode(
              season: 1,
              number: 1,
              watchedAt: DateTime(2026, 1, 1),
              diary: DiaryEntry(note: 'личное'),
              rewatchViews: [
                Viewing(
                    date: DateTime(2026, 2, 1),
                    diary: DiaryEntry(note: 'тоже личное')),
              ],
            ),
          ]).toJson(),
        ],
      });
      final p = repo.buildPublicProfile();
      final viewing = ((p['movies'] as List).single['viewings'] as List).single;
      expect((viewing as Map).containsKey('diary'), isFalse);
      expect(viewing['score'], 8.5);
      final episode =
          ((p['series'] as List).single['episodes'] as List).single as Map;
      expect(episode.containsKey('diary'), isFalse);
      expect(((episode['rewatchViews'] as List).single as Map)
          .containsKey('diary'), isFalse);
    });

    test('доп. рецензии проходят то же сито, что и первая', () {
      final a = Viewing(date: DateTime(2026, 1, 1));
      final b = Viewing(date: DateTime(2026, 2, 1));
      final c = Viewing(date: DateTime(2026, 3, 1));
      final repo = MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'm',
            title: 'Фильм',
            status: LibraryStatus.watched,
            viewings: [a, b, c],
            review: 'открытая',
            reviewMeta: ReviewMeta(viewId: a.id),
            moreReviews: [
              ExtraReview(
                  id: 'x1',
                  review: 'черновик',
                  reviewMeta: ReviewMeta(viewId: b.id, draft: true)),
              ExtraReview(
                  id: 'x2',
                  review: 'тоже открытая',
                  reviewMeta: ReviewMeta(viewId: c.id)),
            ],
          ).toJson(),
        ],
      });
      final movie = (repo.buildPublicProfile()['movies'] as List).single as Map;
      expect(movie['review'], 'открытая');
      // Черновик не уехал; id наружу уходит порядковый, а не свой.
      final more = movie['moreReviews'] as List;
      expect([for (final r in more) (r as Map)['review']], ['тоже открытая']);
    });
  });
}
