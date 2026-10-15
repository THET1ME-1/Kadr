// Ответы YouTube для тестов по образцу настоящих (канал Dev the Geek,
// плейлист «Абсолют Флэш»). Без суффикса `_test`: сам по себе не запускается.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> ytPlayer(String id, String title, {int len = 1754}) => {
      'videoDetails': {
        'videoId': id,
        'title': title,
        'lengthSeconds': '$len',
        'channelId': 'UCdev',
        'author': 'Dev the Geek',
        'thumbnail': {
          'thumbnails': [
            {'url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg', 'width': 480},
            {'url': 'https://i.ytimg.com/vi/$id/maxresdefault.jpg', 'width': 1920},
          ],
        },
      },
      'microformat': {
        'playerMicroformatRenderer': {'publishDate': '2025-04-14T06:00:32-07:00'},
      },
    };

Map<String, dynamic> ytPanelItem(
        String id, String index, String title, String length) =>
    {
      'playlistPanelVideoRenderer': {
        'videoId': id,
        'indexText': {'simpleText': index},
        'title': {'simpleText': title},
        'lengthText': {'simpleText': length},
      },
    };

Map<String, dynamic> ytNext(String listId, String title, List<Map> items) => {
      'contents': {
        'twoColumnWatchNextResults': {
          'results': {
            'results': {
              'contents': [
                {
                  'videoSecondaryInfoRenderer': {
                    'owner': {
                      'videoOwnerRenderer': {
                        'title': {
                          'runs': [
                            {'text': 'Dev the Geek'}
                          ]
                        },
                        'navigationEndpoint': {
                          'browseEndpoint': {'browseId': 'UCdev'}
                        },
                        'thumbnail': {
                          'thumbnails': [
                            {'url': 'https://yt3.ggpht.com/ava=s48'},
                            {'url': 'https://yt3.ggpht.com/ava=s176'},
                          ]
                        },
                      },
                    },
                  },
                },
              ],
            },
          },
          'playlist': {
            'playlist': {
              'title': title,
              'playlistId': listId,
              'totalVideos': items.length,
              'ownerName': {'simpleText': 'Dev the Geek'},
              'contents': items,
            },
          },
        },
      },
    };

Map<String, dynamic> ytLockup(String id, String type, String title) => {
      'lockupViewModel': {
        'contentId': id,
        'contentType': type,
        'metadata': {
          'lockupMetadataViewModel': {
            'title': {'content': title},
          },
        },
      },
    };

const ytChannelTabs = {
  'contents': {
    'twoColumnBrowseResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'title': 'Главная',
            'endpoint': {
              'browseEndpoint': {'browseId': 'UCdev', 'params': 'HOME'}
            },
          },
        },
        {
          'tabRenderer': {
            'title': 'Плейлисты',
            'endpoint': {
              'browseEndpoint': {
                'browseId': 'UCdev',
                'params': 'EglwbGF5bGlzdHPyBgoKCEIGCgIQaCIA',
                'canonicalBaseUrl': '/@DevtheGeek',
              }
            },
          },
        },
      ],
    },
  },
};

const ytFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns="http://www.w3.org/2005/Atom">
 <title>Абсолют Флэш</title>
 <entry>
  <yt:videoId>TP2jtN2KlSU</yt:videoId>
  <title>Абсолют Флэш №5 (DC)</title>
  <published>2025-07-30T13:01:01+00:00</published>
 </entry>
 <entry>
  <yt:videoId>F7LGGTZaXLs</yt:videoId>
  <title>Абсолют Флэш №1(DC)</title>
  <published>2025-04-14T13:00:32+00:00</published>
 </entry>
</feed>''';

/// Пять выпусков «Абсолют Флэш» в панели плейлиста.
List<Map<String, dynamic>> ytFlashItems() => [
      ytPanelItem('F7LGGTZaXLs', '▶', 'Абсолют Флэш №1(DC)', '29:14'),
      ytPanelItem('ObfHEiiEPMo', '2', 'Абсолют Флэш №2 (DC)', '23:58'),
      ytPanelItem('7AqMmcc62hE', '3', 'Абсолют Флэш №3 (DC)', '17:36'),
      ytPanelItem('GGWKmsPU5Jw', '4', 'Абсолют Флэш №4 (DC)', '31:07'),
      ytPanelItem('TP2jtN2KlSU', '5', 'Абсолют Флэш №5 (DC)', '22:00'),
    ];

/// Сайт YouTube целиком: ролик, вкладки канала, плейлисты, панель и
/// ленты. Ролик `plainvideo1` без номера в названии; остальное — TMDB и
/// прочее — 404. [requests] собирает все адреса.
MockClient ytSite({bool flashHasVideo = true, List<Uri>? requests}) =>
    MockClient((req) async {
      requests?.add(req.url);
      final path = req.url.path;
      final body = req.body.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(req.body) as Map<String, dynamic>;
      Object? out;
      if (req.url.host != 'www.youtube.com') {
        out = null;
      } else if (path.endsWith('/player')) {
        final id = '${body['videoId']}';
        out = ytPlayer(id,
            id == 'plainvideo1' ? 'Обзор без номера' : 'Абсолют Флэш №1(DC)');
      } else if (path.endsWith('/browse') && body['params'] == null) {
        out = ytChannelTabs;
      } else if (path.endsWith('/browse')) {
        out = {
          'items': [
            ytLockup(
                'PLB', 'LOCKUP_CONTENT_TYPE_PLAYLIST', 'DC Абсолют: Бэтмен'),
            ytLockup('PLD', 'LOCKUP_CONTENT_TYPE_PLAYLIST', 'Доктор Дум'),
            ytLockup('PLFlash0000001', 'LOCKUP_CONTENT_TYPE_PLAYLIST',
                'Абсолют Флэш'),
          ],
        };
      } else if (path.endsWith('/next')) {
        final list = '${body['playlistId']}';
        final flash = list.startsWith('PLF');
        out = ytNext(list, flash ? 'Абсолют Флэш' : 'Другое', [
          if (flash && flashHasVideo) ...ytFlashItems(),
          if (!flash || !flashHasVideo)
            ytPanelItem('ObfHEiiEPMo', '2', 'Абсолют Флэш №2 (DC)', '23:58'),
        ]);
      } else if (path.endsWith('/feeds/videos.xml')) {
        return http.Response.bytes(utf8.encode(ytFeed), 200,
            headers: {'content-type': 'application/xml; charset=utf-8'});
      }
      return out == null
          ? http.Response('{}', 404)
          : http.Response.bytes(utf8.encode(jsonEncode(out)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
    });
