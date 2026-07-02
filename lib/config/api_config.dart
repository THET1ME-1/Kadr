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

  /// TMDB v4 read-access token (Bearer). Бесплатно, без суточного лимита
  /// (~50 запросов/сек). Переопределить: `--dart-define=TMDB_TOKEN=...`.
  static const String tmdbToken = String.fromEnvironment(
    'TMDB_TOKEN',
    defaultValue:
        'REMOVED_TMDB_TOKEN',
  );

  static const String tmdbBase = 'https://api.themoviedb.org/3';
  static const String tmdbImageBase = 'https://image.tmdb.org/t/p/w342';
}
