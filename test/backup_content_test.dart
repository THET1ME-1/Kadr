import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/app_prefs.dart';
import 'package:kadr/services/backup_archive.dart';
import 'package:kadr/services/backup_service.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/poster_store.dart';
import 'package:kadr/services/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Что лежит в копии кроме самой библиотеки: любимые персонаж и актёры,
/// свои постеры и фото дневника. Раньше первое жило только в настройках, а
/// от картинок в копию попадали одни имена файлов.
void main() {
  late Directory tmp;
  late Directory posters;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.remove('favChar');
    await Store.instance.remove('favActors');
    await AppPrefs.instance.load();
    tmp = await Directory.systemTemp.createTemp('kadr_backup_');
    posters = await Directory('${tmp.path}/posters').create();
    await PosterStore.instance.useDir(posters);
  });

  tearDown(() async {
    await Store.instance.remove('favChar');
    await Store.instance.remove('favActors');
    await AppPrefs.instance.load();
    await tmp.delete(recursive: true);
  });

  Future<File> image(String name, [String body = 'картинка']) =>
      File('${posters.path}/$name').writeAsString(body);

  /// Библиотека с постером фильма, постером сериала и тремя фото дневника.
  MovieRepository library() => MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'm',
            title: 'Дюна',
            status: LibraryStatus.watched,
            enrichTried: true,
            posterUrl: 'https://image.example/dune.jpg',
            posterFile: 'p_m.jpg',
            viewings: [
              Viewing(
                date: DateTime(2024, 3, 1),
                diary: DiaryEntry(note: 'в кино', photoFile: 'p_diary_m.jpg'),
              ),
            ],
          ).toJson(),
        ],
        'series': [
          LibrarySeries(
            tvShowId: 's',
            title: 'Аркейн',
            enrichTried: true,
            posterFile: 'p_s.jpg',
            episodes: [
              Episode(
                season: 1,
                number: 1,
                watchedAt: DateTime(2024, 4, 1),
                diary: DiaryEntry(photoFile: 'p_diary_e1.jpg'),
                rewatchViews: [
                  Viewing(
                    date: DateTime(2025, 4, 1),
                    diary: DiaryEntry(photoFile: 'p_diary_e1r.jpg'),
                  ),
                ],
              ),
            ],
          ).toJson(),
        ],
      });

  const allImages = {
    'p_m.jpg',
    'p_diary_m.jpg',
    'p_s.jpg',
    'p_diary_e1.jpg',
    'p_diary_e1r.jpg',
  };

  test('копия называет все свои картинки', () {
    expect(backupImageNames(library().toJson()), allImages);
  });

  group('свой постер, которого нет на устройстве', () {
    test('карточка показывает сетевой постер, а не пустоту', () async {
      final m = library().byUuid('m')!;
      expect(m.displayPoster, 'https://image.example/dune.jpg');
      await image('p_m.jpg');
      await PosterStore.instance.useDir(posters);
      expect(m.displayPoster, '${posters.path}/p_m.jpg');
    });

    test('сохранённый и удалённый постер учитываются сразу', () async {
      final name = await PosterStore.instance
          .save('m', Uint8List.fromList([1, 2, 3]));
      expect(PosterStore.instance.pathOf(name), isNotNull);
      await PosterStore.instance.delete(name);
      expect(PosterStore.instance.pathOf(name), isNull);
    });
  });

  group('любимые персонаж и актёры', () {
    const hero = FavoriteCharacter(
      character: 'Пол Атрейдес',
      actor: 'Тимоти Шаламе',
      photoUrl: 'https://image.example/paul.jpg',
      title: 'Дюна',
    );
    const zendaya = FavoriteActor(id: 505710, name: 'Зендея');
    const rebecca = FavoriteActor(id: 933238, name: 'Ребекка Фергюсон');

    Future<String> backupWithFavorites() async {
      await AppPrefs.instance.setFavoriteCharacter(hero);
      await AppPrefs.instance.toggleFavoriteActor(zendaya);
      final raw = BackupService.exportJson(repo: library());
      await AppPrefs.instance.setFavoriteCharacter(null);
      await AppPrefs.instance.toggleFavoriteActor(zendaya);
      expect(AppPrefs.instance.favoriteActors, isEmpty);
      return raw;
    }

    test('попадают в копию и возвращаются при замене', () async {
      final raw = await backupWithFavorites();
      expect((jsonDecode(raw) as Map).containsKey('favorites'), isTrue);
      final res = await BackupService.restore(raw,
          merge: false, repo: MovieRepository.detached(const {}));
      expect(res.ok, isTrue);
      expect(AppPrefs.instance.favoriteCharacter!.character, 'Пол Атрейдес');
      expect(AppPrefs.instance.favoriteActors.single.id, zendaya.id);
      // И переживают перезапуск: лежат в настройках, а не только в памяти.
      await AppPrefs.instance.load();
      expect(AppPrefs.instance.favoriteActors.single.name, 'Зендея');
    });

    test('при добавлении актёры складываются, свой персонаж остаётся',
        () async {
      final raw = await backupWithFavorites();
      const mine = FavoriteCharacter(
          character: 'Джинкс', actor: 'Элла Пернелл', title: 'Аркейн');
      await AppPrefs.instance.setFavoriteCharacter(mine);
      await AppPrefs.instance.toggleFavoriteActor(rebecca);
      await BackupService.restore(raw,
          merge: true, repo: MovieRepository.detached(const {}));
      expect(AppPrefs.instance.favoriteCharacter!.character, 'Джинкс');
      expect({for (final a in AppPrefs.instance.favoriteActors) a.id},
          {zendaya.id, rebecca.id});
    });

    test('копия старой версии без любимых ничего не стирает', () async {
      await AppPrefs.instance.setFavoriteCharacter(hero);
      await AppPrefs.instance.toggleFavoriteActor(zendaya);
      final old = jsonEncode({'app': 'kadr', 'version': 1, ...library().toJson()});
      await BackupService.restore(old,
          merge: false, repo: MovieRepository.detached(const {}));
      expect(AppPrefs.instance.favoriteCharacter, isNotNull);
      expect(AppPrefs.instance.favoriteActors.single.id, zendaya.id);
    });
  });

  group('копия с картинками', () {
    test('без своих картинок копия остаётся файлом JSON', () async {
      final repo = MovieRepository.detached({
        'movies': [
          LibraryMovie(uuid: 'm', title: 'Дюна', enrichTried: true).toJson(),
        ],
      });
      final f = await BackupService.writeBackupFile(tmp, repo: repo);
      expect(f.path, endsWith('.json'));
      expect(jsonDecode(await f.readAsString())['movies'], hasLength(1));
    });

    test('с картинками копия собирается архивом и встаёт на новом устройстве',
        () async {
      for (final name in allImages.take(3)) {
        await image(name, 'байты $name');
      }
      await PosterStore.instance.useDir(posters);
      final f = await BackupService.writeBackupFile(tmp, repo: library());
      expect(f.path, endsWith('.zip'));

      // Новое устройство: папка картинок пуста, библиотека пуста.
      final fresh = await Directory('${tmp.path}/fresh').create();
      await PosterStore.instance.useDir(fresh);
      final target = MovieRepository.detached(const {});
      final picked = await BackupService.readBackupFile(f.path);
      expect(picked, isNotNull);
      final res = await BackupService.restorePicked(picked!,
          merge: false, repo: target);
      expect(res.ok, isTrue);
      expect(target.byUuid('m')!.displayPoster, '${fresh.path}/p_m.jpg');
      for (final name in allImages.take(3)) {
        expect(await File('${fresh.path}/$name').readAsString(), 'байты $name');
      }
      // Фото, которого не было на старом устройстве, нет и тут.
      expect(File('${fresh.path}/p_diary_e1r.jpg').existsSync(), isFalse);
    });

    test('файл копии читается и как JSON, и как архив', () async {
      final json = File('${tmp.path}/b.json');
      await json.writeAsString(BackupService.exportJson(repo: library()));
      final picked = await BackupService.readBackupFile(json.path);
      expect(jsonDecode(picked!.json)['movies'], hasLength(1));
      expect(picked.zipPath, isNull);
      final junk = File('${tmp.path}/junk.bin');
      await junk.writeAsBytes([0x50, 0x4B, 3, 4, 0, 0, 0]);
      expect(await BackupService.readBackupFile(junk.path), isNull);
    });
  });

  group('архив', () {
    test('своя картинка на устройстве не затирается картинкой из копии',
        () async {
      await image('p_m.jpg', 'из копии');
      final zip = '${tmp.path}/b.zip';
      await BackupArchive.pack(zip, '{}', {
        'p_m.jpg': File('${posters.path}/p_m.jpg'),
      });
      final dest = await Directory('${tmp.path}/dest').create();
      await File('${dest.path}/p_m.jpg').writeAsString('моя');
      final got = await BackupArchive.unpack(zip, imagesTo: dest);
      expect(got.json, '{}');
      expect(got.images, isEmpty);
      expect(await File('${dest.path}/p_m.jpg').readAsString(), 'моя');
    });

    test('имя с путём наружу в папку картинок не попадает', () async {
      final src = await image('p_m.jpg');
      final zip = '${tmp.path}/b.zip';
      await BackupArchive.pack(zip, '{}', {
        '../../evil.jpg': src,
        'ok.jpg': src,
      });
      final dest = await Directory('${tmp.path}/dest').create();
      final got = await BackupArchive.unpack(zip, imagesTo: dest);
      expect(got.images, ['ok.jpg']);
      expect(File('${tmp.path}/evil.jpg').existsSync(), isFalse);
      expect(dest.listSync().map((f) => f.uri.pathSegments.last), ['ok.jpg']);
    });
  });
}
