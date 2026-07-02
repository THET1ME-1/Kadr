#!/usr/bin/env python3
"""Импорт GDPR-экспорта TV Time → kadr_import.json (модель данных Kadr).

Полностью офлайн: названия/годы/хронометраж/даты/эмоции/списки/отзывы берутся из
экспорта. Постеры и kinopoisk-id дотягиваются приложением лениво по названию+году.
"""
import csv, os, json, re, collections

SP = "/tmp/claude-1000/-home-alelx/770fa471-7a17-42c2-ac80-24fc84c3cf24/scratchpad/gdpr"
OUT = "/tmp/claude-1000/-home-alelx/770fa471-7a17-42c2-ac80-24fc84c3cf24/scratchpad/kadr_import.json"

def rows(n):
    p = os.path.join(SP, n)
    if not os.path.exists(p): return []
    return list(csv.DictReader(open(p, encoding='utf-8')))

# ---- Таблица «эмоция TV Time → стартовый балл 1..10» (выведена по тому, какие
# фильмы получили каждую реакцию; подлежит правке пользователем) ----
EMOTION = {
    '37': {'label': 'Понравилось', 'emoji': '😊', 'score': 7.5},
    '28': {'label': 'Отлично',     'emoji': '😍', 'score': 8.5},
    '33': {'label': 'Смешно',      'emoji': '😂', 'score': 7.5},
    '32': {'label': 'Эпично',      'emoji': '🤩', 'score': 8.0},
    '30': {'label': 'Тронуло',     'emoji': '🥹', 'score': 8.0},
    '39': {'label': 'Круто',       'emoji': '😎', 'score': 7.5},
    '31': {'label': 'Вынос мозга', 'emoji': '🤯', 'score': 8.5},
    '29': {'label': 'Напряжённо',  'emoji': '😬', 'score': 7.0},
    '35': {'label': 'Тревожно',    'emoji': '😰', 'score': 6.5},
    '34': {'label': 'Страшно',     'emoji': '😱', 'score': 6.5},
    '38': {'label': 'Тяжело',      'emoji': '😖', 'score': 6.0},
    '36': {'label': 'Неожиданно',  'emoji': '😮', 'score': 7.5},
}

def tail(vk, uid):
    s = vk.rsplit('-'+uid+'-', 1)
    return s[1] if len(s) == 2 else None

# ---------------------------- эмоции по uuid ----------------------------
emo_by_uuid = collections.defaultdict(list)
for r in rows("emotions-live-votes.csv"):
    eid = tail(r['vote_key'], r['user_id'])
    if eid: emo_by_uuid[r['uuid']].append(eid)

def score_from_emotions(eids):
    vals = [EMOTION[e]['score'] for e in eids if e in EMOTION]
    return round(sum(vals)/len(vals), 1) if vals else None

# ---------------------------- отзывы по названию ----------------------------
review_by_name = {}
for r in rows("comments-prod-comments.csv"):
    txt = (r.get('text') or '').strip()
    nm = r.get('movie_name') or r.get('series_name') or ''
    if txt and nm and nm not in review_by_name:
        review_by_name[nm] = txt

# ---------------------------- списки ----------------------------
lists_out = []
list_by_uuid = collections.defaultdict(list)
favorite_uuids = set()
for r in rows("lists-prod-lists.csv"):
    if r['type'] == 'list' and r['name']:
        uuids = re.findall(r'uuid:([0-9a-f-]{36})', r['objects'])
        lists_out.append({'name': r['name'], 'movieUuids': uuids,
                          'public': r.get('is_public') == 'true'})
        for u in uuids:
            list_by_uuid[u].append(r['name'])
        if 'favorite' in (r.get('s_key') or '').lower():
            favorite_uuids.update(uuids)

# ---------------------------- фильмы (tracking v1) ----------------------------
tv1 = rows("tracking-prod-records.csv")
movies = {}   # uuid -> record
for r in tv1:
    if r['entity_type'] != 'movie':
        continue
    u = r['uuid']
    m = movies.setdefault(u, {
        'uuid': u, 'title': r['movie_name'], 'year': None, 'runtimeMin': None,
        'watched': False, 'inWatchlist': False, 'viewings': [], 'rewatchCount': 0,
        'towatch_at': None, 'follow_at': None,
    })
    if not m['title']:
        m['title'] = r['movie_name']
    rel = (r.get('release_date') or '')[:4]
    if rel.isdigit():
        m['year'] = int(rel)
    rt = (r.get('runtime') or '').strip()
    if rt.isdigit() and int(rt) > 0:
        m['runtimeMin'] = round(int(rt) / 60)
    t = r['type']
    created = (r.get('created_at') or '').strip()
    if t in ('watch', 'rewatch'):
        m['watched'] = True
        if created:
            m['viewings'].append(created)
    elif t == 'towatch':
        m['inWatchlist'] = True
        if created:
            m['towatch_at'] = created
    elif t == 'follow':
        if created:
            m['follow_at'] = created
    rc = (r.get('rewatch_count') or '').strip()
    if rc.isdigit():
        m['rewatchCount'] = max(m['rewatchCount'], int(rc))

