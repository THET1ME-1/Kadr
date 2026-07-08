// Kadr social backend — Cloudflare Worker + D1.
//
// Профили (email + пароль), дружба (взаимная: запрос → принятие) и «публичная
// проекция» библиотеки (что посмотрел + оценка, что в желаниях). Данные на
// телефоне остаются источником истины — сюда заливается только соц-слой.
//
// Аутентификация: opaque bearer-токен (заголовок Authorization: Bearer <token>).
// Пароли хранятся как PBKDF2-SHA256 (saltHex:hashHex:iterations).

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PATCH,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization',
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS },
  });

const err = (message, status = 400) => json({ error: message }, status);

// ------------------------------- утилиты -------------------------------

const now = () => Date.now();

function toHex(bytes) {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function randomHex(nBytes) {
  const buf = new Uint8Array(nBytes);
  crypto.getRandomValues(buf);
  return toHex(buf);
}

// Код друга: 6 символов без похожих (0/O, 1/I/L). Легко продиктовать.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
function makeFriendCode() {
  const buf = new Uint8Array(6);
  crypto.getRandomValues(buf);
  let s = '';
  for (const b of buf) s += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return s;
}

// Код восстановления: 12 символов (~60 бит) из того же алфавита, показывается
// сгруппированным «XXXX-XXXX-XXXX». Хранится хэшем; для сверки нормализуем.
function makeRecoveryCode() {
  const buf = new Uint8Array(12);
  crypto.getRandomValues(buf);
  let s = '';
  for (const b of buf) s += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return s;
}
const formatRecovery = (s) => `${s.slice(0, 4)}-${s.slice(4, 8)}-${s.slice(8, 12)}`;
const normRecovery = (s) => String(s).toUpperCase().replace(/[^A-Z0-9]/g, '');

async function pbkdf2(password, saltBytes, iterations) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: saltBytes, iterations, hash: 'SHA-256' },
    key,
    256,
  );
  return new Uint8Array(bits);
}

async function hashPassword(password) {
  const iterations = 100000;
  const salt = new Uint8Array(16);
  crypto.getRandomValues(salt);
  const hash = await pbkdf2(password, salt, iterations);
  return `${toHex(salt)}:${toHex(hash)}:${iterations}`;
}

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return out;
}

// Константное по времени сравнение hex-строк равной длины.
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function verifyPassword(password, stored) {
  const [saltHex, hashHex, iterStr] = stored.split(':');
  if (!saltHex || !hashHex || !iterStr) return false;
  const hash = await pbkdf2(password, hexToBytes(saltHex), parseInt(iterStr, 10));
  return timingSafeEqual(toHex(hash), hashHex);
}

async function sha256Hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return toHex(new Uint8Array(buf));
}

const TOKEN_TTL_MS = 90 * 24 * 60 * 60 * 1000; // 90 дней

// Создаёт сессию: генерит случайный токен, кладёт в БД его ХЕШ + срок жизни,
// возвращает клиенту сам токен (в БД его нет — только хеш).
async function createSession(env, userId) {
  const token = randomHex(24);
  const ts = now();
  await env.DB.prepare(
    'INSERT INTO tokens (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
  )
    .bind(await sha256Hex(token), userId, ts, ts + TOKEN_TTL_MS)
    .run();
  return token;
}

// Ограничение частоты: не более [max] обращений за [windowMs] на [key].
// Возвращает true, если запрос разрешён. Скользящее фиксированное окно в D1.
async function rateLimit(env, key, max, windowMs) {
  const ts = now();
  const row = await env.DB.prepare(
    'SELECT count, window_start FROM rate_limits WHERE key = ?',
  )
    .bind(key)
    .first();
  if (!row || ts - row.window_start > windowMs) {
    await env.DB.prepare(
      `INSERT INTO rate_limits (key, count, window_start) VALUES (?1, 1, ?2)
       ON CONFLICT(key) DO UPDATE SET count = 1, window_start = ?2`,
    )
      .bind(key, ts)
      .run();
    return true;
  }
  if (row.count >= max) return false;
  await env.DB.prepare('UPDATE rate_limits SET count = count + 1 WHERE key = ?')
    .bind(key)
    .run();
  return true;
}

const clientIp = (request) =>
  request.headers.get('CF-Connecting-IP') || 'unknown';

function base64FromArrayBuffer(buf) {
  const bytes = new Uint8Array(buf);
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

const isEmail = (s) => typeof s === 'string' && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s);
const normEmail = (s) => String(s).trim().toLowerCase();

// Публичное представление профиля (без email/хэша) — для показа друзьям.
// avatar — версия фото (0 = нет); клиент строит URL `/avatars/<id>?v=<ver>`.
const publicUser = (u) => ({
  id: u.id,
  displayName: u.display_name,
  avatar: u.avatar_updated || 0,
  banner: u.banner_updated || 0,
  friendCode: u.friend_code,
});

