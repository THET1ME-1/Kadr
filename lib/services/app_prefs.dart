import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'store.dart';

/// Любимый персонаж (выбирается из каста фильма/сериала) — показывается в статистике.
class FavoriteCharacter {
  final String character;
  final String actor;
  final String? photoUrl;
  final String title;
  const FavoriteCharacter({
    required this.character,
    required this.actor,
    this.photoUrl,
    required this.title,
  });
  Map<String, dynamic> toJson() =>
      {'c': character, 'a': actor, 'p': photoUrl, 't': title};
  factory FavoriteCharacter.fromJson(Map<String, dynamic> j) =>
      FavoriteCharacter(
        character: j['c'] as String? ?? '',
        actor: j['a'] as String? ?? '',
        photoUrl: j['p'] as String?,
        title: j['t'] as String? ?? '',
      );
}

/// Любимый актёр (со страницы актёра). Список показывается в статистике.
class FavoriteActor {
  final int id; // TMDB person id
  final String name;
  final String? photoUrl;
  const FavoriteActor({required this.id, required this.name, this.photoUrl});
  Map<String, dynamic> toJson() => {'id': id, 'n': name, 'p': photoUrl};
  factory FavoriteActor.fromJson(Map<String, dynamic> j) => FavoriteActor(
        id: (j['id'] as num).toInt(),
        name: j['n'] as String? ?? '',
        photoUrl: j['p'] as String?,
      );
}

/// Экран, открываемый при запуске приложения.
enum StartScreen { watchlist, watched, nowWatching, discover, cinema }

/// Вид нижнего меню. Плавающее (по умолчанию с 0.24) висит над контентом, и
/// кнопка «+» стоит в его ряду. Классическое — прежняя полоса во всю ширину.
enum NavStyle { floating, classic }

/// Настраиваемые пункты бокового меню (порядок и видимость). Настройки и «О
/// приложении» — фиксированные, здесь их нет.
enum DrawerItem {
  search,
  nowWatching,
  activity,
  roulette,
  forYou,
  schedule,
  news,
  stats,
  lists,
  dropped,
}

/// Что скрывать в ленте «Обзор» — по типу (фильм/сериал) и статусу отдельно.
enum DiscoverHide {
  watchedMovies,
  watchedSeries,
  droppedMovies,
  droppedSeries,
  watchlistMovies,
  watchlistSeries,
}

/// Небольшие пользовательские настройки, влияющие на интерфейс на лету
/// (формат дат в лентах, стартовый экран). Аналог ThemeController/LocaleController —
/// загружается один раз в main() и слушается корнем приложения, чтобы смена
/// настройки сразу перестраивала дерево.
class AppPrefs extends ChangeNotifier {
  AppPrefs._();
  static final AppPrefs instance = AppPrefs._();

  /// Числовой формат дат в разделителях («18.10.2023» вместо «18 октября 2023»).
  bool numericDates = false;

  /// Режим «Дневник просмотров»: в ленте «Просмотрено» у каждого просмотра можно
  /// добавить настроение/с кем/где/фото/заметку. По умолчанию включён.
  bool diaryEnabled = true;

  /// «Снимать серии по порядку»: сняли серию, и все отмеченные после неё
  /// снимаются тоже. Отметка по порядку настраивается отдельно.
  bool sequentialUnmark = true;

  Future<void> setSequentialUnmark(bool v) async {
    sequentialUnmark = v;
    await Store.instance.setBool('sequentialUnmark', v);
    notifyListeners();
  }

  /// Свёрнут ли блок «Мои рецензии»: один ответ на все фильмы и один на все
  /// сериалы. Блоку ответ нужен сразу при создании, а не кадром позже.
  /// Список карточки фильма ленивый: блок, ушедший далеко вверх,
  /// выбрасывается и при возврате создаётся заново. Пока он узнавал ответ
  /// из настроек уже после первого кадра, он появлялся развёрнутым, тут же
  /// сворачивался и сдвигал всё под собой: страница не листалась вверх.
  bool movieReviewsCollapsed = false;
  bool seriesReviewsCollapsed = false;

  static const movieReviewsCollapsedKey = 'movieReviewsCollapsed';
  static const seriesReviewsCollapsedKey = 'seriesReviewsCollapsed';

  // Слушателей не будим: сворачивание перерисовывает сам блок, а будить
  // корень приложения из-за него незачем.
  Future<void> setMovieReviewsCollapsed(bool v) async {
    movieReviewsCollapsed = v;
    await Store.instance.setBool(movieReviewsCollapsedKey, v);
  }

