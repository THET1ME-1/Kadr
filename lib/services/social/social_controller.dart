import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/social.dart';
import '../movie_repository.dart';
import '../store.dart';
import 'social_api.dart';

/// Состояние соц-слоя: текущая сессия (токен+профиль), списки друзей/заявок и
/// публикация своей проекции. Слушается экранами «Друзья»/«Профиль». Локальная
/// библиотека остаётся источником истины — сюда уходит лишь публичная витрина.
class SocialController extends ChangeNotifier {
  SocialController._();
  static final SocialController instance = SocialController._();

  static const _kToken = 'socialToken';

  String? _token;
  SocialUser? _user;
  FriendsData _friends = const FriendsData();
  bool _loading = false;

  SocialUser? get user => _user;
  FriendsData get friends => _friends;
  bool get isLoggedIn => _token != null && _user != null;
  bool get loading => _loading;
  int get incomingCount => _friends.incoming.length;

  /// Восстановление сессии при старте: валидируем токен, тянем свежий профиль.
  Future<void> load() async {
    _token = await Store.instance.getString(_kToken);
    if (_token == null) return;
    try {
      _user = await SocialApi.instance.me(_token!);
      notifyListeners();
      // Подтягиваем друзей и публикуем актуальную витрину в фоне.
      unawaited(refreshFriends());
      unawaited(publishSilently());
    } on SocialException catch (e) {
      // Токен протух/отозван — чистим. Сетевую ошибку игнорируем (попробуем позже).
      if (e.status == 401) await _clearSession();
    }
  }

  Future<void> _saveSession(String token, SocialUser user) async {
    _token = token;
    _user = user;
    await Store.instance.setString(_kToken, token);
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _token = null;
    _user = null;
    _friends = const FriendsData();
    await Store.instance.remove(_kToken);
    notifyListeners();
  }

  // ------------------------------- auth -------------------------------

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _setLoading(true);
    try {
      final r = await SocialApi.instance.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _saveSession(r.token, r.user);
      unawaited(publishSilently()); // сразу выкладываем свою библиотеку
      unawaited(refreshFriends());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> login({required String email, required String password}) async {
    _setLoading(true);
    try {
      final r = await SocialApi.instance.login(email: email, password: password);
      await _saveSession(r.token, r.user);
      unawaited(publishSilently());
      unawaited(refreshFriends());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    final t = _token;
    await _clearSession();
    if (t != null) {
      try {
        await SocialApi.instance.logout(t);
      } catch (_) {/* уже вышли локально */}
    }
  }

  Future<void> updateProfile({required String displayName}) async {
    final t = _token;
    if (t == null) return;
    _user = await SocialApi.instance.updateMe(t, displayName: displayName);
    notifyListeners();
  }

  /// Загружает новый аватар (сжатые PNG-байты) и обновляет профиль в памяти.
  Future<void> setAvatar(List<int> pngBytes) async {
    final t = _token;
    final u = _user;
    if (t == null || u == null) return;
    final ver = await SocialApi.instance.uploadAvatar(t, pngBytes);
    _user = SocialUser(
      id: u.id,
      displayName: u.displayName,
      avatarVer: ver,
      friendCode: u.friendCode,
      email: u.email,
    );
    notifyListeners();
  }

  // ------------------------------ friends ------------------------------

  Future<void> refreshFriends() async {
    final t = _token;
    if (t == null) return;
    try {
      _friends = await SocialApi.instance.friends(t);
      notifyListeners();
    } on SocialException catch (e) {
      if (e.status == 401) await _clearSession();
    }
  }

  /// Заявка по коду (или id). Возвращает статус (`pending`/`accepted`).
  Future<String> addFriend({String? code, String? userId}) async {
    final t = _token;
    if (t == null) throw const SocialException('unauthorized', status: 401);
    final status =
        await SocialApi.instance.requestFriend(t, code: code, userId: userId);
    await refreshFriends();
    return status;
  }

  Future<void> respond(String userId, {required bool accept}) async {
    final t = _token;
    if (t == null) return;
    await SocialApi.instance
        .respondFriend(t, userId: userId, action: accept ? 'accept' : 'decline');
    await refreshFriends();
  }

  Future<void> removeFriend(String userId) async {
    final t = _token;
    if (t == null) return;
    await SocialApi.instance.removeFriend(t, userId);
    await refreshFriends();
  }

  /// Друзья указанного пользователя (соц-граф) — для его профиля.
  Future<List<SocialUser>> userFriends(String userId) async {
    final t = _token;
    if (t == null) return const [];
    return SocialApi.instance.userFriends(t, userId);
  }

  /// true — [userId] уже мой принятый друг (для перехода к его профилю).
  bool isFriend(String userId) =>
      _friends.friends.any((f) => f.user.id == userId);

  // ------------------------------ library ------------------------------

  /// Тихо публикует мою публичную проекцию (при логине/синке/сворачивании).
  Future<void> publishSilently() async {
    final t = _token;
    if (t == null || _user == null) return;
    try {
      await SocialApi.instance
          .putLibrary(t, MovieRepository.instance.buildPublicProfile());
    } catch (_) {/* молча — попробуем в следующий раз */}
  }

  /// Загружает публичную библиотеку друга как read-only [MovieRepository].
  /// Возвращает (repo, updatedAt); repo пуст, если друг ещё не публиковал.
  Future<({MovieRepository repo, int updatedAt})> friendLibrary(
      String userId) async {
    final t = _token;
    if (t == null) throw const SocialException('unauthorized', status: 401);
    final res = await SocialApi.instance.friendLibrary(t, userId);
    final repo = MovieRepository.detached(res.data ?? const {});
    return (repo: repo, updatedAt: res.updatedAt);
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }
}
