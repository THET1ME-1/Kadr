import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'movie_source.dart';
import 'store.dart';

/// Клиент TheTVDB (v4). apikey живёт ТОЛЬКО в воркере — сюда приходит только
/// bearer-токен (`$socialBase/tvdb/token`), который кэшируется (~месяц).
/// Возвращает [SourceMatch] с перекрёстными ID (tvdb + imdb + tmdb) — по ним
/// запись сопоставляется в любой базе (миграция без потерь).
class TvdbService {
  static const String _base = 'https://api4.thetvdb.com/v4';
  static String? _token;
  static int _tokenAt = 0; // unix-секунды получения

  static int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;
  static const int _ttl = 25 * 86400; // держим токен 25 дней (живёт ~30)

  /// Актуальный токен (из памяти/Store или свежий через воркер).
  static Future<String?> _getToken({bool force = false}) async {
    if (!force && _token != null && _now - _tokenAt < _ttl) return _token;
    if (!force) {
      final stored = await Store.instance.getString('tvdb.token');
      final at = await Store.instance.getInt('tvdb.tokenAt') ?? 0;
      if (stored != null && stored.isNotEmpty && _now - at < _ttl) {
        _token = stored;
        _tokenAt = at;
        return _token;
      }
    }
    try {
      final r = await http
          .post(Uri.parse('${ApiConfig.socialBase}/tvdb/token'),
              headers: {'Content-Type': 'application/json'}, body: '{}')
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final t = ((jsonDecode(r.body)['data'] as Map?)?['token']) as String?;
      if (t == null || t.isEmpty) return null;
      _token = t;
      _tokenAt = _now;
      await Store.instance.setString('tvdb.token', t);
      await Store.instance.setInt('tvdb.tokenAt', _now);
      return t;
    } catch (_) {
      return null;
    }
  }

  /// Поиск фильма. Как у TMDB/Kinopoisk — возвращает [SourceMatch] или null.
  static Future<SourceMatch?> search(String title, {int? year}) async {
    var token = await _getToken();
    if (token == null) return null;
    final uri = Uri.parse('$_base/search').replace(queryParameters: {
      'query': title,
      'type': 'movie',
      if (year != null) 'year': '$year',
      'limit': '6',
    });
    try {
      var r = await http.get(uri, headers: _h(token)).timeout(
            const Duration(seconds: 15),
          );
      // Токен протух — обновляем и повторяем один раз.
      if (r.statusCode == 401) {
        token = await _getToken(force: true);
        if (token == null) return null;
        r = await http.get(uri, headers: _h(token)).timeout(
              const Duration(seconds: 15),
            );
      }
      if (r.statusCode == 429) throw SourceLimitException(429);
      if (r.statusCode != 200) return null;
      final data = (jsonDecode(r.body)['data'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final best = _pick(data, title, year);
      if (best == null) return null;

      int? tmdb;
      String? imdb;
      for (final rid in (best['remote_ids'] as List? ?? [])) {
        final src = ((rid as Map)['sourceName'] ?? '').toString().toLowerCase();
        final id = rid['id']?.toString();
        if (id == null) continue;
        if (src.contains('moviedb')) tmdb = int.tryParse(id);
        if (src.contains('imdb')) imdb = id;
      }
      final image = best['image_url'] as String?;
      return SourceMatch(
        ruName: (best['name'] as String?)?.trim(),
        posterUrl: (image != null && image.isNotEmpty) ? image : null,
        tvdbId: int.tryParse('${best['tvdb_id'] ?? ''}'),
        tmdbId: tmdb,
        imdbId: imdb,
      );
    } catch (e) {
      if (e is SourceLimitException) rethrow;
      return null;
    }
  }

  static Map<String, String> _h(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  /// Выбор лучшего результата: точное совпадение названия + год, иначе первый.
  static Map<String, dynamic>? _pick(
      List<Map<String, dynamic>> docs, String query, int? year) {
    if (docs.isEmpty) return null;
    final q = query.toLowerCase().trim();
    Map<String, dynamic>? best;
    for (final d in docs) {
      final name = (d['name'] as String? ?? '').toLowerCase().trim();
      final y = int.tryParse('${d['year'] ?? ''}');
      final titleOk = name == q;
      final yearOk = year == null || y == null || (y - year).abs() <= 1;
      if (titleOk && yearOk) return d;
      if (best == null && yearOk) best = d;
    }
    return best ?? docs.first;
  }
}
