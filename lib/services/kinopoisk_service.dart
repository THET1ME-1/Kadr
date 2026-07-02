import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Совпадение из kinopoisk.dev: русское название, постер, рейтинг КП.
class KpMatch {
  final int id;
  final String? ruName;
  final String? posterUrl;
  final double? kpRating;
  const KpMatch({required this.id, this.ruName, this.posterUrl, this.kpRating});
}

/// Исключение при исчерпании суточного лимита (или блокировке) API.
class KinopoiskLimitException implements Exception {
  final int statusCode;
  KinopoiskLimitException(this.statusCode);
  @override
  String toString() => 'Kinopoisk API limit/blocked ($statusCode)';
}

/// Клиент kinopoisk.dev (ПоискКино API). Поиск фильма по названию+году →
/// русское имя + постер. Демо-тариф ограничен (200/сутки), поэтому вызовы
/// делаются экономно и результаты кэшируются в библиотеке.
class KinopoiskService {
  KinopoiskService._();

  static final Map<String, String> _headers = {
    'X-API-KEY': ApiConfig.kinopoiskKey,
    'accept': 'application/json',
  };

  /// Ищет фильм и возвращает лучшее совпадение (или null, если не найдено).
  /// Бросает [KinopoiskLimitException] при 403/429 — чтобы остановить дозагрузку.
  static Future<KpMatch?> search(String title, {int? year}) async {
    final uri = Uri.parse('${ApiConfig.kinopoiskBase}/v1.4/movie/search')
        .replace(queryParameters: {
      'page': '1',
      'limit': '5',
      'query': title,
    });
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 403 || resp.statusCode == 429) {
      throw KinopoiskLimitException(resp.statusCode);
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
    return KpMatch(
      id: (best['id'] as num).toInt(),
      ruName: best['name'] as String?,
      posterUrl: (poster?['url'] ?? poster?['previewUrl']) as String?,
      kpRating: (rating?['kp'] as num?)?.toDouble(),
    );
  }

  /// Выбор лучшего совпадения: приоритет — совпадение оригинального названия и
  /// года; постер и наличие русского имени — плюсом.
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
