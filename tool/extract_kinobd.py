#!/usr/bin/env python3
"""Извлекает из DLE-дампа KinoBD компактный индекс {kp, foreign, russian, year,
poster} и матчит его с библиотекой Kadr. Дамп НЕ попадает в приложение —
используется один раз здесь для оффлайн-обогащения (обход лимита 200/сутки)."""
import re, json, os, collections

DUMP = "/tmp/claude-1000/-home-alelx/770fa471-7a17-42c2-ac80-24fc84c3cf24/scratchpad/kinobd/dle_kinobd_dump.sql"
LIB = "/home/alelx/Projects/GitHub/Kadr/assets/seed/library.json"
OUT_INDEX = "/tmp/claude-1000/-home-alelx/770fa471-7a17-42c2-ac80-24fc84c3cf24/scratchpad/kinobd_index.json"

print("читаю дамп (~400МБ)...")
with open(DUMP, 'r', encoding='utf-8', errors='replace') as f:
    data = f.read()
print(f"прочитано {len(data)//1024//1024} МБ, извлекаю фильмы...")

def field(window, key):
    m = re.search(re.escape(key) + r'\|([^|]*)', window)
    return m.group(1).strip() if m else None

index = {}   # kp -> {foreign, russian, year, poster}
for m in re.finditer(r'kp\|(\d+)', data):
    kp = m.group(1)
    if kp in index:
        continue
    s = m.start()
    w = data[max(0, s - 1800): s + 400]
    foreign = field(w, 'name_foreign')
    russian = field(w, 'name_russian')
    year = field(w, 'year')
    poster = field(w, 'poster_big') or field(w, 'poster_sm')
    yr = int(year) if (year or '').isdigit() else None
    index[kp] = {'kp': int(kp), 'foreign': foreign, 'russian': russian,
                 'year': yr, 'poster': poster}
print(f"фильмов в индексе: {len(index)}")

# индексы для матчинга
def norm(s):
    if not s: return ''
    s = s.lower().strip()
    s = re.sub(r'[^\w\s]', ' ', s, flags=re.UNICODE)
    return re.sub(r'\s+', ' ', s).strip()

by_foreign = collections.defaultdict(list)
by_russian = collections.defaultdict(list)
for e in index.values():
    if e['foreign']: by_foreign[norm(e['foreign'])].append(e)
    if e['russian']: by_russian[norm(e['russian'])].append(e)

json.dump(list(index.values()), open(OUT_INDEX, 'w', encoding='utf-8'),
          ensure_ascii=False)
print(f"индекс сохранён: {OUT_INDEX} ({os.path.getsize(OUT_INDEX)//1024//1024} МБ)")

# --- матчим библиотеку ---
lib = json.load(open(LIB, encoding='utf-8'))
movies = lib['movies']

def match(title, year):
    cands = by_foreign.get(norm(title)) or by_russian.get(norm(title))
    if not cands: return None
    if year is not None:
        for e in cands:
            if e['year'] is not None and abs(e['year'] - year) <= 1:
                return e
    return cands[0]

matched = 0
matched_examples = []
for mv in movies:
    e = match(mv['title'], mv.get('year'))
    if e:
        matched += 1
        if len(matched_examples) < 12 and e['russian']:
            matched_examples.append((mv['title'], e['russian'], e['kp'], e['year']))

print(f"\n=== ПОКРЫТИЕ: {matched} / {len(movies)} фильмов сматчено с дампом "
      f"({100*matched//len(movies)}%) ===")
print("примеры совпадений (наше → русское, kp_id):")
for t, r, kp, y in matched_examples:
    print(f"  {t[:30]:30} -> {r}  (kp={kp}, {y})")
