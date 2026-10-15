import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/sync/sync_merge.dart';

/// Фильм в несколько заходов: «Досмотрю потом» ставит просмотр на паузу с
/// минутой, «Досмотрел» делает его просмотром днём досмотра. Прошлые
/// остановки лежат заходами: в ленте это строки «начал» и «продолжил».
void main() {
  final oct14 = DateTime(2026, 10, 14, 21, 40);
  final oct15 = DateTime(2026, 10, 15, 22, 10);
  final oct1 = DateTime(2026, 10, 1, 20);
  final oct8 = DateTime(2026, 10, 8, 22, 5);

  LibraryMovie movie(List<Viewing> views,
          {LibraryStatus status = LibraryStatus.watched, int? runtime = 137}) =>
      LibraryMovie(
        uuid: 'jm',
        title: 'Just Mercy',
        ruTitle: 'Просто помиловать',
        runtimeMin: runtime,
        status: status,
        viewings: views,
      );

  MovieRepository repo(LibraryMovie m) =>
      MovieRepository.detached({'movies': [m.toJson()]});

  group('просмотр', () {
    test('пауза и заходы переживают запись в файл', () {
      final v = Viewing(
        id: 'a',
        date: oct8,
        pause: PauseMark(atMin: 115),
        parts: [Sitting(date: oct1, toMin: 64)],
      );
      final back = Viewing.fromAny(v.toJson());
      expect(back.pause?.atMin, 115);
      expect(back.isPaused, isTrue);
      expect(back.isFull, isFalse);
      expect(back.parts.single.date, oct1);
      expect(back.parts.single.toMin, 64);
    });

    test('обычный просмотр паузы и заходов в файл не пишет', () {
      final json = Viewing(id: 'a', date: oct15).toJson();
      expect(json.containsKey('pause'), isFalse);
      expect(json.containsKey('parts'), isFalse);
      final back = Viewing.fromAny(json);
      expect(back.isPaused, isFalse);
      expect(back.isFull, isTrue);
      expect(back.parts, isEmpty);
    });

    test('пауза без минуты всё равно пауза', () {
      final back =
          Viewing.fromAny(Viewing(id: 'a', date: oct14, pause: PauseMark()).toJson());
      expect(back.isPaused, isTrue);
      expect(back.pause!.atMin, isNull);
    });
  });

  group('фильм', () {
    test('только начат: не просмотрен и не брошен', () {
      final m = movie(
          [Viewing(id: 'a', date: oct14, pause: PauseMark(atMin: 52))]);
      expect(m.isWatched, isFalse);
      expect(m.isDropped, isFalse);
      expect(m.pausedViewing?.id, 'a');
      expect(m.viewCount, 1);
      expect(m.rewatchCount, 0);
    });

    test('досмотренный и начатый пересмотр: просмотрен, пересмотра ещё нет', () {
      final m = movie([
        Viewing(id: 'a', date: DateTime(2026, 3, 1)),
        Viewing(id: 'b', date: oct14, pause: PauseMark(atMin: 30)),
      ]);
      expect(m.isWatched, isTrue);
      expect(m.isRewatched, isFalse);
      expect(m.pausedViewing?.id, 'b');
      expect(m.fullOrdinalOf(m.viewingById('b')!), 0);
    });

    test('время у экрана: начатый идёт до своей минуты', () {
      final m = movie([
        Viewing(id: 'a', date: DateTime(2026, 3, 1)),
        Viewing(id: 'b', date: oct14, pause: PauseMark(atMin: 52)),
      ]);
      expect(m.screenMinutes(137), 137 + 52);
    });

    test('последний досмотренный просмотр не видит начатых и брошенных', () {
      final m = movie([
        Viewing(id: 'a', date: DateTime(2026, 3, 1)),
        Viewing(id: 'b', date: oct14, pause: PauseMark(atMin: 52)),
        Viewing(id: 'c', date: oct15, drop: DropMark(atMin: 10)),
      ]);
      expect(m.lastFullViewing, DateTime(2026, 3, 1));
    });
  });

  group('репозиторий', () {
    test('«Досмотрю потом» из «Буду смотреть»: попытка в ленте, не в списках',
        () async {
      final r = repo(movie(const [], status: LibraryStatus.watchlist));
      await r.pauseViewing('jm', atMin: 52, date: oct14);
      final m = r.byUuid('jm')!;
      expect(m.status, LibraryStatus.watched);
      expect(m.viewings.single.pause?.atMin, 52);
      expect(m.viewings.single.date, oct14);
      expect(r.watchlist, isEmpty);
      expect(r.watched, isEmpty);
      expect(r.droppedMovies, isEmpty);
      expect(r.startedMovies.map((x) => x.uuid), ['jm']);
      final feed = [for (final g in r.watchedEntriesByMonth()) ...g.value];
      expect(feed.single.viewing?.isPaused, isTrue);
    });

    test('второй заход: прошлая остановка уходит в заходы', () async {
      final r = repo(movie(
          [Viewing(id: 'a', date: oct1, pause: PauseMark(atMin: 64))],
          runtime: 180));
      await r.pauseViewing('jm', atMin: 115, date: oct8);
      final v = r.byUuid('jm')!.viewings.single;
      expect(v.pause?.atMin, 115);
      expect(v.date, oct8);
      expect(v.parts.single.date, oct1);
      expect(v.parts.single.toMin, 64);
      expect(v.editedAt, isNotNull);
    });

    test('«Досмотрел»: просмотр встаёт днём досмотра, начало остаётся заходом',
        () async {
      final r = repo(
          movie([Viewing(id: 'a', date: oct14, pause: PauseMark(atMin: 52))]));
      await r.finishViewing('jm', r.byUuid('jm')!.viewingById('a')!, oct15);
      final m = r.byUuid('jm')!;
      final v = m.viewings.single;
      expect(v.isFull, isTrue);
      expect(v.date, oct15);
      expect(v.parts.single.date, oct14);
      expect(v.parts.single.toMin, 52);
      expect(m.isWatched, isTrue);
      expect(r.startedMovies, isEmpty);
      expect(m.screenMinutes(137), 137);
    });

    test('«Досмотрел» с «не помню»: пауза снята, дата на месте', () async {
      final r = repo(
          movie([Viewing(id: 'a', date: oct14, pause: PauseMark(atMin: 52))]));
      await r.finishViewing('jm', r.byUuid('jm')!.viewingById('a')!, null);
      final v = r.byUuid('jm')!.viewings.single;
      expect(v.isFull, isTrue);
      expect(v.date, oct14);
      expect(v.parts, isEmpty);
    });

    test('брошенную попытку досмотрел позже: день, когда бросил, стал началом',
        () async {
      final r = repo(movie(
          [Viewing(id: 'a', date: oct14, drop: DropMark(atMin: 52))]));
      await r.finishViewing('jm', r.byUuid('jm')!.viewingById('a')!, oct15);
      final v = r.byUuid('jm')!.viewings.single;
      expect(v.drop, isNull);
      expect(v.date, oct15);
      expect(v.parts.single.date, oct14);
      expect(v.parts.single.toMin, 52);
      expect(r.droppedMovies, isEmpty);
    });

    test('начатый бросил: минута переезжает в пометку, пауза снята', () async {
      final r = repo(
          movie([Viewing(id: 'a', date: oct14, pause: PauseMark(atMin: 52))]));
      await r.setViewingDrop('jm', r.byUuid('jm')!.viewingById('a')!,
          DropMark(atMin: 52, reasons: ['Затянуто']));
      final m = r.byUuid('jm')!;
      expect(m.viewings.single.isPaused, isFalse);
      expect(m.isDropped, isTrue);
      expect(r.startedMovies, isEmpty);
    });

    test('правка паузы двигает минуту без нового захода', () async {
      final r = repo(
          movie([Viewing(id: 'a', date: oct14, pause: PauseMark(atMin: 52))]));
      await r.setViewingPause(
          'jm', r.byUuid('jm')!.viewingById('a')!, PauseMark(atMin: 60));
      final v = r.byUuid('jm')!.viewings.single;
      expect(v.pause?.atMin, 60);
      expect(v.parts, isEmpty);
    });

    test('«Начал» задним числом: первый заход, убирается крестиком', () async {
      final r = repo(movie([Viewing(id: 'a', date: oct15)]));
      Viewing live() => r.byUuid('jm')!.viewingById('a')!;
      await r.setViewingStart('jm', live(), oct1);
      expect(live().parts.single.date, oct1);
      expect(live().parts.single.toMin, isNull);
      // Начало позже досмотра не встаёт.
      await r.setViewingStart('jm', live(), DateTime(2026, 10, 20));
      expect(live().parts.single.date, oct1);
      await r.setViewingStart('jm', live(), null);
      expect(live().parts, isEmpty);
    });

    test('лента: заходы встают строками в свои дни, если их просят', () async {
      final r = repo(movie([
        Viewing(id: 'a', date: oct15, parts: [
          Sitting(date: oct1, toMin: 64),
          Sitting(date: oct8, toMin: 115),
        ]),
      ]));
      final plain = [for (final g in r.watchedEntriesByMonth()) ...g.value];
      expect(plain.length, 1);
      final withTraces = [
        for (final g in r.watchedEntriesByMonth(traces: true)) ...g.value,
      ];
      expect(withTraces.map((e) => e.date), [oct15, oct8, oct1]);
      expect(withTraces.map((e) => e.part), [null, 1, 0]);
    });

    test('друзья не видят начатый фильм, пока не досмотрен', () {
      final r = repo(movie([
        Viewing(id: 'a', date: oct14, pause: PauseMark(atMin: 52)),
      ]));
      final pub = r.buildPublicProfile();
      final m = (pub['movies'] as List).single as Map<String, dynamic>;
      expect(m['viewings'], isEmpty);
      expect(m['status'], 'watchlist');
    });

    test('досмотренный уходит друзьям с заходами, скрытые даты огрублены', () {
      final r = repo(movie([
        Viewing(id: 'a', date: oct15, parts: [Sitting(date: oct14, toMin: 52)]),
      ]));
      final pub = r.buildPublicProfile(hideDates: true);
      final v = (((pub['movies'] as List).single as Map)['viewings'] as List)
          .single as Map;
      final part = (v['parts'] as List).single as Map;
      expect(part['min'], 52);
      expect(part['date'], DateTime(2026, 10).toIso8601String());
    });
  });

  group('синхронизация', () {
    Map<String, dynamic> lib(Viewing v) => {
          'movies': [movie([v]).toJson()],
        };

    test('«Досмотрел» на другом устройстве снимает паузу и здесь', () {
      final local = Viewing(id: 'a', date: oct14, pause: PauseMark(atMin: 52));
      final remote = Viewing(
          id: 'a',
          date: oct15,
          editedAt: oct15,
          parts: [Sitting(date: oct14, toMin: 52)]);
      final out = mergeSnapshots(lib(local), lib(remote), SyncStats());
      final v = ((out['movies'] as List).single['viewings'] as List).single
          as Map;
      expect(v.containsKey('pause'), isFalse);
      expect((v['parts'] as List).length, 1);
    });

    test('неправленая запись берёт паузу и заходы с другой стороны', () {
      final local = Viewing(id: 'a', date: oct8);
      final remote = Viewing(
          id: 'a',
          date: oct8,
          pause: PauseMark(atMin: 115),
          parts: [Sitting(date: oct1, toMin: 64)]);
      final out = mergeSnapshots(lib(local), lib(remote), SyncStats());
      final v = ((out['movies'] as List).single['viewings'] as List).single
          as Map;
      expect(v['pause'], {'min': 115});
      expect((v['parts'] as List).length, 1);
    });
  });
}
