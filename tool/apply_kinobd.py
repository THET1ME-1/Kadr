#!/usr/bin/env python3
"""Оффлайн-обогащение сида Kadr из индекса KinoBD: kp_id + русское название +
постер (по kp_id со статичного CDN Кинопоиска, бесплатно и без лимита).
Строгий матчинг по (оригинальное название, год ±1). Дамп в приложение НЕ идёт."""
import json, re, collections, shutil

IDX = "/tmp/claude-1000/-home-alelx/770fa471-7a17-42c2-ac80-24fc84c3cf24/scratchpad/kinobd_index.json"
LIB = "/home/alelx/Projects/GitHub/Kadr/assets/seed/library.json"

def poster_url(kp):
    return f"https://st.kp.yandex.net/images/film_iphone/iphone360_{kp}.jpg"

def norm(s):
    if not s: return ''
    s = s.lower().strip()
    s = re.sub(r'[^\w\s]', ' ', s, flags=re.UNICODE)
    return re.sub(r'\s+', ' ', s).strip()

idx = json.load(open(IDX, encoding='utf-8'))
by_f = collections.defaultdict(list)
by_r = collections.defaultdict(list)
for e in idx:
    if e['foreign']: by_f[norm(e['foreign'])].append(e)
    if e['russian']: by_r[norm(e['russian'])].append(e)

def match(title, year):
    cands = by_f.get(norm(title)) or by_r.get(norm(title))
    if not cands: return None
    if year is None:
        return cands[0] if len(cands) == 1 else None
    for e in cands:
        if e['year'] is not None and abs(e['year'] - year) <= 1:
            return e
    return None

shutil.copy(LIB, LIB + '.bak')
lib = json.load(open(LIB, encoding='utf-8'))

n_kp = n_ru = n_poster = 0
for mv in lib['movies']:
    if mv.get('kinopoiskId'):
        continue
    e = match(mv['title'], mv.get('year'))
    if not e:
        continue
    mv['kinopoiskId'] = e['kp']
    mv['posterUrl'] = poster_url(e['kp'])
    mv['enrichTried'] = True
    n_kp += 1
    n_poster += 1
    if e['russian'] and norm(e['russian']) != norm(mv['title']):
        mv['ruTitle'] = e['russian']
        n_ru += 1

# версия сида — чтобы приложение подхватило обогащение при обновлении
lib.setdefault('meta', {})['seedVersion'] = 4
json.dump(lib, open(LIB, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

print(f"обогащено из дампа: kp_id={n_kp}, русских названий={n_ru}, постеров={n_poster}")
print(f"осталось без kp_id (уйдёт в kinopoisk.dev API): "
      f"{sum(1 for m in lib['movies'] if not m.get('kinopoiskId'))}")
print("примеры:")
for mv in lib['movies'][:14]:
    if mv.get('kinopoiskId'):
        print(f"  {mv['title'][:26]:26} -> {mv.get('ruTitle') or mv['title']}  kp={mv['kinopoiskId']}")
