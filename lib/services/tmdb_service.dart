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
  final String name;
  final String? character;
  final String? photoUrl;
  const TmdbCast({required this.name, this.character, this.photoUrl});
}

/// Подробности фильма из TMDB (для карточки: бэкдроп, описание, жанры, актёры,
/// бюджет/сборы, режиссёр).
class TmdbDetails {
  final String? overview;
  final String? tagline;
  final String? backdropUrl;
  final String? director;
  final String? imdbId;
  final List<String> genres;
  final int? budget;
  final int? revenue;
  final int? runtime;
  final List<TmdbCast> cast;
  const TmdbDetails({
    this.overview,
    this.tagline,
    this.backdropUrl,
    this.director,
    this.imdbId,
    this.genres = const [],
    this.budget,
    this.revenue,
    this.runtime,
    this.cast = const [],
  });
}

/// Сезон сериала (для навигации по сериям).
class TmdbSeason {
  final int number;
  final String name;
  final int episodeCount;
  const TmdbSeason(
      {required this.number, required this.name, required this.episodeCount});
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
      final castList = (credits?['cast'] as List? ?? []).take(12).map((c) {
        final m = c as Map<String, dynamic>;
        final photo = m['profile_path'] as String?;
        return TmdbCast(
          name: m['name'] as String? ?? '',
          character: m['character'] as String?,
          photoUrl:
              photo != null ? '${ApiConfig.tmdbProfileBase}$photo' : null,
        );
      }).toList();
      String? director;
      for (final c in (credits?['crew'] as List? ?? [])) {
        final m = c as Map<String, dynamic>;
        if (m['job'] == 'Director') {
          director = m['name'] as String?;
          break;
        }
      }
      final backdrop = j['backdrop_path'] as String?;
      final details = TmdbDetails(
        overview: j['overview'] as String?,
        imdbId: j['imdb_id'] as String?,
        tagline: (j['tagline'] as String?)?.isNotEmpty == true
            ? j['tagline'] as String
            : null,
        backdropUrl:
            backdrop != null ? '${ApiConfig.tmdbBackdropBase}$backdrop' : null,
        director: director,
        genres: [
          for (final g in (j['genres'] as List? ?? []))
            (g as Map<String, dynamic>)['name'] as String? ?? ''
        ].where((s) => s.isNotEmpty).toList(),
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

  /// Популярное сейчас (лента «Обзор»).
  static Future<List<TmdbMovie>> trending() =>
      _list('/trending/movie/week', {'language': 'ru-RU'});

  /// Сейчас в кино (лента «В кино»).
  static Future<List<TmdbMovie>> nowPlaying() => _list(
      '/movie/now_playing', {'language': 'ru-RU', 'region': 'RU', 'page': '1'});

  static Future<List<TmdbMovie>> _list(
      String path, Map<String, String> query) async {
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
          .where((r) => r['poster_path'] != null)
          .map((r) => TmdbMovie.fromJson(r))
          .toList();
    } catch (e) {
      debugPrint('tmdb list $path error: $e');
      return [];
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
      final list = (j['seasons'] as List? ?? [])
          .map((s) => s as Map<String, dynamic>)
          .where((s) => s['season_number'] != null)
          .map((s) => TmdbSeason(
                number: (s['season_number'] as num).toInt(),
                name: s['name'] as String? ?? '',
                episodeCount: (s['episode_count'] as num?)?.toInt() ?? 0,
              ))
          .where((s) => s.episodeCount > 0 && s.number >= 1)
          .toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      _seasonsCache[tvId] = list;
      return list;
    } catch (e) {
      debugPrint('tmdb seasons $tvId error: $e');
      return [];
    }
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
