import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

/// OAuth-токен Trakt (хранится локально; refresh — через воркер).
class TraktToken {
  final String accessToken;
  final String refreshToken;
  final int createdAt; // unix-секунды
  final int expiresIn; // секунды

  const TraktToken({
    required this.accessToken,
    required this.refreshToken,
    required this.createdAt,
    required this.expiresIn,
  });

  /// Пора обновлять (за час до истечения).
  bool get needsRefresh =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 >
      createdAt + expiresIn - 3600;

  Map<String, dynamic> toJson() =>
      {'a': accessToken, 'r': refreshToken, 'c': createdAt, 'e': expiresIn};

  /// Понимает и локальный формат ('a'/'r'/…), и ответ Trakt (access_token/…).
  factory TraktToken.fromJson(Map<String, dynamic> j) => TraktToken(
        accessToken: (j['a'] ?? j['access_token'] ?? '') as String,
        refreshToken: (j['r'] ?? j['refresh_token'] ?? '') as String,
        createdAt: (j['c'] as num?)?.toInt() ??
            (j['created_at'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
        expiresIn: (j['e'] as num?)?.toInt() ??
            (j['expires_in'] as num?)?.toInt() ??
            7776000,
      );
}

class TraktDeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int interval;
  final int expiresIn;
  const TraktDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.interval,
    required this.expiresIn,
  });
}

enum TraktPollStatus { pending, ok, slowDown, expired, denied, error }

class TraktPollResult {
  final TraktPollStatus status;
  final TraktToken? token;
  const TraktPollResult(this.status, [this.token]);
}

/// Фильм из Trakt (для загрузки в Kadr).
typedef TraktMovie = ({int tmdb, String title, int? year, DateTime? at});

/// Низкоуровневый клиент Trakt. Секрет НЕ используется — обмен токена идёт через
/// воркер (`$socialBase/trakt/*`), а API-вызовы — с bearer-токеном пользователя.
class TraktService {
  static Map<String, String> _apiHeaders(String token) => {
        'Content-Type': 'application/json',
        'trakt-api-version': '2',
        'trakt-api-key': ApiConfig.traktClientId,
        'Authorization': 'Bearer $token',
      };

  static const Map<String, String> _pubHeaders = {
    'Content-Type': 'application/json',
    'trakt-api-version': '2',
    'trakt-api-key': ApiConfig.traktClientId,
  };

  // ---- OAuth (device flow) ----

  /// Шаг 1: получить device-код (напрямую, нужен только client_id).
  static Future<TraktDeviceCode?> deviceCode() async {
    try {
      final r = await http
          .post(Uri.parse('${ApiConfig.traktBase}/oauth/device/code'),
              headers: _pubHeaders,
              body: jsonEncode({'client_id': ApiConfig.traktClientId}))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return TraktDeviceCode(
        deviceCode: j['device_code'] as String,
        userCode: j['user_code'] as String,
        verificationUrl:
            j['verification_url'] as String? ?? 'https://trakt.tv/activate',
        interval: (j['interval'] as num?)?.toInt() ?? 5,
        expiresIn: (j['expires_in'] as num?)?.toInt() ?? 600,
      );
    } catch (_) {
      return null;
    }
  }

  /// Шаг 2: опрос токена (через воркер — там client_secret).
  static Future<TraktPollResult> pollToken(String deviceCode) async {
    try {
      final r = await http
          .post(Uri.parse('${ApiConfig.socialBase}/trakt/token'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'code': deviceCode}))
          .timeout(const Duration(seconds: 12));
      switch (r.statusCode) {
        case 200:
          return TraktPollResult(TraktPollStatus.ok,
              TraktToken.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
        case 400:
          return const TraktPollResult(TraktPollStatus.pending);
        case 429:
          return const TraktPollResult(TraktPollStatus.slowDown);
        case 418:
          return const TraktPollResult(TraktPollStatus.denied);
        case 404:
        case 409:
        case 410:
          return const TraktPollResult(TraktPollStatus.expired);
        default:
          return const TraktPollResult(TraktPollStatus.error);
      }
    } catch (_) {
      return const TraktPollResult(TraktPollStatus.error);
    }
  }

