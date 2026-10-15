import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../l10n/locale_controller.dart';
import '../models/youtube.dart';

/// Что указывает ссылка: ролик, плейлист или оба сразу.
class YtLink {
  final String? videoId;
  final String? playlistId;
  const YtLink({this.videoId, this.playlistId});
}

/// Ролик по данным сайта.
class YtVideoInfo {
  final String id;
  final String title;
  final String channelId;
  final String channelName;
  final int? durSec;
  final DateTime? published;

  /// Самый крупный кадр, какой есть у ролика.
  final String? thumb;
  const YtVideoInfo({
    required this.id,
    required this.title,
    required this.channelId,
    required this.channelName,
    this.durSec,
    this.published,
    this.thumb,
  });

  YtEntry toEntry() => YtEntry(
      id: id, title: title, durSec: durSec, published: published);
}

/// Плейлист по данным сайта: название, канал и ролики по порядку.
class YtPlaylistInfo {
  final String id;
  final String title;
  final String channelId;
  final String channelName;
  final String? avatar;
  final List<YtEntry> videos;
  const YtPlaylistInfo({
    required this.id,
    required this.title,
    required this.channelId,
    required this.channelName,
    required this.videos,
    this.avatar,
  });
}

/// Запись ленты плейлиста (RSS).
class YtFeedItem {
  final String id;
  final String title;
  final DateTime? published;
  const YtFeedItem({required this.id, required this.title, this.published});
}

/// Что нашлось по ссылке: цикл (плейлист) и/или сам ролик. Цикла нет —
/// ролик живёт фильмом.
class YtFound {
  final YtPlaylistInfo? cycle;
  final YtVideoInfo? video;
  const YtFound({this.cycle, this.video});
}

/// Ролики и плейлисты YouTube без ключей Google и без входа: открытые
/// адреса веб-версии сайта (youtubei) и лента плейлиста RSS.
///
/// Цикл ищется так: у ролика с номером в названии («Абсолют Флэш №1») Kadr
/// открывает вкладку «Плейлисты» его канала, берёт плейлисты с теми же
/// словами в названии и проверяет, что ролик действительно в плейлисте.
class YouTubeService {
  YouTubeService._();

  static const _api = 'https://www.youtube.com/youtubei/v1';
  static const _ua =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Safari/537.36';

  // ------------------------------ ссылка ------------------------------

  static final _url = RegExp(
    r'https?://(?:www\.|m\.|music\.)?(?:youtube\.com|youtu\.be)/[^\s<>"]*',
    caseSensitive: false,
  );
  static final _id = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Ссылка на YouTube в тексте (из поиска или «Поделиться»). null — ссылки
  /// нет.
  static YtLink? parseLink(String text) {
    final m = _url.firstMatch(text);
    if (m == null) return null;
    final uri = Uri.tryParse(m.group(0)!);
    if (uri == null) return null;
    String? video;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (uri.host.toLowerCase().contains('youtu.be')) {
      if (segs.isNotEmpty) video = segs.first;
    } else if (segs.isNotEmpty &&
        const {'shorts', 'live', 'embed', 'v'}.contains(segs.first) &&
        segs.length > 1) {
      video = segs[1];
    } else {
      video = uri.queryParameters['v'];
    }
    if (video != null && !_id.hasMatch(video)) video = null;
    final list = uri.queryParameters['list'];
    final playlist =
        list != null && RegExp(r'^[A-Za-z0-9_-]{10,}$').hasMatch(list)
            ? list
            : null;
    if (video == null && playlist == null) return null;
    return YtLink(videoId: video, playlistId: playlist);
  }

  // ------------------------------ разбор ------------------------------

  /// Все значения ключа [key] в дереве ответа, по порядку обхода.
  static List<dynamic> _all(dynamic node, String key) {
    final out = <dynamic>[];
    void walk(dynamic o) {
      if (o is Map) {
        for (final e in o.entries) {
          if (e.key == key) out.add(e.value);
          walk(e.value);
        }
      } else if (o is List) {
        for (final v in o) {
          walk(v);
        }
      }
    }

    walk(node);
    return out;
  }

