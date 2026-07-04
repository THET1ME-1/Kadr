import 'package:flutter/foundation.dart';

import 'store.dart';

/// Экран, открываемый при запуске приложения.
enum StartScreen { watchlist, watched, nowWatching, discover, cinema }

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

  Future<void> load() async {
    numericDates = await Store.instance.getBool('numericDates');
    final raw = await Store.instance.getString('startScreen');
    startScreen = _parse(raw);
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

  static StartScreen _parse(String? raw) {
    for (final s in StartScreen.values) {
      if (s.name == raw) return s;
    }
    return StartScreen.watchlist;
  }
}
