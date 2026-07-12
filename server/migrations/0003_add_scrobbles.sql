-- Миграция: скробблинг Plex/Jellyfin. Аддитивная, безопасная.
-- Вебхук плеера прилетает на воркер по персональному токену → кладём событие в
-- очередь; приложение забирает и отмечает просмотр локально (local-first).
-- Применение к живой БД:
--   npx wrangler d1 execute kadr-social --remote --file migrations/0003_add_scrobbles.sql
CREATE TABLE IF NOT EXISTS scrobbles (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  kind       TEXT NOT NULL,   -- movie | episode
  title      TEXT NOT NULL,   -- название фильма или сериала
  year       INTEGER,         -- для фильмов
  season     INTEGER,         -- для серий
  episode    INTEGER,         -- для серий
  source     TEXT,            -- plex | jellyfin
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_scrobbles_user ON scrobbles(user_id, created_at);

-- Персональный секрет для URL вебхука (кто знает URL — может слать события ТОЛЬКО
-- в очередь этого пользователя). Аддитивная колонка.
ALTER TABLE users ADD COLUMN scrobble_token TEXT;
CREATE INDEX IF NOT EXISTS idx_users_scrobble ON users(scrobble_token);