  static String _text(dynamic t) {
    if (t is String) return t;
    if (t is Map) {
      final s = t['simpleText'] ?? t['content'];
      if (s is String) return s;
      final runs = t['runs'];
      if (runs is List) return runs.map((r) => (r as Map)['text'] ?? '').join();
    }
    return '';
  }

  /// «23:58» или «1:02:03» в секундах.
  static int? parseClock(String s) {
    final parts = s.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    var sec = 0;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      sec = sec * 60 + n;
    }
    return sec;
  }

  /// Ролик из ответа `player`.
  static YtVideoInfo? parsePlayer(Map<String, dynamic> j) {
    final d = j['videoDetails'];
    if (d is! Map || d['videoId'] == null) return null;
    final thumbs = (d['thumbnail'] as Map?)?['thumbnails'] as List? ?? const [];
    String? best;
    num width = -1;
    for (final t in thumbs) {
      final w = (t as Map)['width'] as num? ?? 0;
      if (w > width) {
        width = w;
        best = t['url'] as String?;
      }
    }
    final mf = _all(j, 'playerMicroformatRenderer');
    final date = mf.isEmpty
        ? null
        : DateTime.tryParse('${(mf.first as Map)['publishDate'] ?? ''}');
    return YtVideoInfo(
      id: '${d['videoId']}',
      title: '${d['title'] ?? ''}',
      channelId: '${d['channelId'] ?? ''}',
      channelName: '${d['author'] ?? ''}',
      durSec: int.tryParse('${d['lengthSeconds'] ?? ''}'),
      published: date,
      thumb: best?.split('?').first,
    );
  }

  /// Плейлист из ответа `next` с playlistId: панель плейлиста и владелец.
  static YtPlaylistInfo? parseNext(Map<String, dynamic> j) {
    Map? list;
    for (final p in _all(j, 'playlist')) {
      if (p is Map && p['playlistId'] != null) {
        list = p;
        break;
      }
    }
    if (list == null) return null;
    final videos = <YtEntry>[];
    final seen = <String>{};
    for (final it in _all(list, 'playlistPanelVideoRenderer')) {
      if (it is! Map || it['videoId'] == null) continue;
      final id = '${it['videoId']}';
      if (!seen.add(id)) continue;
      videos.add(YtEntry(
        id: id,
        title: _text(it['title']),
        durSec: parseClock(_text(it['lengthText'])),
      ));
    }
    String channelId = '';
    String channelName = _text(list['ownerName']);
    String? avatar;
    final owners = _all(j, 'videoOwnerRenderer');
    if (owners.isNotEmpty && owners.first is Map) {
      final o = owners.first as Map;
      channelId =
          '${(o['navigationEndpoint'] as Map?)?['browseEndpoint']?['browseId'] ?? ''}';
      if (channelName.isEmpty) channelName = _text(o['title']);
      final th = (o['thumbnail'] as Map?)?['thumbnails'] as List?;
      if (th != null && th.isNotEmpty) avatar = (th.last as Map)['url'] as String?;
    }
    return YtPlaylistInfo(
      id: '${list['playlistId']}',
      title: _text(list['title']),
      channelId: channelId,
      channelName: channelName,
      avatar: avatar,
      videos: videos,
    );
  }

  /// Параметр вкладки «Плейлисты» из ответа `browse` канала.
  static String? parsePlaylistsTab(Map<String, dynamic> j) {
    for (final t in _all(j, 'tabRenderer')) {
      if (t is! Map) continue;
      final ep = (t['endpoint'] as Map?)?['browseEndpoint'] as Map?;
      final params = ep?['params'] as String?;
      if (params == null) continue;
      // Вкладку узнаём по параметру: в нём закодировано слово «playlists».
      if (_decodeParams(params).contains('playlists')) return params;
    }
    return null;
  }

  static String _decodeParams(String params) {
    try {
      final raw = Uri.decodeComponent(params)
          .replaceAll('=', '')
          .replaceAll('+', '-')
          .replaceAll('/', '_');
      return utf8.decode(base64Url.decode(base64Url.normalize(raw)),
          allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  /// Плейлисты канала из ответа `browse` вкладки «Плейлисты».
  static List<({String id, String title})> parseChannelPlaylists(
      Map<String, dynamic> j) {
    final out = <({String id, String title})>[];
    final seen = <String>{};
    for (final l in _all(j, 'lockupViewModel')) {
      if (l is! Map) continue;
      if (l['contentType'] != 'LOCKUP_CONTENT_TYPE_PLAYLIST') continue;
      final id = '${l['contentId'] ?? ''}';
      if (id.isEmpty || !seen.add(id)) continue;
      final title = _text(
          ((l['metadata'] as Map?)?['lockupMetadataViewModel'] as Map?)?['title']);
      out.add((id: id, title: title));
    }
    // Старая разметка сайта.
    for (final g in _all(j, 'gridPlaylistRenderer')) {
      if (g is! Map || g['playlistId'] == null) continue;
      final id = '${g['playlistId']}';
      if (seen.add(id)) out.add((id: id, title: _text(g['title'])));
    }
    return out;
  }

  /// Записи ленты плейлиста RSS, свежие первыми.
  static List<YtFeedItem> parseFeed(String xml) {
    try {
      final doc = XmlDocument.parse(xml);
      return [
        for (final e in doc.findAllElements('entry'))
          if (_child(e, 'videoId') != null)
            YtFeedItem(
              id: _child(e, 'videoId')!,
              title: _child(e, 'title') ?? '',
              published: DateTime.tryParse(_child(e, 'published') ?? ''),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String? _child(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (c.name.local == local) return c.innerText.trim();
    }
    return null;
  }

  // ------------------------------ сеть ------------------------------

  static Map<String, dynamic> _context() => {
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20250101.00.00',
            'hl': LocaleController.instance.code,
          },
        },
      };

  static Future<Map<String, dynamic>?> _post(
      String path, Map<String, dynamic> body) async {
    try {
      final r = await http
          .post(
            Uri.parse('$_api/$path?prettyPrint=false'),
            headers: {'Content-Type': 'application/json', 'User-Agent': _ua},
            body: jsonEncode({..._context(), ...body}),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : null;
    } catch (e) {
      debugPrint('youtube $path: $e');
      return null;
    }
  }

  /// Ролик по id.
  static Future<YtVideoInfo?> video(String id) async {
    final j = await _post('player', {'videoId': id});
    return j == null ? null : parsePlayer(j);
  }

  /// Плейлист по id: ролики по порядку, канал и аватар.
  static Future<YtPlaylistInfo?> playlist(String id) async {
    final j = await _post('next', {'playlistId': id});
    final p = j == null ? null : parseNext(j);
    return p == null || p.videos.isEmpty ? null : p;
  }

  /// Плейлисты канала: вкладка «Плейлисты», первая страница.
  static Future<List<({String id, String title})>> channelPlaylists(
      String channelId) async {
    final ch = await _post('browse', {'browseId': channelId});
    final params = ch == null ? null : parsePlaylistsTab(ch);
    if (params == null) return const [];
    final tab =
        await _post('browse', {'browseId': channelId, 'params': params});
    return tab == null ? const [] : parseChannelPlaylists(tab);
  }

  /// Лента RSS: у плейлиста это первые 15 его роликов, у канала — 15
  /// свежих загрузок. Обе с датами выхода.
  static Future<List<YtFeedItem>> feed(
      {String? playlistId, String? channelId}) async {
    final q = playlistId != null
        ? 'playlist_id=$playlistId'
        : 'channel_id=$channelId';
    try {
      final r = await http.get(
        Uri.parse('https://www.youtube.com/feeds/videos.xml?$q'),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const [];
      return parseFeed(utf8.decode(r.bodyBytes));
    } catch (e) {
      debugPrint('youtube feed: $e');
      return const [];
    }
  }

  /// Плейлист цикла для ролика [v]: на канале ищутся плейлисты с теми же
  /// словами, что в названии до номера, и проверяется, что ролик в нём.
  static Future<YtPlaylistInfo?> findCycle(YtVideoInfo v) async {
    final name = ytCycleName(v.title);
    if (name == null || v.channelId.isEmpty) return null;
    final words = ytWords(name);
    final lists = await channelPlaylists(v.channelId);
    final ranked = [
      for (final l in lists)
        if (ytWords(l.title).containsAll(words))
          (l: l, score: words.length / ytWords(l.title).length),
    ]..sort((a, b) => b.score.compareTo(a.score));
    for (final c in ranked.take(3)) {
      final p = await playlist(c.l.id);
      if (p != null && p.videos.any((e) => e.id == v.id)) return p;
    }
    return null;
  }

  /// Ставит выпускам цикла даты из лент: у плейлиста первые 15 роликов, у
  /// канала 15 свежих. Остальные дозаполняет [fillDates].
  static Future<void> _datesFromFeed(YtPlaylistInfo p) async {
    final items = [
      ...await feed(playlistId: p.id),
      if (p.channelId.isNotEmpty) ...await feed(channelId: p.channelId),
    ];
    final byId = {for (final i in items) i.id: i};
    for (final v in p.videos) {
      v.published ??= byId[v.id]?.published;
    }
  }

  /// Что за ссылкой: цикл (плейлист) и ролик. Ролик без номера и без
  /// плейлиста в ссылке — просто ролик, его добавляют фильмом.
  static Future<YtFound?> resolve(YtLink link) async {
    final v = link.videoId == null ? null : await video(link.videoId!);
    YtPlaylistInfo? cycle;
    if (link.playlistId != null) {
      cycle = await playlist(link.playlistId!);
    } else if (v != null && ytIssueNumber(v.title) != null) {
      cycle = await findCycle(v);
    }
    if (cycle != null) await _datesFromFeed(cycle);
    if (cycle == null && v == null) return null;
    return YtFound(cycle: cycle, video: v);
  }

  /// Слова, по которым ролик канала узнаётся как выпуск цикла: название до
  /// номера у первого выпуска, иначе название плейлиста.
  static Set<String> cycleWords(YtCycle cycle, String playlistTitle) {
    for (final v in cycle.videos) {
      final name = ytCycleName(v.title);
      if (name != null) return ytWords(name);
    }
    return ytWords(playlistTitle);
  }

  /// Новые выпуски цикла: те, которых в нём ещё нет, по порядку плейлиста.
  ///
  /// Лента плейлиста отдаёт его первые 15 роликов, поэтому свежие ролики
  /// берутся из ленты канала: похожий по названию ролик — повод открыть
  /// плейлист и сверить. Раз в неделю ([fullEvery]) плейлист открывается и
  /// без повода. null — плейлист не открывали (повода нет или сеть не
  /// ответила), пусто — открыли, новых нет.
  static Future<List<YtEntry>?> newVideos(YtCycle cycle, String title,
      {Duration fullEvery = const Duration(days: 7)}) async {
    final known = {for (final v in cycle.videos) v.id};
    final latest = cycle.channelId.isEmpty
        ? const <YtFeedItem>[]
        : await feed(channelId: cycle.channelId);
    final words = cycleWords(cycle, title);
    final hint = latest.any((i) =>
        !known.contains(i.id) && ytWords(i.title).containsAll(words));
    final last = cycle.checkedAt;
    final due = last == null || DateTime.now().difference(last) >= fullEvery;
    if (!hint && !due) return null;
    final p = await playlist(cycle.playlistId);
    if (p == null) return null;
    final dates = {for (final i in latest) i.id: i.published};
    return [
      for (final v in p.videos)
        if (!known.contains(v.id))
          v..published ??= dates[v.id],
    ];
  }

  /// Дозаполняет даты выхода выпускам без даты: по ролику на запрос, не
  /// больше [limit] за раз.
  static Future<int> fillDates(List<YtEntry> videos, {int limit = 30}) async {
    var n = 0;
    for (final v in videos) {
      if (n >= limit) break;
      if (v.published != null) continue;
      n++;
      final info = await video(v.id);
      if (info == null) continue;
      v.published = info.published;
      v.durSec ??= info.durSec;
    }
    return n;
  }
}
