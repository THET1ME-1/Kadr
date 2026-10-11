import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Восстановление из копии и загрузка файла библиотеки. Главное правило:
/// что бы ни лежало в файле, библиотека в памяти не остаётся обрубком,
/// которым следующая запись на диск затёрла бы настоящую базу.
void main() {
  Map<String, dynamic> movie(String uuid, {List<Viewing>? viewings}) =>
      LibraryMovie(
        uuid: uuid,
        title: 'Фильм $uuid',
        status: LibraryStatus.watched,
        enrichTried: true,
        viewings: viewings ?? [Viewing(date: DateTime(2024, 3, 1), score: 8.0)],
      ).toJson();

  Map<String, dynamic> series(String id) => LibrarySeries(
        tvShowId: id,
        title: 'Сериал $id',
        enrichTried: true,
        episodes: [
          Episode(season: 1, number: 1, watchedAt: DateTime(2024, 4, 1)),
        ],
      ).toJson();

  /// Запись, на которой разбор падает: серии лежат строкой, а не списком.
  const brokenSeries = {'tvShowId': 'bad', 'title': 'Битый', 'episodes': 'мусор'};

  MovieRepository mine() => MovieRepository.detached({
        'movies': [movie('a'), movie('b')],
        'series': [series('s1')],
        'lists': [
          const MovieList(name: 'Любимое', movieUuids: ['a']).toJson(),
        ],
      });

  group('синхронизация', () {
    test('битая запись в чужом снимке библиотеку не трогает', () async {
      final repo = mine();
      await expectLater(
        repo.mergeSyncSnapshot({
          'movies': [movie('c')],
          'series': [brokenSeries],
        }),
        throwsA(anything),
      );
      expect([for (final m in repo.movies) m.uuid], ['a', 'b']);
      expect([for (final s in repo.series) s.tvShowId], ['s1']);
      expect(repo.lists.single.name, 'Любимое');
    });
  });

  group('восстановление из копии', () {
    String backup(Map<String, dynamic> data) =>
        jsonEncode({'app': 'kadr', 'version': 1, ...data});

    test('замена оставляет только то, что в копии', () async {
      final repo = mine();
      final res = await repo.restoreBackup(
        backup({
          'movies': [movie('z')],
          'series': const [],
          'lists': const [],
        }),
        merge: false,
      );
      expect(res.ok, isTrue);
      expect(res.skipped, 0);
      expect([for (final m in repo.movies) m.uuid], ['z']);
      expect(repo.series, isEmpty);
      expect(repo.lists, isEmpty);
    });

    test('добавление складывает копию с библиотекой и ничего не теряет',
        () async {
      final repo = mine();
      final res = await repo.restoreBackup(
        backup({
          'movies': [
            movie('a', viewings: [Viewing(date: DateTime(2020, 1, 1))]),
            movie('z'),
          ],
          'series': [series('s2')],
          'lists': [
            const MovieList(name: 'Любимое', movieUuids: ['z']).toJson(),
          ],
        }),
        merge: true,
      );
      expect(res.ok, isTrue);
      expect({for (final m in repo.movies) m.uuid}, {'a', 'b', 'z'});
      expect(repo.byUuid('a')!.viewings.length, 2,
          reason: 'свой просмотр и просмотр из копии');
      expect({for (final s in repo.series) s.tvShowId}, {'s1', 's2'});
      expect(repo.lists.single.movieUuids, unorderedEquals(['a', 'z']));
    });

    test('битая запись пропускается, остальное восстанавливается', () async {
      for (final merge in [false, true]) {
        final repo = mine();
        final res = await repo.restoreBackup(
          backup({
            'movies': [movie('z')],
            'series': [brokenSeries, series('s2')],
          }),
          merge: merge,
        );
        expect(res.ok, isTrue);
        expect(res.skipped, 1);
        expect(repo.byUuid('z'), isNotNull);
        expect(repo.seriesById('s2'), isNotNull);
        expect(repo.seriesById('bad'), isNull);
      }
    });

    test('файл, в котором нет библиотеки, базу не трогает', () async {
      for (final raw in ['{"foo": 1}', '{"movies": [', 'не json', '[1, 2]']) {
        final repo = mine();
        final res = await repo.restoreBackup(raw, merge: false);
        expect(res.ok, isFalse, reason: raw);
        expect([for (final m in repo.movies) m.uuid], ['a', 'b'], reason: raw);
        expect(repo.series.single.tvShowId, 's1', reason: raw);
      }
    });

    test('копия, в которой не прочиталась ни одна запись, базу не заменяет',
        () async {
      final repo = mine();
      final res = await repo.restoreBackup(
        backup({
          'movies': const [],
          'series': [brokenSeries],
        }),
        merge: false,
      );
      expect(res.ok, isFalse);
      expect([for (final m in repo.movies) m.uuid], ['a', 'b']);
    });
  });

  group('загрузка файла библиотеки', () {
    late Directory docs;
    const paths = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      docs = await Directory.systemTemp.createTemp('kadr_load_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, (_) async => docs.path);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paths, null);
      await docs.delete(recursive: true);
    });

    File library() => File('${docs.path}/library.json');
    File kept() => File('${docs.path}/library.unreadable.json');

    test('запись с ошибкой пропускается, файл остаётся копией', () async {
      final original = jsonEncode({
        'movies': [movie('a'), movie('b')],
        'series': [series('s1'), brokenSeries, series('s2')],
        'lists': const [],
      });
      await library().writeAsString(original);
      final repo = MovieRepository.fresh();
      await repo.load();
      expect([for (final m in repo.movies) m.uuid], ['a', 'b']);
      expect([for (final s in repo.series) s.tvShowId], ['s1', 's2']);
      expect(repo.loadSkipped, 1);
      expect(await kept().readAsString(), original,
          reason: 'исходный файл сохранён до первой записи');
      // Правка перезаписывает библиотеку без битой записи; копия остаётся.
      await repo.toggleFavorite('a');
      expect(await library().readAsString(), isNot(contains('Битый')));
      expect(await kept().readAsString(), original);
    });

    test('нечитаемый файл не затирается и уходит в копию', () async {
      const original = '{"movies": [{"uuid": "a", "title": "Обрыв';
      await library().writeAsString(original);
      final repo = MovieRepository.fresh();
      await repo.load();
      expect(repo.isLoaded, isTrue);
      expect(repo.movies, isEmpty);
      expect(repo.loadFailed, isTrue);
      expect(await kept().readAsString(), original);
      expect(await library().readAsString(), original,
          reason: 'пустая библиотека поверх файла не пишется');
    });

    test('целый файл читается как раньше, копии не появляется', () async {
      await library().writeAsString(jsonEncode({
        'movies': [movie('a')],
        'series': [series('s1')],
        'lists': const [],
      }));
      final repo = MovieRepository.fresh();
      await repo.load();
      expect(repo.movies.single.uuid, 'a');
      expect(repo.loadSkipped, 0);
      expect(repo.loadFailed, isFalse);
      expect(kept().existsSync(), isFalse);
    });
  });
}
