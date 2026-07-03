import 'package:flutter_test/flutter_test.dart';
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
}
