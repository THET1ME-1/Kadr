import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/store.dart';
import 'package:kadr/services/sync/webdav_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сервер синхронизации в памяти: помнит, что читали и что писали.
class _FakeRemote implements SyncRemote {
  final files = <String, List<int>>{};
  final reads = <String>[];
  final writes = <String>[];

  @override
  Future<List<int>?> read(String path) async {
    reads.add(path);
    return files[path];
  }

  @override
  Future<String?> signature(String path) async {
    final f = files[path];
    return f == null ? null : '${f.length}:${Object.hashAll(f)}';
  }

  @override
  Future<void> write(String path, List<int> data) async {
    writes.add(path);
    files[path] = data;
  }
}

/// Сервер, у которого чтение обрывается.
class _BrokenRemote extends _FakeRemote {
  @override
  Future<List<int>?> read(String path) async => throw StateError('нет связи');
}

/// Сервер, который не умеет отдавать отпечаток файла.
class _NoSignatureRemote extends _FakeRemote {
  @override
  Future<String?> signature(String path) async =>
      files.containsKey(path) ? '' : null;
}

/// Версии до 0.29 склеивали просмотры по паре «дата и оценка» и общую оценку
/// фильма держали отдельным полем. Новый формат хранит оценку в просмотре:
/// получив его, старое устройство задвоило бы просмотр у каждого оценённого
/// фильма. Поэтому новый формат пишется в свой файл, а файл прежних версий
/// только читается.
void main() {
  const seen = '2024-03-01T20:00:00.000';

  List<int> bytes(Map<String, dynamic> m) => utf8.encode(jsonEncode(m));

  Map<String, dynamic> oldMovie(String uuid, {double? score}) => {
        'uuid': uuid,
        'title': 'Фильм $uuid',
        'status': 'watched',
        'viewings': [
          {'date': seen, 'score': null},
        ],
        'rewatchCount': 0,
        'score': score,
      };

  /// Снимок, каким его пишет версия до 0.29.
  Map<String, dynamic> oldSnapshot(List<Map<String, dynamic>> movies) => {
        'kind': 'kadr-sync',
        'version': 1,
        'movies': movies,
        'series': const [],
        'lists': const [],
      };

  MovieRepository mine() => MovieRepository.detached({
        'movies': [oldMovie('m', score: 8.0)],
      });

  int count(List<String> log, String path) =>
      log.where((p) => p == path).length;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.remove(WebdavService.legacySignatureKey);
  });

  test('новый формат пишется в свой файл, прежний не трогается', () async {
    final remote = _FakeRemote()
      ..files[WebdavService.legacyFile] =
          bytes(oldSnapshot([oldMovie('m', score: 8.0)]));
    final before = [...remote.files[WebdavService.legacyFile]!];
    final repo = mine();
    await WebdavService.instance.syncWith(remote, repo: repo);
    expect(remote.writes, [WebdavService.file]);
    expect(remote.files[WebdavService.legacyFile], before);
    final written = jsonDecode(utf8.decode(remote.files[WebdavService.file]!))
        as Map<String, dynamic>;
    expect(written['version'], 2);
    expect((written['movies'] as List).length, 1);
  });

  test('просмотры из файла прежних версий вливаются без дублей', () async {
    final remote = _FakeRemote()
      ..files[WebdavService.legacyFile] = bytes(oldSnapshot([
        oldMovie('m', score: 8.0),
        oldMovie('n', score: 6.5),
      ]));
    final repo = mine();
    await WebdavService.instance.syncWith(remote, repo: repo);
    final m = repo.byUuid('m')!;
    expect(m.viewings.length, 1, reason: 'оценка в просмотре дубля не даёт');
    expect(m.currentScore, 8.0);
    expect(repo.byUuid('n')!.currentScore, 6.5);
  });

  test('неизменившийся файл прежних версий второй раз не скачивается',
      () async {
    final remote = _FakeRemote()
      ..files[WebdavService.legacyFile] =
          bytes(oldSnapshot([oldMovie('m', score: 8.0)]));
    final repo = mine();
    await WebdavService.instance.syncWith(remote, repo: repo);
    await WebdavService.instance.syncWith(remote, repo: repo);
    expect(count(remote.reads, WebdavService.legacyFile), 1);
    // Старое устройство дописало фильм: файл изменился и читается снова.
    remote.files[WebdavService.legacyFile] = bytes(oldSnapshot([
      oldMovie('m', score: 8.0),
      oldMovie('n', score: 6.5),
    ]));
    await WebdavService.instance.syncWith(remote, repo: repo);
    expect(count(remote.reads, WebdavService.legacyFile), 2);
    expect(repo.byUuid('n'), isNotNull);
  });

  test('два устройства на новой версии обмениваются через новый файл',
      () async {
    final remote = _FakeRemote();
    final phone = mine();
    final tv = MovieRepository.detached({
      'movies': [oldMovie('n', score: 6.5)],
    });
    await WebdavService.instance.syncWith(remote, repo: phone);
    await WebdavService.instance.syncWith(remote, repo: tv);
    await WebdavService.instance.syncWith(remote, repo: phone);
    expect(phone.byUuid('n')!.currentScore, 6.5);
    expect(tv.byUuid('m')!.currentScore, 8.0);
    expect(remote.files.keys, [WebdavService.file]);
  });

  // Обрыв связи на чтении раньше считался «файла ещё нет», и снимок с этого
  // устройства записывался поверх общего. На новом телефоне с пустой
  // библиотекой это стирало всё, что лежало на сервере.
  test('сбой чтения обрывает синк и ничего не пишет', () async {
    final remote = _BrokenRemote()
      ..files[WebdavService.file] = bytes(oldSnapshot([oldMovie('n')]));
    final repo = mine();
    await expectLater(
        WebdavService.instance.syncWith(remote, repo: repo), throwsStateError);
    expect(remote.writes, isEmpty);
    expect(repo.byUuid('n'), isNull);
  });

  // Файл на сервере есть, но это не снимок: недокачанный или чужой. Писать
  // поверх него нельзя, там может лежать единственная копия библиотеки.
  test('нечитаемый общий файл не затирается', () async {
    for (final junk in ['{"kind": "kadr-sync", "movies": [', '{"x": 1}']) {
      final remote = _FakeRemote()
        ..files[WebdavService.file] = utf8.encode(junk);
      await expectLater(
          WebdavService.instance.syncWith(remote, repo: mine()),
          throwsFormatException);
      expect(remote.writes, isEmpty);
    }
  });

  test('нечитаемый файл прежних версий синку не мешает', () async {
    final remote = _FakeRemote()
      ..files[WebdavService.legacyFile] = utf8.encode('{"movies": [');
    await WebdavService.instance.syncWith(remote, repo: mine());
    expect(remote.writes, [WebdavService.file]);
  });

  // Сервер не отдаёт отпечаток файла: читать приходится каждый раз, иначе
  // отметки со старого устройства перестали бы доезжать молча.
  test('без отпечатка файл прежних версий читается каждый раз', () async {
    final remote = _NoSignatureRemote()
      ..files[WebdavService.legacyFile] =
          bytes(oldSnapshot([oldMovie('n', score: 6.5)]));
    final repo = mine();
    await WebdavService.instance.syncWith(remote, repo: repo);
    await WebdavService.instance.syncWith(remote, repo: repo);
    expect(count(remote.reads, WebdavService.legacyFile), 2);
    expect(repo.byUuid('n'), isNotNull);
  });

  test('оценка, поставленная на новой версии, доезжает до второго устройства',
      () async {
    final remote = _FakeRemote();
    final phone = mine();
    final tv = mine();
    await WebdavService.instance.syncWith(remote, repo: phone);
    await WebdavService.instance.syncWith(remote, repo: tv);
    final v = phone.byUuid('m')!.viewings.single;
    await phone.setViewingScore('m', v, 9.5);
    await WebdavService.instance.syncWith(remote, repo: phone);
    await WebdavService.instance.syncWith(remote, repo: tv);
    expect(tv.byUuid('m')!.viewings.length, 1);
    expect(tv.byUuid('m')!.currentScore, 9.5);
  });
}
