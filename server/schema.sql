-- Kadr social backend — схема D1 (SQLite).
-- Профили пользователей, сессии, дружба и «публичная проекция» библиотеки.

CREATE TABLE IF NOT EXISTS users (
  id             TEXT PRIMARY KEY,        -- uuid
  email          TEXT UNIQUE NOT NULL,    -- нормализованный (lower/trim)
  pass_hash      TEXT NOT NULL,           -- pbkdf2: saltHex:hashHex:iterations
  display_name   TEXT NOT NULL,
  avatar_updated INTEGER NOT NULL DEFAULT 0, -- 0 = фото нет; иначе ver (cache-bust)
  friend_code    TEXT UNIQUE NOT NULL,    -- короткий код для добавления в друзья
  recovery_hash  TEXT,                    -- PBKDF2-хэш кода восстановления (nullable)
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_users_code ON users(friend_code);
CREATE INDEX IF NOT EXISTS idx_users_name ON users(display_name);

-- Аватарки (сжатые на телефоне до ~256px). Храним в D1 как base64 —
-- у токена нет прав на R2, а фото после ресайза весит десятки КБ.
CREATE TABLE IF NOT EXISTS avatars (
  user_id      TEXT PRIMARY KEY,
  data_b64     TEXT NOT NULL,
  content_type TEXT NOT NULL,
  updated_at   INTEGER NOT NULL
);

-- Сессии. Храним SHA-256 ХЕШ токена (не сам токен) + срок жизни (TTL).
-- Даже при утечке БД по хешу нельзя выдать себя за пользователя.
CREATE TABLE IF NOT EXISTS tokens (
  token_hash TEXT PRIMARY KEY,            -- sha256(bearer-токен)
  user_id    TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tokens_user ON tokens(user_id);

-- Ограничение частоты (анти-брутфорс/спам): ключ вида «login:<ip>».
CREATE TABLE IF NOT EXISTS rate_limits (
  key          TEXT PRIMARY KEY,
  count        INTEGER NOT NULL,
  window_start INTEGER NOT NULL
);

-- Одна строка на направление запроса (requester -> addressee).
-- status: 'pending' (ждёт подтверждения) | 'accepted' (дружат).
CREATE TABLE IF NOT EXISTS friendships (
  requester  TEXT NOT NULL,
  addressee  TEXT NOT NULL,
  status     TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (requester, addressee)
);
CREATE INDEX IF NOT EXISTS idx_friend_addr ON friendships(addressee);
CREATE INDEX IF NOT EXISTS idx_friend_req  ON friendships(requester);

-- Публичная проекция библиотеки пользователя (просмотры + желания) как JSON.
-- Источник истины — телефон; сюда заливается только то, что видно друзьям.
CREATE TABLE IF NOT EXISTS library (
  user_id    TEXT PRIMARY KEY,
  data       TEXT NOT NULL,               -- JSON-строка проекции
  updated_at INTEGER NOT NULL
);

-- Совместные списки: несколько участников редактируют один список фильмов.
CREATE TABLE IF NOT EXISTS shared_lists (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  owner      TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS shared_list_members (
  list_id    TEXT NOT NULL,
  user_id    TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (list_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_slm_user ON shared_list_members(user_id);
CREATE TABLE IF NOT EXISTS shared_list_items (
  list_id  TEXT NOT NULL,
  item_key TEXT NOT NULL,                 -- tmdb-<id> либо title|year
  data     TEXT NOT NULL,                 -- JSON {title, year, posterUrl, tmdbId}
  added_by TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (list_id, item_key)
);

-- «Советую тебе»: явные рекомендации фильма от друга к другу.
CREATE TABLE IF NOT EXISTS recommendations (
  id         TEXT PRIMARY KEY,
  from_user  TEXT NOT NULL,
  to_user    TEXT NOT NULL,
  data       TEXT NOT NULL,               -- JSON {title, year, posterUrl, tmdbId}
  note       TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rec_to ON recommendations(to_user);
