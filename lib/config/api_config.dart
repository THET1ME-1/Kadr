/// Адреса внешних API и КОМПИЛЯЦИОННЫЙ fallback ключей.
///
/// ВАЖНО: в публичной сборке ключи ПУСТЫЕ — их вводит сам пользователь (см.
/// [ApiKeys]/`TmdbKeyScreen`), потому что API-ключи персональные. Для своей
/// сборки можно вшить: `--dart-define=TMDB_TOKEN=... --dart-define=KINOPOISK_KEY=...`.
class ApiConfig {
  /// Ключ kinopoisk.dev из окружения сборки (пусто → берётся введённый в приложении).
  static const String kinopoiskKeyEnv = String.fromEnvironment(
    'KINOPOISK_KEY',
    defaultValue: '',
  );

  static const String kinopoiskBase = 'https://api.poiskkino.dev';

  /// TMDB v4 read-access token из окружения сборки (пусто → вводит пользователь).
  static const String tmdbTokenEnv = String.fromEnvironment(
    'TMDB_TOKEN',
    defaultValue: '',
  );

  static const String tmdbBase = 'https://api.themoviedb.org/3';
  static const String tmdbImageBase = 'https://image.tmdb.org/t/p/w342';
  static const String tmdbBackdropBase = 'https://image.tmdb.org/t/p/w780';
  static const String tmdbProfileBase = 'https://image.tmdb.org/t/p/w185';

  /// Бэкенд соц-слоя (профили/друзья/публичная проекция) — Cloudflare Worker.
  /// Переопределить: `--dart-define=SOCIAL_BASE=...`.
  static const String socialBase = String.fromEnvironment(
    'SOCIAL_BASE',
    defaultValue: 'https://kadr-social.badzoff.workers.dev',
  );
}
