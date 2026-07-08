# 🎬 Kadr

**Kadr** — a movie & TV series tracker in **Material 3 Expressive** style: bold design,
rich statistics, deep customization, 7 UI languages. Local-first, open source.

*Русская версия — [ниже](#-kadr-русский).*

---

## English

### Stack
- **Flutter** (Material 3 Expressive, dynamic color / Material You)
- **Movie database**: [TMDB](https://www.themoviedb.org/) — localized titles, posters, ratings, series
- **Data**: local-first + JSON backup + sync (WebDAV / P2P)
- **Backend** (social / friends): Cloudflare Workers + D1 + R2 — entirely on the **free tier**
  (10 GB R2 with zero egress, $0). No secrets are stored in this repo.

### Features
- Light / dark / system / time-based themes, live color picker, 8 palettes, AMOLED
- Bottom-sheet dialogs everywhere, big pill-shaped buttons
- Mood ratings (Awful → Amazing), viewings grouped by month
- Social: friends, profiles with custom banners, "watched together", recommendations, shared lists
- 7 languages: 🇬🇧 🇷🇺 🇩🇪 🇫🇷 🇪🇸 🇮🇹 🇵🇹 (auto-detected from the phone)

### Install (Android)
Distributed **only via GitHub Releases** (not on Google Play).

**Recommended — [Obtainium](https://github.com/ImranR98/Obtainium)** (auto-updates):
1. Install Obtainium.
2. **Add App** → paste `https://github.com/THET1ME-1/Kadr` → Add.
3. It finds the latest release; pick the APK for your CPU (`arm64-v8a` — almost all modern phones).

One-tap: `obtainium://add/https://github.com/THET1ME-1/Kadr`

Or download the APK from the [releases page](https://github.com/THET1ME-1/Kadr/releases/latest).

Signing fingerprint (SHA-256) to verify the APK:
`64:87:C6:84:BB:4B:DA:1B:1A:9C:22:72:4C:50:24:9D:00:06:04:E1:D4:18:1D:49:48:A5:B6:DA:6A:B8:CE:B8`

### TMDB API key (personal)
Movie data comes from [TMDB](https://www.themoviedb.org/). The key is **free and personal** —
on first launch each user enters **their own** token (a screen with instructions). No shared
keys ship in the repo or the builds.

Get one: themoviedb.org → **Settings → API** → create a key → copy the **API Read Access Token**
(v4, starts with `eyJ…`).

### Development
```bash
flutter pub get
# enter the token in-app, or bake it into your own build:
flutter run --dart-define=TMDB_TOKEN=<your_token> [--dart-define=KINOPOISK_KEY=<key>]
```

### License
[GPL-3.0](LICENSE) — free software with copyleft: any fork/derivative, when distributed,
must stay open under the same license.

This product uses the TMDB API but is not endorsed or certified by TMDB.

Roadmap & status — see [PLAN.md](PLAN.md).

---

## 🎬 Kadr (Русский)

**Kadr (Кадр)** — трекер просмотренных фильмов и сериалов в стиле **Material 3 Expressive**:
крупный дизайн, богатая статистика, кастомизация на максимуме, 7 языков. Локально-первично, открытый код.

### Стек
- **Flutter** (Material 3 Expressive, dynamic color / Material You)
- **База фильмов**: [TMDB](https://www.themoviedb.org/) — названия на языке юзера, постеры, рейтинги, сериалы
- **Данные**: локально-первично + JSON-бэкап + синхронизация (WebDAV / P2P)
- **Бэкенд** (соц-слой / друзья): Cloudflare Workers + D1 + R2 — целиком на **бесплатном тарифе**
  (10 ГБ R2, нулевой исходящий трафик, $0). Секретов в репозитории нет.

### Особенности
- Тёмная/светлая/системная/авто темы, живой колор-пикер, 8 палитр, AMOLED
- Все попапы — нижними панелями, крупные «таблеточные» кнопки
- Оценки-настроения (Ужасно → Восхитительно), группировка просмотров по месяцам
- Соц: друзья, профили с баннерами, «посмотрел с другом», рекомендации, совместные списки
- 7 языков: 🇷🇺 🇬🇧 🇩🇪 🇫🇷 🇪🇸 🇮🇹 🇵🇹 (определяются по телефону)

### Установка (Android)
Распространяется **только через GitHub Releases** (не в Google Play).

**Рекомендуется — [Obtainium](https://github.com/ImranR98/Obtainium)** (авто-обновления):
1. Установи Obtainium.
2. **Add App** → вставь `https://github.com/THET1ME-1/Kadr` → Add.
3. Он найдёт последний релиз; выбери APK под свой процессор (`arm64-v8a` — почти все телефоны).

One-tap: `obtainium://add/https://github.com/THET1ME-1/Kadr`

Или скачай APK со [страницы релизов](https://github.com/THET1ME-1/Kadr/releases/latest).

Отпечаток подписи (SHA-256) для проверки APK:
`64:87:C6:84:BB:4B:DA:1B:1A:9C:22:72:4C:50:24:9D:00:06:04:E1:D4:18:1D:49:48:A5:B6:DA:6A:B8:CE:B8`

### API-ключ TMDB (личный)
Данные о фильмах — из [TMDB](https://www.themoviedb.org/). Ключ **бесплатный и персональный** —
при первом запуске каждый вводит **свой** токен (экран с инструкцией). В репозитории и сборках
**нет** чужих ключей.

Как получить: themoviedb.org → **Settings → API** → создать ключ → скопировать
**API Read Access Token** (v4, начинается с `eyJ…`).

### Разработка
```bash
flutter pub get
# токен можно ввести в приложении, либо вшить в свою сборку:
flutter run --dart-define=TMDB_TOKEN=<ваш_токен> [--dart-define=KINOPOISK_KEY=<ключ>]
```

### Лицензия
[GPL-3.0](LICENSE) — свободное ПО с копилефтом: любой форк/производная при распространении
должны оставаться открытыми под той же лицензией.

*Инфраструктура (тема, i18n, настройки, синхронизация) — ДНК проекта ScoreMaster.*
