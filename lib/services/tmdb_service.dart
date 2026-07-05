import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'movie_source.dart';

/// Краткая карточка фильма из TMDB (для лент «Обзор»/«В кино»).
class TmdbMovie {
  final int id;
  final String title; // русское (ru-RU)
  final String? originalTitle;
  final String? posterUrl;
  final int? year;
  final double? rating;
  final String? overview;

  const TmdbMovie({
    required this.id,
    required this.title,
    this.originalTitle,
    this.posterUrl,
    this.year,
    this.rating,
    this.overview,
  });

  factory TmdbMovie.fromJson(Map<String, dynamic> j) {
    final rel = j['release_date'] as String? ?? '';
    final poster = j['poster_path'] as String?;
    return TmdbMovie(
      id: (j['id'] as num).toInt(),
      title: (j['title'] as String?)?.isNotEmpty == true
          ? j['title'] as String
          : (j['original_title'] as String? ?? ''),
      originalTitle: j['original_title'] as String?,
      posterUrl:
          poster != null ? '${ApiConfig.tmdbImageBase}$poster' : null,
      year: rel.length >= 4 ? int.tryParse(rel.substring(0, 4)) : null,
      rating: (j['vote_average'] as num?)?.toDouble(),
      overview: j['overview'] as String?,
    );
  }
}

/// Актёр в деталях фильма.
class TmdbCast {
  final int id;
  final String name;
  final String? character;
  final String? photoUrl;
  const TmdbCast(
      {required this.id, required this.name, this.character, this.photoUrl});
}

/// Жанр (id + название) — название кликабельно и ведёт в подборку по жанру.
class TmdbGenre {
  final int id;
  final String name;
  const TmdbGenre({required this.id, required this.name});
}

/// Краткая карточка сериала из TMDB (для ленты «Сериалы»).
class TmdbSeries {
  final int id;
  final String title; // русское (ru-RU)
  final String? originalTitle;
  final String? posterUrl;
  final int? year;
  final double? rating;
  final String? overview;

  const TmdbSeries({
    required this.id,
    required this.title,
    this.originalTitle,
    this.posterUrl,
    this.year,
    this.rating,
    this.overview,
  });

  factory TmdbSeries.fromJson(Map<String, dynamic> j) {
    final rel = j['first_air_date'] as String? ?? '';
    final poster = j['poster_path'] as String?;
    return TmdbSeries(
      id: (j['id'] as num).toInt(),
      title: (j['name'] as String?)?.isNotEmpty == true
          ? j['name'] as String
          : (j['original_name'] as String? ?? ''),
      originalTitle: j['original_name'] as String?,
      posterUrl: poster != null ? '${ApiConfig.tmdbImageBase}$poster' : null,
      year: rel.length >= 4 ? int.tryParse(rel.substring(0, 4)) : null,
      rating: (j['vote_average'] as num?)?.toDouble(),
      overview: j['overview'] as String?,
    );
  }
}

/// Подробности фильма из TMDB (для карточки: бэкдроп, описание, жанры, актёры,
/// бюджет/сборы, режиссёр).
class TmdbDetails {
  final String? overview;
  final String? tagline;
  final String? backdropUrl;
  final String? director;
  final int? directorId;
  final String? imdbId;
  final List<TmdbGenre> genres;
  final int? budget;
  final int? revenue;
  final int? runtime;
  final List<TmdbCast> cast;

  /// Коллекция/франшиза, к которой принадлежит фильм (напр. «Гарри Поттер»).
  final int? collectionId;
  final String? collectionName;

  /// Страны производства (названия, ru).
  final List<String> countries;

  const TmdbDetails({
    this.overview,
    this.tagline,
    this.backdropUrl,
    this.director,
    this.directorId,
    this.imdbId,
    this.genres = const [],
    this.budget,
    this.revenue,
    this.runtime,
    this.cast = const [],
    this.collectionId,
    this.collectionName,
    this.countries = const [],
  });
}

