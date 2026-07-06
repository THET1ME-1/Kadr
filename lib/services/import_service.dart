import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/library_entry.dart';
import 'movie_repository.dart';

class ImportResult {
  final bool ok;
  final int added;
  final int updated;
  final int skipped;
  final String format; // letterboxd | imdb | csv | error
  const ImportResult(
      {this.ok = false,
      this.added = 0,
      this.updated = 0,
      this.skipped = 0,
      this.format = 'error'});
}

/// Импорт истории из других трекеров через CSV (Letterboxd, IMDb, общий формат).
/// Фильмы добавляются с оценкой и датой; постеры/детали подтягиваются в фоне.
class ImportService {
  /// Выбор CSV-файла и импорт.
  static Future<ImportResult> pickAndImport() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return const ImportResult();
    final f = res.files.single;
    String raw;
    if (f.bytes != null) {
      raw = utf8.decode(f.bytes!, allowMalformed: true);
    } else if (f.path != null) {
      raw = await File(f.path!).readAsString();
    } else {
      return const ImportResult();
    }
    return importCsv(raw);
  }

  static Future<ImportResult> importCsv(String raw) async {
    final rows = _parseCsv(raw);
    if (rows.length < 2) return const ImportResult(format: 'error');
    final headers = rows.first.map((h) => h.toLowerCase().trim()).toList();
    final format = _detect(headers);

    // Индексы нужных колонок.
    int col(List<String> names) {
      for (final n in names) {
        final i = headers.indexOf(n);
        if (i >= 0) return i;
      }
      return -1;
    }

    final iTitle = col(['name', 'title', 'original title', 'film']);
    final iYear = col(['year', 'release year']);
    final iRating = col(['rating', 'your rating', 'score', 'stars']);
    final iDate =
        col(['watched date', 'date rated', 'date', 'watched', 'last watched']);
    final iType = col(['title type', 'type']);
    if (iTitle < 0) return const ImportResult(format: 'error');

    // Определяем шкалу оценки (5 или 10) по максимуму.
    var maxRating = 0.0;
    if (iRating >= 0) {
      for (var r = 1; r < rows.length; r++) {
        if (iRating < rows[r].length) {
          final v = double.tryParse(rows[r][iRating].replaceAll(',', '.'));
          if (v != null && v > maxRating) maxRating = v;
        }
      }
    }
    final scale = format == 'letterboxd'
        ? 5.0
        : format == 'imdb'
            ? 10.0
            : (maxRating > 5 ? 10.0 : 5.0);

    // Letterboxd без колонки rating = watchlist.csv.
    final defaultStatus = (format == 'letterboxd' && iRating < 0)
        ? LibraryStatus.watchlist
        : LibraryStatus.watched;

    final base = DateTime.now().microsecondsSinceEpoch;
    final movies = <LibraryMovie>[];
    var skipped = 0;
    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      String cell(int i) => (i >= 0 && i < row.length) ? row[i].trim() : '';
      final title = cell(iTitle);
      if (title.isEmpty) {
        skipped++;
        continue;
      }
      // Пропускаем сериалы/эпизоды (пока импортируем фильмы).
      final type = cell(iType).toLowerCase();
      if (type.contains('series') ||
          type.contains('episode') ||
          type == 'tvminiseries') {
        skipped++;
        continue;
      }
      final year = int.tryParse(cell(iYear));
      double? score;
      final rawR = cell(iRating).replaceAll(',', '.');
      final rv = double.tryParse(rawR);
      if (rv != null && rv > 0) {
        score = (rv * (10.0 / scale)).clamp(1.0, 10.0);
        score = (score * 10).round() / 10; // до 0.1
      }
      final date = _parseDate(cell(iDate));
      final status = defaultStatus;

      movies.add(LibraryMovie(
        uuid: 'imp-$base-$r',
        title: title,
        year: year,
        status: status,
        addedAt: date ?? DateTime.now(),
        score: score,
        viewings: status == LibraryStatus.watched
            ? [Viewing(date: date, score: score)]
            : const [],
      ));
    }

    if (movies.isEmpty) {
      return ImportResult(ok: true, skipped: skipped, format: format);
    }
    final (added, updated) =
        await MovieRepository.instance.importMovies(movies);
    return ImportResult(
        ok: true,
        added: added,
        updated: updated,
        skipped: skipped,
        format: format);
  }

  static String _detect(List<String> headers) {
    if (headers.contains('letterboxd uri')) return 'letterboxd';
    if (headers.contains('const') && headers.contains('your rating')) {
      return 'imdb';
    }
    return 'csv';
  }

  static DateTime? _parseDate(String s) {
    if (s.isEmpty) return null;
    final d = DateTime.tryParse(s);
    if (d != null && d.millisecondsSinceEpoch > 0) return d;
    // Формат DD.MM.YYYY / DD/MM/YYYY.
    final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(s);
    if (m != null) {
      return DateTime(
          int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    }
    return null;
  }

  /// Минимальный CSV-парсер: кавычки, запятые и переводы строк внутри кавычек,
  /// экранирование "" внутри поля. Разделитель — запятая (Letterboxd/IMDb).
  static List<List<String>> _parseCsv(String raw) {
    final rows = <List<String>>[];
    var field = StringBuffer();
    var record = <String>[];
    var inQuotes = false;
    final s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < s.length && s[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          record.add(field.toString());
          field = StringBuffer();
        } else if (c == '\n') {
          record.add(field.toString());
          field = StringBuffer();
          if (record.any((f) => f.trim().isNotEmpty)) rows.add(record);
          record = <String>[];
        } else {
          field.write(c);
        }
      }
    }
    if (field.isNotEmpty || record.isNotEmpty) {
      record.add(field.toString());
      if (record.any((f) => f.trim().isNotEmpty)) rows.add(record);
    }
    return rows;
  }
}
