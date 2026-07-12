/// Чистый (без Flutter) парсер GDPR-экспорта TV Time → промежуточные DTO.
///
/// Порт `tool/import_tvtime.py`. Не зависит от Flutter/моделей приложения —
/// поэтому тестируется обычным `dart run` (см. `tool/tvtime_verify.dart`).
/// Сервис [TvTimeImportService] превращает эти DTO в [LibraryMovie]/[LibrarySeries]
/// и пишет в репозиторий; постеры/kinopoisk-id дотягиваются лениво по названию+году.
library;

/// Реакция TV Time → стартовый балл 1..10 (пользователь может поправить).
class TvEmotion {
  final String id;
  final String label;
  final String emoji;
  final double score;
  const TvEmotion(this.id, this.label, this.emoji, this.score);
}

const Map<String, TvEmotion> kTvEmotions = {
  '37': TvEmotion('37', 'Понравилось', '😊', 7.5),
  '28': TvEmotion('28', 'Отлично', '😍', 8.5),
  '33': TvEmotion('33', 'Смешно', '😂', 7.5),
  '32': TvEmotion('32', 'Эпично', '🤩', 8.0),
  '30': TvEmotion('30', 'Тронуло', '🥹', 8.0),
  '39': TvEmotion('39', 'Круто', '😎', 7.5),
  '31': TvEmotion('31', 'Вынос мозга', '🤯', 8.5),
  '29': TvEmotion('29', 'Напряжённо', '😬', 7.0),
  '35': TvEmotion('35', 'Тревожно', '😰', 6.5),
  '34': TvEmotion('34', 'Страшно', '😱', 6.5),
  '38': TvEmotion('38', 'Тяжело', '😖', 6.0),
  '36': TvEmotion('36', 'Неожиданно', '😮', 7.5),
};

class TvMovie {
  final String uuid;
  String title;
  int? year;
  int? runtimeMin;
  String status; // watched | watchlist | library
  List<String> viewings; // ISO-даты просмотров
  int rewatchCount;
  double? score;
  List<TvEmotion> emotions;
  bool favorite;
  List<String> lists;
  String? review;
  String? addedAt;
  TvMovie(this.uuid)
      : title = '',
        status = 'library',
        viewings = [],
        rewatchCount = 0,
        emotions = [],
        favorite = false,
        lists = [];
}

class TvEpisode {
  final int? season;
  final int? number;
  final String watchedAt; // ISO
  final int? runtimeMin;
  final String epId;
  const TvEpisode(
      {this.season, this.number, required this.watchedAt, this.runtimeMin, required this.epId});
}

class TvSeries {
  final String tvShowId;
  final String title;
  bool favorite;
  String? review;
  List<TvEpisode> episodes;
  TvSeries(this.tvShowId, this.title)
      : favorite = false,
        episodes = [];
}

class TvList {
  final String name;
  final List<String> movieUuids;
  final bool public;
  const TvList(this.name, this.movieUuids, this.public);
}

class TvTimeData {
  final List<TvMovie> movies;
  final List<TvSeries> series;
  final List<TvList> lists;
  final Map<String, int> counts;
  const TvTimeData(this.movies, this.series, this.lists, this.counts);
}

