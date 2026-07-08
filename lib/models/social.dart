// Модели соц-слоя Kadr: профиль пользователя и дружба. Приезжают с бэкенда
// (Cloudflare Worker). Публичная проекция библиотеки друга парсится обычным
// MovieRepository.detached — здесь только профиль и связи.

import '../config/api_config.dart';

/// Профиль пользователя. [email] заполнен только для СВОЕГО профиля.
/// [avatarVer] — версия загруженного фото (0 = фото нет); URL строится из неё.
/// [bannerVer] — версия баннера-обложки (0 = нет); URL строится из неё.
class SocialUser {
  final String id;
  final String displayName;
  final int avatarVer;
  final int bannerVer;
  final String friendCode;
  final String? email;

  /// Задан ли код восстановления (только в своём профиле) — для подсказки.
  final bool hasRecovery;

  const SocialUser({
    required this.id,
    required this.displayName,
    required this.avatarVer,
    this.bannerVer = 0,
    required this.friendCode,
    this.email,
    this.hasRecovery = false,
  });

  /// URL аватара (null — фото не загружено). Версия в query сбрасывает кэш.
  String? get avatarUrl => avatarVer > 0
      ? '${ApiConfig.socialBase}/avatars/$id?v=$avatarVer'
      : null;

  /// URL баннера-обложки (null — не загружен). Версия в query сбрасывает кэш.
  String? get bannerUrl => bannerVer > 0
      ? '${ApiConfig.socialBase}/banners/$id?v=$bannerVer'
      : null;

  /// Первая буква ника для заглушки-аватара, когда фото нет.
  String get initial {
    final t = displayName.trim();
    return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
  }

  /// Копия с изменёнными полями (безопасно сохраняет остальные, в т.ч. версии
  /// аватара/баннера — чтобы одна правка не обнуляла другую).
  SocialUser copyWith({
    String? displayName,
    int? avatarVer,
    int? bannerVer,
    bool? hasRecovery,
  }) =>
      SocialUser(
        id: id,
        displayName: displayName ?? this.displayName,
        avatarVer: avatarVer ?? this.avatarVer,
        bannerVer: bannerVer ?? this.bannerVer,
        friendCode: friendCode,
        email: email,
        hasRecovery: hasRecovery ?? this.hasRecovery,
      );