  Future<void> setSeriesReviewsCollapsed(bool v) async {
    seriesReviewsCollapsed = v;
    await Store.instance.setBool(seriesReviewsCollapsedKey, v);
  }

  /// Какой экран открывать при старте.
  StartScreen startScreen = StartScreen.watchlist;

  NavStyle navStyle = NavStyle.floating;

  /// Устройство — Android TV (leanback). Определяется при запуске.
  bool isTvDevice = false;

  /// Принудительно включить TV-режим (для превью на телефоне).
  bool forceTvMode = false;

  /// Активен ли TV-режим (крупный интерфейс под пульт).
  bool get tvActive => isTvDevice || forceTvMode;

  /// Скрытые в «Обзоре» статусы. По умолчанию скрыты уже просмотренные
  /// (как было раньше), остальное показывается.
  final Map<DiscoverHide, bool> _discHide = {};

  bool discoverHidden(DiscoverHide h) => _discHide[h] ?? false;

  /// Полный порядок пунктов меню и скрытые из них.
  List<DrawerItem> drawerOrder = List.of(DrawerItem.values);
  Set<DrawerItem> drawerHidden = {};

  /// Видимые пункты меню в выбранном порядке (для отрисовки drawer).
  List<DrawerItem> get drawerItems =>
      [for (final i in drawerOrder) if (!drawerHidden.contains(i)) i];

  static DrawerItem? _parseDrawer(String s) {
    for (final i in DrawerItem.values) {
      if (i.name == s) return i;
    }
    return null;
  }

  /// Любимый персонаж (для статистики). null — не выбран.
  FavoriteCharacter? favoriteCharacter;

  /// Любимые актёры (отмечаются на странице актёра).
  List<FavoriteActor> favoriteActors = [];

  bool isFavoriteActor(int id) => favoriteActors.any((a) => a.id == id);