/// Русские названия стран по ISO-3166-1 (частые). Фолбэк — англ. название TMDB.
const Map<String, String> kCountryRu = {
  'US': 'США', 'GB': 'Великобритания', 'RU': 'Россия', 'FR': 'Франция',
  'DE': 'Германия', 'IT': 'Италия', 'ES': 'Испания', 'JP': 'Япония',
  'KR': 'Южная Корея', 'CN': 'Китай', 'IN': 'Индия', 'CA': 'Канада',
  'AU': 'Австралия', 'BR': 'Бразилия', 'MX': 'Мексика', 'SE': 'Швеция',
  'NO': 'Норвегия', 'DK': 'Дания', 'FI': 'Финляндия', 'NL': 'Нидерланды',
  'BE': 'Бельгия', 'PL': 'Польша', 'CZ': 'Чехия', 'AT': 'Австрия',
  'CH': 'Швейцария', 'IE': 'Ирландия', 'PT': 'Португалия', 'GR': 'Греция',
  'TR': 'Турция', 'UA': 'Украина', 'HK': 'Гонконг', 'TW': 'Тайвань',
  'TH': 'Таиланд', 'AR': 'Аргентина', 'NZ': 'Новая Зеландия', 'ZA': 'ЮАР',
  'IL': 'Израиль', 'IS': 'Исландия', 'HU': 'Венгрия', 'RO': 'Румыния',
};

/// Доп. данные сериала для шапки экрана: бэкдроп, описание, жанры.
class TmdbTvExtra {
  final String? backdropUrl;
  final String? overview;
  final List<TmdbGenre> genres;
  const TmdbTvExtra({this.backdropUrl, this.overview, this.genres = const []});
}

/// Сезон сериала (для навигации по сериям).
class TmdbSeason {
  final int number;
  final String name;
  final int episodeCount;

  /// Дата выхода сезона (первой серии), ISO `YYYY-MM-DD`. Нужна, чтобы не
  /// показывать сезоны, которые ещё не начали выходить.
  final String? airDate;
  const TmdbSeason(
      {required this.number,
      required this.name,
      required this.episodeCount,
      this.airDate});
}

/// Эпизод сериала из TMDB.
class TmdbEpisode {
  final int season;
  final int number;
  final String name;
  final String? airDate;
  final String? stillUrl;
  final int? runtime;
  final String? overview;
  const TmdbEpisode({
    required this.season,
    required this.number,
    required this.name,
    this.airDate,
    this.stillUrl,
    this.runtime,
    this.overview,
  });
}

/// Клиент TMDB (v4 Bearer). Бесплатно, без суточного лимита. Отдаёт русские
/// названия и постеры (`language=ru-RU`). Поиск фильма по названию+году.
class TmdbService {
  TmdbService._();

  static final Map<String, String> _headers = {
    'Authorization': 'Bearer ${ApiConfig.tmdbToken}',
    'accept': 'application/json',
  };

  /// Кэш подробностей в памяти (на сессию).
  static final Map<int, TmdbDetails> _detailsCache = {};

  /// Подробности фильма по tmdbId (описание, жанры, актёры, бюджет, бэкдроп).
  static Future<TmdbDetails?> details(int tmdbId) async {
    if (_detailsCache.containsKey(tmdbId)) return _detailsCache[tmdbId];
    try {
      final uri = Uri.parse('${ApiConfig.tmdbBase}/movie/$tmdbId').replace(
          queryParameters: {
            'language': 'ru-RU',
            'append_to_response': 'credits'
          });
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final credits = j['credits'] as Map<String, dynamic>?;
      final castList = (credits?['cast'] as List? ?? []).take(16).map((c) {
        final m = c as Map<String, dynamic>;
        final photo = m['profile_path'] as String?;
        return TmdbCast(
          id: (m['id'] as num?)?.toInt() ?? 0,
          name: m['name'] as String? ?? '',
          character: m['character'] as String?,
          photoUrl:
              photo != null ? '${ApiConfig.tmdbProfileBase}$photo' : null,
        );
      }).toList();
      String? director;
      int? directorId;
      for (final c in (credits?['crew'] as List? ?? [])) {
        final m = c as Map<String, dynamic>;
        if (m['job'] == 'Director') {
          director = m['name'] as String?;
          directorId = (m['id'] as num?)?.toInt();
          break;
        }
      }
      final backdrop = j['backdrop_path'] as String?;
      final coll = j['belongs_to_collection'] as Map<String, dynamic>?;
      final countries = [
        for (final c in (j['production_countries'] as List? ?? []))
          kCountryRu[(c as Map<String, dynamic>)['iso_3166_1']] ??
              (c['name'] as String? ?? '')
      ].where((s) => s.isNotEmpty).toList();
      final details = TmdbDetails(
        collectionId: (coll?['id'] as num?)?.toInt(),
        collectionName: coll?['name'] as String?,
        countries: countries,
        overview: j['overview'] as String?,
        imdbId: j['imdb_id'] as String?,
        tagline: (j['tagline'] as String?)?.isNotEmpty == true
            ? j['tagline'] as String
            : null,
        backdropUrl:
            backdrop != null ? '${ApiConfig.tmdbBackdropBase}$backdrop' : null,
        director: director,
        directorId: directorId,
        genres: [
          for (final g in (j['genres'] as List? ?? []))
            TmdbGenre(
              id: ((g as Map<String, dynamic>)['id'] as num?)?.toInt() ?? 0,
              name: g['name'] as String? ?? '',
            )
        ].where((g) => g.name.isNotEmpty).toList(),
        budget: (j['budget'] as num?)?.toInt(),
        revenue: (j['revenue'] as num?)?.toInt(),
        runtime: (j['runtime'] as num?)?.toInt(),
        cast: castList,
      );
      _detailsCache[tmdbId] = details;
      return details;
    } catch (e) {
      debugPrint('tmdb details $tmdbId error: $e');
      return null;
    }
  }

