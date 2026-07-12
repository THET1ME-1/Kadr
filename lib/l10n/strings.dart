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
  'poster_change': {'ru': 'Изменить постер', 'en': 'Change poster'},
  'poster_load_failed': {
    'ru': 'Не удалось загрузить постер',
    'en': 'Failed to load poster'
  },
  'poster_reset': {'ru': 'Вернуть оригинал', 'en': 'Restore original'},
  'disc_hide_section': {'ru': 'Скрывать в Обзоре', 'en': 'Hide in Discover'},
  'disc_hide_watched_movies': {
    'ru': 'Просмотренные фильмы',
    'en': 'Watched movies',
  },
  'disc_hide_watched_series': {
    'ru': 'Просмотренные сериалы',
    'en': 'Watched series',
  },
  'disc_hide_dropped_movies': {
    'ru': 'Брошенные фильмы',
    'en': 'Dropped movies',
  },
  'disc_hide_dropped_series': {
    'ru': 'Брошенные сериалы',
    'en': 'Dropped series',
  },
  'disc_hide_watchlist_movies': {
    'ru': '«Буду смотреть» — фильмы',
    'en': 'Watchlist — movies',
  },
  'disc_hide_watchlist_series': {
    'ru': '«Буду смотреть» — сериалы',
    'en': 'Watchlist — series',
  },
  'fav_char_set': {
    'ru': 'Сделать любимым персонажем',
    'en': 'Set as favourite character',
  },
  'fav_char_remove': {
    'ru': 'Убрать из любимых',
    'en': 'Remove from favourites',
  },
  'fav_char_title': {'ru': 'Любимый персонаж', 'en': 'Favourite character'},
  'fav_char_from': {'ru': 'из «{title}»', 'en': 'from "{title}"'},
  'drawer_schedule': {'ru': 'Расписание', 'en': 'Schedule'},
  'schedule_empty_title': {'ru': 'Пока нечего ждать', 'en': 'Nothing upcoming'},
  'schedule_empty_sub': {
    'ru': 'Здесь появятся ближайшие серии сериалов из «Сейчас смотрю».',
    'en': 'Upcoming episodes of your in-progress series will show here.',
  },
  'schedule_today': {'ru': 'сегодня', 'en': 'today'},
  'schedule_tomorrow': {'ru': 'завтра', 'en': 'tomorrow'},
  'schedule_in_days': {'ru': 'через {n} дн.', 'en': 'in {n} days'},
  'fav_actor_add': {'ru': 'В любимые актёры', 'en': 'Favourite this actor'},
  'fav_actor_remove': {
    'ru': 'Убрать из любимых',
    'en': 'Remove from favourites',
  },
  'fav_actors_title': {'ru': 'Любимые актёры', 'en': 'Favourite actors'},
  'drawer_news': {'ru': 'Кино-новости', 'en': 'Movie news'},
  'news_empty_title': {'ru': 'Новостей нет', 'en': 'No news'},
  'news_empty_sub': {
    'ru':
        'Не удалось загрузить новости. Проверь соединение и попробуй ещё раз.',
    'en': 'Couldn\'t load news. Check your connection and try again.',
  },
  'news_recent': {'ru': 'только что', 'en': 'just now'},
  'news_hours_ago': {'ru': '{n} ч назад', 'en': '{n}h ago'},
  'news_days_ago': {'ru': '{n} дн назад', 'en': '{n}d ago'},
  'drawer_customize': {'ru': 'Настроить меню', 'en': 'Customize menu'},
  'drawer_customize_sub': {
    'ru': 'Порядок и видимость пунктов бокового меню',
    'en': 'Order and visibility of side-menu items',
  },
  'tv_mode': {'ru': 'TV-режим', 'en': 'TV mode'},
  'tv_mode_sub': {
    'ru': 'Интерфейс под пульт (авто на Android TV)',
    'en': 'Remote-friendly UI (auto on Android TV)',
  },
  'trakt_sub': {
    'ru': 'Синхронизация просмотренного и списков',
    'en': 'Sync watched and lists',
  },
  'trakt_intro': {
    'ru':
        'Синхронизируй просмотренное, «буду смотреть» и оценки с Trakt. Kadr '
        'остаётся источником правды — синк только добавляет и заполняет, ничего '
        'не удаляет и не перезаписывает.',
    'en':
        'Sync your watched, watchlist and ratings with Trakt. Kadr stays the '
        'source of truth — sync only adds and fills gaps, never deletes or '
        'overwrites.',
  },
  'trakt_limits_note': {
    'ru':
        'Бесплатный аккаунт Trakt: «буду смотреть» — до 250, история '
        'просмотров — до 100 000, оценки — до 10 000. Нужно больше — Trakt VIP '
        '(платно, оформляется на стороне Trakt).',
    'en':
        'Free Trakt account: watchlist up to 250, watched history up to '
        '100,000, ratings up to 10,000. Need more — Trakt VIP (paid, on Trakt\'s '
        'side).',
  },
  'trakt_connect': {'ru': 'Подключить Trakt', 'en': 'Connect Trakt'},
  'trakt_disconnect': {'ru': 'Отключить Trakt', 'en': 'Disconnect Trakt'},
  'trakt_connected': {'ru': 'Trakt подключён', 'en': 'Trakt connected'},
  'trakt_activate': {
    'ru':
        'Открой trakt.tv/activate и введи этот код (нажми, чтобы скопировать):',
    'en': 'Open trakt.tv/activate and enter this code (tap to copy):',
  },
  'trakt_open_activate': {
    'ru': 'Открыть trakt.tv/activate',
    'en': 'Open trakt.tv/activate',
  },
  'trakt_push': {'ru': 'Отправить в Trakt', 'en': 'Push to Trakt'},
  'trakt_pull': {'ru': 'Загрузить из Trakt', 'en': 'Pull from Trakt'},
  'trakt_pushing': {'ru': 'Отправка в Trakt…', 'en': 'Pushing to Trakt…'},
  'trakt_pulling': {'ru': 'Загрузка из Trakt…', 'en': 'Pulling from Trakt…'},
  'trakt_done': {'ru': 'Готово', 'en': 'Done'},
  'trakt_sync_ratings': {'ru': 'Синхронизировать оценки', 'en': 'Sync ratings'},
  'trakt_ratings_note': {
    'ru': 'Kadr главный: твои оценки из Trakt не перезаписываются',
    'en': 'Kadr wins: your ratings are never overwritten from Trakt',
  },
  'trakt_login_failed': {
    'ru': 'Не удалось войти. Попробуй ещё раз.',
    'en': 'Login failed. Please try again.',
  },
  'trakt_error': {
    'ru': 'Ошибка Trakt. Проверь соединение.',
    'en': 'Trakt error. Check your connection.',
  },
  'trakt_powered': {'ru': 'Работает на Trakt', 'en': 'Powered by Trakt'},
  'about_tvdb': {
    'ru': 'Данные о фильмах и сериалах — также TheTVDB (thetvdb.com)',
    'en': 'Movie & TV data also by TheTVDB (thetvdb.com)',
  },
  'undo': {'ru': 'Отменить', 'en': 'Undo'},
  'save': {'ru': 'Сохранить', 'en': 'Save'},
  'delete': {'ru': 'Удалить', 'en': 'Delete'},
  'reset': {'ru': 'Сбросить', 'en': 'Reset'},
  'apply': {'ru': 'Применить', 'en': 'Apply'},
  'done': {'ru': 'Готово', 'en': 'Done'},
  'add': {'ru': 'Добавить', 'en': 'Add'},
  'accept': {'ru': 'Принять', 'en': 'Accept'},
  'decline': {'ru': 'Отклонить', 'en': 'Decline'},
  // ------------------------- Профиль и друзья -------------------------
  'nav_profile': {'ru': 'Профиль', 'en': 'Profile'},
  'profile_about': {'ru': 'О друге', 'en': 'About'},
  'profile_friends': {'ru': 'Друзья', 'en': 'Friends'},
  'profile_join_title': {'ru': 'Друзья в Kadr', 'en': 'Friends on Kadr'},
  'profile_join_sub': {
    'ru':
        'Заведи профиль, добавляй друзей и смотри их просмотры, оценки и списки желаний.',
    'en':
        'Create a profile, add friends and see their watches, ratings and watchlists.',
  },
  'profile_login_cta': {
    'ru': 'Войти или создать профиль',
    'en': 'Sign in or sign up',
  },
  'profile_your_code': {'ru': 'твой код', 'en': 'your code'},
  'profile_code_copied': {'ru': 'Код скопирован', 'en': 'Code copied'},
  'profile_requests': {
    'ru': 'Заявки в друзья · {n}',
    'en': 'Friend requests · {n}',
  },
  'profile_friends_n': {'ru': 'Друзья · {n}', 'en': 'Friends · {n}'},
  'profile_no_friends': {
    'ru': 'Пока никого. Добавь друга по коду.',
    'en': 'No friends yet. Add one by code.',
  },
  'profile_outgoing': {
    'ru': 'Отправленные заявки: {n}',
    'en': 'Sent requests: {n}',
  },
  'profile_edit_name': {'ru': 'Изменить имя', 'en': 'Edit name'},
  'avatar_edit': {'ru': 'Фото профиля', 'en': 'Profile photo'},
  'banner_edit': {'ru': 'Баннер профиля', 'en': 'Profile banner'},
  'banner_change': {'ru': 'Сменить баннер', 'en': 'Change banner'},
  'banner_choose': {'ru': 'Выбрать из галереи', 'en': 'Choose from gallery'},
  'banner_remove': {'ru': 'Убрать баннер', 'en': 'Remove banner'},
  'pick_from_poster': {'ru': 'Из постера фильма', 'en': 'From a movie poster'},
  'pick_from_backdrop': {'ru': 'Из кадра фильма', 'en': 'From a movie still'},
  'pick_media_title_poster': {'ru': 'Постер как фото', 'en': 'Poster as photo'},
  'pick_media_title_backdrop': {
    'ru': 'Кадр как баннер',
    'en': 'Still as banner',
  },
  'pick_media_search': {
    'ru': 'Поиск фильма или сериала',
    'en': 'Search a movie or show',
  },
  'pick_media_hint': {
    'ru': 'Найди фильм или сериал — возьмём его картинку.',
    'en': 'Find a movie or show — we\'ll use its image.',
  },
  'pick_media_empty': {'ru': 'Ничего не нашлось', 'en': 'Nothing found'},
  'pick_media_no_images': {
    'ru': 'Нет доступных кадров',
    'en': 'No images available',
  },
  'cowatch_with_friend': {
    'ru': 'Посмотрел с другом',
    'en': 'Watched with a friend',
  },
  'cowatch_pick_title': {
    'ru': 'С кем смотрели?',
    'en': 'Who did you watch with?',
  },
  'cowatch_with': {'ru': 'С: {names}', 'en': 'With: {names}'},
  'cowatch_change': {'ru': 'Изменить', 'en': 'Change'},
  'cowatch_marked': {
    'ru': 'Отмечено совместно · +{n} друг(а/ей)',
    'en': 'Marked together · +{n} friend(s)',
  },
  'notif_cowatch_title': {
    'ru': 'Совместный просмотр',
    'en': 'Watched together',
  },
  'notif_cowatch_one': {
    'ru': '{name}: вы вместе посмотрели «{title}»',
    'en': '{name}: you watched "{title}" together',
  },
  'notif_cowatch_many': {
    'ru': '{name} и ещё +{n} совместных просмотра',
    'en': '{name} and +{n} more shared views',
  },
  'paste': {'ru': 'Вставить', 'en': 'Paste'},
  'open_link_fail': {
    'ru': 'Не удалось открыть {url}',
    'en': 'Could not open {url}',
  },
  'tmdb_key_title': {'ru': 'Ключ TMDB', 'en': 'TMDB key'},
  'tmdb_key_intro_title': {
    'ru': 'Нужен свой ключ TMDB',
    'en': 'Your own TMDB key is needed',
  },
  'tmdb_key_intro': {
    'ru':
        'Kadr берёт данные о фильмах из TMDB. Ключ бесплатный и личный — '
        'получи свой за пару минут и вставь ниже. Он хранится только на этом устройстве.',
    'en':
        'Kadr gets movie data from TMDB. The key is free and personal — '
        'grab yours in a couple of minutes and paste it below. It stays only on this device.',
  },
  'tmdb_key_step1': {
    'ru': 'Зарегистрируйся на themoviedb.org (бесплатно).',
    'en': 'Sign up at themoviedb.org (free).',
  },
  'tmdb_key_step2': {
    'ru': 'Настройки → API → создай ключ (тип Developer).',
    'en': 'Settings → API → create a key (Developer type).',
  },
  'tmdb_key_step3': {
    'ru': 'Скопируй «API Read Access Token» (длинный, начинается с eyJ…).',
    'en': 'Copy the "API Read Access Token" (long, starts with eyJ…).',
  },
  'tmdb_key_step4': {
    'ru': 'Вставь его в поле ниже и сохрани.',
    'en': 'Paste it into the field below and save.',
  },
  'tmdb_key_form_note': {
    'ru':
        'При создании ключа TMDB попросит заполнить анкету — название '
        'приложения, ссылку на сайт, описание. Вписывай что угодно: TMDB это '
        'не проверяет и ни на что не влияет. Не переживай.',
    'en':
        'When creating the key, TMDB asks you to fill a short form — app '
        'name, website URL, description. Put anything you like: TMDB does not '
        'verify it and it affects nothing. No worries.',
  },
  'tmdb_key_open': {
    'ru': 'Открыть настройки API TMDB',
    'en': 'Open TMDB API settings',
  },
  'tmdb_key_field': {
    'ru': 'TMDB Read Access Token',
    'en': 'TMDB Read Access Token',
  },
  'tmdb_key_hint': {'ru': 'eyJ…', 'en': 'eyJ…'},
  'kinopoisk_key_field': {
    'ru': 'Ключ ПоискКино (необязательно)',
    'en': 'PoiskKino key (optional)',
  },
  'kinopoisk_key_hint': {
    'ru': 'Только если хочешь источник «ПоискКино»',
    'en': 'Only if you want the "PoiskKino" source',
  },
  'tmdb_key_save_go': {
    'ru': 'Сохранить и продолжить',
    'en': 'Save and continue',
  },
  'tmdb_key_empty': {'ru': 'Вставь токен', 'en': 'Paste a token'},
  'tmdb_key_invalid': {
    'ru': 'Токен не подошёл — проверь и вставь снова',
    'en': "Token didn't work — check and paste again",
  },
  'tmdb_key_saved': {'ru': 'Ключ сохранён', 'en': 'Key saved'},
  'tmdb_key_offline': {
    'ru': 'Не удалось проверить (нет сети) — сохранил, поправишь позже',
    'en': "Couldn't verify (offline) — saved, fix later if needed",
  },
  'api_keys_title': {'ru': 'API-ключи (TMDB)', 'en': 'API keys (TMDB)'},
  'api_keys_sub': {
    'ru': 'Свой токен TMDB / PoiskKino',
    'en': 'Your TMDB / PoiskKino key',
  },
  'support_authors': {'ru': 'Поддержать авторов', 'en': 'Support the authors'},
  'support_authors_sub': {
    'ru': 'Boosty — помочь развитию приложения',
    'en': 'Boosty — help the app grow',
  },
  'support_section': {'ru': 'Поддержать', 'en': 'Support'},
  'support_intro': {
    'ru':
        'Kadr — бесплатное приложение с открытым кодом. Любой донат помогает развивать проект.',
    'en':
        'Kadr is a free, open-source app. Any donation helps the project grow.',
  },
  'contact_support': {'ru': 'Связаться с поддержкой', 'en': 'Contact support'},
  'source_code': {'ru': 'Исходный код (GitHub)', 'en': 'Source code (GitHub)'},
  'profile_add_hint': {
    'ru': 'Введи код друга — он покажет его на своём профиле.',
    'en': 'Enter your friend’s code — they can find it on their profile.',
  },
  'profile_friend_code': {'ru': 'Код друга', 'en': 'Friend code'},
  'profile_remove_friend': {'ru': 'Удалить из друзей?', 'en': 'Remove friend?'},
  'profile_remove_q': {
    'ru': 'Убрать {name} из друзей?',
    'en': 'Remove {name} from friends?',
  },
  'profile_logout_q': {
    'ru': 'Выйти из профиля на этом устройстве?',
    'en': 'Sign out on this device?',
  },
  'social_register': {'ru': 'Регистрация', 'en': 'Sign up'},
  'social_login': {'ru': 'Вход', 'en': 'Sign in'},
  'social_intro': {
    'ru':
        'Профиль нужен, чтобы добавлять друзей и видеть их фильмы. Твоя библиотека остаётся на телефоне.',
    'en':
        'A profile lets you add friends and see their films. Your library stays on your phone.',
  },
  'social_name': {'ru': 'Имя', 'en': 'Name'},
  'social_password': {'ru': 'Пароль', 'en': 'Password'},
  'social_logout': {'ru': 'Выйти', 'en': 'Sign out'},
  'social_add_friend': {'ru': 'Добавить друга', 'en': 'Add friend'},
  'social_send_request': {'ru': 'Отправить заявку', 'en': 'Send request'},
  'social_request_sent': {'ru': 'Заявка отправлена', 'en': 'Request sent'},
  'social_now_friends': {
    'ru': 'Теперь вы друзья!',
    'en': 'You are now friends!',
  },
  'social_err_email_taken': {
    'ru': 'Этот email уже занят',
    'en': 'Email already in use',
  },
  'social_err_credentials': {
    'ru': 'Неверный email или пароль',
    'en': 'Wrong email or password',
  },
  'social_err_weak': {
    'ru': 'Пароль не короче 8 символов',
    'en': 'Password must be 8+ characters',
  },
  'social_err_email': {
    'ru': 'Введите корректный email',
    'en': 'Enter a valid email',
  },
  'social_err_name': {'ru': 'Введите имя', 'en': 'Enter a name'},
  'social_err_rate': {
    'ru': 'Слишком много попыток. Попробуйте позже.',
    'en': 'Too many attempts. Try again later.',
  },
  'social_err_user_not_found': {
    'ru': 'Друг по коду не найден',
    'en': 'No user with that code',
  },
  'social_err_network': {
    'ru': 'Нет связи с сервером',
    'en': 'Can’t reach the server',
  },
  'social_err_generic': {
    'ru': 'Что-то пошло не так',
    'en': 'Something went wrong',
  },
  // ------------------------- Код восстановления -------------------------
  'recovery_title': {'ru': 'Код восстановления', 'en': 'Recovery code'},
  'recovery_sub': {'ru': 'Создать новый код', 'en': 'Generate a new code'},
  'recovery_missing': {
    'ru': 'Не задан — создай, чтобы не потерять доступ',
    'en': 'Not set — create one so you don’t lose access',
  },
  'recovery_save_hint': {
    'ru':
        'Сохрани этот код. Он понадобится, чтобы восстановить доступ, если забудешь пароль. Показывается один раз.',
    'en':
        'Save this code. You’ll need it to recover access if you forget your password. Shown once.',
  },
  'recovery_copied': {'ru': 'Код скопирован', 'en': 'Code copied'},
  'recovery_saved': {'ru': 'Я сохранил', 'en': 'I saved it'},
  'recovery_regen_q': {
    'ru': 'Создать новый код? Старый перестанет работать.',
    'en': 'Generate a new code? The old one will stop working.',
  },
  'recovery_regen': {'ru': 'Создать', 'en': 'Generate'},
  'reset_title': {'ru': 'Сброс пароля', 'en': 'Reset password'},
  'reset_hint': {
    'ru': 'Введи email, код восстановления и новый пароль.',
    'en': 'Enter your email, recovery code and a new password.',
  },
  'reset_code': {'ru': 'Код восстановления', 'en': 'Recovery code'},
  'reset_new_password': {'ru': 'Новый пароль', 'en': 'New password'},
  'reset_submit': {'ru': 'Сбросить пароль', 'en': 'Reset password'},
  'reset_forgot': {'ru': 'Забыли пароль?', 'en': 'Forgot password?'},
  'reset_err_code': {
    'ru': 'Введите код восстановления',
    'en': 'Enter the recovery code',
  },
  'reset_err_invalid': {
    'ru': 'Неверный email или код восстановления',
    'en': 'Wrong email or recovery code',
  },
  // ------------------------- Приватность витрины -------------------------
  'privacy_hide_ratings': {
    'ru': 'Скрывать мои оценки',
    'en': 'Hide my ratings',
  },
  'privacy_hide_dates': {
    'ru': 'Скрывать точные даты',
    'en': 'Hide exact dates',
  },
  'privacy_hide_dates_sub': {
    'ru': 'Друзья увидят месяц, но не день',
    'en': 'Friends see the month, not the day',
  },
  // --------------------------- Сравнение вкусов ---------------------------
  'taste_title': {'ru': 'Сравнение вкусов', 'en': 'Taste match'},
  'taste_none': {
    'ru': 'Пока нет общих просмотренных фильмов',
    'en': 'No films you’ve both watched yet',
  },
  'taste_common_n': {'ru': '{n} общих фильмов', 'en': '{n} films in common'},
  'taste_and_more': {'ru': 'и ещё {n}', 'en': 'and {n} more'},
  'taste_you': {'ru': 'Ты', 'en': 'You'},
  'taste_friend': {'ru': 'Друг', 'en': 'Friend'},
  // ------------------------ Уведомления (заявки) ------------------------
  'notif_friend_req_title': {'ru': 'Заявка в друзья', 'en': 'Friend request'},
  'notif_friend_req_one': {
    'ru': '{name} хочет добавить вас в друзья',
    'en': '{name} wants to be your friend',
  },
  'notif_friend_req_many': {
    'ru': '{name} и ещё {n} хотят добавить вас',
    'en': '{name} and {n} more want to add you',
  },
  // --------------------------- Совместные списки ---------------------------
  'sl_section': {'ru': 'Совместные списки', 'en': 'Shared lists'},
  'sl_create': {'ru': 'Совместный список', 'en': 'Shared list'},
  'sl_create_hint': {
    'ru': 'Список, который вы редактируете вместе с друзьями',
    'en': 'A list you and your friends edit together',
  },
  'sl_none': {'ru': 'Пока нет совместных списков', 'en': 'No shared lists yet'},
  'sl_members_n': {'ru': '{n} участн.', 'en': '{n} members'},
  'sl_add_movie': {'ru': 'Добавить фильм', 'en': 'Add film'},
  'sl_search_hint': {'ru': 'Поиск фильма…', 'en': 'Search a film…'},
  'sl_empty': {'ru': 'В списке пока пусто', 'en': 'List is empty'},
  'sl_invite': {'ru': 'Пригласить друга', 'en': 'Invite friend'},
  'sl_rename': {'ru': 'Переименовать', 'en': 'Rename'},
  'sl_delete': {'ru': 'Удалить список', 'en': 'Delete list'},
  'sl_leave': {'ru': 'Выйти из списка', 'en': 'Leave list'},
  'sl_delete_q': {
    'ru': 'Удалить список у всех участников?',
    'en': 'Delete the list for everyone?',
  },
  'sl_leave_q': {'ru': 'Выйти из этого списка?', 'en': 'Leave this list?'},
  'sl_no_friends_to_invite': {
    'ru': 'Все друзья уже в списке',
    'en': 'All friends are already in',
  },
  'sl_add_to_watchlist': {'ru': 'В «Буду смотреть»', 'en': 'Add to watchlist'},
  'sl_added_to_watchlist': {
    'ru': 'Добавлено в «Буду смотреть»',
    'en': 'Added to watchlist',
  },
  'sl_remove_item': {'ru': 'Убрать из списка', 'en': 'Remove from list'},
  // ---------------------------- Активность друзей ----------------------------
  'activity_title': {'ru': 'Активность друзей', 'en': 'Friends activity'},
  'activity_recent': {'ru': 'Недавно у друзей', 'en': 'Recent from friends'},
  'activity_recs': {'ru': 'Советуют друзья', 'en': 'Friends recommend'},
  'activity_recs_sub': {
    'ru': 'Высоко оценили то, что ты ещё не смотрел',
    'en': 'Highly rated by friends, not watched by you',
  },
  'activity_empty': {
    'ru': 'У друзей пока нет активности. Добавь друзей в профиле.',
    'en': 'No friend activity yet. Add friends in your profile.',
  },
  'activity_login': {
    'ru': 'Войди в профиль, чтобы видеть активность друзей',
    'en': 'Sign in to see friends activity',
  },
  'activity_watched': {'ru': 'посмотрел', 'en': 'watched'},
  'activity_wishlisted': {'ru': 'хочет посмотреть', 'en': 'wants to watch'},
  'activity_series': {'ru': 'смотрит сериал', 'en': 'is watching'},
  // --------------------------- Посмотреть вместе ---------------------------
  'together_title': {'ru': 'Посмотреть вместе', 'en': 'Watch together'},
  'together_n': {
    'ru': 'Вы оба хотите посмотреть — {n}',
    'en': 'You both want to watch — {n}',
  },
  // ---------------------------- «Советую тебе» ----------------------------
  'recommend_to_friend': {
    'ru': 'Советовать другу',
    'en': 'Recommend to friend',
  },
  'recommend_title': {'ru': 'Советую «{title}»', 'en': 'Recommend “{title}”'},
  'recommend_note_hint': {
    'ru': 'Заметка (необязательно)',
    'en': 'Note (optional)',
  },
  'recommend_pick_friend': {
    'ru': 'Кому советуешь?',
    'en': 'Recommend to whom?',
  },
  'recommend_sent': {'ru': 'Отправлено {name}', 'en': 'Sent to {name}'},
  'rec_for_you': {'ru': 'Тебе советуют', 'en': 'Recommended to you'},
  'rec_from': {'ru': 'советует {name}', 'en': '{name} recommends'},
  'notif_rec_title': {'ru': 'Тебе советуют фильм', 'en': 'A film for you'},
  'notif_rec_one': {
    'ru': '{name} советует «{title}»',
    'en': '{name} recommends “{title}”',
  },
  'notif_rec_many': {
    'ru': '{name} и ещё {n} советуют тебе фильмы',
    'en': '{name} and {n} more recommend films',
  },
  // ------------------------------ Кинорулетка ------------------------------
  'roulette_title': {'ru': 'Кинорулетка', 'en': 'Movie roulette'},
  'roulette_spin': {'ru': 'Крутить!', 'en': 'Spin!'},
  'roulette_spinning': {'ru': 'Крутим…', 'en': 'Spinning…'},
  'roulette_open': {'ru': 'Открыть фильм', 'en': 'Open film'},
  'roulette_src_watchlist': {'ru': 'Мой вишлист', 'en': 'My watchlist'},
  'roulette_src_friends': {'ru': 'Советы друзей', 'en': 'Friends’ picks'},
  'roulette_empty_watchlist': {
    'ru': 'В «Буду смотреть» пусто — добавь фильмы',
    'en': 'Your watchlist is empty — add some films',
  },
  'roulette_empty_friends': {
    'ru': 'Друзья пока ничего не советуют',
    'en': 'No picks from friends yet',
  },
  // -------------------------- Похоже на твой вкус --------------------------
  'for_you_title': {'ru': 'Похоже на твой вкус', 'en': 'Your taste'},
  'for_you_sub': {
    'ru': 'Собрано из фильмов, которые ты оценил высоко',
    'en': 'Built from films you rated highly',
  },
  'for_you_empty': {'ru': 'Нет рекомендаций', 'en': 'No recommendations'},
  'for_you_no_seeds': {
    'ru': 'Оцени несколько фильмов на 7+, и здесь появятся рекомендации',
    'en': 'Rate a few films 7+ and recommendations will appear here',
  },
  'select_all': {'ru': 'Выбрать все', 'en': 'Select all'},
  'n_selected': {'ru': 'Выбрано: {n}', 'en': '{n} selected'},
  'delete_selected_title': {
    'ru': 'Удалить выбранное?',
    'en': 'Delete selected?',
  },
  'delete_selected_watched': {
    'ru':
        'Отметки о просмотре ({n}) будут убраны. Сами фильмы и сериалы останутся в базе.',
    'en': 'Watch records ({n}) will be removed. Titles stay in the database.',
  },
  'delete_selected_watchlist': {
    'ru':
        'Выбранное ({n}) уберётся из «Буду смотреть». Из базы фильмы не удаляются.',
    'en':
        'Selected ({n}) will be removed from the watchlist. Titles stay in the database.',
  },
  'removed_n': {'ru': 'Убрано: {n}', 'en': 'Removed: {n}'},
  'mark_watched_selected': {
    'ru': 'Отметить просмотренными',
    'en': 'Mark as watched',
  },
  'add_to_list_selected': {'ru': 'Добавить в список', 'en': 'Add to list'},
  'batch_marked_watched': {
    'ru': 'Отмечено просмотренными: {n}',
    'en': 'Marked as watched: {n}',
  },
  'batch_added_to_list': {
    'ru': 'Добавлено в «{name}»: {n}',
    'en': 'Added to "{name}": {n}',
  },
  'batch_no_movies': {
    'ru': 'В выделении нет фильмов',
    'en': 'No movies in selection',
  },
  'on': {'ru': 'Вкл', 'en': 'On'},
  'off': {'ru': 'Выкл', 'en': 'Off'},
  'soon': {'ru': 'Скоро', 'en': 'Coming soon'},
  'next': {'ru': 'Далее', 'en': 'Next'},
  'start': {'ru': 'Начать', 'en': 'Get started'},
  'skip': {'ru': 'Пропустить', 'en': 'Skip'},
  'ob1_title': {'ru': 'Твоё кино', 'en': 'Your cinema'},
  'ob1_sub': {
    'ru': 'Веди коллекцию просмотренных фильмов и сериалов — красиво и удобно.',
    'en': 'Track the movies and series you\'ve watched — beautifully.',
  },
  'ob2_title': {'ru': 'Оценивай просмотры', 'en': 'Rate every watch'},
  'ob2_sub': {
    'ru':
        'У каждого просмотра своя оценка 1.0–10.0 — мнение меняется при пересмотре.',
    'en':
        'Each viewing has its own 1.0–10.0 rating — opinions change on rewatch.',
  },
  'ob3_title': {'ru': 'Русский и постеры', 'en': 'Russian & posters'},
  'ob3_sub': {
    'ru': 'Названия и обложки подтягиваются автоматически из TMDB и ПоискКино.',
    'en': 'Titles and posters are fetched automatically from TMDB.',
  },
  'ob4_title': {'ru': 'Статистика и списки', 'en': 'Stats & lists'},
  'ob4_sub': {
    'ru': 'Смотри статистику, собирай свои списки и переноси всё бэкапом.',
    'en': 'See your stats, build lists and back everything up.',
  },
  'soon_sub': {
    'ru': 'Этот раздел ещё в разработке',
    'en': 'This section is under construction',
  },

  // ---------------------------- Навигация ----------------------------
  'nav_watchlist': {'ru': 'Буду смотреть', 'en': 'Watchlist'},
  'nav_watched': {'ru': 'Просмотрено', 'en': 'Watched'},
  'nav_discover': {'ru': 'Обзор', 'en': 'Discover'},
  'disc_for_you': {'ru': 'Для вас', 'en': 'For you'},
  'nav_cinema': {'ru': 'В кино', 'en': 'In theaters'},
  'discover_error': {'ru': 'Не удалось загрузить', 'en': 'Failed to load'},
  'retry': {'ru': 'Повторить', 'en': 'Retry'},
  'added_to_watchlist': {
    'ru': 'Добавлено в «Буду смотреть»',
    'en': 'Added to watchlist',
  },
  'added_to_watched': {
    'ru': 'Отмечено просмотренным',
    'en': 'Marked as watched',
  },
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
  'stat_days_watching': {
    'ru': '≈ {n} дн. у экрана',
    'en': '≈ {n} days on screen',
  },
  'stat_summary_sub': {
    'ru': '{f} фильмов · {s} сериалов · {e} серий',
    'en': '{f} movies · {s} series · {e} episodes',
  },
  'stat_by_month': {'ru': 'По месяцам', 'en': 'By month'},
  'stat_by_weekday': {'ru': 'По дням недели', 'en': 'By weekday'},
  'stat_by_decade': {'ru': 'Годы выхода', 'en': 'Release years'},
  'stat_split': {'ru': 'Фильмы и сериалы', 'en': 'Movies & series'},
  'stat_vs_kp': {'ru': 'Ты и ПоискКино', 'en': 'You vs PoiskKino'},
  'stat_vs_kp_higher': {
    'ru': 'Ты оцениваешь выше КП на {d}',
    'en': "You rate higher than KP by {d}",
  },
  'stat_vs_kp_lower': {
    'ru': 'Ты оцениваешь ниже КП на {d}',
    'en': 'You rate lower than KP by {d}',
  },
  'stat_vs_kp_same': {
    'ru': 'Твои оценки почти как у КП',
    'en': 'Your ratings match KP',
  },
  'stat_vs_kp_sub': {
    'ru': 'по {n} фильмам с рейтингом КП',
    'en': 'across {n} films rated on KP',
  },
  'stat_records': {'ru': 'Рекорды', 'en': 'Records'},
  'stat_most_active_day': {
    'ru': 'Самый активный день',
    'en': 'Most active day',
  },
  'stat_first_mark': {'ru': 'Первая отметка', 'en': 'First entry'},
  'stat_days_tracked': {'ru': 'Дней в трекере', 'en': 'Days tracked'},
  'stat_avg_runtime': {
    'ru': 'Средняя длина фильма',
    'en': 'Average movie length',
  },
  'stat_longest': {'ru': 'Самый длинный', 'en': 'Longest'},
  'stat_highest': {'ru': 'Высшая оценка', 'en': 'Highest rating'},
  'stat_lowest': {'ru': 'Низшая оценка', 'en': 'Lowest rating'},
  'stat_most_rewatched': {
    'ru': 'Чаще всего пересматриваешь',
    'en': 'Most rewatched',
  },
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
    'ru':
        'Данные о фильмах — TMDB и ПоискКино. Продукт использует API TMDB, но не одобрен и не сертифицирован TMDB.',
    'en':
        'Movie data by TMDB and PoiskKino. This product uses the TMDB API but is not endorsed or certified by TMDB.',
  },
  'search_hint': {'ru': 'Фильмы и сериалы…', 'en': 'Movies and series…'},
  'search_all_hint': {
    'ru': 'Поиск по всей базе фильмов…',
    'en': 'Search the whole movie database…',
  },

  // ---------------------------- Настройки ----------------------------
  'settings_title': {'ru': 'Настройки', 'en': 'Settings'},
  'appearance': {'ru': 'Внешний вид', 'en': 'Appearance'},
  'general': {'ru': 'Общее', 'en': 'General'},
  'start_screen': {'ru': 'Экран при запуске', 'en': 'Start screen'},
  'fab_position': {'ru': 'Кнопка «+»', 'en': 'The + button'},
  'fab_center': {'ru': 'По центру', 'en': 'Center'},
  'fab_left': {'ru': 'Слева', 'en': 'Left'},
  'fab_right': {'ru': 'Справа', 'en': 'Right'},
  'date_format': {'ru': 'Формат даты', 'en': 'Date format'},
  'date_format_long': {
    'ru': 'Как «24 июня 2026»',
    'en': 'Like “June 24, 2026”',
  },
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
    'en': 'Color from system wallpaper (Android 12+)',
  },
  'amoled': {'ru': 'AMOLED-чёрный', 'en': 'AMOLED black'},
  'amoled_sub': {
    'ru': 'Чистый чёрный фон в тёмной теме',
    'en': 'Pure black background in dark theme',
  },
  'theme_presets': {'ru': 'Палитры', 'en': 'Palettes'},
  'theme_color': {'ru': 'Цвет оформления', 'en': 'Theme color'},
  'theme_color_custom': {'ru': 'Свой цвет', 'en': 'Custom color'},
  'theme_intensity': {'ru': 'Насыщенность', 'en': 'Intensity'},
  'theme_vibrant': {'ru': 'Сочно', 'en': 'Vivid'},
  'theme_faithful': {'ru': 'Точь-в-точь', 'en': 'Exact'},
  'movies_section': {'ru': 'Фильмы', 'en': 'Movies'},
  'movie_source': {'ru': 'Источник поиска', 'en': 'Search source'},
  'movie_source_sub': {
    'ru': 'Откуда брать названия, постеры и данные',
    'en': 'Where to get titles, posters and data',
  },
  'data': {'ru': 'Данные', 'en': 'Data'},
  'sync_backup': {'ru': 'Синхронизация и бэкап', 'en': 'Sync & backup'},
  'sync_backup_sub': {
    'ru': 'Резервные копии и перенос между устройствами',
    'en': 'Backups and transfer between devices',
  },
  'create_backup': {'ru': 'Создать резервную копию', 'en': 'Create backup'},
  'create_backup_sub': {
    'ru': 'Поделиться файлом (Telegram, Диск, …)',
    'en': 'Share a file (Telegram, Drive, …)',
  },
  'restore_backup': {'ru': 'Восстановить из копии', 'en': 'Restore backup'},
  'restore_backup_sub': {
    'ru': 'Выбрать JSON-файл резервной копии',
    'en': 'Pick a backup JSON file',
  },
  'backup_hint': {
    'ru':
        'Перенос на новый телефон: создайте копию здесь и восстановите её на новом устройстве.',
    'en':
        'Moving to a new phone: create a backup here and restore it on the new device.',
  },
  'backup_import_ok': {
    'ru': 'Библиотека восстановлена',
    'en': 'Library restored',
  },
  'backup_import_fail': {
    'ru': 'Не удалось прочитать файл',
    'en': 'Could not read file',
  },
  'clear_all_data': {'ru': 'Очистить все данные', 'en': 'Clear all data'},
  'clear_all_data_sub': {
    'ru': 'Удалить все просмотры, списки, оценки и сериалы',
    'en': 'Delete all watches, lists, ratings and series',
  },
  'clear_image_cache': {
    'ru': 'Очистить кэш изображений',
    'en': 'Clear image cache',
  },
  'clear_image_cache_sub': {
    'ru': 'Постеры и картинки перекачаются заново',
    'en': 'Posters and images will re-download',
  },
  'cache_cleared': {
    'ru': 'Кэш изображений очищен',
    'en': 'Image cache cleared',
  },
  'clear_all_title': {'ru': 'Очистить все данные?', 'en': 'Clear all data?'},
  'clear_all_body': {
    'ru':
        'Все просмотры, оценки, списки, избранное и сериалы будут удалены безвозвратно. Останутся только ленты «Обзор» и «В кино». Сделайте бэкап заранее, если нужно сохранить.',
    'en':
        'All watches, ratings, lists, favorites and series will be deleted permanently. Only the Discover and In theaters feeds remain. Make a backup first if you want to keep the data.',
  },
  'clear_all_done': {'ru': 'Все данные очищены', 'en': 'All data cleared'},
  'clear': {'ru': 'Очистить', 'en': 'Clear'},
  'about': {'ru': 'О приложении', 'en': 'About'},
  'about_sub': {
    'ru': 'Трекер просмотренных фильмов и сериалов',
    'en': 'Watched movies and series tracker',
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
  'when_watched_q': {
    'ru': 'Когда вы его посмотрели?',
    'en': 'When did you watch it?',
  },
  'when_unknown': {'ru': 'Неизвестная дата', 'en': 'Unknown date'},
  'when_just_finished': {'ru': 'Только что завершил', 'en': 'Just finished'},
  'when_pick_date': {'ru': 'Выберите дату', 'en': 'Pick a date'},

  // -------------------------- Библиотека --------------------------
  'your_rating': {'ru': 'Ваша оценка', 'en': 'Your rating'},
  'rate_it': {'ru': 'Оцените фильм', 'en': 'Rate this movie'},
  'not_rated': {'ru': 'Без оценки', 'en': 'Not rated'},
  'viewings_n': {'ru': 'Просмотров: {n}', 'en': 'Viewings: {n}'},
  'watched_month': {
    'ru': 'Просмотры {month} {year} г.',
    'en': 'Watched · {month} {year}',
  },
  'watched_date': {'ru': 'Дата просмотра: {date}', 'en': 'Watched on {date}'},
  'lib_empty_watched': {
    'ru': 'Пока нет просмотренных фильмов',
    'en': 'No watched movies yet',
  },
  'lib_empty_watchlist': {
    'ru': 'Список «Буду смотреть» пуст',
    'en': 'Your watchlist is empty',
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
  'no_episodes': {
    'ru': 'Не удалось загрузить серии',
    'en': 'Could not load episodes',
  },
  'link_hint': {
    'ru':
        'Сериал мог сохраниться другим названием (напр. латиницей). Найдите его в базе вручную — отметки серий сохранятся.',
    'en':
        'The series may be saved under another title. Find it manually — your episode marks are kept.',
  },
  'link_find': {'ru': 'Найти в TMDB', 'en': 'Find on TMDB'},
  'link_hint_field': {
    'ru': 'Название сериала (кириллицей)',
    'en': 'Series name',
  },
  'now_watching': {'ru': 'Сейчас смотрю', 'en': 'Now watching'},
  'now_watching_empty': {
    'ru': 'Начните смотреть сериал — он появится здесь',
    'en': 'Start a series — it will show up here',
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
    'en': 'No internet connection',
  },
  'load_more': {'ru': 'Загрузить ещё', 'en': 'Load more'},
  'rate_after_watch': {
    'ru': 'Посмотрите фильм, чтобы его оценить',
    'en': 'Watch the movie to rate it',
  },
  'copied': {'ru': 'Скопировано', 'en': 'Copied'},
  'view_poster': {'ru': 'Открыть постер', 'en': 'Open poster'},
  'rewatch': {'ru': 'Повтор', 'en': 'Rewatch'},
  'rewatch_full': {'ru': 'Повторный просмотр', 'en': 'Rewatched'},
  'rewatches_n': {'ru': 'Повторов: {n}', 'en': 'Rewatches: {n}'},
  'mark_watched': {'ru': 'Отметить просмотр', 'en': 'Log a watch'},
  'add_watchlist': {'ru': 'Буду смотреть', 'en': 'Watchlist'},
  'in_watchlist': {'ru': 'В списке', 'en': 'In watchlist'},
  'kp_rating': {'ru': 'ПоискКино', 'en': 'PoiskKino'},

  // ---------------------- Когда посмотрели ----------------------
  'when_today': {'ru': 'Сегодня', 'en': 'Today'},
  'when_yesterday': {'ru': 'Вчера', 'en': 'Yesterday'},
  'when_now': {'ru': 'Только что', 'en': 'Just now'},
  'viewing_added': {
    'ru': 'Отмечено как просмотрено',
    'en': 'Marked as watched',
  },
  'rewatch_added': {
    'ru': 'Добавлен повторный просмотр',
    'en': 'Rewatch logged',
  },

  // ------------------- Оценки по просмотрам -------------------
  'overall_score': {'ru': 'Общая оценка', 'en': 'Overall rating'},
  'current_viewing_score': {
    'ru': 'Оценка текущего просмотра',
    'en': 'Current viewing rating',
  },
  'per_viewing_scores': {
    'ru': 'Оценки по просмотрам',
    'en': 'Ratings per viewing',
  },
  'score_comparison': {
    'ru': 'Как менялась оценка',
    'en': 'How your rating changed',
  },
  'rate_this_viewing': {'ru': 'Оценка просмотра', 'en': 'Rate this viewing'},
  'remove_score': {'ru': 'Убрать оценку', 'en': 'Clear rating'},
  'cmp_improved': {
    'ru': 'Мнение улучшилось на {d}',
    'en': 'Opinion improved by {d}',
  },
  'cmp_dropped': {
    'ru': 'Мнение ухудшилось на {d}',
    'en': 'Opinion dropped by {d}',
  },
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
    'en': 'Rated {n} episodes · {v}',
  },
  'season_no_watched': {
    'ru': 'В сезоне нет просмотренных серий для оценки',
    'en': 'No watched episodes in this season to rate',
  },
  'season_date': {'ru': 'Дата просмотра сезона', 'en': 'Season watch date'},
  'season_dated': {
    'ru': 'Дата задана для {n} серий',
    'en': 'Date set for {n} episodes',
  },
  'season_dates_replace_title': {
    'ru': 'Заменить даты серий?',
    'en': 'Replace episode dates?',
  },
  'season_dates_replace_body': {
    'ru':
        'У серий сезона проставлены разные даты ({n} дней просмотра). Они будут заменены одной. Продолжить?',
    'en':
        'Season episodes have different dates ({n} watch days). They will be collapsed into one. Continue?',
  },
  'replace': {'ru': 'Заменить', 'en': 'Replace'},
  'season_done_undated': {
    'ru': 'Сезон {n} отмечен без даты — не попадает в ленту «Просмотрено»',
    'en': "Season {n} marked without a date — won't appear in the Watched feed",
  },
  'restrict_unaired': {
    'ru': 'Запрет невышедших серий',
    'en': 'Block unaired episodes',
  },
  'restrict_unaired_sub': {
    'ru': 'Нельзя отметить/оценить серию, которая ещё не вышла',
    'en': "Can't mark or rate an episode that hasn't aired yet",
  },
  'episode_not_aired': {
    'ru': 'Серия ещё не вышла',
    'en': "Episode hasn't aired yet",
  },
  'not_aired_badge': {'ru': 'скоро', 'en': 'soon'},
  'series_avg_locked': {
    'ru':
        'Оценка считается по оценкам серий. Уберите оценки серий, чтобы поставить вручную.',
    'en':
        'Rating is the episode average. Clear episode ratings to set it manually.',
  },
  'mark_season': {'ru': 'Отметить весь сезон', 'en': 'Mark whole season'},
  'unmark_season': {'ru': 'Снять весь сезон', 'en': 'Unmark whole season'},
  'season_done': {'ru': 'Сезон {n} отмечен', 'en': 'Season {n} marked'},
  'watch_again': {'ru': 'Смотрел ещё раз', 'en': 'Watched again'},
  'season_mark_when': {
    'ru': 'Когда вы посмотрели сезон {n}?',
    'en': 'When did you watch season {n}?',
  },
  'season_mark_sub': {
    'ru': 'Отметить все {n} серий сезона',
    'en': 'Mark all {n} episodes of the season',
  },
  'season_all_watched': {
    'ru': 'Все вышедшие серии сезона уже отмечены',
    'en': 'All aired episodes of the season are already marked',
  },
  'season_rewatch_title': {
    'ru': 'Отметить весь сезон {n} ещё раз?',
    'en': 'Mark whole season {n} watched again?',
  },
  'season_rewatch_sub': {
    'ru': 'Повторный просмотр всех {n} серий сезона',
    'en': 'Rewatch all {n} episodes of the season',
  },
  'season_rewatched': {
    'ru': 'Сезон отмечен ещё раз ({c} серий)',
    'en': 'Season marked again ({c} episodes)',
  },
  'episode_mark_when': {
    'ru': 'Когда вы посмотрели серию?',
    'en': 'When did you watch this episode?',
  },
  'share': {'ru': 'Поделиться', 'en': 'Share'},
  'share_want_to_watch': {'ru': 'Хочу посмотреть', 'en': 'Want to watch'},
  'delete_from_base': {'ru': 'Удалить из базы', 'en': 'Delete from library'},
  'delete_from_base_confirm': {
    'ru':
        '«{title}» и вся история просмотров, оценки и даты по нему будут удалены НАВСЕГДА. Вернуть можно только сразу — кнопкой «Отменить». После этого восстановить уже не получится.',
    'en':
        '"{title}" and its entire watch history, ratings and dates will be deleted PERMANENTLY. The only way back is the "Undo" button right after — after that it cannot be restored.',
  },
  'deleted_from_base': {'ru': 'Удалено из базы', 'en': 'Deleted from library'},
  'delete_from_base_n': {
    'ru':
        'Выбранное ({n}) и вся история просмотров, оценки и даты по нему будут удалены НАВСЕГДА. Вернуть можно только сразу — кнопкой «Отменить». После этого восстановить уже не получится.',
    'en':
        'The selected ({n}) and their entire watch history, ratings and dates will be deleted PERMANENTLY. The only way back is the "Undo" button right after — after that it cannot be restored.',
  },
  'deleted_n_from_base': {
    'ru': 'Удалено из базы: {n}',
    'en': 'Deleted from library: {n}',
  },
  'import_tracker': {
    'ru': 'Импорт из трекера (CSV)',
    'en': 'Import from tracker (CSV)',
  },
  'import_tracker_sub': {
    'ru': 'Letterboxd, IMDb и другие — файл .csv',
    'en': 'Letterboxd, IMDb and others — .csv file',
  },
  'import_tracker_ok': {
    'ru': 'Импортировано: +{a}, обновлено {u}',
    'en': 'Imported: +{a}, updated {u}',
  },
  'import_tracker_fail': {
    'ru': 'Не удалось прочитать файл',
    'en': 'Could not read the file',
  },
  'wrapped_title': {'ru': 'Кинокод года', 'en': 'Year in review'},
  'wrapped_open': {'ru': 'Кинокод {year}', 'en': 'Year in review {year}'},
  'wrapped_open_sub': {
    'ru': 'Твой год в кино — красиво и можно поделиться',
    'en': 'Your movie year — shareable recap',
  },
  'wrapped_empty': {
    'ru': 'За этот год ещё нет отметок',
    'en': 'Nothing marked this year yet',
  },
  'wrapped_watched': {
    'ru': '{m} фильмов · {e} серий',
    'en': '{m} movies · {e} episodes',
  },
  'wrapped_more': {
    'ru': 'На {n} больше, чем годом ранее',
    'en': '{n} more than last year',
  },
  'wrapped_less': {
    'ru': 'На {n} меньше, чем годом ранее',
    'en': '{n} fewer than last year',
  },
  'wrapped_hours': {'ru': 'часов у экрана', 'en': 'hours watched'},
  'wrapped_avg': {'ru': 'средняя оценка', 'en': 'average score'},
  'wrapped_busiest': {'ru': 'Самый активный месяц', 'en': 'Busiest month'},
  'wrapped_top_genres': {'ru': 'Топ жанры года', 'en': 'Top genres'},
  'wrapped_mood': {'ru': 'Эмоция года', 'en': 'Mood of the year'},
  'wrapped_movie': {'ru': 'Фильм года', 'en': 'Movie of the year'},
  'wrapped_series': {'ru': 'Сериал года', 'en': 'Series of the year'},
  'stat_ratings_by_year': {
    'ru': 'Оценки по годам выхода',
    'en': 'Ratings by release year',
  },
  'stat_my_ratings_by_year': {
    'ru': 'Мои оценки по годам просмотра',
    'en': 'My ratings by year watched',
  },
  'stat_wy_best': {
    'ru': 'Щедрее всего оценивали в {y} ({s})',
    'en': 'Most generous in {y} ({s})',
  },
  'stat_wy_worst': {
    'ru': 'Строже всего — в {y} ({s})',
    'en': 'Harshest in {y} ({s})',
  },
  'stat_wy_trend_up': {
    'ru': 'Со временем вы оцениваете кино добрее — средний балл растёт.',
    'en': 'Over time you rate films more kindly — your average is rising.',
  },
  'stat_wy_trend_down': {
    'ru': 'Со временем вы оцениваете строже — средний балл снижается.',
    'en': 'Over time you rate more harshly — your average is dropping.',
  },
  'stat_wy_trend_flat': {
    'ru': 'Ваши оценки стабильны из года в год — вкус устоялся.',
    'en': 'Your ratings are steady year to year — a settled taste.',
  },
  'stat_ry_best': {
    'ru': 'Выше всех — фильмы {y} года ({s})',
    'en': 'Highest — {y} films ({s})',
  },
  'stat_ry_worst': {
    'ru': 'Ниже всех — {y} года ({s})',
    'en': 'Lowest — {y} ({s})',
  },
  'stat_ry_trend_up': {
    'ru':
        'Чем новее фильм — тем выше вы его оцениваете. Современное кино заходит вам больше классики.',
    'en':
        'The newer the film, the higher you rate it — modern cinema wins over classics for you.',
  },
  'stat_ry_trend_down': {
    'ru':
        'Чем новее фильм — тем ниже оценка. Классику вы цените заметно выше нового кино.',
    'en':
        'The newer the film, the lower the score — you value the classics over modern films.',
  },
  'stat_ry_trend_flat': {
    'ru':
        'Старое и новое кино вы оцениваете примерно одинаково — год выхода на оценку почти не влияет.',
    'en':
        'You rate old and new films about the same — release year barely affects your score.',
  },
  'watched_movies': {'ru': 'Просмотренные фильмы', 'en': 'Watched movies'},
  'watched_series': {'ru': 'Просмотренные сериалы', 'en': 'Watched series'},
  'auto_backup': {'ru': 'Автобекап', 'en': 'Auto backup'},
  'auto_backup_sub': {
    'ru': 'Локальные копии в выбранную папку',
    'en': 'Local copies to a chosen folder',
  },
  'auto_backup_hint': {
    'ru':
        'Приложение само сохраняет копию библиотеки в выбранную папку. Копии переживают удаление приложения — это защита от потери данных. Хранятся последние 20 копий.',
    'en':
        'The app saves a copy of your library to the chosen folder. Copies survive uninstall — a safety net. Last 20 copies are kept.',
  },
  'auto_backup_enable': {
    'ru': 'Включить автобекап',
    'en': 'Enable auto backup',
  },
  'auto_backup_folder': {'ru': 'Папка', 'en': 'Folder'},
  'auto_backup_no_folder': {'ru': 'Не выбрана', 'en': 'Not selected'},
  'auto_backup_need_folder': {
    'ru': 'Сначала выберите папку и выдайте доступ',
    'en': 'Choose a folder and grant access first',
  },
  'auto_backup_not_writable': {
    'ru': 'В эту папку нельзя писать — выберите другую',
    'en': 'This folder is not writable — pick another',
  },
  'auto_backup_when': {'ru': 'Когда сохранять', 'en': 'When to save'},
  'auto_backup_on_change': {'ru': 'При изменениях', 'en': 'On changes'},
  'auto_backup_on_change_sub': {
    'ru': 'Через полминуты после правок, не чаще раза в 10 минут',
    'en': 'Half a minute after edits, at most once per 10 minutes',
  },
  'auto_backup_daily': {'ru': 'Раз в день', 'en': 'Once a day'},
  'auto_backup_daily_sub': {
    'ru': 'Проверяется при запуске приложения',
    'en': 'Checked on app launch',
  },
  'auto_backup_now': {'ru': 'Создать копию сейчас', 'en': 'Back up now'},
  'auto_backup_done': {'ru': 'Копия сохранена', 'en': 'Backup saved'},
  'auto_backup_failed': {
    'ru': 'Не удалось сохранить копию',
    'en': 'Backup failed',
  },
  'auto_backup_never': {'ru': 'Копий ещё не было', 'en': 'No backups yet'},
  'auto_backup_last': {
    'ru': 'Последняя копия: {when}',
    'en': 'Last backup: {when}',
  },
  'restore_title': {
    'ru': 'Восстановить из копии',
    'en': 'Restore from a backup',
  },
  'restore_hint': {
    'ru': 'Выбери копию из папки — данные вернутся в приложение.',
    'en': 'Pick a backup from the folder to bring your data back.',
  },
  'restore_none': {
    'ru': 'В папке нет копий',
    'en': 'No backups in this folder',
  },
  'restore_btn': {'ru': 'Восстановить', 'en': 'Restore'},
  'restore_confirm_title': {'ru': 'Восстановить?', 'en': 'Restore?'},
  'restore_confirm_body': {
    'ru': 'Данные из копии от {when} будут добавлены в библиотеку.',
    'en': 'Data from the {when} backup will be added to your library.',
  },
  'restore_done': {
    'ru': 'Восстановлено из копии',
    'en': 'Restored from backup',
  },
  'restore_done_n': {
    'ru': 'Восстановлено • {n} фильмов',
    'en': 'Restored • {n} movies',
  },
  'restore_failed': {
    'ru': 'Не удалось восстановить копию',
    'en': "Couldn't restore the backup",
  },
  'restore_found_title': {'ru': 'Найдены копии', 'en': 'Backups found'},
  'restore_found_body': {
    'ru': 'В папке {n} копий. Восстановить последнюю (от {when})?',
    'en': 'This folder has {n} backups. Restore the latest ({when})?',
  },
  'choose': {'ru': 'Выбрать', 'en': 'Choose'},
  'mark_finished': {'ru': 'Досмотрел сериал', 'en': 'Finished the series'},
  'finished_removed': {
    'ru': 'Убрано из «Сейчас смотрю»',
    'en': 'Removed from Now Watching',
  },
  'now_watching_hint': {
    'ru': 'Удержание — «Досмотрел»',
    'en': 'Long-press to mark finished',
  },
  'episode_rewatch_when': {
    'ru': 'Когда вы пересмотрели серию?',
    'en': 'When did you rewatch this episode?',
  },
  'season_clear_all': {'ru': 'Снять все просмотры', 'en': 'Remove all watches'},
  'season_cleared': {
    'ru': 'Просмотры сезона сняты',
    'en': 'Season watches removed',
  },
  'extra_episodes_removed': {
    'ru': 'Убрано лишних серий: {n}',
    'en': 'Removed {n} extra episodes',
  },
  'ep_watched_n': {'ru': 'Просмотров: {n}', 'en': 'Watches: {n}'},
  'rewatch_removed': {'ru': 'Повтор убран', 'en': 'Rewatch removed'},
  'season_progress': {'ru': 'Сезон {s}: {n}/{m}', 'en': 'Season {s}: {n}/{m}'},
  'episode': {'ru': 'Серия', 'en': 'Episode'},
  'rate_short': {'ru': 'Оценить', 'en': 'Rate'},
  'episode_score': {'ru': 'Оценка серии', 'en': 'Episode rating'},
  'rate_after_watch_ep': {
    'ru': 'Отметьте просмотр серии, чтобы её оценить',
    'en': 'Mark the episode watched to rate it',
  },
  'clear_all_checks': {'ru': 'Снять просмотр', 'en': 'Unmark watched'},
  'reset_to_one': {'ru': 'Вернуть один просмотр', 'en': 'Keep a single watch'},
  'remove_one_watch': {'ru': 'Убрать просмотр', 'en': 'Remove one watch'},
  'edit_watch_date': {
    'ru': 'Изменить дату и время',
    'en': 'Change date & time',
  },
  'set_unknown_date': {'ru': 'Дата: неизвестно', 'en': 'Date: unknown'},
  'marked_unknown': {
    'ru': 'Отмечено без даты («Неизвестно»)',
    'en': 'Marked without a date (“Unknown”)',
  },
  'enter_score': {'ru': 'Введите оценку', 'en': 'Enter your score'},
  'collection': {'ru': 'Части франшизы', 'en': 'Franchise'},
  'search_local_empty': {
    'ru': 'В вашей библиотеке ничего не найдено по «{q}».',
    'en': 'Nothing in your library for “{q}”.',
  },
  'search_all_db': {
    'ru': 'Искать по всей базе',
    'en': 'Search the whole database',
  },
  'edit': {'ru': 'Изменить', 'en': 'Edit'},
  'my_review': {'ru': 'Моя рецензия', 'en': 'My review'},
  'write_review': {'ru': 'Написать рецензию', 'en': 'Write a review'},
  'review_hint': {
    'ru': 'Что думаешь о фильме? Впечатления, мысли, оценка…',
    'en': 'What did you think? Your impressions, thoughts…',
  },
  'filters': {'ru': 'Фильтры', 'en': 'Filters'},
  'filter_genres': {'ru': 'Жанры', 'en': 'Genres'},
  'filter_genres_loading': {
    'ru': 'Жанры подгружаются в фоне — открой пару карточек или зайди позже.',
    'en':
        'Genres load in the background — open a few cards or come back later.',
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
    'en': 'Download failed. Open the release manually.',
  },
  'update_whats_new': {'ru': 'Что нового', 'en': "What's new"},
  'check_updates': {'ru': 'Проверить обновления', 'en': 'Check for updates'},
  'check_updates_sub': {
    'ru': 'Скачать новую версию с GitHub',
    'en': 'Download the latest version from GitHub',
  },
  'up_to_date': {
    'ru': 'У вас последняя версия',
    'en': "You're on the latest version",
  },
  'checking_updates': {
    'ru': 'Проверяю обновления…',
    'en': 'Checking for updates…',
  },
  'update_check_failed': {
    'ru': 'Не удалось проверить обновления',
    'en': 'Could not check for updates',
  },
  'sync_title': {'ru': 'Синхронизация', 'en': 'Sync'},
  'sync_webdav': {'ru': 'Синхронизация (WebDAV)', 'en': 'Sync (WebDAV)'},
  'sync_webdav_sub': {
    'ru': 'Между устройствами через ваш облачный диск',
    'en': 'Between devices via your cloud drive',
  },
  'sync_intro': {
    'ru':
        'Двусторонняя синхронизация через WebDAV (Nextcloud, Яндекс.Диск, ownCloud). Данные на вашем сервере, ничего добавленного не теряется.',
    'en':
        'Two-way sync via WebDAV (Nextcloud, Yandex.Disk, ownCloud). Data stays on your server; nothing added is lost.',
  },
  'sync_url': {'ru': 'Адрес WebDAV', 'en': 'WebDAV URL'},
  'sync_url_hint': {
    'ru': 'https://облако.домен/remote.php/dav/files/user/',
    'en': 'https://cloud.example/remote.php/dav/files/user/',
  },
  'sync_user': {'ru': 'Логин', 'en': 'Username'},
  'sync_pass': {
    'ru': 'Пароль (или пароль приложения)',
    'en': 'Password (or app password)',
  },
  'sync_connect': {'ru': 'Подключить', 'en': 'Connect'},
  'sync_connected': {'ru': 'Подключено', 'en': 'Connected'},
  'sync_connect_failed': {
    'ru': 'Не удалось подключиться. Проверьте адрес и данные.',
    'en': 'Connection failed. Check URL and credentials.',
  },
  'sync_now': {'ru': 'Синхронизировать сейчас', 'en': 'Sync now'},
  'sync_done': {
    'ru': 'Синхронизировано (+{a}, объединено {m})',
    'en': 'Synced (+{a}, merged {m})',
  },
  'sync_no_changes': {'ru': 'Всё уже синхронно', 'en': 'Already up to date'},
  'sync_error': {'ru': 'Ошибка синхронизации', 'en': 'Sync failed'},
  'sync_auto': {'ru': 'Авто-синхронизация', 'en': 'Auto-sync'},
  'sync_auto_sub': {
    'ru': 'Синхронизировать при запуске приложения',
    'en': 'Sync on app start',
  },
  'sync_forget': {'ru': 'Отключить', 'en': 'Disconnect'},
  'sync_last': {'ru': 'Последний синк: {t}', 'en': 'Last sync: {t}'},
  'sync_never': {'ru': 'Ещё не синхронизировано', 'en': 'Not synced yet'},
  'seq_mode': {
    'ru': 'Отмечать серии по порядку',
    'en': 'Mark episodes in order',
  },
  'seq_mode_sub': {
    'ru': 'Отметил серию — все до неё тоже; снял — все после снимаются',
    'en': 'Marking an episode marks all before it; unmarking clears all after',
  },

  // ------------------------------ Брошено ------------------------------
  'dropped': {'ru': 'Брошено', 'en': 'Dropped'},
  'mark_dropped': {'ru': 'Бросить', 'en': 'Drop'},
  'in_dropped': {'ru': 'Брошено', 'en': 'Dropped'},
  'drawer_dropped': {'ru': 'Брошено', 'en': 'Dropped'},
  'dropped_empty': {
    'ru': 'Здесь будут фильмы и сериалы, которые вы бросили',
    'en': 'Movies and series you dropped will appear here',
  },
  'dropped_movies': {'ru': 'Фильмы', 'en': 'Movies'},
  'dropped_series': {'ru': 'Сериалы', 'en': 'Series'},
  'dropped_count': {'ru': 'Брошено: {n}', 'en': 'Dropped: {n}'},

  // --------------------- Уведомления о новых сериях ---------------------
  'notif_new_episodes': {'ru': 'Новые серии', 'en': 'New episodes'},
  'notif_new_episodes_sub': {
    'ru': 'Уведомлять о выходе новых серий сериалов, которые смотрю',
    'en': 'Notify when new episodes of series I watch are released',
  },
  'notif_inapp': {'ru': 'Блок в приложении', 'en': 'In-app banner'},
  'notif_inapp_sub': {
    'ru': 'Показывать новые серии баннером внутри приложения',
    'en': 'Show new episodes as a banner inside the app',
  },
  'notif_push': {'ru': 'Пуш-уведомления', 'en': 'Push notifications'},
  'notif_push_sub': {
    'ru': 'Системные уведомления о новых сериях (по умолчанию выкл.)',
    'en': 'System notifications for new episodes (off by default)',
  },
  'notif_channel_name': {'ru': 'Новые серии', 'en': 'New episodes'},
  'notif_new_ep_title': {'ru': 'Вышла новая серия', 'en': 'New episode out'},
  'notif_mark_watched': {'ru': 'Отметить просмотренной', 'en': 'Mark watched'},
  'notif_new_ep_body': {
    'ru': '{title}: серия {ep} уже вышла',
    'en': '{title}: episode {ep} is out',
  },
  'new_episodes_n': {'ru': '{n} новых серий', 'en': '{n} new episodes'},
  'notif_test': {'ru': 'Показать пример', 'en': 'Show a sample'},
  'notif_test_sub': {
    'ru': 'Проверить, как выглядит уведомление',
    'en': 'Preview how the notification looks',
  },
  'close': {'ru': 'Закрыть', 'en': 'Close'},
  'kp_limit_hit': {
    'ru':
        'Лимит ПоискКино на сегодня исчерпан (200 запросов/сутки). '
        'Постеры и поиск дозагрузятся позже.',
    'en':
        'PoiskKino daily limit reached (200 requests/day). '
        'Posters and search will resume later.',
  },
  'kp_limit_switch': {'ru': 'На TMDB', 'en': 'Use TMDB'},

  // --- Импорт из TV Time ---
  'tvtime_title': {'ru': 'Импорт из TV Time', 'en': 'Import from TV Time'},
  'tvtime_settings_sub': {
    'ru': 'Перенести фильмы, сериалы и просмотры',
    'en': 'Move movies, series and watch history'
  },
  'tvtime_headline': {
    'ru': 'Перенеси свою историю из TV Time',
    'en': 'Bring your history from TV Time'
  },
  'tvtime_sub': {
    'ru':
        'TV Time закрывается 15 июля 2026 — забери свою библиотеку в Kadr: '
        'фильмы, сериалы и все просмотры с датами.',
    'en':
        'TV Time shuts down on July 15, 2026 — move your library to Kadr: '
        'movies, series and every watch with dates.'
  },
  'tvtime_what_movies': {
    'ru': 'Фильмы: просмотрено, оценки, «буду смотреть»',
    'en': 'Movies: watched, ratings, watchlist'
  },
  'tvtime_what_series': {
    'ru': 'Сериалы и все серии — с датами просмотра',
    'en': 'Series and every episode — with watch dates'
  },
  'tvtime_what_ratings': {
    'ru': 'Оценки из реакций-эмоций',
    'en': 'Ratings from your emotion reactions'
  },
  'tvtime_what_watchlist': {
    'ru': 'Список «Буду смотреть»',
    'en': 'Your watchlist'
  },
  'tvtime_what_lists': {'ru': 'Свои списки', 'en': 'Your custom lists'},
  'tvtime_how': {
    'ru':
        'Как получить файл: в TV Time → Настройки → Аккаунт → «Скачать мои '
        'данные» (GDPR). На почту придёт gdpr-data.zip — выбери его здесь.',
    'en':
        'How to get the file: in TV Time → Settings → Account → “Download my '
        'data” (GDPR). You’ll get gdpr-data.zip by email — pick it here.'
  },
  'tvtime_pick': {
    'ru': 'Выбрать gdpr-data.zip',
    'en': 'Choose gdpr-data.zip'
  },
  'tvtime_st_unzip': {
    'ru': 'Распаковываю архив…',
    'en': 'Unpacking the archive…'
  },
  'tvtime_st_read': {
    'ru': 'Читаю фильмы и сериалы…',
    'en': 'Reading movies and series…'
  },
  'tvtime_st_import': {
    'ru': 'Переношу в библиотеку…',
    'en': 'Adding to your library…'
  },
  'tvtime_st_finish': {'ru': 'Почти готово…', 'en': 'Almost done…'},
  'tvtime_done_title': {'ru': 'Готово!', 'en': 'All set!'},
  'tvtime_done_sub': {
    'ru': 'Библиотека перенесена. Постеры подтянутся сами.',
    'en': 'Your library is imported. Posters will load automatically.'
  },
  'tvtime_stat_movies': {'ru': 'Фильмов', 'en': 'Movies'},
  'tvtime_stat_series': {'ru': 'Сериалов', 'en': 'Series'},
  'tvtime_stat_episodes': {'ru': 'Просмотров серий', 'en': 'Episode watches'},
  'tvtime_stat_rated': {'ru': 'С оценкой', 'en': 'Rated'},
  'tvtime_posters_note': {
    'ru':
        'Постеры, названия на твоём языке и детали подтягиваются в фоне по мере '
        'лимита TMDB.',
    'en':
        'Posters, localized titles and details load in the background within '
        'your TMDB limit.'
  },
  'tvtime_continue': {'ru': 'Продолжить', 'en': 'Continue'},
  'tvtime_error': {'ru': 'Не удалось импортировать', 'en': 'Import failed'},
  'tvtime_error_sub': {
    'ru': 'Проверь, что выбран gdpr-data.zip из экспорта TV Time.',
    'en': 'Make sure you picked gdpr-data.zip from your TV Time export.'
  },
  'tvtime_retry': {'ru': 'Попробовать снова', 'en': 'Try again'},

  // --- Онбординг: перенос из TV Time ---
  'ob5_title': {'ru': 'Пришёл из TV Time?', 'en': 'Coming from TV Time?'},
  'ob5_sub': {
    'ru':
        'Перенеси свою историю просмотров за пару касаний — фильмы, сериалы и '
        'даты.',
    'en':
        'Bring your watch history in a couple of taps — movies, series and '
        'dates.'
  },

  // --- Вход без ключа TMDB ---
  'tmdb_key_skip': {'ru': 'Войти без ключа', 'en': 'Continue without a key'},
  'tmdb_skip_title': {
    'ru': 'Войти без ключа TMDB?',
    'en': 'Enter without a TMDB key?'
  },
  'tmdb_skip_body': {
    'ru':
        'Без ключа не будет постеров, поиска и деталей — приложение почти '
        'пустое. Импорт из TV Time и ручные записи работают. Ключ можно '
        'добавить позже в Настройках.',
    'en':
        'Without a key there are no posters, search or details — the app is '
        'nearly empty. TV Time import and manual entries still work. You can '
        'add a key later in Settings.'
  },
  'tmdb_skip_confirm': {'ru': 'Всё равно войти', 'en': 'Enter anyway'},
};