# обогащение фильмов
movie_list = []
for u, m in movies.items():
    eids = emo_by_uuid.get(u, [])
    m['viewings'] = sorted(set(m['viewings']))
    m['status'] = 'watched' if m['watched'] else ('watchlist' if m['inWatchlist'] else 'library')
    m['score'] = score_from_emotions(eids)
    m['emotions'] = [{'id': e, **EMOTION[e]} for e in eids if e in EMOTION]
    m['favorite'] = u in favorite_uuids
    m['lists'] = list_by_uuid.get(u, [])
    m['review'] = review_by_name.get(m['title'])
    # Дата добавления в список: towatch → когда добавил в «Буду смотреть»,
    # иначе follow → когда добавил в библиотеку.
    m['addedAt'] = m.get('towatch_at') or m.get('follow_at')
    for k in ('watched', 'inWatchlist', 'towatch_at', 'follow_at'):
        m.pop(k, None)
    movie_list.append(m)

# ---------------------------- сериалы (tracking v2) ----------------------------
utd = {r['tv_show_id']: r for r in rows("user_tv_show_data.csv")}
series = {}
for r in rows("tracking-prod-records-v2.csv"):
    name = (r.get('series_name') or '').strip()
    sid = (r.get('s_id') or '').strip()
    if not name:
        continue
    key = sid or name
    s = series.setdefault(key, {
        'tvShowId': sid, 'title': name, 'episodesSeen': 0, 'viewings': [],
    })
    created = (r.get('created_at') or '').strip()
    if (r.get('ep_id') or '').strip() and created:
        s['episodesSeen'] += 1
        s['viewings'].append(created)

series_list = []
for key, s in series.items():
    d = utd.get(s['tvShowId'], {})
    s['favorite'] = (d.get('is_favorited') == 'true')
    s['nbEpisodesSeen'] = int(d['nb_episodes_seen']) if (d.get('nb_episodes_seen') or '').isdigit() else s['episodesSeen']
    s['viewings'] = sorted(set(s['viewings']))
    s['firstWatch'] = s['viewings'][0] if s['viewings'] else None
    s['lastWatch'] = s['viewings'][-1] if s['viewings'] else None
    s['addedAt'] = s['firstWatch']
    s['review'] = review_by_name.get(s['title'])
    series_list.append(s)

# ---------------------------- сборка ----------------------------
watched = [m for m in movie_list if m['status'] == 'watched']
watchlist = [m for m in movie_list if m['status'] == 'watchlist']
data = {
    'meta': {
        'source': 'tvtime-gdpr',
        'emotionTable': EMOTION,
        'counts': {
            'movies': len(movie_list),
            'moviesWatched': len(watched),
            'moviesWatchlist': len(watchlist),
            'moviesRated': sum(1 for m in movie_list if m['score'] is not None),
            'movieViewings': sum(len(m['viewings']) for m in movie_list),
            'series': len(series_list),
            'seriesFavorite': sum(1 for s in series_list if s['favorite']),
            'episodeViewings': sum(len(s['viewings']) for s in series_list),
            'lists': len(lists_out),
            'reviews': len(review_by_name),
        },
    },
    'movies': sorted(movie_list, key=lambda m: (m['viewings'][-1] if m['viewings'] else ''), reverse=True),
    'series': sorted(series_list, key=lambda s: (s['lastWatch'] or ''), reverse=True),
    'lists': lists_out,
}
json.dump(data, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print("== kadr_import.json написан ==")
for k, v in data['meta']['counts'].items():
    print(f"  {k}: {v}")
print(f"\nфайл: {OUT}  ({os.path.getsize(OUT)//1024} КБ)")
print("\n-- примеры фильмов (свежие просмотры) --")
for m in data['movies'][:6]:
    em = ' '.join(e['emoji'] for e in m['emotions'])
    print(f"  {m['title'][:38]:38} {m['year']} · {m['runtimeMin']}м · балл={m['score']} {em} · просмотров={len(m['viewings'])}")
print("\n-- сериалы --")
for s in data['series'][:5]:
    print(f"  {s['title'][:38]:38} эп.={s['episodesSeen']} fav={s['favorite']} last={s['lastWatch']}")
