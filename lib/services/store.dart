import 'package:shared_preferences/shared_preferences.dart';

/// Единый слой хранения настроек и пользовательских данных Kadr поверх
/// SharedPreferences. Аналог репозитория ScoreMaster, но заточен под трекер
/// фильмов. Контроллеры темы и языка обращаются сюда за persist-настройками;
/// сюда же лягут списки, просмотры и оценки (см. будущий MovieRepository).
class Store {
  Store._();
  static final Store instance = Store._();

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ------------------------------- Тема -------------------------------
  Future<int?> seedColorValue() async => (await _p).getInt('seedColor');
  Future<void> setSeedColorValue(int v) async =>
      (await _p).setInt('seedColor', v);

  Future<int?> themeModeRaw() async => (await _p).getInt('themeMode');
  Future<void> setThemeModeRaw(int v) async => (await _p).setInt('themeMode', v);

  /// Старый булев ключ — для миграции со времён «только тёмная/светлая».
  Future<bool> isDarkTheme() async => (await _p).getBool('darkTheme') ?? true;
  Future<void> setDarkTheme(bool v) async => (await _p).setBool('darkTheme', v);

  Future<bool> dynamicColorEnabled() async =>
      (await _p).getBool('dynamicColor') ?? false;
  Future<void> setDynamicColorEnabled(bool v) async =>
      (await _p).setBool('dynamicColor', v);

  Future<bool> amoledEnabled() async => (await _p).getBool('amoled') ?? false;
  Future<void> setAmoledEnabled(bool v) async =>
      (await _p).setBool('amoled', v);

  /// Насыщенность схемы: true — «Сочно» (vibrant), false — «Точь-в-точь»
  /// (fidelity). По умолчанию сочно.
  Future<bool> vibrantSchemeEnabled() async =>
      (await _p).getBool('vibrantScheme') ?? true;
  Future<void> setVibrantSchemeEnabled(bool v) async =>
      (await _p).setBool('vibrantScheme', v);

  // ------------------------------- Язык -------------------------------
  Future<String?> languageCode() async => (await _p).getString('lang');
  Future<void> setLanguageCode(String v) async =>
      (await _p).setString('lang', v);

  // ------------------- Общий доступ (данные/бэкап) --------------------
  Future<String?> getString(String k) async => (await _p).getString(k);
  Future<void> setString(String k, String v) async =>
      (await _p).setString(k, v);
  Future<bool> getBool(String k, {bool def = false}) async =>
      (await _p).getBool(k) ?? def;
  Future<void> setBool(String k, bool v) async => (await _p).setBool(k, v);
  Future<int?> getInt(String k) async => (await _p).getInt(k);
  Future<void> setInt(String k, int v) async => (await _p).setInt(k, v);
  Future<List<String>> getStringList(String k) async =>
      (await _p).getStringList(k) ?? const [];
  Future<void> setStringList(String k, List<String> v) async =>
      (await _p).setStringList(k, v);
  Future<void> remove(String k) async => (await _p).remove(k);
}
