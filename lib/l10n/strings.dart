import 'locale_controller.dart';
import 'translations.dart';

/// Перевод строки по ключу на текущий язык.
///
/// Базовые ru/en лежат в [_strings]; остальные языки — в [kTranslations]
/// (translations.dart). Если перевода на выбранный язык нет — откатываемся на
/// английский, затем на русский, затем на сам ключ.
String tr(String key) {
  final code = LocaleController.instance.code;
  final extra = kTranslations[code]?[key];
  if (extra != null && extra.isNotEmpty) return extra;
  final entry = _strings[key];
  if (entry == null) return key;
  return entry[code] ?? entry['en'] ?? entry['ru'] ?? key;
}

/// Перевод с подстановкой `{name}` → значение.
String trf(String key, Map<String, Object> params) {
  var s = tr(key);
  params.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Словарь интерфейсных строк (ru/en). Растёт по мере локализации экранов.
const Map<String, Map<String, String>> _strings = {
  // ------------------------------ Общее ------------------------------
  'app_name': {'ru': 'Kadr', 'en': 'Kadr'},
  'cancel': {'ru': 'Отмена', 'en': 'Cancel'},
  'save': {'ru': 'Сохранить', 'en': 'Save'},
  'delete': {'ru': 'Удалить', 'en': 'Delete'},
  'reset': {'ru': 'Сбросить', 'en': 'Reset'},
  'apply': {'ru': 'Применить', 'en': 'Apply'},
  'done': {'ru': 'Готово', 'en': 'Done'},
  'add': {'ru': 'Добавить', 'en': 'Add'},
  'on': {'ru': 'Вкл', 'en': 'On'},
  'off': {'ru': 'Выкл', 'en': 'Off'},
  'soon': {'ru': 'Скоро', 'en': 'Coming soon'},
  'soon_sub': {
    'ru': 'Этот раздел ещё в разработке',
    'en': 'This section is under construction'
  },

  // ---------------------------- Навигация ----------------------------
  'nav_watchlist': {'ru': 'Буду смотреть', 'en': 'Watchlist'},
  'nav_watched': {'ru': 'Просмотрено', 'en': 'Watched'},
  'nav_discover': {'ru': 'Обзор', 'en': 'Discover'},
  'nav_cinema': {'ru': 'В кино', 'en': 'In theaters'},
  'drawer_home': {'ru': 'Главная', 'en': 'Home'},
  'drawer_search': {'ru': 'Поиск фильмов', 'en': 'Search movies'},
  'drawer_stats': {'ru': 'Статистика', 'en': 'Statistics'},
  'drawer_lists': {'ru': 'Списки', 'en': 'Lists'},
  'drawer_settings': {'ru': 'Настройки', 'en': 'Settings'},
  'drawer_about': {'ru': 'О приложении', 'en': 'About'},
  'search_hint': {'ru': 'Фильмы и сериалы…', 'en': 'Movies and series…'},

  // ---------------------------- Настройки ----------------------------
  'settings_title': {'ru': 'Настройки', 'en': 'Settings'},
  'appearance': {'ru': 'Внешний вид', 'en': 'Appearance'},
  'language': {'ru': 'Язык', 'en': 'Language'},
  'theme_mode': {'ru': 'Тема', 'en': 'Theme'},
  'theme_light': {'ru': 'Светлая', 'en': 'Light'},
  'theme_dark': {'ru': 'Тёмная', 'en': 'Dark'},
  'theme_system': {'ru': 'Системная', 'en': 'System'},
  'theme_auto': {'ru': 'Авто (по времени)', 'en': 'Auto (by time)'},
  'dynamic_color': {'ru': 'Material You', 'en': 'Material You'},
  'dynamic_color_sub': {
    'ru': 'Цвет из обоев системы (Android 12+)',
    'en': 'Color from system wallpaper (Android 12+)'
  },
  'amoled': {'ru': 'AMOLED-чёрный', 'en': 'AMOLED black'},
  'amoled_sub': {
    'ru': 'Чистый чёрный фон в тёмной теме',
    'en': 'Pure black background in dark theme'
  },
  'theme_presets': {'ru': 'Палитры', 'en': 'Palettes'},
  'theme_color': {'ru': 'Цвет оформления', 'en': 'Theme color'},
  'theme_color_custom': {'ru': 'Свой цвет', 'en': 'Custom color'},
  'data': {'ru': 'Данные', 'en': 'Data'},
  'sync_backup': {'ru': 'Синхронизация и бэкап', 'en': 'Sync & backup'},
  'sync_backup_sub': {
    'ru': 'Резервные копии и перенос между устройствами',
    'en': 'Backups and transfer between devices'
  },
  'create_backup': {'ru': 'Создать резервную копию', 'en': 'Create backup'},
  'restore_backup': {'ru': 'Восстановить из копии', 'en': 'Restore backup'},
  'about': {'ru': 'О приложении', 'en': 'About'},
  'about_sub': {
    'ru': 'Трекер просмотренных фильмов и сериалов',
    'en': 'Watched movies and series tracker'
  },

  // ----------------------- Оценки-настроения -----------------------
  'mood_awful': {'ru': 'Ужасно', 'en': 'Awful'},
  'mood_bad': {'ru': 'Плохо', 'en': 'Bad'},
  'mood_meh': {'ru': 'Так себе', 'en': 'Meh'},
  'mood_good': {'ru': 'Хорошо', 'en': 'Good'},
  'mood_great': {'ru': 'Отлично', 'en': 'Great'},
  'mood_fantastic': {'ru': 'Восхитительно', 'en': 'Fantastic'},

  // -------------------------- Детали фильма --------------------------
  'tab_info': {'ru': 'Инфо', 'en': 'Info'},
  'tab_reviews': {'ru': 'Отзывы', 'en': 'Reviews'},
  'act_watched': {'ru': 'Просмотрено', 'en': 'Watched'},
  'act_lists': {'ru': 'Списки', 'en': 'Lists'},
  'act_watchlist': {'ru': 'Буду смотреть', 'en': 'Watchlist'},
  'act_favorite': {'ru': 'Избранное', 'en': 'Favorite'},
  'when_watched_q': {'ru': 'Когда вы его посмотрели?', 'en': 'When did you watch it?'},
  'when_unknown': {'ru': 'Неизвестная дата', 'en': 'Unknown date'},
  'when_just_finished': {'ru': 'Только что завершил', 'en': 'Just finished'},
  'when_pick_date': {'ru': 'Выберите дату', 'en': 'Pick a date'},

  // -------------------------- Библиотека --------------------------
  'your_rating': {'ru': 'Ваша оценка', 'en': 'Your rating'},
  'rate_it': {'ru': 'Оцените фильм', 'en': 'Rate this movie'},
  'not_rated': {'ru': 'Без оценки', 'en': 'Not rated'},
  'viewings_n': {'ru': 'Просмотров: {n}', 'en': 'Viewings: {n}'},
  'watched_month': {'ru': 'Просмотры {month} {year} г.', 'en': 'Watched · {month} {year}'},
  'watched_date': {'ru': 'Дата просмотра: {date}', 'en': 'Watched on {date}'},
  'lib_empty_watched': {
    'ru': 'Пока нет просмотренных фильмов',
    'en': 'No watched movies yet'
  },
  'lib_empty_watchlist': {
    'ru': 'Список «Буду смотреть» пуст',
    'en': 'Your watchlist is empty'
  },
  'lib_count': {'ru': 'Всего: {n}', 'en': 'Total: {n}'},
  'rewatch': {'ru': 'Повтор', 'en': 'Rewatch'},
  'rewatch_full': {'ru': 'Повторный просмотр', 'en': 'Rewatched'},
  'rewatches_n': {'ru': 'Повторов: {n}', 'en': 'Rewatches: {n}'},
  'mark_watched': {'ru': 'Отметить просмотр', 'en': 'Log a watch'},
  'add_watchlist': {'ru': 'Буду смотреть', 'en': 'Watchlist'},
  'in_watchlist': {'ru': 'В списке', 'en': 'In watchlist'},
  'kp_rating': {'ru': 'Кинопоиск', 'en': 'Kinopoisk'},

  // ---------------------- Когда посмотрели ----------------------
  'when_today': {'ru': 'Сегодня', 'en': 'Today'},
  'when_yesterday': {'ru': 'Вчера', 'en': 'Yesterday'},
  'when_now': {'ru': 'Только что', 'en': 'Just now'},
  'viewing_added': {'ru': 'Отмечено как просмотрено', 'en': 'Marked as watched'},
  'rewatch_added': {'ru': 'Добавлен повторный просмотр', 'en': 'Rewatch logged'},

  // ------------------- Оценки по просмотрам -------------------
  'overall_score': {'ru': 'Общая оценка', 'en': 'Overall rating'},
  'per_viewing_scores': {'ru': 'Оценки по просмотрам', 'en': 'Ratings per viewing'},
  'score_comparison': {'ru': 'Как менялась оценка', 'en': 'How your rating changed'},
  'rate_this_viewing': {'ru': 'Оценка просмотра', 'en': 'Rate this viewing'},
  'remove_score': {'ru': 'Убрать оценку', 'en': 'Clear rating'},
  'cmp_improved': {'ru': 'Мнение улучшилось на {d}', 'en': 'Opinion improved by {d}'},
  'cmp_dropped': {'ru': 'Мнение ухудшилось на {d}', 'en': 'Opinion dropped by {d}'},
  'cmp_same': {'ru': 'Оценка не изменилась', 'en': 'Rating unchanged'},
  'viewing_n': {'ru': '{n}-й просмотр', 'en': 'Viewing {n}'},
};
