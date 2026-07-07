import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../models/social.dart';

/// Ошибка бэкенда соц-слоя с машинным кодом (`email_taken`, `invalid_credentials`,
/// `rate_limited`, `weak_password`, `user_not_found`, …) — UI переводит её в
/// понятное сообщение. [network] == true — не достучались до сервера.
class SocialException implements Exception {
  final String code;
  final int status;
  final bool network;
  const SocialException(this.code, {this.status = 0, this.network = false});

  @override
  String toString() => 'SocialException($code, $status)';
}

/// Тонкий HTTP-клиент к Worker'у соц-слоя. Без состояния — токен передаётся
/// аргументом; хранит и раздаёт его [SocialController].
class SocialApi {
  SocialApi._();
  static final SocialApi instance = SocialApi._();

  static const _timeout = Duration(seconds: 15);
  Uri _u(String path) => Uri.parse('${ApiConfig.socialBase}$path');

  Map<String, String> _headers([String? token]) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Общий разбор ответа: 2xx → тело (Map), иначе — SocialException с кодом.
  Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      body = {};
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    throw SocialException(
      body['error'] as String? ?? 'http_${r.statusCode}',
      status: r.statusCode,
    );
  }

  Future<http.Response> _get(String path, String token) => http
      .get(_u(path), headers: _headers(token))
      .timeout(_timeout);

  Future<http.Response> _post(String path, Map<String, dynamic> body,
          [String? token]) =>
      http
          .post(_u(path), headers: _headers(token), body: jsonEncode(body))
          .timeout(_timeout);

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on SocialException {
      rethrow;
    } catch (_) {
      throw const SocialException('network', network: true);
    }
  }

  // ------------------------------- auth -------------------------------

  Future<({String token, SocialUser user})> register({
    required String email,
    required String password,
    required String displayName,
  }) =>
      _guard(() async {
        final b = _decode(await _post('/auth/register', {
          'email': email,
          'password': password,
          'displayName': displayName,
        }));
        return (
          token: b['token'] as String,
          user: SocialUser.fromJson(b['user'] as Map<String, dynamic>),
        );
      });

  Future<({String token, SocialUser user})> login({
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final b = _decode(
            await _post('/auth/login', {'email': email, 'password': password}));
        return (
          token: b['token'] as String,
          user: SocialUser.fromJson(b['user'] as Map<String, dynamic>),
        );
      });

  Future<SocialUser> me(String token) => _guard(() async {
        final b = _decode(await _get('/me', token));
        return SocialUser.fromJson(b['user'] as Map<String, dynamic>);
      });

  Future<SocialUser> updateMe(String token, {required String displayName}) =>
      _guard(() async {
        final r = await http
            .patch(_u('/me'),
                headers: _headers(token),
                body: jsonEncode({'displayName': displayName}))
            .timeout(_timeout);
        final b = _decode(r);
        return SocialUser.fromJson(b['user'] as Map<String, dynamic>);
      });

  /// Загрузить аватар (байты уже сжатого PNG). Возвращает новую версию фото.
  Future<int> uploadAvatar(String token, List<int> pngBytes) =>
      _guard(() async {
        final r = await http
            .put(_u('/me/avatar'),
                headers: {
                  'Content-Type': 'image/png',
                  'Authorization': 'Bearer $token',
                },
                body: pngBytes)
            .timeout(_timeout);
        final b = _decode(r);
        return (b['avatar'] as num?)?.toInt() ?? 0;
      });

  Future<void> logout(String token) => _guard(() async {
        await _post('/auth/logout', {}, token);
      });

  // ------------------------------ friends ------------------------------

  Future<FriendsData> friends(String token) => _guard(() async {
        return FriendsData.fromJson(_decode(await _get('/friends', token)));
      });

  /// Отправить заявку по коду ИЛИ id. Возвращает итоговый статус
  /// (`pending` / `accepted`).
  Future<String> requestFriend(String token, {String? code, String? userId}) =>
      _guard(() async {
        final b = _decode(await _post('/friends/request', {
          'code': ?code,
          'userId': ?userId,
        }, token));
        return b['status'] as String? ?? 'pending';
      });

  Future<void> respondFriend(String token,
          {required String userId, required String action}) =>
      _guard(() async {
        _decode(await _post(
            '/friends/respond', {'userId': userId, 'action': action}, token));
      });

  Future<void> removeFriend(String token, String userId) => _guard(() async {
        final r = await http
            .delete(_u('/friends/$userId'), headers: _headers(token))
            .timeout(_timeout);
        _decode(r);
      });

  Future<List<SocialUser>> userFriends(String token, String userId) =>
      _guard(() async {
        final b = _decode(await _get('/friends/$userId/friends', token));
        return [
          for (final e in (b['friends'] as List? ?? []))
            SocialUser.fromJson(e as Map<String, dynamic>),
        ];
      });

  // ------------------------------ library ------------------------------

  /// Опубликовать свою публичную проекцию (перезаписью).
  Future<void> putLibrary(String token, Map<String, dynamic> projection) =>
      _guard(() async {
        final r = await http
            .put(_u('/library'),
                headers: _headers(token), body: jsonEncode(projection))
            .timeout(_timeout);
        _decode(r);
      });

  /// Проекция библиотеки друга: `data` (или null, если не публиковал) + время.
  Future<({Map<String, dynamic>? data, int updatedAt})> friendLibrary(
          String token, String userId) =>
      _guard(() async {
        final b = _decode(await _get('/friends/$userId/library', token));
        return (
          data: b['data'] as Map<String, dynamic>?,
          updatedAt: (b['updatedAt'] as num?)?.toInt() ?? 0,
        );
      });
}
