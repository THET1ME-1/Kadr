// Модели соц-слоя Kadr: профиль пользователя и дружба. Приезжают с бэкенда
// (Cloudflare Worker). Публичная проекция библиотеки друга парсится обычным
// MovieRepository.detached — здесь только профиль и связи.

import '../config/api_config.dart';

/// Профиль пользователя. [email] заполнен только для СВОЕГО профиля.
/// [avatarVer] — версия загруженного фото (0 = фото нет); URL строится из неё.
class SocialUser {
  final String id;
  final String displayName;
  final int avatarVer;
  final String friendCode;
  final String? email;

  const SocialUser({
    required this.id,
    required this.displayName,
    required this.avatarVer,
    required this.friendCode,
    this.email,
  });

  /// URL аватара (null — фото не загружено). Версия в query сбрасывает кэш.
  String? get avatarUrl => avatarVer > 0
      ? '${ApiConfig.socialBase}/avatars/$id?v=$avatarVer'
      : null;

  /// Первая буква ника для заглушки-аватара, когда фото нет.
  String get initial {
    final t = displayName.trim();
    return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
  }

  factory SocialUser.fromJson(Map<String, dynamic> j) => SocialUser(
        id: '${j['id']}',
        displayName: j['displayName'] as String? ?? '',
        avatarVer: (j['avatar'] as num?)?.toInt() ?? 0,
        friendCode: j['friendCode'] as String? ?? '',
        email: j['email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'avatar': avatarVer,
        'friendCode': friendCode,
        if (email != null) 'email': email,
      };
}

/// Друг/заявка: профиль + когда обновлял свою библиотеку (для значка «свежее»).
class FriendEntry {
  final SocialUser user;
  final int libraryUpdatedAt; // ms epoch, 0 — ещё не публиковал
  final int since; // ms epoch, когда связь создана/принята

  const FriendEntry({
    required this.user,
    this.libraryUpdatedAt = 0,
    this.since = 0,
  });

  factory FriendEntry.fromJson(Map<String, dynamic> j) => FriendEntry(
        user: SocialUser.fromJson(j['user'] as Map<String, dynamic>),
        libraryUpdatedAt: (j['libraryUpdatedAt'] as num?)?.toInt() ?? 0,
        since: (j['since'] as num?)?.toInt() ?? 0,
      );
}

/// Ответ `GET /friends`: три корзины связей.
class FriendsData {
  final List<FriendEntry> friends; // принятые
  final List<FriendEntry> incoming; // мне прислали заявку
  final List<FriendEntry> outgoing; // я отправил заявку

  const FriendsData({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
  });

  bool get isEmpty =>
      friends.isEmpty && incoming.isEmpty && outgoing.isEmpty;

  factory FriendsData.fromJson(Map<String, dynamic> j) {
    List<FriendEntry> parse(String k) => [
          for (final e in (j[k] as List? ?? []))
            FriendEntry.fromJson(e as Map<String, dynamic>),
        ];
    return FriendsData(
      friends: parse('friends'),
      incoming: parse('incoming'),
      outgoing: parse('outgoing'),
    );
  }
}
