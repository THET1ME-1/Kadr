import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

/// Имена картинок, на которые ссылается библиотека [data]: свои постеры
/// фильмов и сериалов и фото дневника просмотров. В JSON копии от картинок
/// только имена файлов, сами файлы едут рядом.
Set<String> backupImageNames(Map<String, dynamic> data) {
  final names = <String>{};
  void add(Object? name) {
    if (name is String && name.isNotEmpty) names.add(name);
  }

  void diary(Object? view) {
    final d = view is Map ? view['diary'] : null;
    if (d is Map) add(d['photoFile']);
  }

  for (final m in (data['movies'] as List? ?? const [])) {
    if (m is! Map) continue;
    add(m['posterFile']);
    (m['viewings'] as List? ?? const []).forEach(diary);
  }
  for (final s in (data['series'] as List? ?? const [])) {
    if (s is! Map) continue;
    add(s['posterFile']);
    for (final e in (s['episodes'] as List? ?? const [])) {
      if (e is! Map) continue;
      diary(e);
      (e['rewatchViews'] as List? ?? const []).forEach(diary);
    }
  }
  return names;
}

/// Копия с картинками: zip, в котором лежит JSON библиотеки и папка
/// `images/` со своими постерами и фото дневника.
class BackupArchive {
  static const jsonName = 'kadr_backup.json';
  static const _imagesDir = 'images/';

  /// Имя картинки, которое можно положить в папку: без пути и без точки в
  /// начале. Архив приходит извне, и запись `images/../../x` не должна
  /// выбраться из папки картинок.
  static final _plainName = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9_.-]*$');

  /// Zip начинается с «PK\x03\x04».
  static bool isZip(List<int> head) =>
      head.length >= 4 &&
      head[0] == 0x50 &&
      head[1] == 0x4B &&
      head[2] == 0x03 &&
      head[3] == 0x04;

  /// Пишет архив в [zipPath]: [json] и картинки [images] (имя → файл).
  /// Картинки не сжимаются: это и так JPEG.
  static Future<void> pack(
      String zipPath, String json, Map<String, File> images) async {
    final bytes = utf8.encode(json);
    final zip = ZipFileEncoder()..create(zipPath);
    zip.addArchiveFile(ArchiveFile(jsonName, bytes.length, bytes));
    for (final e in images.entries) {
      await zip.addFile(e.value, '$_imagesDir${e.key}', ZipFileEncoder.STORE);
    }
    await zip.close();
  }

  /// Читает архив: отдаёт JSON копии и раскладывает картинки в [imagesTo].
  /// Картинку, которая там уже лежит, не трогает. В [images] имена тех, что
  /// положены сейчас. Без [imagesTo] читается только JSON.
  static Future<({String? json, List<String> images})> unpack(String zipPath,
      {Directory? imagesTo}) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      String? json;
      final placed = <String>[];
      for (final entry in archive) {
        if (!entry.isFile) continue;
        if (entry.name == jsonName) {
          final content = entry.content;
          if (content is List<int>) json = utf8.decode(content);
          continue;
        }
        if (imagesTo == null || !entry.name.startsWith(_imagesDir)) continue;
        final name = entry.name.substring(_imagesDir.length);
        if (!_plainName.hasMatch(name)) continue;
        final target = File('${imagesTo.path}/$name');
        if (await target.exists()) continue;
        final out = OutputFileStream(target.path);
        entry.writeContent(out);
        await out.close();
        placed.add(name);
      }
      return (json: json, images: placed);
    } finally {
      await input.close();
    }
  }
}
