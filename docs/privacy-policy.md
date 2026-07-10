# Kadr — Privacy Policy / Политика конфиденциальности

**Last updated / Дата обновления: 2026-07-10**

> Replace `CONTACT_EMAIL` below with the email you want to publish (e.g. badzoff@gmail.com).
> Замените `CONTACT_EMAIL` ниже на публичный email (например, badzoff@gmail.com).

---

## English

Kadr ("the app") is an open-source movie and TV tracker. This policy explains what data the app handles.

**1. The app works locally by default.** You can use Kadr without creating an account. Your library (watched titles, ratings, watchlist, notes) is stored only on your device. In this mode no personal data is sent to us.

**2. Optional online account (social features).** If you choose to register, we collect and store on our server the following data, solely to provide social features (friends, shared lists, recommendations, "watched together"):

- **Email address** — used as your login identifier. We do not send marketing email.
- **Password** — stored only as a salted hash (PBKDF2‑SHA256, 100 000 iterations). We never store your plain password.
- **Display name** and a public **friend code**.
- **Optional recovery code** — stored only as a hash.
- **Avatar and banner images** you upload (stored on Cloudflare R2; accessible by public URL).
- A **public projection of your library** (watched/watchlist) so friends can see it, plus your **friendships, shared lists, recommendations and "watched together" records**.
- **Session tokens** — stored only as a hash.

**3. IP address.** When you register, log in or request password recovery, your IP address is stored temporarily as an anti‑abuse (rate‑limiting) key and is automatically deleted within 24 hours. It is not used for tracking, advertising or profiling.

**4. Where data is stored.** Account data is hosted on Cloudflare (Workers, D1 database, R2 storage); default endpoint `https://kadr-social.badzoff.workers.dev`. Data is encrypted in transit (HTTPS/TLS).

**5. Third‑party movie data (TMDB & Kinopoisk).** Movie and TV metadata and poster images are fetched directly from The Movie Database (TMDB) and Kinopoisk (via kinopoisk.dev) using an API key that you provide. Poster images load directly from those services and are cached on your device; we do not host them. Your use of these services is subject to their own terms. *This product uses the TMDB API but is not endorsed or certified by TMDB.*

**6. Optional WebDAV backup.** You may optionally back up your library to your own WebDAV server (e.g. Nextcloud, Yandex.Disk). The server address, login and password you enter are stored only on your device and are never sent to us. Backup data goes only to the server you specify.

**7. Analytics.** The app contains **no analytics, advertising or crash‑reporting SDKs**. We do not track your behaviour.

**8. Notifications.** The app shows only **local** notifications (e.g. new‑episode reminders) generated on your device. There is no push service; no notification data is sent to any server.

**9. Data sharing.** We do not sell your personal data and do not share it with third parties for advertising. The only sharing is between you and the friends you add, by your own action (shared lists, recommendations, public library projection, avatar/banner).

**10. Data retention and deletion.** Local data is removed when you uninstall the app or clear its data. To delete your online account and all associated server data, contact us at **CONTACT_EMAIL**; we will delete it within 30 days. *(In‑app deletion under Profile → Delete account, when available.)*

**11. Children.** The app is not directed to children under 13.

**12. Changes.** We may update this policy; the "last updated" date will change accordingly.

**13. Contact.** **CONTACT_EMAIL**

---

## Русский

Kadr («приложение») — трекер фильмов и сериалов с открытым исходным кодом. Эта политика описывает, какие данные обрабатывает приложение.

**1. По умолчанию приложение работает локально.** Пользоваться Kadr можно без регистрации. Ваша библиотека (просмотренное, оценки, список желаемого, заметки) хранится только на вашем устройстве. В этом режиме никакие персональные данные нам не передаются.

**2. Необязательный онлайн‑аккаунт (соцфункции).** Если вы решите зарегистрироваться, мы собираем и храним на нашем сервере следующие данные — исключительно для работы соцфункций (друзья, совместные списки, рекомендации, «посмотрел с другом»):

- **Email** — используется как логин. Рекламных писем мы не отправляем.
- **Пароль** — хранится только в виде соленого хэша (PBKDF2‑SHA256, 100 000 итераций). Пароль в открытом виде мы не храним.
- **Отображаемое имя** и публичный **код друга**.
- **Необязательный код восстановления** — хранится только как хэш.
- **Аватар и баннер**, которые вы загружаете (хранятся в Cloudflare R2, доступны по публичной ссылке).
- **Публичная витрина вашей библиотеки** (просмотренное/желаемое), чтобы её видели друзья, а также ваши **дружеские связи, совместные списки, рекомендации и записи «посмотрел с другом»**.
- **Токены сессии** — хранятся только как хэш.

**3. IP‑адрес.** При регистрации, входе или запросе восстановления пароля ваш IP‑адрес временно сохраняется как ключ защиты от злоупотреблений (ограничение частоты запросов) и автоматически удаляется в течение 24 часов. Он не используется для отслеживания, рекламы или профилирования.

**4. Где хранятся данные.** Данные аккаунта размещены в Cloudflare (Workers, база D1, хранилище R2); адрес по умолчанию — `https://kadr-social.badzoff.workers.dev`. Данные передаются по защищённому соединению (HTTPS/TLS).

**5. Сторонние киноданные (TMDB и Кинопоиск).** Метаданные фильмов/сериалов и постеры загружаются напрямую из The Movie Database (TMDB) и Кинопоиска (через kinopoisk.dev) с использованием API‑ключа, который вводите вы. Постеры грузятся напрямую с серверов этих сервисов и кэшируются на вашем устройстве; мы их не храним. Использование этих сервисов регулируется их собственными условиями. *Этот продукт использует API TMDB, но не одобрен и не сертифицирован TMDB.*

**6. Необязательный бэкап по WebDAV.** По желанию вы можете делать резервные копии библиотеки на ваш собственный WebDAV‑сервер (например, Nextcloud, Яндекс.Диск). Введённые вами адрес сервера, логин и пароль хранятся только на вашем устройстве и нам не передаются. Данные копии уходят только на указанный вами сервер.

**7. Аналитика.** В приложении **нет SDK аналитики, рекламы или сбора отчётов о сбоях**. Мы не отслеживаем ваше поведение.

**8. Уведомления.** Приложение показывает только **локальные** уведомления (например, напоминания о выходе новых серий), формируемые на устройстве. Пуш‑сервиса нет; данные уведомлений никуда не отправляются.

**9. Передача данных.** Мы не продаём ваши персональные данные и не передаём их третьим лицам для рекламы. Единственная «передача» — между вами и добавленными вами друзьями, по вашему собственному действию (совместные списки, рекомендации, публичная витрина библиотеки, аватар/баннер).

**10. Хранение и удаление данных.** Локальные данные удаляются при удалении приложения или очистке его данных. Чтобы удалить онлайн‑аккаунт и все связанные с ним данные на сервере, напишите нам на **CONTACT_EMAIL**; мы удалим их в течение 30 дней. *(Удаление прямо в приложении — «Профиль → Удалить аккаунт», когда функция будет добавлена.)*

**11. Дети.** Приложение не предназначено для детей младше 13 лет.

**12. Изменения.** Мы можем обновлять эту политику; дата обновления будет меняться соответственно.

**13. Контакт.** **CONTACT_EMAIL**
