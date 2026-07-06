import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';

/// Регрессия «обновление сбрасывает базу»: проверяем, что текущий код МОДЕЛИ
/// способен прочитать реальную базу пользователя и пережить round-trip
/// (fromJson → toJson → fromJson). Если хоть один элемент кидает исключение —
/// `load()` в приложении уйдёт в catch, оставит базу пустой, а фоновый sweep
/// перезапишет её пустой → потеря данных.
void main() {
  final file = File('tool/personal_seed_backup.json');

  test('реальная база парсится текущим кодом без исключений', () {
    expect(file.existsSync(), true, reason: 'нет tool/personal_seed_backup.json');
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final movies = (data['movies'] as List);
    final series = (data['series'] as List);
    final lists = (data['lists'] as List? ?? []);

    var mOk = 0, sOk = 0, lOk = 0;
    final errors = <String>[];

    for (final e in movies) {
      try {
        final m = LibraryMovie.fromJson(e as Map<String, dynamic>);
        // round-trip
        LibraryMovie.fromJson(m.toJson());
        mOk++;
      } catch (err) {
        errors.add('movie[${(e as Map)['title']}]: $err');
      }
    }
    for (final e in series) {
      try {
        final s = LibrarySeries.fromJson(e as Map<String, dynamic>);
        LibrarySeries.fromJson(s.toJson());
        sOk++;
      } catch (err) {
        errors.add('series[${(e as Map)['title']}]: $err');
      }
    }
    for (final e in lists) {
      try {
        final l = MovieList.fromJson(e as Map<String, dynamic>);
        MovieList.fromJson(l.toJson());
        lOk++;
      } catch (err) {
        errors.add('list: $err');
      }
    }

    // ignore: avoid_print
    print('movies $mOk/${movies.length}, series $sOk/${series.length}, '
        'lists $lOk/${lists.length}, ошибок: ${errors.length}');
    for (final e in errors.take(20)) {
      // ignore: avoid_print
      print('  ✗ $e');
    }

    expect(errors, isEmpty, reason: 'парсинг реальной базы падает — это и есть сброс');
  });
}
