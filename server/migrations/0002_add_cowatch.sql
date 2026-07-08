-- Миграция: совместные просмотры «Посмотрел с другом». Аддитивная, безопасная.
-- Применение к живой БД:
--   npx wrangler d1 execute kadr-social --remote --file migrations/0002_add_cowatch.sql
CREATE TABLE IF NOT EXISTS co_watches (
  id         TEXT PRIMARY KEY,
  from_user  TEXT NOT NULL,
  to_user    TEXT NOT NULL,
  data       TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_cowatch_to ON co_watches(to_user);