  /// Кэш частей коллекций (на сессию).
  static final Map<int, List<TmdbMovie>> _collectionCache = {};

  /// Части коллекции/франшизы по id, по порядку выхода (ранние сверху).
  static Future<List<TmdbMovie>> collection(int collectionId) async {
    if (_collectionCache.containsKey(collectionId)) {
      return _collectionCache[collectionId]!;
    }
    try {
      final uri = Uri.parse('${ApiConfig.tmdbBase}/collection/$collectionId')
          .replace(queryParameters: {'language': 'ru-RU'});
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final parts = (j['parts'] as List? ?? [])
          .map((e) => TmdbMovie.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
      _collectionCache[collectionId] = parts;
      return parts;
    } catch (e) {
      debugPrint('tmdb collection $collectionId error: $e');
      return [];
    }
  }

  /// Популярное сейчас (лента «Обзор»). Пагинируется для бесконечной ленты.
  static Future<List<TmdbMovie>> trending({int page = 1}) =>
      _list('/trending/movie/week', {'language': 'ru-RU', 'page': '$page'});

  /// Сейчас в кино (лента «В кино»).
  static Future<List<TmdbMovie>> nowPlaying({int page = 1}) => _list(
      '/movie/now_playing',
      {'language': 'ru-RU', 'region': 'RU', 'page': '$page'});

  /// Поиск фильмов по всей базе TMDB (для общего поиска в «Обзор»/«В кино»).
  /// Не отбрасываем результаты без постера — у поиска важна полнота
  /// (Poster рисует заглушку).
  static Future<List<TmdbMovie>> searchMovies(String query,
      {int page = 1}) {
    final q = query.trim();
    if (q.isEmpty) return Future.value([]);
    return _list('/search/movie', {
      'language': 'ru-RU',
      'include_adult': 'true',
      'query': q,
      'page': '$page',
    }, requirePoster: false);
  }

  static String get _today =>
      DateTime.now().toIso8601String().split('T').first;

  /// Подборка фильмов с фильтрами: жанр, год, сортировка. Используется и для
  /// страницы жанра, и для фильтров в «Обзоре»/«В кино».
  /// [nowPlayingWindow] — ограничить прокатным окном (последние ~1.5 месяца).
  static Future<List<TmdbMovie>> discoverMovies({
    int page = 1,
    int? genreId,
    int? year,
    String sortBy = 'popularity.desc',
    bool nowPlayingWindow = false,
  }) {
    final byRating = sortBy.startsWith('vote_average');
    final byDate = sortBy.startsWith('primary_release_date');
    final window = nowPlayingWindow && year == null;
    final from = DateTime.now().subtract(const Duration(days: 45));
    return _list('/discover/movie', {
      'language': 'ru-RU',
      'sort_by': sortBy,
      'page': '$page',
      if (genreId != null) 'with_genres': '$genreId',
      if (year != null) 'primary_release_year': '$year',
      // Отсечь мусор без голосов при сортировке по рейтингу.
      if (byRating) 'vote_count.gte': '200',
      if (!byRating && genreId != null && !window) 'vote_count.gte': '40',
      // «Новинки» — только уже вышедшее.
      if (byDate) 'primary_release_date.lte': _today,
      if (window) ...{
        'primary_release_date.gte':
            from.toIso8601String().split('T').first,
        'primary_release_date.lte': _today,
        'with_release_type': '2|3',
      },
    });
  }

  /// Подборка сериалов с фильтрами (жанр, год, сортировка).
  static Future<List<TmdbSeries>> discoverTv({
    int page = 1,
    int? genreId,
    int? year,
    String sortBy = 'popularity.desc',
  }) {
    final byRating = sortBy.startsWith('vote_average');
    final byDate = sortBy.startsWith('first_air_date');
    return _listTv('/discover/tv', {
      'language': 'ru-RU',
      'sort_by': sortBy,
      'page': '$page',
      if (genreId != null) 'with_genres': '$genreId',
      if (year != null) 'first_air_date_year': '$year',
      if (byRating) 'vote_count.gte': '150',
      if (byDate) 'first_air_date.lte': _today,
    });
  }

  /// Фильмография персоны (актёр/режиссёр) — все фильмы, где участвовал.
  static Future<List<TmdbMovie>> personMovieCredits(int personId) async {
    try {
      final uri = Uri.parse('${ApiConfig.tmdbBase}/person/$personId/movie_credits')
          .replace(queryParameters: {'language': 'ru-RU'});
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final cast =
          (data['cast'] as List? ?? []).cast<Map<String, dynamic>>();
      final crew =
          (data['crew'] as List? ?? []).cast<Map<String, dynamic>>();
      // Уникальные фильмы (актёр мог быть и в команде), свежие/популярные сверху.
      final byId = <int, Map<String, dynamic>>{};
      for (final r in [...cast, ...crew]) {
        final id = (r['id'] as num?)?.toInt();
        if (id == null) continue;
        byId.putIfAbsent(id, () => r);
      }
      final list = byId.values.map((r) => TmdbMovie.fromJson(r)).toList()
        ..sort((a, b) {
          final ay = a.year ?? 0, by = b.year ?? 0;
          return by.compareTo(ay);
        });
      return list;
    } catch (e) {
      debugPrint('tmdb person credits $personId error: $e');
      return [];
    }
  }

  static Future<List<TmdbMovie>> _list(
      String path, Map<String, String> query,
      {bool requirePoster = true}) async {
    try {
      final uri =
          Uri.parse('${ApiConfig.tmdbBase}$path').replace(queryParameters: query);
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results =
          (data['results'] as List? ?? []).cast<Map<String, dynamic>>();
      return results
          .where((r) => !requirePoster || r['poster_path'] != null)
          .map((r) => TmdbMovie.fromJson(r))
          .toList();
    } catch (e) {
      // Пробрасываем сетевой сбой — лента (InfiniteGrid) покажет «нет
      // соединения» с повтором, а не обманчивое «ничего не найдено».
      debugPrint('tmdb list $path error: $e');
      rethrow;
    }
  }

  /// Популярные сериалы (лента «Сериалы» в «Обзоре»).
  static Future<List<TmdbSeries>> trendingTv({int page = 1}) =>
      _listTv('/trending/tv/week', {'language': 'ru-RU', 'page': '$page'});

  /// Сериалы в эфире (лента «Сериалы» в «В кино»).
  static Future<List<TmdbSeries>> onAirTv({int page = 1}) =>
      _listTv('/tv/on_the_air', {'language': 'ru-RU', 'page': '$page'});

  /// Поиск сериалов по всей базе TMDB (без фильтра постеров — важна полнота).
  static Future<List<TmdbSeries>> searchTvShows(String query, {int page = 1}) {
    final q = query.trim();
    if (q.isEmpty) return Future.value([]);
    return _listTv('/search/tv', {
      'language': 'ru-RU',
      'include_adult': 'true',
      'query': q,
      'page': '$page',
    }, requirePoster: false);
  }

  static Future<List<TmdbSeries>> _listTv(
      String path, Map<String, String> query,
      {bool requirePoster = true}) async {
    try {
      final uri =
          Uri.parse('${ApiConfig.tmdbBase}$path').replace(queryParameters: query);
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final results =
          (data['results'] as List? ?? []).cast<Map<String, dynamic>>();
      return results
          .where((r) => !requirePoster || r['poster_path'] != null)
          .map((r) => TmdbSeries.fromJson(r))
          .toList();
    } catch (e) {
      // Пробрасываем сетевой сбой — лента покажет «нет соединения» с повтором.
      debugPrint('tmdb tv list $path error: $e');
      rethrow;
    }
  }

  static Future<SourceMatch?> search(String title, {int? year}) async {
    final uri = Uri.parse('${ApiConfig.tmdbBase}/search/movie')
        .replace(queryParameters: {
      'query': title,
      'language': 'ru-RU',
      'include_adult': 'true',
      if (year != null) 'year': '$year',
    });
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 429) {
      throw SourceLimitException(resp.statusCode);
    }
    if (resp.statusCode != 200) {
      debugPrint('tmdb search ${resp.statusCode}: ${resp.body}');
      return null;
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final results =
        (data['results'] as List? ?? []).cast<Map<String, dynamic>>();
    if (results.isEmpty) return null;
    final best = _pick(results, title, year);
    if (best == null) return null;
    final poster = best['poster_path'] as String?;
    final ru = best['title'] as String?; // локализованное (ru-RU) название
    return SourceMatch(
      tmdbId: (best['id'] as num).toInt(),
      ruName: ru,
      posterUrl: poster != null ? '${ApiConfig.tmdbImageBase}$poster' : null,
      rating: (best['vote_average'] as num?)?.toDouble(),
    );
  }

  static final Map<int, List<TmdbSeason>> _seasonsCache = {};
  static final Map<String, List<TmdbEpisode>> _episodesCache = {};
  static final Map<int, TmdbTvExtra> _tvExtraCache = {};

  /// Бэкдроп/описание/жанры сериала (для крупной шапки экрана сериала).
  /// Заполняется попутно при загрузке [seasons]; здесь — гарантированная выборка.
  static Future<TmdbTvExtra?> tvExtra(int tvId) async {
    if (_tvExtraCache.containsKey(tvId)) return _tvExtraCache[tvId];
    await seasons(tvId); // сама выборка `/tv/{id}` кэширует extra
    return _tvExtraCache[tvId];
  }

  /// Сезоны сериала по tmdbId.
  static Future<List<TmdbSeason>> seasons(int tvId) async {
    if (_seasonsCache.containsKey(tvId)) return _seasonsCache[tvId]!;
    try {
      final uri = Uri.parse('${ApiConfig.tmdbBase}/tv/$tvId')
          .replace(queryParameters: {'language': 'ru-RU'});
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final backdrop = j['backdrop_path'] as String?;
      _tvExtraCache[tvId] = TmdbTvExtra(
        backdropUrl:
            backdrop != null ? '${ApiConfig.tmdbBackdropBase}$backdrop' : null,
        overview: (j['overview'] as String?)?.isNotEmpty == true
            ? j['overview'] as String
            : null,
        genres: [
          for (final g in (j['genres'] as List? ?? []))
            TmdbGenre(
              id: ((g as Map<String, dynamic>)['id'] as num?)?.toInt() ?? 0,
              name: g['name'] as String? ?? '',
            )
        ].where((g) => g.name.isNotEmpty).toList(),
      );
      final now = DateTime.now();
      final list = (j['seasons'] as List? ?? [])
          .map((s) => s as Map<String, dynamic>)
          .where((s) => s['season_number'] != null)
          .map((s) => TmdbSeason(
                number: (s['season_number'] as num).toInt(),
                name: s['name'] as String? ?? '',
                episodeCount: (s['episode_count'] as num?)?.toInt() ?? 0,
                airDate: s['air_date'] as String?,
              ))
          // Спецматериалы (сезон 0) и пустые сезоны — пропускаем. Сезоны, которые
          // ещё не начали выходить (дата эфира в будущем), тоже не показываем.
          .where((s) => s.episodeCount > 0 && s.number >= 1 && !_seasonInFuture(s, now))
          .toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      _seasonsCache[tvId] = list;
      return list;
    } catch (e) {
      debugPrint('tmdb seasons $tvId error: $e');
      return [];
    }
  }

  /// Сезон ещё не начал выходить (дата эфира строго в будущем). Неизвестную
  /// дату считаем «вышел» (сериалы в эфире часто без даты у текущего сезона).
  static bool _seasonInFuture(TmdbSeason s, DateTime now) {
    final d = s.airDate;
    if (d == null || d.isEmpty) return false;
    final parsed = DateTime.tryParse(d);
    if (parsed == null) return false;
    return parsed.isAfter(now);
  }

  /// Эпизоды конкретного сезона сериала.
  static Future<List<TmdbEpisode>> episodesOf(int tvId, int season) async {
    final key = '$tvId/$season';
    if (_episodesCache.containsKey(key)) return _episodesCache[key]!;
    try {
      final uri = Uri.parse('${ApiConfig.tmdbBase}/tv/$tvId/season/$season')
          .replace(queryParameters: {'language': 'ru-RU'});
      final resp = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final list = (j['episodes'] as List? ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        final still = m['still_path'] as String?;
        return TmdbEpisode(
          season: (m['season_number'] as num?)?.toInt() ?? season,
          number: (m['episode_number'] as num?)?.toInt() ?? 0,
          name: m['name'] as String? ?? '',
          airDate: m['air_date'] as String?,
          stillUrl: still != null ? '${ApiConfig.tmdbBackdropBase}$still' : null,
          runtime: (m['runtime'] as num?)?.toInt(),
          overview: m['overview'] as String?,
        );
      }).toList();
      _episodesCache[key] = list;
      return list;
    } catch (e) {
      debugPrint('tmdb episodes $key error: $e');
      return [];
    }
  }

