import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_keys.dart';
import 'movie_source.dart';

/// Клиент kinopoisk.dev (ПоискКино API). Поиск фильма по названию+году →
/// русское имя + постер + рейтинг КП. Демо-тариф ограничен (200/сутки).
class KinopoiskService {
  KinopoiskService._();

  // Геттер: ключ вводит пользователь (может смениться в настройках).
  static Map<String, String> get _headers => {
        'X-API-KEY': ApiKeys.kinopoiskKey,
        'accept': 'application/json',
  };

  static Future<SourceMatch?> search(String title, {int? year}) async {
    final uri = Uri.parse('${ApiConfig.kinopoiskBase}/v1.4/movie/search')
        .replace(queryParameters: {'page': '1', 'limit': '5', 'query': title});
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 403 || resp.statusCode == 429) {
      throw SourceLimitException(resp.statusCode);
    }
    if (resp.statusCode != 200) {
      debugPrint('kinopoisk search ${resp.statusCode}: ${resp.body}');
      return null;
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final docs = (data['docs'] as List? ?? []).cast<Map<String, dynamic>>();
    if (docs.isEmpty) return null;
    final best = _pick(docs, title, year);
    if (best == null) return null;
    final rating = best['rating'] as Map<String, dynamic>?;
    final poster = best['poster'] as Map<String, dynamic>?;
    final id = (best['id'] as num).toInt();
    return SourceMatch(
      kinopoiskId: id,
      ruName: best['name'] as String?,
      posterUrl: (poster?['url'] ?? poster?['previewUrl']) as String? ??
          'https://st.kp.yandex.net/images/film_iphone/iphone360_$id.jpg',
      rating: (rating?['kp'] as num?)?.toDouble(),
    );
  }

  static Map<String, dynamic>? _pick(
      List<Map<String, dynamic>> docs, String query, int? year) {
    final q = query.toLowerCase().trim();
    Map<String, dynamic>? best;
    int bestScore = -1000;
    for (final d in docs) {
      final names = <String>{
        if (d['name'] is String) (d['name'] as String).toLowerCase(),
        if (d['alternativeName'] is String)
          (d['alternativeName'] as String).toLowerCase(),
        if (d['enName'] is String) (d['enName'] as String).toLowerCase(),
        for (final n in (d['names'] as List? ?? []))
          if (n is Map && n['name'] is String)
            (n['name'] as String).toLowerCase(),
      };
      final y = (d['year'] as num?)?.toInt();
      var s = 0;
      if (names.contains(q)) s += 3;
      if (year != null && y != null) {
        if (y == year) {
          s += 4;
        } else if ((y - year).abs() <= 1) {
          s += 1;
        } else {
          s -= 2;
        }
      }
      if ((d['poster'] as Map?)?['url'] != null) s += 1;
      if ((d['name'] as String?)?.isNotEmpty == true) s += 1;
      if (s > bestScore) {
        bestScore = s;
        best = d;
      }
    }
    return best;
  }
}
