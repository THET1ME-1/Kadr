# Kadr — Google Play Data Safety (form answers / ответы для формы)

Reference for filling the **Data safety** section in Play Console.
Справочник для заполнения раздела **Безопасность данных** в Play Console.

> Applies to the app as shipped: no analytics/ads/crash SDK; social layer is optional.
> Верно для текущей сборки: нет SDK аналитики/рекламы/крэшей; соцслой опционален.

---

## Overview / Обзор

- **Does your app collect or share any of the required user data types?** → **Yes** (only for users who register the optional online account).
  **Собирает ли приложение данные пользователей?** → **Да** (только у зарегистрировавших необязательный онлайн-аккаунт).
- **Is all of the user data collected by your app encrypted in transit?** → **Yes** (HTTPS/TLS).
  **Все ли данные шифруются при передаче?** → **Да**.
- **Do you provide a way for users to request that their data be deleted?** → **Yes** — via the email in the Privacy Policy (and, once implemented, in-app: Profile → Delete account).
  **Есть ли способ запросить удаление данных?** → **Да** — через email из Политики (и, после реализации, в приложении: Профиль → Удалить аккаунт).
  ⚠️ Requires the account-deletion mechanism to actually exist. / Требует реально работающего механизма удаления.

---

## Data collected / Собираемые данные

For every item below: **Collected = Yes**, **Shared = No**, **Optional** (the app is fully usable without an account), and it is **linked to the user's identity** (tied to the account). None is used for advertising or tracking.
Для каждого пункта: **Собирается = Да**, **Передаётся третьим лицам = Нет**, **Необязательно** (приложение полностью работает без аккаунта), данные **связаны с личностью** (привязаны к аккаунту). Ничего не используется для рекламы/трекинга.

| Play category → data type | Что это в Kadr | Purpose / Цель |
|---|---|---|
| **Personal info → Email address** | Email — логин аккаунта | Account management / Управление аккаунтом |
| **Personal info → Name** | Отображаемое имя (display name) | Account management, App functionality |
| **Personal info → User IDs** | Публичный «код друга», ID пользователя | App functionality, Account management |
| **Photos and videos → Photos** | Аватар и баннер, которые грузит юзер | App functionality |
| **App activity → Other user-generated content** | Библиотека (просмотрено/желаемое), оценки, заметки, совместные списки, рекомендации, «посмотрел с другом» | App functionality |

---

## Processed ephemerally / Обрабатывается эпизодически

- **IP address** — used **only** for anti-abuse rate-limiting, auto-deleted within 24 h. Under Google's rules, data used solely for security/fraud-prevention may be **excluded** from the disclosure; if you prefer to disclose it, mark purpose = **Fraud prevention, security and compliance**, not linked to identity.
  **IP-адрес** — только для защиты от злоупотреблений, удаляется в течение 24 ч. По правилам Google данные, используемые исключительно для безопасности, можно **не декларировать**; если декларируете — цель «Предотвращение мошенничества, безопасность», без привязки к личности.

---

## NOT collected / НЕ собирается

Location, Financial info, Health & fitness, Messages, Audio, Files & docs, Calendar, Contacts, Web browsing history, Device or other IDs (advertising ID), **App info & performance (no crash logs / diagnostics)**.
Геолокация, финансы, здоровье, сообщения, аудио, файлы, календарь, контакты, история браузера, идентификаторы устройства/рекламный ID, **сведения о работе приложения (нет отчётов о сбоях/диагностики)**.

---

## Notes / Примечания

- **No third-party data sharing.** Friend visibility (shared lists, recommendations, public library projection, avatar/banner) is user-directed sharing *inside the app* → in Google's terms this is **App functionality, not "sharing"** (which means transfer to another company).
  **Нет передачи третьим лицам.** Видимость друзьям — направленный самим пользователем обмен *внутри приложения* → по терминологии Google это **функциональность**, а не «передача».
- **Passwords / recovery codes** are stored only as hashes; Google's Data Safety has no "password" data type, so nothing to declare for them.
  **Пароли/коды восстановления** хранятся только как хэши; в форме Google нет типа «пароль» — декларировать нечего.
- **Movie posters** come from TMDB/Kinopoisk CDNs and are cached on-device; not collected by us.
  **Постеры** берутся с CDN TMDB/Кинопоиска и кэшируются на устройстве; нами не собираются.
