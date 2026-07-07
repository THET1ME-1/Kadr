import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../l10n/strings.dart';
import '../../models/social.dart';
import '../movie_repository.dart';
import '../notification_service.dart';
import '../store.dart';
import 'social_api.dart';

/// Состояние соц-слоя: текущая сессия (токен+профиль), списки друзей/заявок и
/// публикация своей проекции. Слушается экранами «Друзья»/«Профиль». Локальная
/// библиотека остаётся источником истины — сюда уходит лишь публичная витрина.
class SocialController extends ChangeNotifier {
  SocialController._();
  static final SocialController instance = SocialController._();

  static const _kToken = 'socialToken';
  static const _kUser = 'socialUser'; // кэш профиля для мгновенного входа

  String? _token;
  SocialUser? _user;
  FriendsData _friends = const FriendsData();
  bool _loading = false;

  SocialUser? get user => _user;
  String? get token => _token; // для экранов совместных списков
  FriendsData get friends => _friends;
  bool get isLoggedIn => _token != null && _user != null;
  bool get loading => _loading;
  int get incomingCount => _friends.incoming.length;

  /// Восстановление сессии при старте: мгновенно поднимаем профиль из кэша
  /// (вход переживает перезапуск даже без сети), затем валидируем токен в фоне.
  Future<void> load() async {
    attachLibraryListener(); // публиковать витрину при изменениях библиотеки
    _token = await Store.instance.getString(_kToken);
    if (_token == null) return;
    // Оптимистично — из кэша, чтобы не выкидывать на экран входа при заминке сети.
    final cached = await Store.instance.getString(_kUser);
    if (cached != null) {
      try {
        _user = SocialUser.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        notifyListeners();
      } catch (_) {/* повреждённый кэш — обновит me() ниже */}
    }
    try {
      _user = await SocialApi.instance.me(_token!);
      await _cacheUser();
      notifyListeners();
      // Подтягиваем друзей и публикуем актуальную витрину в фоне.
      unawaited(refreshFriends());
      unawaited(publishSilently());
    } on SocialException catch (e) {
      // Чистим ТОЛЬКО при явном «недействителен» (401). Сеть/прочее —
      // остаёмся в сессии по кэшу и попробуем позже.
      if (e.status == 401) await _clearSession();
    }
  }

  Future<void> _cacheUser() async {
    final u = _user;
    if (u != null) {
      await Store.instance.setString(_kUser, jsonEncode(u.toJson()));
    }
  }

  Future<void> _saveSession(String token, SocialUser user) async {
    _token = token;
    _user = user;
    await Store.instance.setString(_kToken, token);
    await _cacheUser();
    notifyListeners();
  }

  Future<void> _clearSession() async {
    _token = null;
    _user = null;
    _friends = const FriendsData();
    await Store.instance.remove(_kToken);
    await Store.instance.remove(_kUser);
    notifyListeners();
  }

  // ------------------------------- auth -------------------------------

  /// Регистрация. Возвращает КОД ВОССТАНОВЛЕНИЯ (показать один раз пользователю).
  Future<String?> register({
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
      return r.recoveryCode;
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

  /// Сброс пароля по коду восстановления. Возвращает НОВЫЙ код восстановления.
  Future<String?> resetPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    _setLoading(true);
    try {
      final r = await SocialApi.instance.resetPassword(
        email: email,
        recoveryCode: recoveryCode,
        newPassword: newPassword,
      );
      await _saveSession(r.token, r.user);
      unawaited(publishSilently());
      unawaited(refreshFriends());
      return r.recoveryCode;
    } finally {
      _setLoading(false);
    }
  }

  /// Перегенерация кода восстановления (в профиле).
  Future<String> regenerateRecovery() async {
    final t = _token;
    if (t == null) throw const SocialException('unauthorized', status: 401);
    final code = await SocialApi.instance.regenerateRecovery(t);
    // Обновим hasRecovery в профиле.
    final u = _user;
    if (u != null) {
      _user = SocialUser(
        id: u.id,
        displayName: u.displayName,
        avatarVer: u.avatarVer,
        friendCode: u.friendCode,
        email: u.email,
        hasRecovery: true,
      );
      await _cacheUser();
      notifyListeners();
    }
    return code;
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
    await _cacheUser();
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
      hasRecovery: u.hasRecovery,
    );
    await _cacheUser();
    notifyListeners();
  }

  // ------------------------------ friends ------------------------------

  Future<void> refreshFriends() async {
    final t = _token;
    if (t == null) return;
    try {
      _friends = await SocialApi.instance.friends(t);
      notifyListeners();
      await _notifyNewRequests();
    } on SocialException catch (e) {
      if (e.status == 401) await _clearSession();
    }
  }

  /// Локальное уведомление о НОВЫХ входящих заявках (появившихся с прошлой
  /// проверки). Срабатывает при открытии/возврате приложения — без фонового пуша.
  Future<void> _notifyNewRequests() async {
    final incoming = _friends.incoming;
    final seen = (await Store.instance.getStringList('socialSeenRequests')).toSet();
    final current = incoming.map((f) => f.user.id).toSet();
    final fresh = incoming.where((f) => !seen.contains(f.user.id)).toList();
    if (fresh.isNotEmpty) {
      final name = fresh.first.user.displayName;
      final body = fresh.length > 1
          ? trf('notif_friend_req_many', {'name': name, 'n': fresh.length - 1})
          : trf('notif_friend_req_one', {'name': name});
      await NotificationService.instance.showSocial(tr('notif_friend_req_title'), body);
    }
    // Запоминаем текущий набор входящих (и убираем ушедшие).
    await Store.instance.setStringList('socialSeenRequests', current.toList());
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
  /// Учитывает настройки видимости (скрыть оценки/даты).
  Future<void> publishSilently() async {
    final t = _token;
    if (t == null || _user == null) return;
    try {
      final hideRatings = await Store.instance.getBool('socialHideRatings');
      final hideDates = await Store.instance.getBool('socialHideDates');
      await SocialApi.instance.putLibrary(
        t,
        MovieRepository.instance.buildPublicProfile(
            hideRatings: hideRatings, hideDates: hideDates),
      );
    } catch (_) {/* молча — попробуем в следующий раз */}
  }

  // ------------------------ свежесть витрины (#3) ------------------------

  Timer? _publishDebounce;
  bool _repoAttached = false;

  /// Подписка на изменения библиотеки — публикуем витрину с дебаунсом, чтобы
  /// друг видел свежие просмотры, не дожидаясь сворачивания приложения.
  void attachLibraryListener() {
    if (_repoAttached) return;
    _repoAttached = true;
    MovieRepository.instance.addListener(_onLibraryChanged);
  }

  void _onLibraryChanged() {
    if (_token == null) return;
    _publishDebounce?.cancel();
    _publishDebounce =
        Timer(const Duration(seconds: 6), () => unawaited(publishSilently()));
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

  /// Библиотеки ВСЕХ принятых друзей (параллельно) — для ленты активности и
  /// рекомендаций. Друзья без данных/с ошибкой просто пропускаются.
  Future<List<({SocialUser user, MovieRepository repo})>>
      allFriendLibraries() async {
    final t = _token;
    if (t == null) return const [];
    final results = await Future.wait(_friends.friends.map((f) async {
      try {
        final res = await SocialApi.instance.friendLibrary(t, f.user.id);
        return (
          user: f.user,
          repo: MovieRepository.detached(res.data ?? const {})
        );
      } catch (_) {
        return null;
      }
    }));
    return [for (final r in results) ?r];
  }

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }
}