  Future<void> load() async {
    numericDates = await Store.instance.getBool('numericDates');
    diaryEnabled = await Store.instance.getBool('diaryEnabled', def: true);
    // Раньше одна настройка «по порядку» отвечала и за отметку, и за
    // снятие. Пока новую не трогали, снятие идёт так же, как отметка.
    sequentialUnmark = await Store.instance.getBool(
      'sequentialUnmark',
      def: await Store.instance.getBool('sequentialEpisodes', def: true),
    );
    movieReviewsCollapsed =
        await Store.instance.getBool(movieReviewsCollapsedKey);
    seriesReviewsCollapsed =
        await Store.instance.getBool(seriesReviewsCollapsedKey);
    final raw = await Store.instance.getString('startScreen');
    startScreen = _parse(raw);
    navStyle = await Store.instance.getString('navStyle') == 'classic'
        ? NavStyle.classic
        : NavStyle.floating;
    forceTvMode = await Store.instance.getBool('forceTvMode');
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        isTvDevice = info.systemFeatures
                .contains('android.software.leanback') ||
            info.systemFeatures.contains('android.software.leanback_only');
      }
    } catch (_) {/* детект не критичен */}
    for (final h in DiscoverHide.values) {
      final def =
          h == DiscoverHide.watchedMovies || h == DiscoverHide.watchedSeries;
      _discHide[h] = await Store.instance.getBool(_discKey(h), def: def);
    }
    final order = await Store.instance.getString('drawer.order');
    if (order != null && order.isNotEmpty) {
      final parsed =
          order.split(',').map(_parseDrawer).whereType<DrawerItem>().toList();
      // Новые пункты (появившиеся в обновлении) добавляем в конец, чтобы не терять.
      for (final i in DrawerItem.values) {
        if (!parsed.contains(i)) parsed.add(i);
      }
      drawerOrder = parsed;
    }
    final hidden = await Store.instance.getString('drawer.hidden');
    if (hidden != null && hidden.isNotEmpty) {
      drawerHidden =
          hidden.split(',').map(_parseDrawer).whereType<DrawerItem>().toSet();
    }
    final favRaw = await Store.instance.getString('favChar');
    favoriteCharacter = (favRaw == null || favRaw.isEmpty)
        ? null
        : FavoriteCharacter.fromJson(jsonDecode(favRaw) as Map<String, dynamic>);
    final faRaw = await Store.instance.getString('favActors');
    favoriteActors = (faRaw == null || faRaw.isEmpty)
        ? []
        : (jsonDecode(faRaw) as List)
            .map((e) => FavoriteActor.fromJson(e as Map<String, dynamic>))
            .toList();
  }

  Future<void> setDrawerOrder(List<DrawerItem> order) async {
    drawerOrder = order;
    await Store.instance
        .setString('drawer.order', order.map((e) => e.name).join(','));
    notifyListeners();
  }

  Future<void> setDrawerHidden(DrawerItem item, bool hidden) async {
    drawerHidden = hidden
        ? {...drawerHidden, item}
        : drawerHidden.where((x) => x != item).toSet();
    await Store.instance
        .setString('drawer.hidden', drawerHidden.map((e) => e.name).join(','));
    notifyListeners();
  }

  /// Любимые персонаж и актёры для резервной копии; null, если их нет.
  /// Лежат они в настройках, а не в библиотеке, поэтому в копию едут
  /// отдельным блоком.
  Map<String, dynamic>? favoritesJson() {
    final c = favoriteCharacter;
    if (c == null && favoriteActors.isEmpty) return null;
    return {
      if (c != null) 'character': c.toJson(),
      'actors': [for (final a in favoriteActors) a.toJson()],
    };
  }

  /// Возвращает любимых из блока копии [json]. С [merge] актёры
  /// складываются, а свой персонаж остаётся; без него берётся то, что в
  /// копии. Копия без блока (старая версия) ничего не меняет.
  Future<void> restoreFavorites(Object? json, {required bool merge}) async {
    if (json is! Map) return;
    FavoriteCharacter? character;
    final actors = <FavoriteActor>[];
    try {
      final c = json['character'];
      if (c is Map) character = FavoriteCharacter.fromJson(c.cast());
      for (final a in (json['actors'] as List? ?? const [])) {
        if (a is Map) actors.add(FavoriteActor.fromJson(a.cast()));
      }
    } catch (e) {
      debugPrint('AppPrefs: любимые из копии не прочитались: $e');
      return;
    }
    if (merge) {
      favoriteCharacter ??= character;
      favoriteActors = [
        ...favoriteActors,
        for (final a in actors)
          if (!isFavoriteActor(a.id)) a,
      ];
    } else {
      favoriteCharacter = character;
      favoriteActors = actors;
    }
    final c = favoriteCharacter;
    await Store.instance
        .setString('favChar', c == null ? '' : jsonEncode(c.toJson()));
    await Store.instance.setString(
        'favActors', jsonEncode([for (final x in favoriteActors) x.toJson()]));
    notifyListeners();
  }

  Future<void> setFavoriteCharacter(FavoriteCharacter? c) async {
    favoriteCharacter = c;
    await Store.instance
        .setString('favChar', c == null ? '' : jsonEncode(c.toJson()));
    notifyListeners();
  }

  Future<void> toggleFavoriteActor(FavoriteActor a) async {
    if (isFavoriteActor(a.id)) {
      favoriteActors = favoriteActors.where((x) => x.id != a.id).toList();
    } else {
      favoriteActors = [...favoriteActors, a];
    }
    await Store.instance.setString(
        'favActors', jsonEncode([for (final x in favoriteActors) x.toJson()]));
    notifyListeners();
  }

  Future<void> setDiaryEnabled(bool v) async {
    diaryEnabled = v;
    await Store.instance.setBool('diaryEnabled', v);
    notifyListeners();
  }

  Future<void> setNumericDates(bool v) async {
    if (numericDates == v) return;
    numericDates = v;
    await Store.instance.setBool('numericDates', v);
    notifyListeners();
  }

  Future<void> setStartScreen(StartScreen s) async {
    if (startScreen == s) return;
    startScreen = s;
    await Store.instance.setString('startScreen', s.name);
    notifyListeners();
  }

  Future<void> setNavStyle(NavStyle v) async {
    if (navStyle == v) return;
    navStyle = v;
    await Store.instance.setString('navStyle', v.name);
    notifyListeners();
  }

  Future<void> setForceTvMode(bool v) async {
    if (forceTvMode == v) return;
    forceTvMode = v;
    await Store.instance.setBool('forceTvMode', v);
    notifyListeners();
  }

  Future<void> setDiscoverHidden(DiscoverHide h, bool v) async {
    if ((_discHide[h] ?? false) == v) return;
    _discHide[h] = v;
    await Store.instance.setBool(_discKey(h), v);
    notifyListeners();
  }

  static String _discKey(DiscoverHide h) => switch (h) {
        DiscoverHide.watchedMovies => 'disc.hwm',
        DiscoverHide.watchedSeries => 'disc.hws',
        DiscoverHide.droppedMovies => 'disc.hdm',
        DiscoverHide.droppedSeries => 'disc.hds',
        DiscoverHide.watchlistMovies => 'disc.hlm',
        DiscoverHide.watchlistSeries => 'disc.hls',
      };

  static StartScreen _parse(String? raw) {
    for (final s in StartScreen.values) {
      if (s.name == raw) return s;
    }
    return StartScreen.watchlist;
  }
}
