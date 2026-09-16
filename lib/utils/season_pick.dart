/// С какого сезона открывать экран сериала.
library;

import '../models/library_entry.dart';
import '../services/tmdb_service.dart';

/// Сезон, который человек смотрит сейчас.
///
/// Отправная точка — сезон последней отмеченной серии: самой свежей по дате,
/// а если дат нет, самой дальней по порядку. Пока в этом сезоне досмотрены все
/// вышедшие серии, берётся следующий: человек досмотрел сезон и ждёт
/// продолжения, а не того же сезона с зелёными галочками. Раньше экран
/// переходил дальше, только когда отмечена первая серия нового сезона.
///
/// [seasons] — сезоны в порядке номеров, непустой список (в том виде, в каком
/// их показывает экран: без спецвыпусков и не начавших выходить).
/// [episodesOf] отдаёт серии сезона из TMDB. Пустой ответ значит «не знаем»,
/// и такой сезон досмотренным не считается.
Future<int> pickInitialSeason({
  required List<TmdbSeason> seasons,
  required List<Episode> watched,
  required Future<List<TmdbEpisode>> Function(int season) episodesOf,
  DateTime? now,
}) async {
  final numbers = [for (final s in seasons) s.number];
  final last = _lastWatched(watched, numbers.toSet());
  if (last == null) return numbers.first;

  final at = now ?? DateTime.now();
  var i = numbers.indexOf(last);
  while (i + 1 < numbers.length &&
      _finished(numbers[i], await episodesOf(numbers[i]), watched, at)) {
    i++;
  }
  return numbers[i];
}

/// Сезон последней отмеченной серии среди показываемых сезонов.
int? _lastWatched(List<Episode> watched, Set<int> shown) {
  Episode? best;
  for (final e in watched) {
    if (e.season == null || !shown.contains(e.season)) continue;
    if (best == null || _later(e, best)) best = e;
  }
  return best?.season;
}

/// Позже ли [a], чем [b]. Отметка с датой важнее отметки без даты; при равных
/// датах (сезон отмечен целиком одним днём) решает порядок серий.
bool _later(Episode a, Episode b) {
  final da = a.watchedAt, db = b.watchedAt;
  if (da != null && db == null) return true;
  if (da == null && db != null) return false;
  if (da != null && db != null && da != db) return da.isAfter(db);
  final sa = a.season ?? 0, sb = b.season ?? 0;
  if (sa != sb) return sa > sb;
  return (a.number ?? 0) > (b.number ?? 0);
}

/// Досмотрены ли все вышедшие серии сезона.
///
/// Дата выхода проверяется всегда, независимо от настройки «Не отмечать
/// невышедшие серии»: сезон, у которого остались только анонсы, для выбора
/// экрана уже досмотрен.
bool _finished(
  int season,
  List<TmdbEpisode> episodes,
  List<Episode> watched,
  DateTime now,
) {
  final aired = episodes.where((e) => _airedBy(e, now)).toList();
  if (aired.isEmpty) return false;
  final seen = {
    for (final e in watched)
      if (e.season == season && e.number != null) e.number!,
  };
  return aired.every((e) => seen.contains(e.number));
}

/// Неизвестная или непарсимая дата — серия считается вышедшей, как на экране.
bool _airedBy(TmdbEpisode e, DateTime now) {
  final d = DateTime.tryParse(e.airDate ?? '');
  return d == null || !d.isAfter(now);
}
