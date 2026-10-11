import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_prefs.dart';
import 'backup_archive.dart';
import 'movie_repository.dart';
import 'poster_store.dart';

export 'backup_archive.dart' show backupImageNames;

/// Выбранный файл копии: JSON библиотеки и, если это архив, путь к нему.
/// Картинки из архива раскладываются только после того, как человек
/// подтвердил восстановление.
class PickedBackup {
  final String json;
  final String? zipPath;
  const PickedBackup(this.json, {this.zipPath});
}

/// Резервные копии Kadr: экспорт (через системный share — в Telegram/Drive/файл)
/// и импорт (выбор файла). Позволяет перенести всю библиотеку с оценками и
/// просмотрами на новый телефон. Без OAuth — файлом.
///
/// В копии лежит библиотека (фильмы, сериалы, списки со всеми просмотрами,
/// оценками, дневником и рецензиями) и любимые персонаж с актёрами. Свои
/// постеры и фото дневника едут файлами: в ручной копии они упакованы в zip
/// вместе с JSON, в папке автокопий лежат рядом с ним.
///
/// Не входят и вводятся заново: ключи TMDB и ПоискКино, вход в аккаунт,
/// Trakt, WebDAV, скробблинг и настройки интерфейса. Ключи и пароли в файл,
/// которым делятся, класть нельзя.
class BackupService {
  static String _stamp() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
  }

  /// Содержимое копии: библиотека [repo] и любимые из настроек.
  static Map<String, dynamic> buildBackup({MovieRepository? repo}) {
    final fav = AppPrefs.instance.favoritesJson();
    return {
      'app': 'kadr',
      'version': 1,
      ...(repo ?? MovieRepository.instance).toJson(),
      'favorites': ?fav,
    };
  }

  /// Копия строкой JSON.
  static String exportJson({MovieRepository? repo}) =>
      const JsonEncoder.withIndent(' ').convert(buildBackup(repo: repo));

  /// Свои картинки библиотеки, которые есть на устройстве: имя → файл.
  static Map<String, File> localImages(Map<String, dynamic> data) => {
        for (final name in backupImageNames(data))
          name: ?PosterStore.instance.fileOf(name),
      };

  /// Пишет копию в папку [dir]. Если у библиотеки есть свои постеры или
  /// фото дневника, это архив с ними, иначе файл JSON, как раньше.
  static Future<File> writeBackupFile(Directory dir,
      {MovieRepository? repo}) async {
    final data = buildBackup(repo: repo);
    final json = const JsonEncoder.withIndent(' ').convert(data);
    final images = localImages(data);
    final base = '${dir.path}/kadr_backup_${_stamp()}';
    if (images.isEmpty) {
      return File('$base.json').writeAsString(json);
    }
    await BackupArchive.pack('$base.zip', json, images);
    return File('$base.zip');
  }

  /// Создаёт копию и открывает системное «Поделиться».
  static Future<void> exportAndShare() async {
    final file = await writeBackupFile(await getTemporaryDirectory());
    final zip = file.path.endsWith('.zip');
    await Share.shareXFiles(
      [XFile(file.path, mimeType: zip ? 'application/zip' : 'application/json')],
      subject: 'Kadr — резервная копия',
    );
  }

  /// Читает файл копии: JSON или архив с картинками. null, если это не
  /// копия Kadr.
  static Future<PickedBackup?> readBackupFile(String path) async {
    try {
      final file = File(path);
      final head = await file.openRead(0, 4).expand((b) => b).toList();
      if (BackupArchive.isZip(head)) {
        final json = (await BackupArchive.unpack(path)).json;
        return json == null ? null : PickedBackup(json, zipPath: path);
      }
      return PickedBackup(await file.readAsString());
    } catch (e) {
      debugPrint('BackupService: файл копии не читается: $e');
      return null;
    }
  }

  /// Выбор файла копии. null, если выбор отменён или файл не читается.
  static Future<PickedBackup?> pickBackup() async {
    final res = await FilePicker.platform.pickFiles();
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.single;
    if (f.path != null) return readBackupFile(f.path!);
    final bytes = f.bytes;
    if (bytes == null) return null;
    // Пути нет (веб, редкие провайдеры): кладём выбранное во временный файл.
    final tmp = await getTemporaryDirectory();
    final copy = File('${tmp.path}/kadr_picked_backup');
    await copy.writeAsBytes(bytes, flush: true);
    return readBackupFile(copy.path);
  }

  /// Восстанавливает выбранную копию: раскладывает картинки из архива и
  /// поднимает библиотеку с любимыми. [merge] — сложить копию с библиотекой,
  /// иначе заменить библиотеку копией.
  static Future<RestoreResult> restorePicked(PickedBackup picked,
      {required bool merge, MovieRepository? repo}) async {
    final zip = picked.zipPath;
    final dir = PosterStore.instance.directory;
    if (zip != null && dir != null) {
      try {
        final got = await BackupArchive.unpack(zip, imagesTo: dir);
        got.images.forEach(PosterStore.instance.adopt);
      } catch (e) {
        // Без картинок библиотека всё равно встанет: постеры откатятся на
        // сетевые.
        debugPrint('BackupService: картинки из копии не разложились: $e');
      }
    }
    return restore(picked.json, merge: merge, repo: repo);
  }

  /// Восстанавливает библиотеку и любимых из JSON копии [raw].
  static Future<RestoreResult> restore(String raw,
      {required bool merge, MovieRepository? repo}) async {
    final res = await (repo ?? MovieRepository.instance)
        .restoreBackup(raw, merge: merge);
    if (!res.ok) return res;
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        await AppPrefs.instance.restoreFavorites(data['favorites'], merge: merge);
      }
    } catch (e) {
      debugPrint('BackupService: любимые из копии не восстановились: $e');
    }
    return res;
  }
}
