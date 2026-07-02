import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'movie_repository.dart';

/// Резервные копии Kadr: экспорт (через системный share — в Telegram/Drive/файл)
/// и импорт (выбор JSON-файла). Позволяет перенести всю библиотеку с оценками и
/// просмотрами на новый телефон. Без OAuth — файлом.
class BackupService {
  static String _stamp() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
  }

  /// Создаёт JSON-копию и открывает системное «Поделиться».
  static Future<void> exportAndShare() async {
    final json = MovieRepository.instance.exportJson();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kadr_backup_${_stamp()}.json');
    await file.writeAsString(json);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Kadr — резервная копия',
    );
  }

  /// Выбор JSON-файла и восстановление. Возвращает true при успехе.
  static Future<bool> importFromFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return false;
    final f = res.files.single;
    String raw;
    if (f.bytes != null) {
      raw = utf8.decode(f.bytes!);
    } else if (f.path != null) {
      raw = await File(f.path!).readAsString();
    } else {
      return false;
    }
    return MovieRepository.instance.importJson(raw);
  }
}
