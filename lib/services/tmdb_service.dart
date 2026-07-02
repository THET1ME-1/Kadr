import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'movie_source.dart';

/// Клиент TMDB (v4 Bearer). Бесплатно, без суточного лимита. Отдаёт русские
/// названия и постеры (`language=ru-RU`). Поиск фильма по названию+году.
class TmdbService {
  TmdbService._();

  static final Map<String, String> _headers = {
    'Authorization': 'Bearer ${ApiConfig.tmdbToken}',
    'accept': 'application/json',
  };

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