// Полное представление своего профиля (с email) — для владельца.
// hasRecovery — задан ли код восстановления (для подсказки «создай код»).
const selfUser = (u) => ({
  ...publicUser(u),
  email: u.email,
  hasRecovery: !!u.recovery_hash,
});

// ------------------------------- запросы БД -------------------------------

const getUserById = (env, id) =>
  env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first();

const getUserByEmail = (env, email) =>
  env.DB.prepare('SELECT * FROM users WHERE email = ?').bind(email).first();

const getUserByCode = (env, code) =>
  env.DB.prepare('SELECT * FROM users WHERE friend_code = ?').bind(code).first();

async function authenticate(request, env) {
  const header = request.headers.get('Authorization') || '';
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (!m) return null;
  const row = await env.DB.prepare(
    'SELECT user_id, expires_at FROM tokens WHERE token_hash = ?',
  )
    .bind(await sha256Hex(m[1]))
    .first();
  if (!row) return null;
  if (row.expires_at < now()) {
    // Просроченный токен — вычищаем и отклоняем.
    await env.DB.prepare('DELETE FROM tokens WHERE token_hash = ?')
      .bind(await sha256Hex(m[1]))
      .run();
    return null;
  }
  return getUserById(env, row.user_id);
}

// Статус связи между двумя пользователями (в любом направлении).
async function friendship(env, a, b) {
  return env.DB.prepare(
    `SELECT * FROM friendships
     WHERE (requester = ?1 AND addressee = ?2) OR (requester = ?2 AND addressee = ?1)`,
  )
    .bind(a, b)
    .first();
}

async function areFriends(env, a, b) {
  const f = await friendship(env, a, b);
  return !!f && f.status === 'accepted';
}

// ------------------------------- обработчики -------------------------------