  /// Обновление токена (через воркер).
  static Future<TraktToken?> refresh(String refreshToken) async {
    try {
      final r = await http
          .post(Uri.parse('${ApiConfig.socialBase}/trakt/refresh'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refresh_token': refreshToken}))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 200) {
        return TraktToken.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---- Чтение (для загрузки в Kadr) ----

  static TraktMovie? _parseMovie(Object? e, {String? atKey}) {
    if (e is! Map) return null;
    final m = e['movie'] as Map?;
    if (m == null) return null;
    final tmdb = ((m['ids'] as Map?)?['tmdb'] as num?)?.toInt();
    if (tmdb == null) return null;
    return (
      tmdb: tmdb,
      title: (m['title'] as String?) ?? '',
      year: (m['year'] as num?)?.toInt(),
      at: atKey == null ? null : DateTime.tryParse((e[atKey] as String?) ?? ''),
    );
  }

  static Future<List<TraktMovie>> _getMovies(
      String token, String path, String? atKey) async {
    try {
      final r = await http
          .get(Uri.parse('${ApiConfig.traktBase}$path'),
              headers: _apiHeaders(token))
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) return const [];
      return [
        for (final e in jsonDecode(r.body) as List) ?_parseMovie(e, atKey: atKey)
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<TraktMovie>> watchedMovies(String token) =>
      _getMovies(token, '/sync/watched/movies', 'last_watched_at');

  static Future<List<TraktMovie>> watchlistMovies(String token) =>
      _getMovies(token, '/sync/watchlist/movies', 'listed_at');

  /// Оценки фильмов из Trakt: tmdbId → балл 1..10.
  static Future<Map<int, int>> ratedMovies(String token) async {
    final out = <int, int>{};
    try {
      final r = await http
          .get(Uri.parse('${ApiConfig.traktBase}/sync/ratings/movies'),
              headers: _apiHeaders(token))
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) return out;
      for (final e in jsonDecode(r.body) as List) {
        final tmdb =
            (((e as Map)['movie']?['ids'] as Map?)?['tmdb'] as num?)?.toInt();
        final rating = (e['rating'] as num?)?.toInt();
        if (tmdb != null && rating != null) out[tmdb] = rating;
      }
    } catch (_) {}
    return out;
  }

  // ---- Запись (Kadr → Trakt), добавление; батчами ----

  static Future<bool> _post(String token, String path, Object body) async {
    try {
      final r = await http
          .post(Uri.parse('${ApiConfig.traktBase}$path'),
              headers: _apiHeaders(token), body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, i + size > list.length ? list.length : i + size);
    }
  }

  /// Добавить в историю просмотров Trakt (не удаляет ничего).
  static Future<bool> addHistory(
      String token, List<({int tmdb, DateTime? at})> movies) async {
    var ok = true;
    for (final part in _chunks(movies, 1000)) {
      ok &= await _post(token, '/sync/history', {
        'movies': [
          for (final m in part)
            {
              if (m.at != null) 'watched_at': m.at!.toUtc().toIso8601String(),
              'ids': {'tmdb': m.tmdb}
            }
        ]
      });
    }
    return ok;
  }

  static Future<bool> addWatchlist(String token, List<int> tmdbIds) async {
    var ok = true;
    for (final part in _chunks(tmdbIds, 1000)) {
      ok &= await _post(token, '/sync/watchlist', {
        'movies': [
          for (final id in part)
            {
              'ids': {'tmdb': id}
            }
        ]
      });
    }
    return ok;
  }

  static Future<bool> addRatings(
      String token, List<({int tmdb, int rating})> movies) async {
    var ok = true;
    for (final part in _chunks(movies, 1000)) {
      ok &= await _post(token, '/sync/ratings', {
        'movies': [
          for (final m in part)
            {
              'rating': m.rating,
              'ids': {'tmdb': m.tmdb}
            }
        ]
      });
    }
    return ok;
  }
}
