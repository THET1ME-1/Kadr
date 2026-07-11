import 'package:flutter/material.dart';

import '../services/store.dart';
import 'app_theme.dart';

/// Режим темы: фиксированная светлая/тёмная, по системе или авто-по-времени
/// (тёмная ночью, светлая днём).
enum AppThemeMode { light, dark, system, autoTime }

/// Единый центр цветов приложения.
///
/// Хранит выбранный пользователем seed-цвет и режим (тёмный/светлый), кладёт их
/// в [Store] и оповещает слушателей. `MaterialApp` слушает контроллер и
/// перестраивает тему на лету — менять цвет можно из любого экрана через
/// [ThemeController.instance], без проброса колбэков по дереву.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  final Store _repo = Store.instance;

  Color _seedColor = AppTheme.defaultSeed;
  AppThemeMode _mode = AppThemeMode.dark;
  bool _useDynamic = false;
  bool _amoled = false;
  bool _vibrant = true;
  bool _loaded = false;

  Color get seedColor => _seedColor;
  AppThemeMode get mode => _mode;

  /// Ночь (для авто-режима): 20:00–07:00 — тёмная.
  static bool get _isNight {
    final h = DateTime.now().hour;
    return h >= 20 || h < 7;
  }

  /// «Поверхность тёмная» — для UI, где это важно (например, тумблер AMOLED).
  bool get isDark => switch (_mode) {
        AppThemeMode.light => false,
        AppThemeMode.dark => true,
        AppThemeMode.system => true,
        AppThemeMode.autoTime => _isNight,
      };

  /// Режим Material You — брать цвет из системных обоев (Android 12+).
  bool get useDynamicColor => _useDynamic;

  /// AMOLED — чистый чёрный фон в тёмной теме.
  bool get amoled => _amoled;

  /// Насыщенность схемы: true — «Сочно» (яркая версия выбранного цвета,
  /// темы резко различаются), false — «Точь-в-точь» (акцент = ровно выбранный
  /// цвет).
  bool get vibrantScheme => _vibrant;

  bool get isLoaded => _loaded;
  ThemeMode get themeMode => switch (_mode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.autoTime =>
          _isNight ? ThemeMode.dark : ThemeMode.light,
      };

  /// Цвет совпадает со стандартным?
  bool get isDefaultSeed =>
      _seedColor.toARGB32() == AppTheme.defaultSeed.toARGB32();

  /// Подгружает сохранённые настройки. Вызывается один раз до `runApp`.
  Future<void> load() async {
    final stored = await _repo.seedColorValue();
    _seedColor = stored == null ? AppTheme.defaultSeed : Color(stored);
    final rawMode = await _repo.themeModeRaw();
    if (rawMode != null &&
        rawMode >= 0 &&
        rawMode < AppThemeMode.values.length) {
      _mode = AppThemeMode.values[rawMode];
    } else {
      // Миграция со старого булева darkTheme.
      _mode = await _repo.isDarkTheme() ? AppThemeMode.dark : AppThemeMode.light;
    }
    _useDynamic = await _repo.dynamicColorEnabled();
    _amoled = await _repo.amoledEnabled();
    _vibrant = await _repo.vibrantSchemeEnabled();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setUseDynamicColor(bool value) async {
    if (value == _useDynamic) return;
    _useDynamic = value;
    notifyListeners();
    await _repo.setDynamicColorEnabled(value);
  }

  Future<void> setAmoled(bool value) async {
    if (value == _amoled) return;
    _amoled = value;
    notifyListeners();
    await _repo.setAmoledEnabled(value);
  }

  Future<void> setVibrantScheme(bool value) async {
    if (value == _vibrant) return;
    _vibrant = value;
    notifyListeners();
    await _repo.setVibrantSchemeEnabled(value);
  }

  Future<void> setSeedColor(Color color) async {
    if (color.toARGB32() == _seedColor.toARGB32()) return;
    _seedColor = color;
    notifyListeners();
    await _repo.setSeedColorValue(color.toARGB32());
  }

  Future<void> resetSeedColor() => setSeedColor(AppTheme.defaultSeed);

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _repo.setThemeModeRaw(mode.index);
    // Дублируем в старый ключ для совместимости.
    await _repo.setDarkTheme(mode == AppThemeMode.dark);
  }
}
