import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/sync/sync_merge.dart';

/// Циклы с YouTube в библиотеке: цикл — сериал из одного сезона, выпуск —
/// серия; новые выпуски дописываются в конец. Одиночный ролик — фильм.

List<YtEntry> flash(int n) => [
      for (var i = 1; i <= n; i++)
        YtEntry(
          id: 'v$i',
          title: 'Абсолют Флэш №$i (DC)',
          durSec: 1500 + i,
          published: DateTime(2025, 4, i),
        ),
    ];

Future<LibrarySeries> addFlash(MovieRepository r,
        {int watched = 0, int n = 5}) =>
    r.addYouTubeCycle(
      'PLflash000001',
      title: 'Абсолют Флэш',
      channelId: 'UCdev',
      channelName: 'Dev the Geek',
      avatar: 'https://yt3.ggpht.com/ava',
      videos: flash(n),
      watchedUpTo: watched,
    );

void main() {
  test('цикл: сериал из одного сезона в «Буду смотреть»', () async {
    final r = MovieRepository.detached({});
    final s = await addFlash(r, watched: 3);
    expect(s.tvShowId, 'yt:PLflash000001');
    expect(s.isYouTube, isTrue);
    expect(s.title, 'Абсолют Флэш');
    expect(s.watchlist, isTrue);
    expect(s.totalEpisodes, 5);
    expect(s.posterUrl, 'https://i.ytimg.com/vi/v1/maxresdefault.jpg');
    expect(s.youtube!.channelName, 'Dev the Geek');
    // №1–3 без даты, с длиной выпуска для времени у экрана.
    expect(s.episodes.map((e) => e.number), [1, 2, 3]);
    expect(s.episodes.every((e) => e.watchedAt == null), isTrue);
    expect(s.episodes.first.runtimeMin, 26);
    expect(s.youtube!.labelOf(4), '№4');
  });

  test('повторное добавление не дублирует цикл', () async {
    final r = MovieRepository.detached({});
    await addFlash(r);
    await addFlash(r, watched: 2);
    expect(r.series.where((s) => s.isYouTube).length, 1);
    expect(r.seriesById('yt:PLflash000001')!.episodes.length, 2);
  });

  test('новые выпуски встают в конец, номера отмеченных не сдвигаются',
      () async {
    final r = MovieRepository.detached({});
    await addFlash(r, watched: 2);
    final added = await r.appendYouTubeVideos('yt:PLflash000001', [
      YtEntry(id: 'v2', title: 'Абсолют Флэш №2 (DC)'),
      YtEntry(id: 'v6', title: 'Абсолют Флэш №6 (DC)'),
    ]);
    final s = r.seriesById('yt:PLflash000001')!;
    expect(added.map((v) => v.id), ['v6']);
    expect(s.youtube!.videos.map((v) => v.id),
        ['v1', 'v2', 'v3', 'v4', 'v5', 'v6']);
    expect(s.totalEpisodes, 6);
    expect(s.youtube!.checkedAt, isNotNull);
    expect(s.isEpisodeWatched(1, 2), isTrue);
    expect(s.youtube!.entryAt(2)!.id, 'v2');
  });

  test('одиночный ролик — фильм в «Буду смотреть»', () async {
    final r = MovieRepository.detached({});
    final m = await r.addYouTubeVideo(
      videoId: 'plainvideo1',
      title: 'Обзор без номера',
      channelId: 'UCdev',
      channelName: 'Dev the Geek',
      durSec: 1754,
      published: DateTime(2025, 4, 14),
    );
    expect(m.uuid, 'yt:plainvideo1');
    expect(m.isYouTube, isTrue);
    expect(m.status, LibraryStatus.watchlist);
    expect(m.runtimeMin, 30);
    expect(m.year, 2025);
    expect(m.posterUrl, 'https://i.ytimg.com/vi/plainvideo1/maxresdefault.jpg');
    expect(r.watchlist.map((x) => x.uuid), ['yt:plainvideo1']);
  });

  test('цикл и ролик переживают запись в файл', () async {
    final r = MovieRepository.detached({});
    await addFlash(r, watched: 1);
    await r.addYouTubeVideo(
        videoId: 'plainvideo1',
        title: 'Обзор',
        channelId: 'UCdev',
        channelName: 'Dev the Geek');
    final back = MovieRepository.detached(r.toJson());
    final s = back.seriesById('yt:PLflash000001')!;
    expect(s.youtube!.videos.length, 5);
    expect(s.youtube!.videos.first.durSec, 1501);
    expect(s.youtube!.videos.first.published, DateTime(2025, 4, 1));
    expect(s.youtube!.avatar, 'https://yt3.ggpht.com/ava');
    expect(back.byUuid('yt:plainvideo1')!.youtube!.channelName,
        'Dev the Geek');
  });

  test('синхронизация: у цикла побеждает версия с новыми выпусками', () async {
    final a = MovieRepository.detached({});
    await addFlash(a, n: 5);
    final b = MovieRepository.detached({});
    await addFlash(b, n: 6);
    final out = mergeSnapshots(a.toJson(), b.toJson(), SyncStats());
    final s = LibrarySeries.fromJson(
        ((out['series'] as List).single as Map).cast<String, dynamic>());
    expect(s.youtube!.videos.length, 6);
  });
}
