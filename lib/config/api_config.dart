/// Ключи внешних API.
///
/// Токен kinopoisk.dev (ПоискКино API). Демо-тариф: 200 запросов/сутки.
/// Можно переопределить при сборке: `--dart-define=KINOPOISK_KEY=...`.
/// Ключ можно перевыпустить в личном кабинете при необходимости.
class ApiConfig {
  static const String kinopoiskKey = String.fromEnvironment(
    'KINOPOISK_KEY',
    defaultValue: 'REMOVED_KINOPOISK_KEY',
  );

  static const String kinopoiskBase = 'https://api.poiskkino.dev';
}
