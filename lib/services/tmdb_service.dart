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

/// Клиент TMDB (v4 Bearer). Бесплатно, без суточного лимита. Отдаёт русские
/// названия и постеры (`language=ru-RU`). Поиск фильма по названию+году.
class TmdbService {
  TmdbService._();

  static final Map<String, String> _headers = {
    'Authorization': 'Bearer ${ApiConfig.tmdbToken}',
    'accept': 'application/json',
  };

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