  /// Поиск сериала (для обогащения сериалов русским названием + постером).
  static Future<SourceMatch?> searchTv(String title, {int? year}) async {
    final uri = Uri.parse('${ApiConfig.tmdbBase}/search/tv')
        .replace(queryParameters: {
      'query': title,
      'language': 'ru-RU',
      'include_adult': 'true',
      if (year != null) 'first_air_date_year': '$year',
    });
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 401 || resp.statusCode == 429) {
      throw SourceLimitException(resp.statusCode);
    }
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final results =
        (data['results'] as List? ?? []).cast<Map<String, dynamic>>();
    if (results.isEmpty) return null;
    final q = title.toLowerCase().trim();
    Map<String, dynamic>? best;
    int bestScore = -1000;
    for (final r in results) {
      final names = {
        (r['name'] as String? ?? '').toLowerCase(),
        (r['original_name'] as String? ?? '').toLowerCase(),
      };
      var s = 0;
      if (names.contains(q)) s += 3;
      if (r['poster_path'] != null) s += 1;
      s += ((r['vote_count'] as num?)?.toInt() ?? 0) > 20 ? 1 : 0;
      if (s > bestScore) {
        bestScore = s;
        best = r;
      }
    }
    if (best == null) return null;
    final poster = best['poster_path'] as String?;
    return SourceMatch(
      tmdbId: (best['id'] as num).toInt(),
      ruName: best['name'] as String?,
      posterUrl: poster != null ? '${ApiConfig.tmdbImageBase}$poster' : null,
      rating: (best['vote_average'] as num?)?.toDouble(),
    );
  }

  /// Выбор лучшего результата: приоритет — совпадение года и наличие постера.
  static Map<String, dynamic>? _pick(
      List<Map<String, dynamic>> results, String query, int? year) {
    Map<String, dynamic>? best;
    int bestScore = -1000;
    final q = query.toLowerCase().trim();
    for (final r in results) {
      final rel = (r['release_date'] as String? ?? '');
      final ry = rel.length >= 4 ? int.tryParse(rel.substring(0, 4)) : null;
      final titles = {
        (r['title'] as String? ?? '').toLowerCase(),
        (r['original_title'] as String? ?? '').toLowerCase(),
      };
      var s = 0;
      if (titles.contains(q)) s += 3;
      if (year != null && ry != null) {
        if (ry == year) {
          s += 4;
        } else if ((ry - year).abs() <= 1) {
          s += 1;
        } else {
          s -= 3;
        }
      }
      if (r['poster_path'] != null) s += 1;
      // Популярность как мягкий тай-брейк.
      s += ((r['vote_count'] as num?)?.toInt() ?? 0) > 50 ? 1 : 0;
      if (s > bestScore) {
        bestScore = s;
        best = r;
      }
    }
    return best;
  }
}
