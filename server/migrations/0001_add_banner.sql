-- Миграция: баннеры профиля. Аддитивная и безопасная (данные не трогает).
-- Применение к живой БД:
--   npx wrangler d1 execute kadr-social --remote --file migrations/0001_add_banner.sql
ALTER TABLE users ADD COLUMN banner_updated INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS banners (
  user_id      TEXT PRIMARY KEY,
  data_b64     TEXT NOT NULL,
  content_type TEXT NOT NULL,
  updated_at   INTEGER NOT NULL
);
