import 'dart:convert';

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

/// Экран, открываемый при запуске приложения.
enum StartScreen { watchlist, watched, nowWatching, discover, cinema }

/// Позиция кнопки «+» (докнута к нижней навигации).
enum FabPosition { center, left, right }

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

  /// Какой экран открывать при старте.
  StartScreen startScreen = StartScreen.watchlist;

  /// Позиция кнопки «+» над нижней навигацией (центр/слева/справа).
  FabPosition fabPosition = FabPosition.center;

  /// Скрытые в «Обзоре» статусы. По умолчанию скрыты уже просмотренные
  /// (как было раньше), остальное показывается.
  final Map<DiscoverHide, bool> _discHide = {};

  bool discoverHidden(DiscoverHide h) => _discHide[h] ?? false;

  /// Любимый персонаж (для статистики). null — не выбран.
  FavoriteCharacter? favoriteCharacter;

  Future<void> load() async {
    numericDates = await Store.instance.getBool('numericDates');
    final raw = await Store.instance.getString('startScreen');
    startScreen = _parse(raw);
    fabPosition = _parseFab(await Store.instance.getString('fabPosition'));
    for (final h in DiscoverHide.values) {
      final def =
          h == DiscoverHide.watchedMovies || h == DiscoverHide.watchedSeries;
      _discHide[h] = await Store.instance.getBool(_discKey(h), def: def);
    }
    final favRaw = await Store.instance.getString('favChar');
    favoriteCharacter = (favRaw == null || favRaw.isEmpty)
        ? null
        : FavoriteCharacter.fromJson(jsonDecode(favRaw) as Map<String, dynamic>);
  }

  Future<void> setFavoriteCharacter(FavoriteCharacter? c) async {
    favoriteCharacter = c;
    await Store.instance
        .setString('favChar', c == null ? '' : jsonEncode(c.toJson()));
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

  Future<void> setFabPosition(FabPosition p) async {
    if (fabPosition == p) return;
    fabPosition = p;
    await Store.instance.setString('fabPosition', p.name);
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

  static FabPosition _parseFab(String? raw) {
    for (final p in FabPosition.values) {
      if (p.name == raw) return p;
    }
    return FabPosition.center;
  }
}
