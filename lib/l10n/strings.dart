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
  'discover_error': {'ru': 'Не удалось загрузить', 'en': 'Failed to load'},
  'retry': {'ru': 'Повторить', 'en': 'Retry'},
  'added_to_watchlist': {'ru': 'Добавлено в «Буду смотреть»', 'en': 'Added to watchlist'},
  'added_to_watched': {'ru': 'Отмечено просмотренным', 'en': 'Marked as watched'},
  'in_library': {'ru': 'В библиотеке', 'en': 'In library'},
  'drawer_home': {'ru': 'Главная', 'en': 'Home'},
  'drawer_search': {'ru': 'Поиск фильмов', 'en': 'Search movies'},
  'drawer_stats': {'ru': 'Статистика', 'en': 'Statistics'},
  'stat_watched': {'ru': 'Просмотрено', 'en': 'Watched'},
  'stat_hours': {'ru': 'Часов у экрана', 'en': 'Hours watched'},
  'stat_avg': {'ru': 'Средняя оценка', 'en': 'Average rating'},
  'stat_rated': {'ru': 'Оценено', 'en': 'Rated'},
  'stat_by_year': {'ru': 'Просмотры по годам', 'en': 'Views by year'},
  'stat_scores': {'ru': 'Распределение оценок', 'en': 'Rating distribution'},
  'stat_top': {'ru': 'Топ по вашей оценке', 'en': 'Your top rated'},
  'stat_series': {'ru': 'Сериалы', 'en': 'Series'},
  'stat_episodes': {'ru': 'Серий просмотрено', 'en': 'Episodes watched'},
  'stat_favorites': {'ru': 'В избранном', 'en': 'Favorites'},
  'stat_viewings': {'ru': 'Просмотров всего', 'en': 'Total viewings'},
  'stat_emotions': {'ru': 'Ваши эмоции', 'en': 'Your emotions'},
  'stat_empty': {'ru': 'Пока нет данных для статистики', 'en': 'No data yet'},
  'drawer_lists': {'ru': 'Списки', 'en': 'Lists'},
  'movies_count': {'ru': '{n} фильмов', 'en': '{n} movies'},
  'list_empty': {'ru': 'Список пуст', 'en': 'Empty list'},
  'my_lists': {'ru': 'Мои списки', 'en': 'My lists'},
  'manage_lists': {'ru': 'Списки', 'en': 'Lists'},
  'new_list': {'ru': 'Новый список', 'en': 'New list'},
  'create': {'ru': 'Создать', 'en': 'Create'},
  'no_lists_yet': {'ru': 'Пока нет своих списков', 'en': 'No custom lists yet'},
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
  'movies_section': {'ru': 'Фильмы', 'en': 'Movies'},
  'movie_source': {'ru': 'Источник поиска', 'en': 'Search source'},
  'movie_source_sub': {
    'ru': 'Откуда брать названия, постеры и данные',
    'en': 'Where to get titles, posters and data'
  },
  'data': {'ru': 'Данные', 'en': 'Data'},
  'sync_backup': {'ru': 'Синхронизация и бэкап', 'en': 'Sync & backup'},
  'sync_backup_sub': {
    'ru': 'Резервные копии и перенос между устройствами',
    'en': 'Backups and transfer between devices'
  },
  'create_backup': {'ru': 'Создать резервную копию', 'en': 'Create backup'},
  'create_backup_sub': {
    'ru': 'Поделиться файлом (Telegram, Диск, …)',
    'en': 'Share a file (Telegram, Drive, …)'
  },
  'restore_backup': {'ru': 'Восстановить из копии', 'en': 'Restore backup'},
  'restore_backup_sub': {
    'ru': 'Выбрать JSON-файл резервной копии',
    'en': 'Pick a backup JSON file'
  },
  'backup_hint': {
    'ru': 'Перенос на новый телефон: создайте копию здесь и восстановите её на новом устройстве.',
    'en': 'Moving to a new phone: create a backup here and restore it on the new device.'
  },
  'backup_import_ok': {'ru': 'Библиотека восстановлена', 'en': 'Library restored'},
  'backup_import_fail': {'ru': 'Не удалось прочитать файл', 'en': 'Could not read file'},
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
  'overview': {'ru': 'Описание', 'en': 'Overview'},
  'genres': {'ru': 'Жанры', 'en': 'Genres'},
  'cast': {'ru': 'В ролях', 'en': 'Cast'},
  'director': {'ru': 'Режиссёр', 'en': 'Director'},
  'budget': {'ru': 'Бюджет', 'en': 'Budget'},
  'revenue': {'ru': 'Сборы', 'en': 'Box office'},
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
  'sort_newest': {'ru': 'Сначала новые', 'en': 'Newest first'},
  'sort_oldest': {'ru': 'Сначала старые', 'en': 'Oldest first'},
  'nav_series': {'ru': 'Сериалы', 'en': 'Series'},
  'episodes_n': {'ru': '{n} серий', 'en': '{n} episodes'},
  'filter_all': {'ru': 'Все', 'en': 'All'},
  'filter_movies': {'ru': 'Фильмы', 'en': 'Movies'},
  'filter_series': {'ru': 'Сериалы', 'en': 'Series'},
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
  'current_viewing_score': {
    'ru': 'Оценка текущего просмотра',
    'en': 'Current viewing rating'
  },
  'per_viewing_scores': {'ru': 'Оценки по просмотрам', 'en': 'Ratings per viewing'},
  'score_comparison': {'ru': 'Как менялась оценка', 'en': 'How your rating changed'},
  'rate_this_viewing': {'ru': 'Оценка просмотра', 'en': 'Rate this viewing'},
  'remove_score': {'ru': 'Убрать оценку', 'en': 'Clear rating'},
  'cmp_improved': {'ru': 'Мнение улучшилось на {d}', 'en': 'Opinion improved by {d}'},
  'cmp_dropped': {'ru': 'Мнение ухудшилось на {d}', 'en': 'Opinion dropped by {d}'},
  'cmp_same': {'ru': 'Оценка не изменилась', 'en': 'Rating unchanged'},
  'viewing_n': {'ru': '{n}-й просмотр', 'en': 'Viewing {n}'},
  'edit_viewing': {'ru': 'Просмотр', 'en': 'Viewing'},
  'delete_viewing': {'ru': 'Удалить просмотр', 'en': 'Delete viewing'},
  'date_time': {'ru': 'Дата и время', 'en': 'Date & time'},
  'clear_date': {'ru': 'Убрать дату', 'en': 'Clear date'},
  'viewing_deleted': {'ru': 'Просмотр удалён', 'en': 'Viewing deleted'},
};