async function register(request, env) {
  // Анти-спам: не более 5 регистраций с одного IP в час.
  if (!(await rateLimit(env, `reg:${clientIp(request)}`, 5, 60 * 60 * 1000))) {
    return err('rate_limited', 429);
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const email = normEmail(body.email || '');
  const password = String(body.password || '');
  const displayName = String(body.displayName || '').trim();

  if (!isEmail(email)) return err('invalid_email');
  if (password.length < 8) return err('weak_password');
  if (displayName.length < 1 || displayName.length > 40) return err('invalid_name');

  if (await getUserByEmail(env, email)) return err('email_taken', 409);

  const id = crypto.randomUUID();
  const passHash = await hashPassword(password);
  const ts = now();

  // Генерируем уникальный код друга (несколько попыток на случай коллизии).
  let code = makeFriendCode();
  for (let i = 0; i < 5 && (await getUserByCode(env, code)); i++) code = makeFriendCode();

  // Код восстановления доступа (показывается один раз, хранится хэшем).
  const recovery = makeRecoveryCode();
  const recoveryHash = await hashPassword(recovery);

  await env.DB.prepare(
    `INSERT INTO users (id, email, pass_hash, display_name, friend_code, recovery_hash, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(id, email, passHash, displayName, code, recoveryHash, ts, ts)
    .run();

  const token = await createSession(env, id);
  const user = await getUserById(env, id);
  return json({ token, user: selfUser(user), recoveryCode: formatRecovery(recovery) });
}

async function login(request, env) {
  // Анти-брутфорс: не более 10 попыток входа с одного IP за 15 минут.
  if (!(await rateLimit(env, `login:${clientIp(request)}`, 10, 15 * 60 * 1000))) {
    return err('rate_limited', 429);
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const email = normEmail(body.email || '');
  const password = String(body.password || '');
  const user = await getUserByEmail(env, email);
  if (!user || !(await verifyPassword(password, user.pass_hash))) {
    return err('invalid_credentials', 401);
  }
  const token = await createSession(env, user.id);
  return json({ token, user: selfUser(user) });
}

async function logout(request, env) {
  const header = request.headers.get('Authorization') || '';
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (m) {
    await env.DB.prepare('DELETE FROM tokens WHERE token_hash = ?')
      .bind(await sha256Hex(m[1]))
      .run();
  }
  return json({ ok: true });
}

// Сброс пароля по коду восстановления: меняет пароль, РОТИРУЕТ код (старый
// больше не работает), гасит все прежние сессии и входит заново.
async function resetPassword(request, env) {
  if (!(await rateLimit(env, `reset:${clientIp(request)}`, 10, 15 * 60 * 1000))) {
    return err('rate_limited', 429);
  }
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const email = normEmail(body.email || '');
  const code = normRecovery(body.recoveryCode || body.code || '');
  const newPassword = String(body.newPassword || '');
  if (newPassword.length < 8) return err('weak_password');

  const user = await getUserByEmail(env, email);
  if (
    !user ||
    !user.recovery_hash ||
    !(await verifyPassword(code, user.recovery_hash))
  ) {
    return err('invalid_recovery', 401);
  }

  const passHash = await hashPassword(newPassword);
  const recovery = makeRecoveryCode();
  const recoveryHash = await hashPassword(recovery);
  await env.DB.prepare(
    'UPDATE users SET pass_hash = ?, recovery_hash = ?, updated_at = ? WHERE id = ?',
  )
    .bind(passHash, recoveryHash, now(), user.id)
    .run();
  // Безопасность: сброс всех прежних сессий пользователя.
  await env.DB.prepare('DELETE FROM tokens WHERE user_id = ?').bind(user.id).run();

  const token = await createSession(env, user.id);
  const fresh = await getUserById(env, user.id);
  return json({
    token,
    user: selfUser(fresh),
    recoveryCode: formatRecovery(recovery),
  });
}

// Перегенерация кода восстановления (в профиле). Возвращает новый код.
async function regenerateRecovery(env, me) {
  const recovery = makeRecoveryCode();
  const recoveryHash = await hashPassword(recovery);
  await env.DB.prepare('UPDATE users SET recovery_hash = ?, updated_at = ? WHERE id = ?')
    .bind(recoveryHash, now(), me.id)
    .run();
  return json({ recoveryCode: formatRecovery(recovery) });
}

async function updateMe(request, env, me) {
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const name =
      body.displayName != null ? String(body.displayName).trim() : me.display_name;
  if (name.length < 1 || name.length > 40) return err('invalid_name');
  await env.DB.prepare('UPDATE users SET display_name = ?, updated_at = ? WHERE id = ?')
    .bind(name, now(), me.id)
    .run();
  return json({ user: selfUser(await getUserById(env, me.id)) });
}

// ------------------------------- медиа (R2) -------------------------------
// Аватары/баннеры лежат в R2 (env.MEDIA), ключ = `<kind>/<userId>` (kind =
// 'avatars'|'banners' — фиксированные строки, не пользовательский ввод).
// Версия (cache-bust) — в users.avatar_updated/banner_updated. Старые данные из
// D1 (base64) переносятся в R2 ЛЕНИВО при первом показе — без простоя.

async function putMedia(env, kind, userId, ct, buf) {
  await env.MEDIA.put(`${kind}/${userId}`, buf, {
    httpMetadata: { contentType: ct },
  });
}

async function serveMedia(env, kind, userId) {
  const obj = await env.MEDIA.get(`${kind}/${userId}`);
  if (obj) {
    return new Response(obj.body, {
      headers: {
        'Content-Type': obj.httpMetadata?.contentType || 'image/*',
        'Cache-Control': 'public, max-age=31536000, immutable',
        ...CORS,
      },
    });
  }
  // Ленивая миграция из D1 (старые base64-аватары/баннеры).
  const row = await env.DB.prepare(
    `SELECT data_b64, content_type FROM ${kind} WHERE user_id = ?`,
  )
    .bind(userId)
    .first();
  if (!row) return new Response('not found', { status: 404, headers: CORS });
  const bin = atob(row.data_b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  await putMedia(env, kind, userId, row.content_type, bytes);
  await env.DB.prepare(`DELETE FROM ${kind} WHERE user_id = ?`).bind(userId).run();
  return new Response(bytes, {
    headers: {
      'Content-Type': row.content_type,
      'Cache-Control': 'public, max-age=31536000, immutable',
      ...CORS,
    },
  });
}

// Загрузка аватара (клиент уже сжал ~256px, PNG/WebP). Кладём в R2.
async function uploadAvatar(request, env, me) {
  if (!(await rateLimit(env, `media:${me.id}`, 40, 60 * 60 * 1000))) return err('rate_limited', 429);
  const ct = request.headers.get('Content-Type') || '';
  if (!/^image\/(png|jpeg|jpg|webp)$/i.test(ct)) return err('bad_type');
  const buf = await request.arrayBuffer();
  if (buf.byteLength === 0) return err('empty');
  if (buf.byteLength > 400 * 1024) return err('too_large', 413); // ≤ 400 КБ
  const ver = now();
  await putMedia(env, 'avatars', me.id, ct, buf);
  await env.DB.prepare('DELETE FROM avatars WHERE user_id = ?').bind(me.id).run();
  await env.DB.prepare('UPDATE users SET avatar_updated = ? WHERE id = ?')
    .bind(ver, me.id)
    .run();
  return json({ avatar: ver });
}

async function getAvatar(env, userId) {
  return serveMedia(env, 'avatars', userId);
}

// Загрузка баннера профиля (клиент сжал ~1080px, PNG/WebP). Кладём в R2.
async function uploadBanner(request, env, me) {
  if (!(await rateLimit(env, `media:${me.id}`, 40, 60 * 60 * 1000))) return err('rate_limited', 429);
  const ct = request.headers.get('Content-Type') || '';
  if (!/^image\/(png|jpeg|jpg|webp)$/i.test(ct)) return err('bad_type');
  const buf = await request.arrayBuffer();
  if (buf.byteLength === 0) return err('empty');
  if (buf.byteLength > 700 * 1024) return err('too_large', 413); // ≤ 700 КБ
  const ver = now();
  await putMedia(env, 'banners', me.id, ct, buf);
  await env.DB.prepare('DELETE FROM banners WHERE user_id = ?').bind(me.id).run();
  await env.DB.prepare('UPDATE users SET banner_updated = ? WHERE id = ?')
    .bind(ver, me.id)
    .run();
  return json({ banner: ver });
}

// Удаление баннера профиля (сброс к дефолтному градиенту).
async function deleteBanner(env, me) {
  await env.MEDIA.delete(`banners/${me.id}`);
  await env.DB.prepare('DELETE FROM banners WHERE user_id = ?').bind(me.id).run();
  await env.DB.prepare('UPDATE users SET banner_updated = 0 WHERE id = ?')
    .bind(me.id)
    .run();
  return json({ banner: 0 });
}

async function getBanner(env, userId) {
  return serveMedia(env, 'banners', userId);
}

// Списки друзей: принятые + входящие/исходящие заявки. Для каждого — публичный
// профиль и время последнего обновления его библиотеки (для сортировки/значка).
async function listFriends(env, me) {
  const rows = (
    await env.DB.prepare(
      `SELECT f.requester, f.addressee, f.status, f.updated_at AS f_updated,
              u.id, u.display_name, u.avatar_updated, u.banner_updated, u.friend_code,
              (SELECT updated_at FROM library WHERE user_id = u.id) AS lib_updated
       FROM friendships f
       JOIN users u ON u.id = (CASE WHEN f.requester = ?1 THEN f.addressee ELSE f.requester END)
       WHERE f.requester = ?1 OR f.addressee = ?1`,
    )
      .bind(me.id)
      .all()
  ).results;

  const friends = [];
  const incoming = [];
  const outgoing = [];
  for (const r of rows) {
    const entry = {
      user: {
        id: r.id,
        displayName: r.display_name,
        avatar: r.avatar_updated || 0,
        banner: r.banner_updated || 0,
        friendCode: r.friend_code,
      },
      libraryUpdatedAt: r.lib_updated || 0,
      since: r.f_updated,
    };
    if (r.status === 'accepted') friends.push(entry);
    else if (r.addressee === me.id) incoming.push(entry); // мне прислали заявку
    else outgoing.push(entry); // я отправил заявку
  }
  return json({ friends, incoming, outgoing });
}

// Отправить заявку в друзья по коду или по id. Если встречная заявка уже есть —
// сразу дружим (accept). Возвращает итоговый статус.
async function requestFriend(request, env, me) {
  if (!(await rateLimit(env, `fr:${me.id}`, 60, 60 * 60 * 1000))) return err('rate_limited', 429);
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  let target = null;
  if (body.code) target = await getUserByCode(env, String(body.code).trim().toUpperCase());
  else if (body.userId) target = await getUserById(env, String(body.userId));
  if (!target) return err('user_not_found', 404);
  if (target.id === me.id) return err('cannot_add_self');

  const existing = await friendship(env, me.id, target.id);
  const ts = now();
  if (existing) {
    if (existing.status === 'accepted') return json({ status: 'accepted' });
    // Уже есть pending. Если это встречная заявка (они -> я) — принимаем.
    if (existing.addressee === me.id) {
      await env.DB.prepare(
        'UPDATE friendships SET status = ?, updated_at = ? WHERE requester = ? AND addressee = ?',
      )
        .bind('accepted', ts, existing.requester, existing.addressee)
        .run();
      return json({ status: 'accepted' });
    }
    return json({ status: 'pending' }); // моя заявка уже висит
  }

  await env.DB.prepare(
    'INSERT INTO friendships (requester, addressee, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
  )
    .bind(me.id, target.id, 'pending', ts, ts)
    .run();
  return json({ status: 'pending', friend: publicUser(target) });
}

// Ответ на входящую заявку: accept | decline.
async function respondFriend(request, env, me) {
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const requesterId = String(body.userId || '');
  const action = String(body.action || '');
  const row = await env.DB.prepare(
    'SELECT * FROM friendships WHERE requester = ? AND addressee = ? AND status = ?',
  )
    .bind(requesterId, me.id, 'pending')
    .first();
  if (!row) return err('request_not_found', 404);

  if (action === 'accept') {
    await env.DB.prepare(
      'UPDATE friendships SET status = ?, updated_at = ? WHERE requester = ? AND addressee = ?',
    )
      .bind('accepted', now(), requesterId, me.id)
      .run();
    return json({ status: 'accepted' });
  }
  if (action === 'decline') {
    await env.DB.prepare('DELETE FROM friendships WHERE requester = ? AND addressee = ?')
      .bind(requesterId, me.id)
      .run();
    return json({ status: 'declined' });
  }
  return err('bad_action');
}

// Удалить дружбу/заявку в любом направлении.
async function removeFriend(env, me, otherId) {
  await env.DB.prepare(
    `DELETE FROM friendships
     WHERE (requester = ?1 AND addressee = ?2) OR (requester = ?2 AND addressee = ?1)`,
  )
    .bind(me.id, otherId)
    .run();
  return json({ ok: true });
}

// Сохранить свою публичную проекцию библиотеки (перезаписью).
async function putLibrary(request, env, me) {
  if (!(await rateLimit(env, `pub:${me.id}`, 300, 60 * 60 * 1000))) return err('rate_limited', 429);
  const raw = await request.text();
  if (raw.length > 1024 * 1024) return err('too_large', 413); // ≤ 1 МБ
  try {
    JSON.parse(raw); // валидируем, что это JSON
  } catch {
    return err('bad_json');
  }
  await env.DB.prepare(
    `INSERT INTO library (user_id, data, updated_at) VALUES (?1, ?2, ?3)
     ON CONFLICT(user_id) DO UPDATE SET data = ?2, updated_at = ?3`,
  )
    .bind(me.id, raw, now())
    .run();
  return json({ ok: true, updatedAt: now() });
}

// Список друзей другого пользователя (соц-граф). Видно только его друзьям
// (или самому себе). Возвращает публичные профили его принятых друзей.
async function getUserFriends(env, me, userId) {
  if (me.id !== userId && !(await areFriends(env, me.id, userId))) {
    return err('not_friends', 403);
  }
  const rows = (
    await env.DB.prepare(
      `SELECT u.id, u.display_name, u.avatar_updated, u.banner_updated, u.friend_code
       FROM friendships f
       JOIN users u ON u.id = (CASE WHEN f.requester = ?1 THEN f.addressee ELSE f.requester END)
       WHERE (f.requester = ?1 OR f.addressee = ?1) AND f.status = 'accepted'`,
    )
      .bind(userId)
      .all()
  ).results;
  return json({
    friends: rows.map((r) => ({
      id: r.id,
      displayName: r.display_name,
      avatar: r.avatar_updated || 0,
      banner: r.banner_updated || 0,
      friendCode: r.friend_code,
    })),
  });
}

// Прочитать проекцию друга (только если дружба принята).
async function getFriendLibrary(env, me, friendId) {
  if (!(await areFriends(env, me.id, friendId))) return err('not_friends', 403);
  const row = await env.DB.prepare('SELECT data, updated_at FROM library WHERE user_id = ?')
    .bind(friendId)
    .first();
  if (!row) return json({ data: null, updatedAt: 0 });
  return new Response(
    JSON.stringify({ data: JSON.parse(row.data), updatedAt: row.updated_at }),
    { headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS } },
  );
}

// --------------------------- совместные списки ---------------------------

const isMember = async (env, listId, userId) =>
  !!(await env.DB.prepare(
    'SELECT 1 FROM shared_list_members WHERE list_id = ? AND user_id = ?',
  )
    .bind(listId, userId)
    .first());

async function createList(request, env, me) {
  if (!(await rateLimit(env, `mklist:${me.id}`, 60, 60 * 60 * 1000))) return err('rate_limited', 429);
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const name = String(body.name || '').trim();
  if (name.length < 1 || name.length > 60) return err('invalid_name');
  const id = crypto.randomUUID();
  const ts = now();
  await env.DB.prepare(
    'INSERT INTO shared_lists (id, name, owner, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
  )
    .bind(id, name, me.id, ts, ts)
    .run();
  await env.DB.prepare(
    'INSERT INTO shared_list_members (list_id, user_id, created_at) VALUES (?, ?, ?)',
  )
    .bind(id, me.id, ts)
    .run();
  return json({ id });
}

async function listSharedLists(env, me) {
  const rows = (
    await env.DB.prepare(
      `SELECT l.id, l.name, l.owner, l.updated_at,
              (SELECT COUNT(*) FROM shared_list_members m WHERE m.list_id = l.id) AS members,
              (SELECT COUNT(*) FROM shared_list_items i WHERE i.list_id = l.id) AS items
       FROM shared_lists l
       JOIN shared_list_members mm ON mm.list_id = l.id AND mm.user_id = ?1
       ORDER BY l.updated_at DESC`,
    )
      .bind(me.id)
      .all()
  ).results;
  return json({
    lists: rows.map((r) => ({
      id: r.id,
      name: r.name,
      owner: r.owner,
      members: r.members,
      items: r.items,
      updatedAt: r.updated_at,
    })),
  });
}

async function getList(env, me, listId) {
  if (!(await isMember(env, listId, me.id))) return err('not_member', 403);
  const list = await env.DB.prepare('SELECT * FROM shared_lists WHERE id = ?')
    .bind(listId)
    .first();
  if (!list) return err('not_found', 404);
  const members = (
    await env.DB.prepare(
      `SELECT u.id, u.display_name, u.avatar_updated, u.friend_code
       FROM shared_list_members m JOIN users u ON u.id = m.user_id
       WHERE m.list_id = ?`,
    )
      .bind(listId)
      .all()
  ).results.map((u) => ({
    id: u.id,
    displayName: u.display_name,
    avatar: u.avatar_updated || 0,
    friendCode: u.friend_code,
  }));
  const items = (
    await env.DB.prepare(
      'SELECT item_key, data, added_by, added_at FROM shared_list_items WHERE list_id = ? ORDER BY added_at DESC',
    )
      .bind(listId)
      .all()
  ).results.map((r) => ({
    key: r.item_key,
    addedBy: r.added_by,
    addedAt: r.added_at,
    ...JSON.parse(r.data),
  }));
  return json({
    list: { id: list.id, name: list.name, owner: list.owner },
    members,
    items,
  });
}

async function renameList(request, env, me, listId) {
  if (!(await isMember(env, listId, me.id))) return err('not_member', 403);
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const name = String(body.name || '').trim();
  if (name.length < 1 || name.length > 60) return err('invalid_name');
  await env.DB.prepare('UPDATE shared_lists SET name = ?, updated_at = ? WHERE id = ?')
    .bind(name, now(), listId)
    .run();
  return json({ ok: true });
}

// Владелец удаляет список целиком; остальные — выходят из него.
async function deleteOrLeaveList(env, me, listId) {
  const list = await env.DB.prepare('SELECT owner FROM shared_lists WHERE id = ?')
    .bind(listId)
    .first();
  if (!list) return err('not_found', 404);
  if (list.owner === me.id) {
    await env.DB.prepare('DELETE FROM shared_list_items WHERE list_id = ?').bind(listId).run();
    await env.DB.prepare('DELETE FROM shared_list_members WHERE list_id = ?').bind(listId).run();
    await env.DB.prepare('DELETE FROM shared_lists WHERE id = ?').bind(listId).run();
    return json({ ok: true, deleted: true });
  }
  await env.DB.prepare('DELETE FROM shared_list_members WHERE list_id = ? AND user_id = ?')
    .bind(listId, me.id)
    .run();
  return json({ ok: true, left: true });
}

async function addListItem(request, env, me, listId) {
  if (!(await rateLimit(env, `additem:${me.id}`, 300, 60 * 60 * 1000))) return err('rate_limited', 429);
  if (!(await isMember(env, listId, me.id))) return err('not_member', 403);
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const key = String(body.key || '').trim();
  if (!key) return err('bad_item');
  const data = JSON.stringify({
    title: String(body.title || ''),
    year: body.year ?? null,
    posterUrl: body.posterUrl ?? null,
    tmdbId: body.tmdbId ?? null,
  });
  const ts = now();
  await env.DB.prepare(
    `INSERT INTO shared_list_items (list_id, item_key, data, added_by, added_at) VALUES (?1, ?2, ?3, ?4, ?5)
     ON CONFLICT(list_id, item_key) DO UPDATE SET data = ?3`,
  )
    .bind(listId, key, data, me.id, ts)
    .run();
  await env.DB.prepare('UPDATE shared_lists SET updated_at = ? WHERE id = ?').bind(ts, listId).run();
  return json({ ok: true });
}

async function removeListItem(env, me, listId, key) {
  if (!(await isMember(env, listId, me.id))) return err('not_member', 403);
  await env.DB.prepare('DELETE FROM shared_list_items WHERE list_id = ? AND item_key = ?')
    .bind(listId, key)
    .run();
  await env.DB.prepare('UPDATE shared_lists SET updated_at = ? WHERE id = ?').bind(now(), listId).run();
  return json({ ok: true });
}

// Пригласить друга (по коду или id) в список — любой участник.
async function addListMember(request, env, me, listId) {
  if (!(await isMember(env, listId, me.id))) return err('not_member', 403);
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  let target = null;
  if (body.code) target = await getUserByCode(env, String(body.code).trim().toUpperCase());
  else if (body.userId) target = await getUserById(env, String(body.userId));
  if (!target) return err('user_not_found', 404);
  await env.DB.prepare(
    'INSERT OR IGNORE INTO shared_list_members (list_id, user_id, created_at) VALUES (?, ?, ?)',
  )
    .bind(listId, target.id, now())
    .run();
  return json({ ok: true, member: publicUser(target) });
}

// ----------------------------- «Советую тебе» -----------------------------

// Отправить рекомендацию фильма другу (только между друзьями).
async function sendRecommendation(request, env, me) {
  if (!(await rateLimit(env, `rec:${me.id}`, 120, 60 * 60 * 1000))) return err('rate_limited', 429);
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const to = String(body.toUserId || '');
  if (!to || to === me.id) return err('bad_target');
  if (!(await areFriends(env, me.id, to))) return err('not_friends', 403);
  const data = JSON.stringify({
    title: String(body.title || ''),
    year: body.year ?? null,
    posterUrl: body.posterUrl ?? null,
    tmdbId: body.tmdbId ?? null,
  });
  const note = body.note ? String(body.note).slice(0, 300) : null;
  await env.DB.prepare(
    'INSERT INTO recommendations (id, from_user, to_user, data, note, created_at) VALUES (?, ?, ?, ?, ?, ?)',
  )
    .bind(crypto.randomUUID(), me.id, to, data, note, now())
    .run();
  return json({ ok: true });
}

// Рекомендации, присланные МНЕ (с профилем отправителя), новые сверху.
async function listRecommendations(env, me) {
  const rows = (
    await env.DB.prepare(
      `SELECT r.id, r.data, r.note, r.created_at,
              u.id AS from_id, u.display_name, u.avatar_updated, u.friend_code
       FROM recommendations r JOIN users u ON u.id = r.from_user
       WHERE r.to_user = ? ORDER BY r.created_at DESC`,
    )
      .bind(me.id)
      .all()
  ).results;
  return json({
    recommendations: rows.map((r) => ({
      id: r.id,
      note: r.note,
      createdAt: r.created_at,
      from: {
        id: r.from_id,
        displayName: r.display_name,
        avatar: r.avatar_updated || 0,
        friendCode: r.friend_code,
      },
      ...JSON.parse(r.data),
    })),
  });
}

// Убрать рекомендацию (только получатель).
async function dismissRecommendation(env, me, id) {
  await env.DB.prepare('DELETE FROM recommendations WHERE id = ? AND to_user = ?')
    .bind(id, me.id)
    .run();
  return json({ ok: true });
}

// «Посмотрел с другом»: отправитель шлёт совместный просмотр другу. Устройство
// друга заберёт его (GET /cowatches), добавит к себе и удалит (DELETE).
async function sendCoWatch(request, env, me) {
  if (!(await rateLimit(env, `cw:${me.id}`, 120, 60 * 60 * 1000))) return err('rate_limited', 429);
  let body;
  try {
    body = await request.json();
  } catch {
    return err('bad_json');
  }
  const to = String(body.toUserId || '');
  if (!to || to === me.id) return err('bad_target');
  if (!(await areFriends(env, me.id, to))) return err('not_friends', 403);
  const kind = body.kind === 'series' ? 'series' : 'movie';
  const data = JSON.stringify({
    kind,
    title: String(body.title || ''),
    origTitle: body.origTitle ?? null,
    year: body.year ?? null,
    tmdbId: body.tmdbId ?? null,
    posterUrl: body.posterUrl ?? null,
    watchedAt: body.watchedAt ?? null, // ms epoch или null («неизвестно»)
    episodes: Array.isArray(body.episodes) ? body.episodes.slice(0, 500) : null,
  });
  await env.DB.prepare(
    'INSERT INTO co_watches (id, from_user, to_user, data, created_at) VALUES (?, ?, ?, ?, ?)',
  )
    .bind(crypto.randomUUID(), me.id, to, data, now())
    .run();
  return json({ ok: true });
}

// Совместные просмотры, присланные МНЕ (с профилем отправителя), старые сверху
// (обрабатываются по порядку).
async function listCoWatches(env, me) {
  const rows = (
    await env.DB.prepare(
      `SELECT c.id, c.data, c.created_at,
              u.id AS from_id, u.display_name, u.avatar_updated, u.banner_updated, u.friend_code
       FROM co_watches c JOIN users u ON u.id = c.from_user
       WHERE c.to_user = ? ORDER BY c.created_at ASC`,
    )
      .bind(me.id)
      .all()
  ).results;
  return json({
    coWatches: rows.map((r) => ({
      id: r.id,
      createdAt: r.created_at,
      from: {
        id: r.from_id,
        displayName: r.display_name,
        avatar: r.avatar_updated || 0,
        banner: r.banner_updated || 0,
        friendCode: r.friend_code,
      },
      ...JSON.parse(r.data),
    })),
  });
}

// Убрать совместный просмотр (после того как получатель добавил его к себе).
async function dismissCoWatch(env, me, id) {
  await env.DB.prepare('DELETE FROM co_watches WHERE id = ? AND to_user = ?')
    .bind(id, me.id)
    .run();
  return json({ ok: true });
}

// ------------------------------- роутинг -------------------------------

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });
    const url = new URL(request.url);
    const path = url.pathname;
    const method = request.method;

    try {
      if (path === '/health') return json({ ok: true });
      if (path === '/auth/register' && method === 'POST') return register(request, env);
      if (path === '/auth/login' && method === 'POST') return login(request, env);
      if (path === '/auth/reset' && method === 'POST') return resetPassword(request, env);

      // Публичная отдача аватара (без токена — картинка не секрет).
      const avaMatch = path.match(/^\/avatars\/([^/?]+)$/);
      if (avaMatch && method === 'GET') return getAvatar(env, decodeURIComponent(avaMatch[1]));

      // Публичная отдача баннера профиля (без токена).
      const banMatch = path.match(/^\/banners\/([^/?]+)$/);
      if (banMatch && method === 'GET') return getBanner(env, decodeURIComponent(banMatch[1]));

      // Дальше — только с валидным токеном.
      const me = await authenticate(request, env);
      if (!me) return err('unauthorized', 401);

      if (path === '/auth/logout' && method === 'POST') return logout(request, env);
      if (path === '/me' && method === 'GET') return json({ user: selfUser(me) });
      if (path === '/me' && method === 'PATCH') return updateMe(request, env, me);
      if (path === '/me/avatar' && method === 'PUT') return uploadAvatar(request, env, me);
      if (path === '/me/banner' && method === 'PUT') return uploadBanner(request, env, me);
      if (path === '/me/banner' && method === 'DELETE') return deleteBanner(env, me);
      if (path === '/me/recovery' && method === 'POST') return regenerateRecovery(env, me);

      if (path === '/friends' && method === 'GET') return listFriends(env, me);
      if (path === '/friends/request' && method === 'POST') return requestFriend(request, env, me);
      if (path === '/friends/respond' && method === 'POST') return respondFriend(request, env, me);

      if (path === '/library' && method === 'PUT') return putLibrary(request, env, me);

      const libMatch = path.match(/^\/friends\/([^/]+)\/library$/);
      if (libMatch && method === 'GET') return getFriendLibrary(env, me, decodeURIComponent(libMatch[1]));

      const frMatch = path.match(/^\/friends\/([^/]+)\/friends$/);
      if (frMatch && method === 'GET') return getUserFriends(env, me, decodeURIComponent(frMatch[1]));

      const delMatch = path.match(/^\/friends\/([^/]+)$/);
      if (delMatch && method === 'DELETE') return removeFriend(env, me, decodeURIComponent(delMatch[1]));

      // --- рекомендации «советую тебе» ---
      if (path === '/recommend' && method === 'POST') return sendRecommendation(request, env, me);
      if (path === '/recommendations' && method === 'GET') return listRecommendations(env, me);
      const recMatch = path.match(/^\/recommendations\/([^/]+)$/);
      if (recMatch && method === 'DELETE') return dismissRecommendation(env, me, decodeURIComponent(recMatch[1]));

      // --- «посмотрел с другом» (совместные просмотры) ---
      if (path === '/cowatch' && method === 'POST') return sendCoWatch(request, env, me);
      if (path === '/cowatches' && method === 'GET') return listCoWatches(env, me);
      const cwMatch = path.match(/^\/cowatches\/([^/]+)$/);
      if (cwMatch && method === 'DELETE') return dismissCoWatch(env, me, decodeURIComponent(cwMatch[1]));

      // --- совместные списки ---
      if (path === '/lists' && method === 'POST') return createList(request, env, me);
      if (path === '/lists' && method === 'GET') return listSharedLists(env, me);
      const itemMatch = path.match(/^\/lists\/([^/]+)\/items\/([^/]+)$/);
      if (itemMatch && method === 'DELETE') {
        return removeListItem(env, me, decodeURIComponent(itemMatch[1]), decodeURIComponent(itemMatch[2]));
      }
      const itemsMatch = path.match(/^\/lists\/([^/]+)\/items$/);
      if (itemsMatch && method === 'POST') return addListItem(request, env, me, decodeURIComponent(itemsMatch[1]));
      const memMatch = path.match(/^\/lists\/([^/]+)\/members$/);
      if (memMatch && method === 'POST') return addListMember(request, env, me, decodeURIComponent(memMatch[1]));
      const listMatch = path.match(/^\/lists\/([^/]+)$/);
      if (listMatch) {
        const lid = decodeURIComponent(listMatch[1]);
        if (method === 'GET') return getList(env, me, lid);
        if (method === 'PATCH') return renameList(request, env, me, lid);
        if (method === 'DELETE') return deleteOrLeaveList(env, me, lid);
      }

      return err('not_found', 404);
    } catch (e) {
      return err(`server_error: ${e && e.message ? e.message : e}`, 500);
    }
  },

  // Периодическая уборка (cron): просроченные сессии и старые счётчики лимитов.
  async scheduled(event, env, ctx) {
    const ts = Date.now();
    await env.DB.prepare('DELETE FROM tokens WHERE expires_at < ?').bind(ts).run();
    await env.DB.prepare('DELETE FROM rate_limits WHERE window_start < ?')
      .bind(ts - 24 * 60 * 60 * 1000)
      .run();
  },
};
