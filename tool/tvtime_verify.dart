// Dev-утилита: проверка парсера TV Time (lib/services/tvtime_parser.dart) на папке
// с CSV из GDPR-экспорта. Запуск: dart run tool/tvtime_verify.dart <папка_с_csv>
// Печатает счётчики (сверять с tool/import_tvtime.py) и примеры записей.
import 'dart:io';

import 'package:kadr/services/tvtime_parser.dart';

void main(List<String> args) {
  final dir = args.isNotEmpty ? args[0] : '.';
  final files = <String, String>{};
  for (final e in Directory(dir).listSync()) {
    if (e is File && e.path.endsWith('.csv')) {
      files[Uri.file(e.path).pathSegments.last] = e.readAsStringSync();
    }
  }
  final data = parseTvTime(files);
  print('== счётчики ==');
  data.counts.forEach((k, v) => print('  $k: $v'));
  print('\n-- фильмы (свежие) --');
  for (final m in data.movies.take(6)) {
    final em = m.emotions.map((e) => e.emoji).join(' ');
    print('  ${m.title} ${m.year} · ${m.runtimeMin}м · балл=${m.score} · '
        'просмотров=${m.viewings.length} $em');
  }
  print('\n-- сериалы --');
  for (final s in data.series.take(5)) {
    final last = s.episodes.isEmpty ? '—' : s.episodes.last.watchedAt;
    print('  ${s.title} эп.=${s.episodes.length} fav=${s.favorite} last=$last');
  }
}
