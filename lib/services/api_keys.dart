import '../config/api_config.dart';
import 'store.dart';

/// Персональные API-ключи пользователя (TMDB / kinopoisk.dev).
///
/// Публичная сборка идёт БЕЗ ключей — каждый вводит свой (TMDB бесплатный, для
/// личного использования). Приоритет: введённый в приложении → вшитый при сборке
/// (`--dart-define`) → пусто. Держим в памяти + персист в [Store]; [TmdbService]
/// и [KinopoiskService] читают их в заголовках запросов.
class ApiKeys {
  ApiKeys._();

  static const _kTmdb = 'tmdbToken';
  static const _kKinopoisk = 'kinopoiskKey';
  static const _kGateSkipped = 'tmdbGateSkipped';

  static String tmdbToken = '';
  static String kinopoiskKey = '';

  /// Пользователь осознанно вошёл в приложение БЕЗ ключа TMDB (на свой страх и
  /// риск). Тогда стартовый гейт пропускает экран ключа. Ключ можно ввести
  /// позже в Настройках.
  static bool gateSkipped = false;

  /// Есть ли рабочий TMDB-токен (без него приложение почти не функционирует).
  static bool get hasTmdb => tmdbToken.trim().isNotEmpty;

  /// Можно ли пускать в приложение со стартового гейта (есть ключ или вход без
  /// ключа уже подтверждён).
  static bool get canEnter => hasTmdb || gateSkipped;

  /// Загрузка при старте: введённый пользователем ключ имеет приоритет над
  /// вшитым при сборке.
  static Future<void> load() async {
    final t = (await Store.instance.getString(_kTmdb))?.trim() ?? '';
    final k = (await Store.instance.getString(_kKinopoisk))?.trim() ?? '';
    tmdbToken = t.isNotEmpty ? t : ApiConfig.tmdbTokenEnv.trim();
    kinopoiskKey = k.isNotEmpty ? k : ApiConfig.kinopoiskKeyEnv.trim();
    gateSkipped = await Store.instance.getBool(_kGateSkipped);
  }

  /// Отметить осознанный вход без ключа (см. [gateSkipped]).
  static Future<void> setGateSkipped(bool v) async {
    gateSkipped = v;
    await Store.instance.setBool(_kGateSkipped, v);
  }

  static Future<void> setTmdbToken(String v) async {
    tmdbToken = v.trim();
    if (tmdbToken.isEmpty) {
      await Store.instance.remove(_kTmdb);
    } else {
      await Store.instance.setString(_kTmdb, tmdbToken);
    }
  }

  static Future<void> setKinopoiskKey(String v) async {
    kinopoiskKey = v.trim();
    if (kinopoiskKey.isEmpty) {
      await Store.instance.remove(_kKinopoisk);
    } else {
      await Store.instance.setString(_kKinopoisk, kinopoiskKey);
    }
  }
}
