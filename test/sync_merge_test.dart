import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/sync/sync_merge.dart';

Map<String, dynamic> movie(String uuid,
        {String status = 'watched',
        List<Map<String, dynamic>> viewings = const [],
        bool favorite = false,
        List<String> lists = const []}) =>
    {
      'uuid': uuid,
      'title': 'M$uuid',
      'status': status,
      'viewings': viewings,
      'favorite': favorite,
      'lists': lists,
    };

Map<String, dynamic> viewing(String date, double? score) =>
    {'date': date, 'score': score};

Map<String, dynamic> series(String id,
        {List<Map<String, dynamic>> episodes = const [],
        bool favorite = false}) =>
    {
      'tvShowId': id,
      'title': 'S$id',
      'episodes': episodes,
      'favorite': favorite,
    };

Map<String, dynamic> ep(int s, int n, {String? watchedAt, double? score}) =>
    {'season': s, 'number': n, 'watchedAt': watchedAt, 'score': score};

void main() {
  group('mergeSnapshots — объединение без потерь', () {
    test('пустой remote → локальные фильмы сохраняются', () {
      final local = {
        'movies': [movie('a')],
        'series': [],
        'lists': []
      };
      final stats = SyncStats();
      final out = mergeSnapshots(local, {}, stats);
      expect((out['movies'] as List).length, 1);
      expect(stats.changed, isFalse);
    });

    test('фильм только на удалённом → добавляется', () {
      final local = {'movies': [movie('a')]};
      final remote = {'movies': [movie('b')]};
      final stats = SyncStats();
      final out = mergeSnapshots(local, remote, stats);
      final ids = (out['movies'] as List).map((m) => m['uuid']).toSet();
      expect(ids, {'a', 'b'});
      expect(stats.addedMovies, 1);
    });

    test('общий фильм → просмотры объединяются, дубли схлопываются', () {
      final v1 = viewing('2024-01-01T10:00:00.000', 8.0);
      final v2 = viewing('2024-02-01T10:00:00.000', 9.0);
      final local = {'movies': [movie('a', viewings: [v1, v2])]};
      // remote содержит v2 (дубль) + новый v3.
      final v3 = viewing('2024-03-01T10:00:00.000', 7.0);
      final remote = {'movies': [movie('a', viewings: [v2, v3], favorite: true)]};
      final stats = SyncStats();
      final out = mergeSnapshots(local, remote, stats);
      final m = (out['movies'] as List).single as Map;
      expect((m['viewings'] as List).length, 3, reason: 'v1+v2+v3, без дублей');
      expect(m['favorite'], true, reason: 'favorite = ИЛИ');
      expect(stats.mergedMovies, 1);
    });

    test('списки фильма и списки верхнего уровня объединяются', () {
      final local = {
        'movies': [movie('a', lists: ['Топ'])],
        'lists': [
          {'name': 'Топ', 'movieUuids': ['a']}
        ]
      };
      final remote = {
        'movies': [movie('a', lists: ['Вечернее'])],
        'lists': [
          {'name': 'Топ', 'movieUuids': ['x']}
        ]
      };
      final out = mergeSnapshots(local, remote, SyncStats());
      final m = (out['movies'] as List).single as Map;
      expect((m['lists'] as List).toSet(), {'Топ', 'Вечернее'});
      final top = (out['lists'] as List)
          .firstWhere((l) => l['name'] == 'Топ') as Map;
      expect((top['movieUuids'] as List).toSet(), {'a', 'x'});
    });

    test('серии сериала объединяются по (сезон,номер), общая — ранняя дата', () {
      final local = {
        'series': [
          series('s1', episodes: [
            ep(1, 1, watchedAt: '2024-02-01T00:00:00.000'),
            ep(1, 2),
          ])
        ]
      };
      final remote = {
        'series': [
          series('s1', favorite: true, episodes: [
            ep(1, 1, watchedAt: '2024-01-01T00:00:00.000', score: 9.0), // раньше
            ep(1, 3),
          ])
        ]
      };
      final out = mergeSnapshots(local, remote, SyncStats());
      final s = (out['series'] as List).single as Map;
      final eps = (s['episodes'] as List).cast<Map>();
      expect(eps.length, 3, reason: 'E1,E2,E3');
      expect(s['favorite'], true);
      final e1 = eps.firstWhere((e) => e['season'] == 1 && e['number'] == 1);
      expect(e1['watchedAt'], '2024-01-01T00:00:00.000',
          reason: 'у общей серии — ранняя дата');
      expect(e1['score'], 9.0, reason: 'непустая оценка сохраняется');
    });

    test('слияние сериала не теряет «Буду смотреть», год и досмотренность', () {
      final local = {
        'series': [
          {
            ...series('s1', episodes: [ep(1, 1)]),
            'watchlist': true,
            'year': 2022,
            'imdbId': 'tt777',
          }
        ]
      };
      final remote = {
        'series': [
          {
            ...series('s1', episodes: [ep(1, 2)]),
            'finished': true,
            'tvdbId': 555,
          }
        ]
      };
      final s = (mergeSnapshots(local, remote, SyncStats())['series'] as List)
          .single as Map;
      expect(s['watchlist'], true, reason: 'иначе сериал выпадает из списка');
      expect(s['finished'], true);
      expect(s['year'], 2022);
      expect(s['imdbId'], 'tt777');
      expect(s['tvdbId'], 555);
    });

    test('слияние сериала берёт свежие сведения о выходе и всю историю «Догнал»',
        () {
      final local = {
        'series': [
          {
            ...series('s1'),
            'air': {'status': 'Returning Series', 'aired': 8,
                'checkedAt': '2026-10-01T00:00:00.000'},
            'caughtUpAt': ['2026-05-01T21:00:00.000'],
          }
        ]
      };
      final remote = {
        'series': [
          {
            ...series('s1'),
            'air': {'status': 'Returning Series', 'aired': 9,
                'checkedAt': '2026-10-08T00:00:00.000'},
            'caughtUpAt': ['2026-09-01T21:00:00.000'],
          }
        ]
      };
      final s = (mergeSnapshots(local, remote, SyncStats())['series'] as List)
          .single as Map;
      expect((s['air'] as Map)['aired'], 9);
      expect(s['caughtUpAt'], [
        '2026-05-01T21:00:00.000',
        '2026-09-01T21:00:00.000',
      ]);
    });

    test('дата добавления сериала при слиянии берётся ранняя', () {
      final local = {
        'series': [
          {...series('s1'), 'addedAt': '2026-03-01T00:00:00.000'}
        ]
      };
      final remote = {
        'series': [
          {...series('s1'), 'addedAt': '2026-01-01T00:00:00.000'}
        ]
      };
      final s = (mergeSnapshots(local, remote, SyncStats())['series'] as List)
          .single as Map;
      expect(s['addedAt'], '2026-01-01T00:00:00.000');
    });

    test('слияние коммутативно по числу записей (A◁B == B◁A)', () {
      final a = {
        'movies': [movie('a'), movie('b')],
        'series': [series('s1', episodes: [ep(1, 1)])]
      };
      final b = {
        'movies': [movie('b'), movie('c')],
        'series': [series('s1', episodes: [ep(1, 2)])]
      };
      final ab = mergeSnapshots(a, b, SyncStats());
      final ba = mergeSnapshots(b, a, SyncStats());
      expect((ab['movies'] as List).length, (ba['movies'] as List).length);
      expect(
          ((ab['series'] as List).single as Map)['episodes'].length,
          ((ba['series'] as List).single as Map)['episodes'].length);
    });
  });

  group('просмотры по id', () {
    Map<String, dynamic> mergedMovie(
            Map<String, dynamic> a, Map<String, dynamic> b) =>
        (mergeSnapshots({
          'movies': [a]
        }, {
          'movies': [b]
        }, SyncStats())['movies'] as List)
            .single as Map<String, dynamic>;

    Map<String, dynamic> mergedSeries(
            Map<String, dynamic> a, Map<String, dynamic> b) =>
        (mergeSnapshots({
          'series': [a]
        }, {
          'series': [b]
        }, SyncStats())['series'] as List)
            .single as Map<String, dynamic>;

    test('правка оценки на одном устройстве не даёт второй просмотр', () {
      const date = '2024-01-01T10:00:00.000';
      final m = mergedMovie(
        movie('a', viewings: [viewing(date, 9.0)]),
        movie('a', viewings: [viewing(date, 8.0)]),
      );
      final views = m['viewings'] as List;
      expect(views.length, 1);
      expect((views.single as Map)['score'], 9.0, reason: 'побеждает локальная');
    });

    test('правка даты не даёт второй просмотр: записи узнаются по id', () {
      final m = mergedMovie(
        movie('a', viewings: [
          {'id': 'v1', 'date': '2020-05-05T10:00:00.000', 'score': 8.0}
        ]),
        movie('a', viewings: [
          {'id': 'v1', 'date': '2024-01-01T10:00:00.000', 'score': 8.0}
        ]),
      );
      expect((m['viewings'] as List).length, 1);
      expect(((m['viewings'] as List).single as Map)['date'],
          '2020-05-05T10:00:00.000');
    });

    test('дневник просмотра фильма переживает слияние с любой стороны', () {
      const date = '2024-01-01T10:00:00.000';
      final withDiary = {
        'date': date,
        'score': 8.0,
        'diary': {'note': 'личное', 'moods': ['🔥']},
      };
      for (final pair in [
        (withDiary, viewing(date, 8.0)),
        (viewing(date, 8.0), withDiary),
      ]) {
        final m = mergedMovie(
            movie('a', viewings: [pair.$1]), movie('a', viewings: [pair.$2]));
        final v = (m['viewings'] as List).single as Map;
        expect((v['diary'] as Map)['note'], 'личное');
      }
    });

    test('мост между источниками и свой постер не теряются', () {
      final a = movie('a')
        ..['imdbId'] = 'tt1'
        ..['posterFile'] = 'p.jpg';
      final b = movie('a')..['tvdbId'] = 77;
      final m = mergedMovie(a, b);
      expect(m['imdbId'], 'tt1');
      expect(m['posterFile'], 'p.jpg');
      expect(m['tvdbId'], 77);
      final back = mergedMovie(b, a);
      expect(back['imdbId'], 'tt1');
      expect(back['tvdbId'], 77);
    });

    test('просмотры серии объединяются, дневник и оценки остаются', () {
      final a = series('s', episodes: [
        ep(1, 1, watchedAt: '2023-05-29T13:41:00.000', score: 10.0)
          ..['diary'] = {'note': 'первый раз'}
          ..['rewatchViews'] = [
            {'id': 'r1', 'date': '2023-10-02T17:44:00.000', 'score': 9.0}
          ],
      ]);
      final b = series('s', episodes: [
        ep(1, 1, watchedAt: '2023-05-29T13:41:00.000', score: 10.0)
          ..['rewatchViews'] = [
            {'id': 'r1', 'date': '2023-10-02T17:44:00.000'},
            {
              'id': 'r2',
              'date': '2026-08-18T15:47:00.000',
              'diary': {'note': 'третий раз'}
            },
          ],
      ]);
      for (final s in [mergedSeries(a, b), mergedSeries(b, a)]) {
        final e = (s['episodes'] as List).single as Map;
        expect((e['diary'] as Map)['note'], 'первый раз');
        final views = (e['rewatchViews'] as List).cast<Map>();
        expect(views.map((v) => v['id']), ['r1', 'r2']);
        expect(views[0]['score'], 9.0);
        expect((views[1]['diary'] as Map)['note'], 'третий раз');
        expect(e['rewatchCount'], 2);
      }
    });

    // На одном устройстве первый просмотр серии удалили, и на его место
    // встал повтор со своим id. Другое устройство об удалении не знает.
    test('после удаления первого просмотра серии id не задваиваются', () {
      final kept = series('s', episodes: [
        ep(1, 1, watchedAt: '2023-05-29T13:41:00.000', score: 10.0)
          ..['rewatchViews'] = [
            {'id': 'r1', 'date': '2023-10-02T17:44:00.000', 'score': 9.0},
          ],
      ]);
      final promoted = series('s', episodes: [
        ep(1, 1, watchedAt: '2023-10-02T17:44:00.000', score: 9.0)
          ..['vid'] = 'r1',
      ]);
      for (final s in [mergedSeries(kept, promoted), mergedSeries(promoted, kept)]) {
        final e = Episode.fromJson(
            ((s['episodes'] as List).single as Map).cast<String, dynamic>());
        final ids = [for (final v in e.views) v.id];
        expect(ids.toSet().length, ids.length, reason: 'id повторяются: $ids');
        // Удаления синхронизация не переносит: оба просмотра на месте, и
        // каждый со своей датой и оценкой.
        expect(e.watchCount, 2);
        final byId = {for (final v in e.views) v.id: v};
        expect(byId['r1']!.date, DateTime(2023, 10, 2, 17, 44));
        expect(byId['r1']!.score, 9.0);
        expect(e.orderedViews.first.date, DateTime(2023, 5, 29, 13, 41));
        expect(e.orderedViews.first.score, 10.0);
      }
    });

    test('доп. рецензии сливаются по id, у общей побеждает свежая', () {
      Map<String, dynamic> extra(String id, String text, String updated) => {
            'id': id,
            'review': text,
            'reviewMeta': {'shared': true, 'updatedAt': updated, 'viewId': id},
          };
      final a = movie('a')
        ..['moreReviews'] = [
          extra('x1', 'старая', '2026-01-01T00:00:00.000'),
          extra('x2', 'только тут', '2026-01-01T00:00:00.000'),
        ];
      final b = movie('a')
        ..['moreReviews'] = [extra('x1', 'свежая', '2026-02-01T00:00:00.000')];
      final more = (mergedMovie(a, b)['moreReviews'] as List).cast<Map>();
      expect(more.length, 2);
      expect(more.firstWhere((r) => r['id'] == 'x1')['review'], 'свежая');
      expect(more.firstWhere((r) => r['id'] == 'x2')['review'], 'только тут');
    });

    test('две первые рецензии на разные просмотры обе выживают', () {
      final views = [
        {'id': 'v1', 'date': '2026-04-15T00:00:00.000'},
        {'id': 'v2', 'date': '2026-08-16T00:00:00.000'},
      ];
      Map<String, dynamic> withMain(String text, String viewId, String at) =>
          movie('a', viewings: views)
            ..['review'] = text
            ..['reviewMeta'] = {
              'shared': true,
              'updatedAt': at,
              'viewId': viewId,
            };
      final m = mergedMovie(
        withMain('про первый', 'v1', '2026-04-15T12:00:00.000'),
        withMain('про второй', 'v2', '2026-08-16T12:00:00.000'),
      );
      expect(m['review'], 'про второй', reason: 'в старых полях свежая');
      final more = (m['moreReviews'] as List).cast<Map>();
      expect(more.single['review'], 'про первый');
      expect((more.single['reviewMeta'] as Map)['viewId'], 'v1');
    });
  });
}
