import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/models/youtube.dart';
import 'package:kadr/services/youtube_service.dart';

import 'youtube_fixtures.dart';

/// Циклы с YouTube: ссылка, номер и название выпуска, разбор ответов сайта
/// и поиск плейлиста канала по ролику. Ответы собраны по образцу настоящих
/// (канал Dev the Geek, плейлист «Абсолют Флэш»), см. youtube_fixtures.dart.
void main() {
  group('ссылка', () {
    test('youtu.be с хвостом si', () {
      final l = YouTubeService.parseLink(
          'https://youtu.be/F7LGGTZaXLs?si=UzbVUc2ioblpLDne')!;
      expect(l.videoId, 'F7LGGTZaXLs');
      expect(l.playlistId, isNull);
    });

    test('watch с плейлистом и мобильный адрес', () {
      final l = YouTubeService.parseLink(
          'https://m.youtube.com/watch?v=GGWKmsPU5Jw&list=PL0XGlOzy2yrXrjh6XZ0pN7-Qw2sOKyIKY&index=4')!;
      expect(l.videoId, 'GGWKmsPU5Jw');
      expect(l.playlistId, 'PL0XGlOzy2yrXrjh6XZ0pN7-Qw2sOKyIKY');
    });

    test('сам плейлист и shorts', () {
      expect(
          YouTubeService.parseLink(
                  'https://www.youtube.com/playlist?list=PL0XGlOzy2yrXrjh6XZ0pN7-Qw2sOKyIKY')!
              .playlistId,
          'PL0XGlOzy2yrXrjh6XZ0pN7-Qw2sOKyIKY');
      expect(
          YouTubeService.parseLink('https://youtube.com/shorts/abcdefghijk')!
              .videoId,
          'abcdefghijk');
    });

    test('ссылка внутри текста «Поделиться»', () {
      final l = YouTubeService.parseLink(
          'Абсолют Флэш №1(DC) https://youtu.be/F7LGGTZaXLs');
      expect(l?.videoId, 'F7LGGTZaXLs');
    });

    test('не YouTube', () {
      expect(YouTubeService.parseLink('https://example.com/watch?v=x'), isNull);
      expect(YouTubeService.parseLink('Абсолют Флэш'), isNull);
    });
  });

  group('название выпуска', () {
    test('номер', () {
      expect(ytIssueNumber('Абсолют Флэш №1(DC)'), 1);
      expect(ytIssueNumber('Абсолют Бэтмен №24 (Бэтгёрл)'), 24);
      expect(ytIssueNumber('Разбор, часть 3'), 3);
      expect(ytIssueNumber('Season recap Episode 10'), 10);
      expect(ytIssueNumber('Обзор без номера'), isNull);
      expect(ytIssueNumber('Смешное #shorts'), isNull);
    });

    test('название цикла до номера', () {
      expect(ytCycleName('Абсолют Флэш №1(DC)'), 'Абсолют Флэш');
      expect(ytCycleName('Люди Икс: DNX №2'), 'Люди Икс: DNX');
      expect(ytCycleName('Королева в Черном №5'), 'Королева в Черном');
      expect(ytCycleName('Обзор без номера'), isNull);
    });

    test('подзаголовок в скобках, метка издателя не в счёт', () {
      expect(ytSubtitle('Абсолют Бэтмен №24 (Бэтгёрл)'), 'Бэтгёрл');
      expect(ytSubtitle('Абсолют Бэтмен №14 (БЕЙН ФИНАЛ!)'), 'БЕЙН ФИНАЛ!');
      expect(ytSubtitle('Абсолют Флэш №1(DC)'), isNull);
    });

    test('подпись выпуска в цикле: номер из названия или место', () {
      final c = YtCycle(
        playlistId: 'PL',
        channelId: 'UCdev',
        channelName: 'Dev the Geek',
        videos: [
          YtEntry(id: 'a', title: 'Абсолют Бэтмен: анонс'),
          YtEntry(id: 'b', title: 'Абсолют Бэтмен №1 (DC)'),
        ],
      );
      expect(c.labelOf(1), '№1');
      expect(c.labelOf(2), '№1');
    });
  });

  group('ответы YouTube', () {
    test('ролик', () {
      final v = YouTubeService.parsePlayer(
          ytPlayer('F7LGGTZaXLs', 'Абсолют Флэш №1(DC)'))!;
      expect(v.id, 'F7LGGTZaXLs');
      expect(v.title, 'Абсолют Флэш №1(DC)');
      expect(v.durSec, 1754);
      expect(v.channelId, 'UCdev');
      expect(v.channelName, 'Dev the Geek');
      expect(v.published!.toUtc(), DateTime.utc(2025, 4, 14, 13, 0, 32));
      expect(v.thumb, 'https://i.ytimg.com/vi/F7LGGTZaXLs/maxresdefault.jpg');
    });

    test('плейлист из панели просмотра', () {
      final p = YouTubeService.parseNext(ytNext('PLF', 'Абсолют Флэш', [
        ytPanelItem('F7LGGTZaXLs', '▶', 'Абсолют Флэш №1(DC)', '29:14'),
        ytPanelItem('ObfHEiiEPMo', '2', 'Абсолют Флэш №2 (DC)', '23:58'),
        ytPanelItem('long', '3', 'Длинный', '1:02:03'),
      ]))!;
      expect(p.id, 'PLF');
      expect(p.title, 'Абсолют Флэш');
      expect(p.channelId, 'UCdev');
      expect(p.channelName, 'Dev the Geek');
      expect(p.avatar, 'https://yt3.ggpht.com/ava=s176');
      expect(p.videos.map((v) => v.id), ['F7LGGTZaXLs', 'ObfHEiiEPMo', 'long']);
      expect(p.videos.map((v) => v.durSec), [1754, 1438, 3723]);
    });

    test('вкладка «Плейлисты» канала и сами плейлисты', () {
      expect(YouTubeService.parsePlaylistsTab(ytChannelTabs),
          'EglwbGF5bGlzdHPyBgoKCEIGCgIQaCIA');
      final lists = YouTubeService.parseChannelPlaylists({
        'items': [
          ytLockup('PLB', 'LOCKUP_CONTENT_TYPE_PLAYLIST', 'DC Абсолют: Бэтмен'),
          ytLockup('vid1', 'LOCKUP_CONTENT_TYPE_VIDEO', 'Абсолют Бэтмен №24'),
          ytLockup('PLF', 'LOCKUP_CONTENT_TYPE_PLAYLIST', 'Абсолют Флэш'),
        ],
      });
      expect(lists.map((l) => l.id), ['PLB', 'PLF']);
      expect(lists.last.title, 'Абсолют Флэш');
    });

    test('лента плейлиста', () {
      final items = YouTubeService.parseFeed(ytFeed);
      expect(items.map((e) => e.id), ['TP2jtN2KlSU', 'F7LGGTZaXLs']);
      expect(items.first.title, 'Абсолют Флэш №5 (DC)');
      expect(items.first.published, DateTime.utc(2025, 7, 30, 13, 1, 1));
    });
  });

  group('цикл по ролику', () {
    test('находит плейлист канала по названию и сверяет ролик', () async {
      final found = await http.runWithClient(
        () => YouTubeService.resolve(
            YouTubeService.parseLink('https://youtu.be/F7LGGTZaXLs')!),
        ytSite,
      );
      expect(found, isNotNull);
      expect(found!.cycle?.id, 'PLFlash0000001');
      expect(found.cycle!.videos.first.id, 'F7LGGTZaXLs');
      // Даты из лент плейлиста и канала.
      expect(found.cycle!.videos.first.published,
          DateTime.utc(2025, 4, 14, 13, 0, 32));
      expect(found.video?.id, 'F7LGGTZaXLs');
    });

    test('плейлист без этого ролика не подходит: ролик остаётся фильмом',
        () async {
      final found = await http.runWithClient(
        () => YouTubeService.resolve(
            YouTubeService.parseLink('https://youtu.be/F7LGGTZaXLs')!),
        () => ytSite(flashHasVideo: false),
      );
      expect(found!.cycle, isNull);
      expect(found.video?.title, 'Абсолют Флэш №1(DC)');
    });

    test('ролик без номера — фильм, плейлисты не ищутся', () async {
      final extra = <Uri>[];
      final found = await http.runWithClient(
        () => YouTubeService.resolve(
            YouTubeService.parseLink('https://youtu.be/plainvideo1')!),
        () => MockClient((req) async {
          if (req.url.path.endsWith('/player')) {
            return http.Response.bytes(
                utf8.encode(
                    jsonEncode(ytPlayer('plainvideo1', 'Обзор без номера'))),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          extra.add(req.url);
          return http.Response('{}', 404);
        }),
      );
      expect(found!.cycle, isNull);
      expect(found.video?.id, 'plainvideo1');
      expect(extra, isEmpty);
    });

    test('ссылка с плейлистом берёт его сразу', () async {
      final found = await http.runWithClient(
        () => YouTubeService.resolve(YouTubeService.parseLink(
            'https://www.youtube.com/playlist?list=PLFlash0000001')!),
        ytSite,
      );
      expect(found!.cycle?.title, 'Абсолют Флэш');
    });
  });

  group('новые выпуски', () {
    YtCycle cycle({DateTime? checked}) => YtCycle(
          playlistId: 'PLFlash0000001',
          channelId: 'UCdev',
          channelName: 'Dev the Geek',
          checkedAt: checked,
          videos: [
            YtEntry(id: 'F7LGGTZaXLs', title: 'Абсолют Флэш №1(DC)'),
            YtEntry(id: 'ObfHEiiEPMo', title: 'Абсолют Флэш №2 (DC)'),
          ],
        );

    test('свежий похожий ролик в ленте канала: плейлист сверяется', () async {
      final fresh = await http.runWithClient(
        () => YouTubeService.newVideos(
            cycle(checked: DateTime.now()), 'Абсолют Флэш'),
        ytSite,
      );
      expect(fresh!.map((v) => v.id),
          ['7AqMmcc62hE', 'GGWKmsPU5Jw', 'TP2jtN2KlSU']);
      expect(fresh.last.durSec, 1320);
    });

    test('без повода и недавно проверенный: плейлист не открывается',
        () async {
      final requests = <Uri>[];
      final c = cycle(checked: DateTime.now())
        ..videos.addAll([
          YtEntry(id: 'TP2jtN2KlSU', title: 'Абсолют Флэш №5 (DC)'),
        ]);
      final fresh = await http.runWithClient(
        () => YouTubeService.newVideos(c, 'Абсолют Флэш'),
        () => ytSite(requests: requests),
      );
      expect(fresh, isNull);
      expect(requests.where((u) => u.path.endsWith('/next')), isEmpty);
    });
  });
}