  factory SocialUser.fromJson(Map<String, dynamic> j) => SocialUser(
        id: '${j['id']}',
        displayName: j['displayName'] as String? ?? '',
        avatarVer: (j['avatar'] as num?)?.toInt() ?? 0,
        bannerVer: (j['banner'] as num?)?.toInt() ?? 0,
        friendCode: j['friendCode'] as String? ?? '',
        email: j['email'] as String?,
        hasRecovery: j['hasRecovery'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'avatar': avatarVer,
        'banner': bannerVer,
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

/// Краткая карточка совместного списка (для экрана «Списки»).
class SharedListSummary {
  final String id;
  final String name;
  final String owner;
  final int members;
  final int items;
  final int updatedAt;

  const SharedListSummary({
    required this.id,
    required this.name,
    required this.owner,
    required this.members,
    required this.items,
    required this.updatedAt,
  });

  factory SharedListSummary.fromJson(Map<String, dynamic> j) => SharedListSummary(
        id: '${j['id']}',
        name: j['name'] as String? ?? '',
        owner: '${j['owner']}',
        members: (j['members'] as num?)?.toInt() ?? 1,
        items: (j['items'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

/// Фильм в совместном списке (данные для показа, без привязки к своей библиотеке).
class SharedListItem {
  final String key;
  final String title;
  final int? year;
  final int? tmdbId;
  final String? posterUrl;
  final String addedBy;

  const SharedListItem({
    required this.key,
    required this.title,
    this.year,
    this.tmdbId,
    this.posterUrl,
    required this.addedBy,
  });

  factory SharedListItem.fromJson(Map<String, dynamic> j) => SharedListItem(
        key: '${j['key']}',
        title: j['title'] as String? ?? '',
        year: (j['year'] as num?)?.toInt(),
        tmdbId: (j['tmdbId'] as num?)?.toInt(),
        posterUrl: j['posterUrl'] as String?,
        addedBy: '${j['addedBy']}',
      );
}

/// Полное содержимое совместного списка: участники и элементы.
class SharedListDetail {
  final String id;
  final String name;
  final String owner;
  final List<SocialUser> members;
  final List<SharedListItem> items;

  const SharedListDetail({
    required this.id,
    required this.name,
    required this.owner,
    this.members = const [],
    this.items = const [],
  });

  factory SharedListDetail.fromJson(Map<String, dynamic> j) {
    final l = j['list'] as Map<String, dynamic>;
    return SharedListDetail(
      id: '${l['id']}',
      name: l['name'] as String? ?? '',
      owner: '${l['owner']}',
      members: [
        for (final m in (j['members'] as List? ?? []))
          SocialUser.fromJson(m as Map<String, dynamic>),
      ],
      items: [
        for (final i in (j['items'] as List? ?? []))
          SharedListItem.fromJson(i as Map<String, dynamic>),
      ],
    );
  }
}

/// Рекомендация фильма, присланная другом («Тебе советуют»).
class RecommendationItem {
  final String id;
  final SocialUser from;
  final String title;
  final int? year;
  final int? tmdbId;
  final String? posterUrl;
  final String? note;
  final int createdAt;

  const RecommendationItem({
    required this.id,
    required this.from,
    required this.title,
    this.year,
    this.tmdbId,
    this.posterUrl,
    this.note,
    this.createdAt = 0,
  });

  factory RecommendationItem.fromJson(Map<String, dynamic> j) =>
      RecommendationItem(
        id: '${j['id']}',
        from: SocialUser.fromJson(j['from'] as Map<String, dynamic>),
        title: j['title'] as String? ?? '',
        year: (j['year'] as num?)?.toInt(),
        tmdbId: (j['tmdbId'] as num?)?.toInt(),
        posterUrl: j['posterUrl'] as String?,
        note: j['note'] as String?,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// Совместный просмотр («Посмотрел с другом»), присланный мне: устройство
/// добавляет его в мою библиотеку и удаляет с сервера. [kind] = movie|series.
class CoWatchItem {
  final String id;
  final SocialUser from;
  final String kind;
  final String title;
  final String? origTitle;
  final int? year;
  final int? tmdbId;
  final String? posterUrl;

  /// Когда посмотрели (ms epoch) или null («неизвестная дата»).
  final int? watchedAt;

  /// Для сериалов — список [сезон, номер] отмеченных серий.
  final List<List<int>> episodes;

  const CoWatchItem({
    required this.id,
    required this.from,
    required this.kind,
    required this.title,
    this.origTitle,
    this.year,
    this.tmdbId,
    this.posterUrl,
    this.watchedAt,
    this.episodes = const [],
  });

  bool get isSeries => kind == 'series';
  DateTime? get watchedDate =>
      watchedAt != null ? DateTime.fromMillisecondsSinceEpoch(watchedAt!) : null;

  factory CoWatchItem.fromJson(Map<String, dynamic> j) => CoWatchItem(
        id: '${j['id']}',
        from: SocialUser.fromJson(j['from'] as Map<String, dynamic>),
        kind: j['kind'] as String? ?? 'movie',
        title: j['title'] as String? ?? '',
        origTitle: j['origTitle'] as String?,
        year: (j['year'] as num?)?.toInt(),
        tmdbId: (j['tmdbId'] as num?)?.toInt(),
        posterUrl: j['posterUrl'] as String?,
        watchedAt: (j['watchedAt'] as num?)?.toInt(),
        episodes: [
          for (final e in (j['episodes'] as List? ?? []))
            if (e is List && e.length >= 2)
              [(e[0] as num).toInt(), (e[1] as num).toInt()]
        ],
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
