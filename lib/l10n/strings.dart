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
  'undo': {'ru': 'Отменить', 'en': 'Undo'},
  'save': {'ru': 'Сохранить', 'en': 'Save'},
  'delete': {'ru': 'Удалить', 'en': 'Delete'},
  'reset': {'ru': 'Сбросить', 'en': 'Reset'},
  'apply': {'ru': 'Применить', 'en': 'Apply'},
  'done': {'ru': 'Готово', 'en': 'Done'},
  'add': {'ru': 'Добавить', 'en': 'Add'},
  'select_all': {'ru': 'Выбрать все', 'en': 'Select all'},
  'n_selected': {'ru': 'Выбрано: {n}', 'en': '{n} selected'},
  'delete_selected_title': {'ru': 'Удалить выбранное?', 'en': 'Delete selected?'},
  'delete_selected_watched': {
    'ru': 'Отметки о просмотре ({n}) будут убраны. Сами фильмы и сериалы останутся в базе.',
    'en': 'Watch records ({n}) will be removed. Titles stay in the database.'
  },
  'delete_selected_watchlist': {
    'ru': 'Выбранное ({n}) уберётся из «Буду смотреть». Из базы фильмы не удаляются.',
    'en': 'Selected ({n}) will be removed from the watchlist. Titles stay in the database.'
  },
  'removed_n': {'ru': 'Убрано: {n}', 'en': 'Removed: {n}'},
  'on': {'ru': 'Вкл', 'en': 'On'},
  'off': {'ru': 'Выкл', 'en': 'Off'},
  'soon': {'ru': 'Скоро', 'en': 'Coming soon'},
  'next': {'ru': 'Далее', 'en': 'Next'},
  'start': {'ru': 'Начать', 'en': 'Get started'},
  'skip': {'ru': 'Пропустить', 'en': 'Skip'},
  'ob1_title': {'ru': 'Твоё кино', 'en': 'Your cinema'},
  'ob1_sub': {
    'ru': 'Веди коллекцию просмотренных фильмов и сериалов — красиво и удобно.',
    'en': 'Track the movies and series you\'ve watched — beautifully.'
  },
  'ob2_title': {'ru': 'Оценивай просмотры', 'en': 'Rate every watch'},
  'ob2_sub': {
    'ru': 'У каждого просмотра своя оценка 1.0–10.0 — мнение меняется при пересмотре.',
    'en': 'Each viewing has its own 1.0–10.0 rating — opinions change on rewatch.'
  },
  'ob3_title': {'ru': 'Русский и постеры', 'en': 'Russian & posters'},
  'ob3_sub': {
    'ru': 'Названия и обложки подтягиваются автоматически из TMDB и Кинопоиска.',
    'en': 'Titles and posters are fetched automatically from TMDB.'
  },
  'ob4_title': {'ru': 'Статистика и списки', 'en': 'Stats & lists'},
  'ob4_sub': {
    'ru': 'Смотри статистику, собирай свои списки и переноси всё бэкапом.',
    'en': 'See your stats, build lists and back everything up.'
  },
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
  'stat_movies': {'ru': 'Фильмов', 'en': 'Movies'},
  'stat_rewatches': {'ru': 'Пересмотров', 'en': 'Rewatches'},
  'stat_dropped': {'ru': 'Брошено', 'en': 'Dropped'},
  'stat_watchlist': {'ru': 'В планах', 'en': 'Watchlist'},
  'stat_screen_time': {'ru': 'У ЭКРАНА', 'en': 'ON SCREEN'},
  'stat_hours_unit': {'ru': 'ч', 'en': 'h'},
  'stat_days_watching': {'ru': '≈ {n} дн. у экрана', 'en': '≈ {n} days on screen'},
  'stat_summary_sub': {
    'ru': '{f} фильмов · {s} сериалов · {e} серий',
    'en': '{f} movies · {s} series · {e} episodes'
  },
  'stat_by_month': {'ru': 'По месяцам', 'en': 'By month'},
  'stat_by_weekday': {'ru': 'По дням недели', 'en': 'By weekday'},
  'stat_by_decade': {'ru': 'Годы выхода', 'en': 'Release years'},
  'stat_split': {'ru': 'Фильмы и сериалы', 'en': 'Movies & series'},
  'stat_vs_kp': {'ru': 'Ты и Кинопоиск', 'en': 'You vs Kinopoisk'},
  'stat_vs_kp_higher': {
    'ru': 'Ты оцениваешь выше КП на {d}',
    'en': "You rate higher than KP by {d}"
  },
  'stat_vs_kp_lower': {
    'ru': 'Ты оцениваешь ниже КП на {d}',
    'en': 'You rate lower than KP by {d}'
  },
  'stat_vs_kp_same': {
    'ru': 'Твои оценки почти как у КП',
    'en': 'Your ratings match KP'
  },
  'stat_vs_kp_sub': {
    'ru': 'по {n} фильмам с рейтингом КП',
    'en': 'across {n} films rated on KP'
  },
  'stat_records': {'ru': 'Рекорды', 'en': 'Records'},
  'stat_most_active_day': {'ru': 'Самый активный день', 'en': 'Most active day'},
  'stat_first_mark': {'ru': 'Первая отметка', 'en': 'First entry'},
  'stat_days_tracked': {'ru': 'Дней в трекере', 'en': 'Days tracked'},
  'stat_avg_runtime': {'ru': 'Средняя длина фильма', 'en': 'Average movie length'},
  'stat_longest': {'ru': 'Самый длинный', 'en': 'Longest'},
  'stat_highest': {'ru': 'Высшая оценка', 'en': 'Highest rating'},
  'stat_lowest': {'ru': 'Низшая оценка', 'en': 'Lowest rating'},
  'stat_most_rewatched': {'ru': 'Чаще всего пересматриваешь', 'en': 'Most rewatched'},
  'stat_top_series': {'ru': 'Больше всего серий', 'en': 'Most-watched series'},
  'stat_completed': {'ru': 'Пройдено', 'en': 'Completed'},
  'stat_genres': {'ru': 'По жанрам', 'en': 'By genre'},
  'stat_fav_genre': {'ru': 'Любимый жанр', 'en': 'Favorite genre'},
  'stat_activity': {'ru': 'Активность', 'en': 'Activity'},
  'stat_less': {'ru': 'меньше', 'en': 'less'},
  'stat_more': {'ru': 'больше', 'en': 'more'},
  'stat_times_n': {'ru': '×{n}', 'en': '×{n}'},
  'stat_eps_n': {'ru': '{n} сер.', 'en': '{n} ep.'},
  'drawer_lists': {'ru': 'Списки', 'en': 'Lists'},
  'movies_count': {'ru': '{n} фильмов', 'en': '{n} movies'},
  'series_count': {'ru': '{n} сериалов', 'en': '{n} series'},
  'list_empty': {'ru': 'Список пуст', 'en': 'Empty list'},
  'my_lists': {'ru': 'Мои списки', 'en': 'My lists'},
  'manage_lists': {'ru': 'Списки', 'en': 'Lists'},
  'new_list': {'ru': 'Новый список', 'en': 'New list'},
  'create': {'ru': 'Создать', 'en': 'Create'},
  'no_lists_yet': {'ru': 'Пока нет своих списков', 'en': 'No custom lists yet'},
  'create_list': {'ru': 'Создать список', 'en': 'Create list'},
  'list_name': {'ru': 'Название списка', 'en': 'List name'},
  'delete_list': {'ru': 'Удалить список', 'en': 'Delete list'},
  'drawer_settings': {'ru': 'Настройки', 'en': 'Settings'},
  'drawer_about': {'ru': 'О приложении', 'en': 'About'},
  'version': {'ru': 'Версия', 'en': 'Version'},
  'about_attribution': {
    'ru': 'Данные о фильмах — TMDB и Кинопоиск. Продукт использует API TMDB, но не одобрен и не сертифицирован TMDB.',
    'en': 'Movie data by TMDB and Kinopoisk. This product uses the TMDB API but is not endorsed or certified by TMDB.'
  },
  'search_hint': {'ru': 'Фильмы и сериалы…', 'en': 'Movies and series…'},
  'search_all_hint': {
    'ru': 'Поиск по всей базе фильмов…',
    'en': 'Search the whole movie database…'
  },

  // ---------------------------- Настройки ----------------------------
  'settings_title': {'ru': 'Настройки', 'en': 'Settings'},
  'appearance': {'ru': 'Внешний вид', 'en': 'Appearance'},
  'general': {'ru': 'Общее', 'en': 'General'},
  'start_screen': {'ru': 'Экран при запуске', 'en': 'Start screen'},
  'date_format': {'ru': 'Формат даты', 'en': 'Date format'},
  'date_format_long': {'ru': 'Как «24 июня 2026»', 'en': 'Like “June 24, 2026”'},
  'date_format_numeric': {'ru': 'Как «24.06.2026»', 'en': 'Like “24.06.2026”'},
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
  'clear_all_data': {'ru': 'Очистить все данные', 'en': 'Clear all data'},
  'clear_all_data_sub': {
    'ru': 'Удалить все просмотры, списки, оценки и сериалы',
    'en': 'Delete all watches, lists, ratings and series'
  },
  'clear_all_title': {'ru': 'Очистить все данные?', 'en': 'Clear all data?'},
  'clear_all_body': {
    'ru': 'Все просмотры, оценки, списки, избранное и сериалы будут удалены безвозвратно. Останутся только ленты «Обзор» и «В кино». Сделайте бэкап заранее, если нужно сохранить.',
    'en': 'All watches, ratings, lists, favorites and series will be deleted permanently. Only the Discover and In theaters feeds remain. Make a backup first if you want to keep the data.'
  },
  'clear_all_done': {'ru': 'Все данные очищены', 'en': 'All data cleared'},
  'clear': {'ru': 'Очистить', 'en': 'Clear'},
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
  'episodes_section': {'ru': 'Серии', 'en': 'Episodes'},
  'season_n': {'ru': 'Сезон {n}', 'en': 'Season {n}'},
  'more_episodes': {'ru': '+ ещё {n} серий', 'en': '+ {n} more episodes'},
  'all_episodes': {'ru': 'Все серии', 'en': 'All episodes'},
  'mark_upto': {'ru': 'Отметить по эту', 'en': 'Mark up to here'},
  'network_error': {'ru': 'Ошибка сети', 'en': 'Network error'},
  'no_episodes': {'ru': 'Не удалось загрузить серии', 'en': 'Could not load episodes'},
  'link_hint': {
    'ru': 'Сериал мог сохраниться другим названием (напр. латиницей). Найдите его в базе вручную — отметки серий сохранятся.',
    'en': 'The series may be saved under another title. Find it manually — your episode marks are kept.'
  },
  'link_find': {'ru': 'Найти в TMDB', 'en': 'Find on TMDB'},
  'link_hint_field': {
    'ru': 'Название сериала (кириллицей)',
    'en': 'Series name'
  },
  'now_watching': {'ru': 'Сейчас смотрю', 'en': 'Now watching'},
  'now_watching_empty': {
    'ru': 'Начните смотреть сериал — он появится здесь',
    'en': 'Start a series — it will show up here'
  },
  'next_episode': {'ru': 'Дальше', 'en': 'Next up'},
  'seen_of': {'ru': 'Просмотрено {n} из {m}', 'en': '{n} of {m} watched'},
  'filter_all': {'ru': 'Все', 'en': 'All'},
  'filter_movies': {'ru': 'Фильмы', 'en': 'Movies'},
  'filter_series': {'ru': 'Сериалы', 'en': 'Series'},

  // ---------------------- Вид галереи и сортировка ----------------------
  'view_mode': {'ru': 'Вид', 'en': 'View'},
  'view_list': {'ru': 'Список', 'en': 'List'},
  'view_posters': {'ru': 'Постеры', 'en': 'Posters'},
  'view_banners': {'ru': 'Баннеры', 'en': 'Banners'},
  'sort': {'ru': 'Сортировка', 'en': 'Sort'},
  'sort_date_new': {'ru': 'Сначала новые', 'en': 'Newest first'},
  'sort_date_old': {'ru': 'Сначала старые', 'en': 'Oldest first'},
  'sort_rating': {'ru': 'По оценке', 'en': 'By rating'},
  'sort_title': {'ru': 'По названию', 'en': 'By title'},
  'sort_year': {'ru': 'По году', 'en': 'By year'},
  'filter_genre': {'ru': 'Жанр', 'en': 'Genre'},
  'filter_year': {'ru': 'Год выхода', 'en': 'Release year'},
  'all_genres': {'ru': 'Все жанры', 'en': 'All genres'},
  'all_years': {'ru': 'Все годы', 'en': 'All years'},
  'sort_popular': {'ru': 'Популярные', 'en': 'Popular'},
  'sort_top_rated': {'ru': 'Высокий рейтинг', 'en': 'Top rated'},
  'sort_new_release': {'ru': 'Новинки', 'en': 'New releases'},
  'nothing_found': {'ru': 'Ничего не найдено', 'en': 'Nothing found'},
  'no_connection': {
    'ru': 'Нет подключения к интернету',
    'en': 'No internet connection'
  },
  'load_more': {'ru': 'Загрузить ещё', 'en': 'Load more'},
  'rate_after_watch': {
    'ru': 'Посмотрите фильм, чтобы его оценить',
    'en': 'Watch the movie to rate it'
  },
  'copied': {'ru': 'Скопировано', 'en': 'Copied'},
  'view_poster': {'ru': 'Открыть постер', 'en': 'Open poster'},
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

  // ---------------------- Доработки карточки / сериалов ----------------------
  'no_rating_yet': {'ru': 'Оценка не выбрана', 'en': 'No rating yet'},
  'undo_watch': {'ru': 'Отменить просмотр', 'en': 'Undo watch'},
  'watch_undone': {'ru': 'Просмотр отменён', 'en': 'Watch undone'},
  'unwatched': {'ru': 'Убрано из просмотренного', 'en': 'Removed from watched'},
  'rate_series': {'ru': 'Оценить сериал', 'en': 'Rate series'},
  'series_rating': {'ru': 'Оценка сериала', 'en': 'Series rating'},
  'avg_of_episodes': {'ru': 'Средняя по сериям', 'en': 'Episode average'},
  'rate_season': {'ru': 'Оценить сезон', 'en': 'Rate season'},
  'season_rated': {
    'ru': 'Оценено серий: {n} · {v}',
    'en': 'Rated {n} episodes · {v}'
  },
  'season_no_watched': {
    'ru': 'В сезоне нет просмотренных серий для оценки',
    'en': 'No watched episodes in this season to rate'
  },
  'season_date': {'ru': 'Дата просмотра сезона', 'en': 'Season watch date'},
  'season_dated': {
    'ru': 'Дата задана для {n} серий',
    'en': 'Date set for {n} episodes'
  },
  'restrict_unaired': {'ru': 'Запрет невышедших серий', 'en': 'Block unaired episodes'},
  'restrict_unaired_sub': {
    'ru': 'Нельзя отметить/оценить серию, которая ещё не вышла',
    'en': "Can't mark or rate an episode that hasn't aired yet"
  },
  'episode_not_aired': {
    'ru': 'Серия ещё не вышла',
    'en': "Episode hasn't aired yet"
  },
  'not_aired_badge': {'ru': 'скоро', 'en': 'soon'},
  'series_avg_locked': {
    'ru': 'Оценка считается по оценкам серий. Уберите оценки серий, чтобы поставить вручную.',
    'en': 'Rating is the episode average. Clear episode ratings to set it manually.'
  },
  'mark_season': {'ru': 'Отметить весь сезон', 'en': 'Mark whole season'},
  'unmark_season': {'ru': 'Снять весь сезон', 'en': 'Unmark whole season'},
  'season_done': {'ru': 'Сезон {n} отмечен', 'en': 'Season {n} marked'},
  'watch_again': {'ru': 'Смотрел ещё раз', 'en': 'Watched again'},
  'season_rewatch_title': {
    'ru': 'Отметить весь сезон {n} ещё раз?',
    'en': 'Mark whole season {n} watched again?'
  },
  'season_rewatch_sub': {
    'ru': 'Повторный просмотр всех {n} серий сезона',
    'en': 'Rewatch all {n} episodes of the season'
  },
  'season_rewatched': {
    'ru': 'Сезон отмечен ещё раз ({c} серий)',
    'en': 'Season marked again ({c} episodes)'
  },
  'season_clear_all': {
    'ru': 'Снять все просмотры',
    'en': 'Remove all watches'
  },
  'season_cleared': {
    'ru': 'Просмотры сезона сняты',
    'en': 'Season watches removed'
  },
  'extra_episodes_removed': {
    'ru': 'Убрано лишних серий: {n}',
    'en': 'Removed {n} extra episodes'
  },
  'ep_watched_n': {'ru': 'Просмотров: {n}', 'en': 'Watches: {n}'},
  'rewatch_removed': {'ru': 'Повтор убран', 'en': 'Rewatch removed'},
  'season_progress': {'ru': 'Сезон {s}: {n}/{m}', 'en': 'Season {s}: {n}/{m}'},
  'episode': {'ru': 'Серия', 'en': 'Episode'},
  'rate_short': {'ru': 'Оценить', 'en': 'Rate'},
  'episode_score': {'ru': 'Оценка серии', 'en': 'Episode rating'},
  'rate_after_watch_ep': {
    'ru': 'Отметьте просмотр серии, чтобы её оценить',
    'en': 'Mark the episode watched to rate it'
  },
  'clear_all_checks': {'ru': 'Снять просмотр', 'en': 'Unmark watched'},
  'reset_to_one': {'ru': 'Вернуть один просмотр', 'en': 'Keep a single watch'},
  'remove_one_watch': {'ru': 'Убрать просмотр', 'en': 'Remove one watch'},
  'edit_watch_date': {'ru': 'Изменить дату и время', 'en': 'Change date & time'},
  'set_unknown_date': {'ru': 'Дата: неизвестно', 'en': 'Date: unknown'},
  'marked_unknown': {
    'ru': 'Отмечено без даты («Неизвестно»)',
    'en': 'Marked without a date (“Unknown”)'
  },
  'enter_score': {'ru': 'Введите оценку', 'en': 'Enter your score'},
  'collection': {'ru': 'Части франшизы', 'en': 'Franchise'},
  'search_local_empty': {
    'ru': 'В вашей библиотеке ничего не найдено по «{q}».',
    'en': 'Nothing in your library for “{q}”.'
  },
  'search_all_db': {'ru': 'Искать по всей базе', 'en': 'Search the whole database'},
  'edit': {'ru': 'Изменить', 'en': 'Edit'},
  'my_review': {'ru': 'Моя рецензия', 'en': 'My review'},
  'write_review': {'ru': 'Написать рецензию', 'en': 'Write a review'},
  'review_hint': {
    'ru': 'Что думаешь о фильме? Впечатления, мысли, оценка…',
    'en': 'What did you think? Your impressions, thoughts…'
  },
  'filters': {'ru': 'Фильтры', 'en': 'Filters'},
  'filter_genres': {'ru': 'Жанры', 'en': 'Genres'},
  'filter_genres_loading': {
    'ru': 'Жанры подгружаются в фоне — открой пару карточек или зайди позже.',
    'en': 'Genres load in the background — open a few cards or come back later.'
  },
  'update_available': {'ru': 'Доступно обновление', 'en': 'Update available'},
  'update_new_version': {'ru': 'Новая версия {v}', 'en': 'New version {v}'},
  'update_current_version': {'ru': 'У вас {v}', 'en': 'You have {v}'},
  'update_now': {'ru': 'Обновить', 'en': 'Update'},
  'update_later': {'ru': 'Позже', 'en': 'Later'},
  'update_downloading': {'ru': 'Скачивание… {p}%', 'en': 'Downloading… {p}%'},
  'update_installing': {'ru': 'Запуск установки…', 'en': 'Starting install…'},
  'update_open_github': {'ru': 'Открыть на GitHub', 'en': 'Open on GitHub'},
  'update_failed': {
    'ru': 'Не удалось скачать. Откройте релиз вручную.',
    'en': 'Download failed. Open the release manually.'
  },
  'update_whats_new': {'ru': 'Что нового', 'en': "What's new"},
  'check_updates': {'ru': 'Проверить обновления', 'en': 'Check for updates'},
  'check_updates_sub': {
    'ru': 'Скачать новую версию с GitHub',
    'en': 'Download the latest version from GitHub'
  },
  'up_to_date': {
    'ru': 'У вас последняя версия',
    'en': "You're on the latest version"
  },
  'checking_updates': {'ru': 'Проверяю обновления…', 'en': 'Checking for updates…'},
  'update_check_failed': {
    'ru': 'Не удалось проверить обновления',
    'en': 'Could not check for updates'
  },
  'sync_title': {'ru': 'Синхронизация', 'en': 'Sync'},
  'sync_webdav': {'ru': 'Синхронизация (WebDAV)', 'en': 'Sync (WebDAV)'},
  'sync_webdav_sub': {
    'ru': 'Между устройствами через ваш облачный диск',
    'en': 'Between devices via your cloud drive'
  },
  'sync_intro': {
    'ru': 'Двусторонняя синхронизация через WebDAV (Nextcloud, Яндекс.Диск, ownCloud). Данные на вашем сервере, ничего добавленного не теряется.',
    'en': 'Two-way sync via WebDAV (Nextcloud, Yandex.Disk, ownCloud). Data stays on your server; nothing added is lost.'
  },
  'sync_url': {'ru': 'Адрес WebDAV', 'en': 'WebDAV URL'},
  'sync_url_hint': {
    'ru': 'https://облако.домен/remote.php/dav/files/user/',
    'en': 'https://cloud.example/remote.php/dav/files/user/'
  },
  'sync_user': {'ru': 'Логин', 'en': 'Username'},
  'sync_pass': {'ru': 'Пароль (или пароль приложения)', 'en': 'Password (or app password)'},
  'sync_connect': {'ru': 'Подключить', 'en': 'Connect'},
  'sync_connected': {'ru': 'Подключено', 'en': 'Connected'},
  'sync_connect_failed': {
    'ru': 'Не удалось подключиться. Проверьте адрес и данные.',
    'en': 'Connection failed. Check URL and credentials.'
  },
  'sync_now': {'ru': 'Синхронизировать сейчас', 'en': 'Sync now'},
  'sync_done': {
    'ru': 'Синхронизировано (+{a}, объединено {m})',
    'en': 'Synced (+{a}, merged {m})'
  },
  'sync_no_changes': {'ru': 'Всё уже синхронно', 'en': 'Already up to date'},
  'sync_error': {'ru': 'Ошибка синхронизации', 'en': 'Sync failed'},
  'sync_auto': {'ru': 'Авто-синхронизация', 'en': 'Auto-sync'},
  'sync_auto_sub': {
    'ru': 'Синхронизировать при запуске приложения',
    'en': 'Sync on app start'
  },
  'sync_forget': {'ru': 'Отключить', 'en': 'Disconnect'},
  'sync_last': {'ru': 'Последний синк: {t}', 'en': 'Last sync: {t}'},
  'sync_never': {'ru': 'Ещё не синхронизировано', 'en': 'Not synced yet'},
  'seq_mode': {'ru': 'Отмечать серии по порядку', 'en': 'Mark episodes in order'},
  'seq_mode_sub': {
    'ru': 'Отметил серию — все до неё тоже; снял — все после снимаются',
    'en': 'Marking an episode marks all before it; unmarking clears all after'
  },

  // ------------------------------ Брошено ------------------------------
  'dropped': {'ru': 'Брошено', 'en': 'Dropped'},
  'mark_dropped': {'ru': 'Бросить', 'en': 'Drop'},
  'in_dropped': {'ru': 'Брошено', 'en': 'Dropped'},
  'drawer_dropped': {'ru': 'Брошено', 'en': 'Dropped'},
  'dropped_empty': {
    'ru': 'Здесь будут фильмы и сериалы, которые вы бросили',
    'en': 'Movies and series you dropped will appear here'
  },
  'dropped_movies': {'ru': 'Фильмы', 'en': 'Movies'},
  'dropped_series': {'ru': 'Сериалы', 'en': 'Series'},
  'dropped_count': {'ru': 'Брошено: {n}', 'en': 'Dropped: {n}'},

  // --------------------- Уведомления о новых сериях ---------------------
  'notif_new_episodes': {'ru': 'Новые серии', 'en': 'New episodes'},
  'notif_new_episodes_sub': {
    'ru': 'Уведомлять о выходе новых серий сериалов, которые смотрю',
    'en': 'Notify when new episodes of series I watch are released'
  },
  'notif_channel_name': {'ru': 'Новые серии', 'en': 'New episodes'},
  'notif_new_ep_title': {'ru': 'Вышла новая серия', 'en': 'New episode out'},
  'notif_new_ep_body': {
    'ru': '{title}: серия {ep} уже вышла',
    'en': '{title}: episode {ep} is out'
  },
  'new_episodes_n': {'ru': '{n} новых серий', 'en': '{n} new episodes'},
  'notif_test': {'ru': 'Показать пример', 'en': 'Show a sample'},
  'notif_test_sub': {
    'ru': 'Проверить, как выглядит уведомление',
    'en': 'Preview how the notification looks'
  },
  'close': {'ru': 'Закрыть', 'en': 'Close'},
  'kp_limit_hit': {
    'ru': 'Лимит kinopoisk.dev на сегодня исчерпан (200 запросов/сутки). '
        'Постеры и поиск дозагрузятся позже.',
    'en': 'kinopoisk.dev daily limit reached (200 requests/day). '
        'Posters and search will resume later.',
  },
  'kp_limit_switch': {'ru': 'На TMDB', 'en': 'Use TMDB'},
};