/// Разобрать набор CSV из экспорта (имя файла → содержимое).
TvTimeData parseTvTime(Map<String, String> files) {
  List<Map<String, String>> rows(String name) {
    final raw = files[name];
    if (raw == null || raw.isEmpty) return const [];
    return _csvToMaps(raw);
  }

  String? tail(String vk, String uid) {
    final sep = '-$uid-';
    final i = vk.lastIndexOf(sep);
    if (i < 0) return null;
    return vk.substring(i + sep.length);
  }

  // ---- эмоции по uuid ----
  final emoByUuid = <String, List<String>>{};
  for (final r in rows('emotions-live-votes.csv')) {
    final eid = tail(r['vote_key'] ?? '', r['user_id'] ?? '');
    if (eid != null && eid.isNotEmpty) {
      (emoByUuid[r['uuid'] ?? ''] ??= []).add(eid);
    }
  }
  double? scoreFromEmotions(List<String> eids) {
    final vals = [for (final e in eids) if (kTvEmotions[e] != null) kTvEmotions[e]!.score];
    if (vals.isEmpty) return null;
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return (avg * 10).round() / 10;
  }

  // ---- отзывы по названию ----
  final reviewByName = <String, String>{};
  for (final r in rows('comments-prod-comments.csv')) {
    final txt = (r['text'] ?? '').trim();
    final nm = (r['movie_name']?.isNotEmpty ?? false) ? r['movie_name']! : (r['series_name'] ?? '');
    if (txt.isNotEmpty && nm.isNotEmpty && !reviewByName.containsKey(nm)) {
      reviewByName[nm] = txt;
    }
  }

  // ---- списки ----
  final listsOut = <TvList>[];
  final listByUuid = <String, List<String>>{};
  final favoriteUuids = <String>{};
  final uuidRe = RegExp(r'uuid:([0-9a-f-]{36})');
  for (final r in rows('lists-prod-lists.csv')) {
    if (r['type'] == 'list' && (r['name']?.isNotEmpty ?? false)) {
      final uuids = uuidRe.allMatches(r['objects'] ?? '').map((m) => m.group(1)!).toList();
      listsOut.add(TvList(r['name']!, uuids, r['is_public'] == 'true'));
      for (final u in uuids) {
        (listByUuid[u] ??= []).add(r['name']!);
      }
      if ((r['s_key'] ?? '').toLowerCase().contains('favorite')) {
        favoriteUuids.addAll(uuids);
      }
    }
  }

  // ---- фильмы (tracking v1) ----
  final movies = <String, TvMovie>{};
  final watched = <String>{}; // uuid просмотренных
  final inWatchlist = <String>{};
  final towatchAt = <String, String>{};
  final followAt = <String, String>{};
  for (final r in rows('tracking-prod-records.csv')) {
    if (r['entity_type'] != 'movie') continue;
    final u = r['uuid'] ?? '';
    if (u.isEmpty) continue;
    final m = movies[u] ??= TvMovie(u);
    if (m.title.isEmpty) m.title = r['movie_name'] ?? '';
    final rel = (r['release_date'] ?? '');
    if (rel.length >= 4 && int.tryParse(rel.substring(0, 4)) != null) {
      m.year = int.parse(rel.substring(0, 4));
    }
    final rt = int.tryParse((r['runtime'] ?? '').trim());
    if (rt != null && rt > 0) m.runtimeMin = (rt / 60).round();
    final t = r['type'] ?? '';
    final created = (r['created_at'] ?? '').trim();
    if (t == 'watch' || t == 'rewatch') {
      watched.add(u);
      if (created.isNotEmpty) m.viewings.add(created);
    } else if (t == 'towatch') {
      inWatchlist.add(u);
      if (created.isNotEmpty) towatchAt[u] = created;
    } else if (t == 'follow') {
      if (created.isNotEmpty) followAt[u] = created;
    }
    final rc = int.tryParse((r['rewatch_count'] ?? '').trim());
    if (rc != null) m.rewatchCount = m.rewatchCount > rc ? m.rewatchCount : rc;
  }

  final movieList = <TvMovie>[];
  for (final entry in movies.entries) {
    final u = entry.key;
    final m = entry.value;
    if (m.title.isEmpty) continue; // пропускаем агрегатные/пустые записи
    final eids = emoByUuid[u] ?? const [];
    m.viewings = (m.viewings.toSet().toList()..sort());
    m.status = watched.contains(u)
        ? 'watched'
        : (inWatchlist.contains(u) ? 'watchlist' : 'library');
    m.score = scoreFromEmotions(eids);
    m.emotions = [for (final e in eids) if (kTvEmotions[e] != null) kTvEmotions[e]!];
    m.favorite = favoriteUuids.contains(u);
    m.lists = listByUuid[u] ?? const [];
    m.review = reviewByName[m.title];
    m.addedAt = towatchAt[u] ?? followAt[u];
    movieList.add(m);
  }

  // ---- сериалы (tracking v2) ----
  final utd = <String, Map<String, String>>{};
  for (final r in rows('user_tv_show_data.csv')) {
    final id = r['tv_show_id'] ?? '';
    if (id.isNotEmpty) utd[id] = r;
  }
  final seriesMap = <String, TvSeries>{};
  for (final r in rows('tracking-prod-records-v2.csv')) {
    final name = (r['series_name'] ?? '').trim();
    final sid = (r['s_id'] ?? '').trim();
    if (name.isEmpty) continue;
    final key = sid.isNotEmpty ? sid : name;
    final s = seriesMap[key] ??= TvSeries(sid, name);
    final created = (r['created_at'] ?? '').trim();
    final epid = (r['ep_id'] ?? '').trim();
    if (epid.isNotEmpty && created.isNotEmpty) {
      final sn = int.tryParse((r['season_number'] ?? '').trim());
      final en = int.tryParse((r['ep_no'] ?? '').trim()) ??
          int.tryParse((r['episode_number'] ?? '').trim());
      final rt = int.tryParse((r['runtime'] ?? '').trim());
      s.episodes.add(TvEpisode(
        season: sn,
        number: en,
        watchedAt: created,
        runtimeMin: (rt != null && rt > 0) ? (rt / 60).round() : null,
        epId: epid,
      ));
    }
  }

  final seriesList = <TvSeries>[];
  for (final s in seriesMap.values) {
    final d = utd[s.tvShowId];
    s.favorite = d?['is_favorited'] == 'true';
    // дедуп по (epId, watchedAt) + сортировка по времени
    final seen = <String>{};
    final uniq = <TvEpisode>[];
    final sorted = [...s.episodes]..sort((a, b) => a.watchedAt.compareTo(b.watchedAt));
    for (final e in sorted) {
      final k = '${e.epId}|${e.watchedAt}';
      if (seen.add(k)) uniq.add(e);
    }
    s.episodes = uniq;
    s.review = reviewByName[s.title];
    seriesList.add(s);
  }

  final counts = <String, int>{
    'movies': movieList.length,
    'moviesWatched': movieList.where((m) => m.status == 'watched').length,
    'moviesWatchlist': movieList.where((m) => m.status == 'watchlist').length,
    'moviesRated': movieList.where((m) => m.score != null).length,
    'movieViewings': movieList.fold(0, (a, m) => a + m.viewings.length),
    'series': seriesList.length,
    'seriesFavorite': seriesList.where((s) => s.favorite).length,
    'episodeViewings': seriesList.fold(0, (a, s) => a + s.episodes.length),
    'lists': listsOut.length,
    'reviews': reviewByName.length,
  };

  // свежие сверху
  movieList.sort((a, b) => (b.viewings.isEmpty ? '' : b.viewings.last)
      .compareTo(a.viewings.isEmpty ? '' : a.viewings.last));
  seriesList.sort((a, b) => (b.episodes.isEmpty ? '' : b.episodes.last.watchedAt)
      .compareTo(a.episodes.isEmpty ? '' : a.episodes.last.watchedAt));

  return TvTimeData(movieList, seriesList, listsOut, counts);
}

// --------------------------- CSV ---------------------------

/// Разбор CSV в список Map по заголовку (первая строка). Терпим к недостающим
/// колонкам. Поддержка кавычек, запятых и переводов строк внутри кавычек.
List<Map<String, String>> _csvToMaps(String raw) {
  final rows = _parseCsv(raw);
  if (rows.length < 2) return const [];
  final headers = rows.first;
  final out = <Map<String, String>>[];
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    final map = <String, String>{};
    for (var c = 0; c < headers.length; c++) {
      map[headers[c]] = c < row.length ? row[c] : '';
    }
    out.add(map);
  }
  return out;
}

List<List<String>> _parseCsv(String raw) {
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
