import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'store.dart';

/// Колеровка launcher-иконки: знак «Засечка» на подложке.
///
/// [id] совпадает с ключом в `MainActivity.ICON_ALIASES` и с суффиксом ресурсов
/// (`ic_launcher_<id>`). Арт генерирует `tool/gen_icons.py`.
class AppIconOption {
  const AppIconOption({
    required this.id,
    required this.nameKey,
    required this.mark,
    required this.background,
  });

  final String id;

  /// Ключ локализации названия.
  final String nameKey;

  /// Цвет знака и подложки — ими же рисуется превью в пикере.
  final Color mark;
  final Color background;
}

/// Выбор иконки приложения (Android).
///
/// На Android нет API смены иконки, поэтому на каждую колеровку заведён
/// `<activity-alias>`; переключение — включением нужного и выключением остальных
/// через `PackageManager` (нативная часть в `MainActivity.kt`).
class AppIconService extends ChangeNotifier {
  AppIconService._();

  static final AppIconService instance = AppIconService._();

  static const _channel = MethodChannel('app_icon');
  static const _storeKey = 'appIconId';
  static const defaultId = 'graphite';

  static const options = <AppIconOption>[
    AppIconOption(
      id: 'graphite',
      nameKey: 'app_icon_graphite',
      mark: Color(0xFF00B5C7),
      background: Color(0xFF0E1316),
    ),
    AppIconOption(
      id: 'ink',
      nameKey: 'app_icon_ink',
      mark: Color(0xFF0E1316),
      background: Color(0xFF00B5C7),
    ),
    AppIconOption(
      id: 'white',
      nameKey: 'app_icon_white',
      mark: Color(0xFFFFFFFF),
      background: Color(0xFF00B5C7),
    ),
  ];

  /// Смена иконки есть только на Android. На вебе `Platform` бросает — гасим заранее.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  String _current = defaultId;
  String get current => _current;

  AppIconOption get currentOption =>
      options.firstWhere((o) => o.id == _current, orElse: () => options.first);

  static AppIconOption optionById(String id) =>
      options.firstWhere((o) => o.id == id, orElse: () => options.first);

  /// Читает выбор. Источник истины — система (какой alias включён): пользователь
  /// мог переустановить приложение, а запись в настройках остаться от прошлой жизни.
  Future<void> load() async {
    if (!isSupported) return;
    try {
      final native = await _channel.invokeMethod<String>('currentIcon');
      if (native != null && options.any((o) => o.id == native)) {
        _current = native;
        notifyListeners();
        return;
      }
    } on PlatformException catch (e) {
      debugPrint('AppIconService: не смог спросить систему — $e');
    } on MissingPluginException {
      return; // канала нет (не Android-сборка) — молча остаёмся на дефолте
    }
    _current = await Store.instance.getString(_storeKey) ?? defaultId;
    notifyListeners();
  }

  /// Умеет ли лаунчер закреплять ярлыки (Android 8+ и согласие оболочки).
  Future<bool> canPinShortcut() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canPinShortcut') ?? false;
    } on PlatformException catch (e) {
      debugPrint('AppIconService: canPinShortcut — $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Кладёт на стол ярлык с произвольной картинкой.
  ///
  /// Это ДОПОЛНИТЕЛЬНЫЙ ярлык, а не смена иконки приложения: произвольный цвет
  /// Android разрешает только ярлыкам — launcher-иконка обязана лежать в APK.
  Future<bool> pinCustomShortcut(Uint8List png, String label) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'pinShortcut',
            {'icon': png, 'label': label},
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('AppIconService: pinShortcut — $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Цвета последней своей иконки — чтобы экран открывался там, где закрыли.
  Future<(Color, Color)?> loadCustomColors() async {
    final mark = await Store.instance.getInt('customIconMark');
    final bg = await Store.instance.getInt('customIconBg');
    if (mark == null || bg == null) return null;
    return (Color(mark), Color(bg));
  }

  Future<void> saveCustomColors(Color mark, Color bg) async {
    await Store.instance.setInt('customIconMark', mark.toARGB32());
    await Store.instance.setInt('customIconBg', bg.toARGB32());
  }

  /// Применяет колеровку. Возвращает false, если система отказала — в этом
  /// случае выбор не сохраняем, иначе настройки разойдутся с реальной иконкой.
  Future<bool> setIcon(String id) async {
    if (!isSupported || id == _current) return false;
    if (!options.any((o) => o.id == id)) return false;
    try {
      await _channel.invokeMethod<bool>('setIcon', {'id': id});
    } on PlatformException catch (e) {
      debugPrint('AppIconService: смена иконки не удалась — $e');
      return false;
    } on MissingPluginException {
      return false;
    }
    _current = id;
    await Store.instance.setString(_storeKey, id);
    notifyListeners();
    return true;
  }
}
