import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/sync/sync_merge.dart';

/// Брошенный фильм (KADR-1): попытка записана просмотром с пометкой, у
/// пометки минута и причины. Фильм брошен, пока ни разу не досмотрен.
void main() {
  final march = DateTime(2026, 3, 12, 22, 10);
  final may = DateTime(2026, 5, 3, 21);

  DropMark mark({int? at = 52, List<String> why = const ['Затянуто']}) =>
      DropMark(atMin: at, reasons: [...why]);

  LibraryMovie movie(List<Viewing> views,
          {LibraryStatus status = LibraryStatus.watched}) =>
      LibraryMovie(
        uuid: 'b',
        title: 'Blonde',
        ruTitle: 'Блондинка',
        runtimeMin: 166,
        status: status,
        viewings: views,
      );

  MovieRepository repo(LibraryMovie m) =>
      MovieRepository.detached({'movies': [m.toJson()]});

  group('пометка в просмотре', () {
    test('минута и причины переживают запись в файл', () {
      final v = Viewing(
          id: 'a', date: march, drop: mark(why: ['Затянуто', 'Своё слово']));
      final back = Viewing.fromAny(v.toJson());
      expect(back.drop, isNotNull);
      expect(back.drop!.atMin, 52);
      expect(back.drop!.reasons, ['Затянуто', 'Своё слово']);
    });

    test('досмотренный просмотр пометки в файле не пишет', () {
      final json = Viewing(id: 'a', date: march).toJson();
      expect(json.containsKey('drop'), isFalse);
      expect(Viewing.fromAny(json).drop, isNull);
    });

    test('брошен без минуты и причин: пометка всё равно есть', () {
      final v = Viewing(id: 'a', date: march, drop: DropMark());
      final back = Viewing.fromAny(v.toJson());
      expect(back.drop, isNotNull);
      expect(back.drop!.atMin, isNull);
      expect(back.drop!.reasons, isEmpty);
    });
  });

  group('фильм', () {
    test('только брошенные просмотры: фильм брошен и не просмотрен', () {
      final m = movie([Viewing(id: 'a', date: march, drop: mark())]);
      expect(m.isDropped, isTrue);
      expect(m.isWatched, isFalse);
      expect(m.viewCount, 1);
      expect(m.rewatchCount, 0);
      expect(m.lastDropped?.id, 'a');
    });

    test('бросил, потом досмотрел: просмотрен, попытка не пересмотр', () {
      final m = movie([
        Viewing(id: 'a', date: march, drop: mark()),
        Viewing(id: 'b', date: may, score: 7.5),
      ]);
      expect(m.isDropped, isFalse);
      expect(m.isWatched, isTrue);
      expect(m.rewatchCount, 0);
      expect(m.isRewatched, isFalse);
      expect(m.viewCount, 1);
      expect(m.fullOrdinalOf(m.viewingById('b')!), 1);
      expect(m.fullOrdinalOf(m.viewingById('a')!), 0);
    });

    test('брошенный пересмотр не делает фильм брошенным', () {
      final m = movie([
        Viewing(id: 'a', date: march, score: 9),
        Viewing(id: 'b', date: may, drop: mark()),
      ]);
      expect(m.isDropped, isFalse);
      expect(m.isWatched, isTrue);
      expect(m.rewatchCount, 0);
      expect(m.lastDropped?.id, 'b');
    });

    test('старая отметка статусом без просмотров тоже брошена', () {
      final m = movie(const [], status: LibraryStatus.dropped);
      expect(m.isDropped, isTrue);
      expect(m.isWatched, isFalse);
    });

    test('время у экрана: досмотренный целиком, брошенный до своей минуты',
        () {
      final m = movie([
        Viewing(id: 'a', date: march, drop: mark(at: 52)),
        Viewing(id: 'b', date: may),
        Viewing(id: 'c', date: DateTime(2026, 6, 1), drop: mark(at: null)),
        Viewing(id: 'd', date: DateTime(2026, 7, 1), drop: mark(at: 999)),
      ]);
      expect(m.screenMinutes(166), 52 + 166 + 0 + 166);
      // Длительность не знаем: брошенный идёт своей минутой.
      expect(m.screenMinutes(null), 52 + 0 + 0 + 600);
    });
  });

  group('репозиторий', () {
    test('бросить фильм из «Буду смотреть»: попытка в ленте, в «Брошено»',
        () async {
      final r = repo(movie(const [], status: LibraryStatus.watchlist));
      await r.addViewing('b', march, drop: mark());
      final m = r.byUuid('b')!;
      expect(m.status, LibraryStatus.watched);
      expect(m.viewings.single.drop?.atMin, 52);
      expect(r.watchlist, isEmpty);
      expect(r.watched, isEmpty);
      expect(r.droppedMovies.map((x) => x.uuid), ['b']);
      final feed = [
        for (final g in r.watchedEntriesByMonth()) ...g.value,
      ];
      expect(feed.single.viewing?.drop, isNotNull);
    });

    test('досмотрел позже: фильм просмотрен и уходит из «Брошено»', () async {
      final r = repo(movie([Viewing(id: 'a', date: march, drop: mark())]));
      await r.addViewing('b', may);
      expect(r.watched.map((x) => x.uuid), ['b']);
      expect(r.droppedMovies, isEmpty);
    });

    test('«Досмотрел» снимает пометку и ставит момент правки', () async {
      final r = repo(movie([Viewing(id: 'a', date: march, drop: mark())]));
      final v = r.byUuid('b')!.viewingById('a')!;
      await r.setViewingDrop('b', v, null);
      final live = r.byUuid('b')!.viewingById('a')!;
      expect(live.drop, isNull);
      expect(live.editedAt, isNotNull);
      expect(r.droppedMovies, isEmpty);
      expect(r.watched.length, 1);
    });

    test('правка пометки: минута и причины по id просмотра', () async {
      final r = repo(movie([Viewing(id: 'a', date: march, drop: mark())]));
      final v = r.byUuid('b')!.viewingById('a')!;
      await r.setViewingDrop(
          'b', v, DropMark(atMin: 70, reasons: ['Скучно', 'Плохой звук']));
      final live = r.byUuid('b')!.viewingById('a')!;
      expect(live.drop!.atMin, 70);
      expect(live.drop!.reasons, ['Скучно', 'Плохой звук']);
      expect(live.editedAt, isNotNull);
    });

    test('свои причины подсказываются снова, свежие первыми', () async {
      final r = MovieRepository.detached({
        'movies': [
          movie([
            Viewing(
                id: 'a', date: march, drop: mark(why: ['Скучно', 'Плохой звук'])),
          ]).toJson(),
          LibraryMovie(
            uuid: 'c',
            title: 'Other',
            status: LibraryStatus.watched,
            viewings: [
              Viewing(id: 'x', date: may, drop: mark(why: ['Мутная картинка'])),
            ],
          ).toJson(),
        ],
      });
      expect(r.usedDropReasons,
          ['Мутная картинка', 'Скучно', 'Плохой звук']);
    });

    test('друзьям уходит минута, причины остаются у владельца', () {
      final r = repo(movie([
        Viewing(id: 'a', date: march, drop: mark(why: ['Тяжело смотреть'])),
      ]));
      final pub = r.buildPublicProfile();
      final view = ((pub['movies'] as List).single['viewings'] as List).single
          as Map<String, dynamic>;
      expect(view['drop'], {'min': 52});
      final friend = MovieRepository.detached(pub);
      expect(friend.droppedMovies.single.viewings.single.drop?.atMin, 52);
    });
  });

  group('синхронизация', () {
    Map<String, dynamic> lib(Viewing v) => {
          'movies': [movie([v]).toJson()],
        };

    test('свежая правка пометки с другого устройства побеждает', () {
      final local = Viewing(id: 'a', date: march, drop: mark());
      final remote = Viewing(
          id: 'a', date: march, editedAt: may, drop: mark(why: ['Скучно']));
      final out = mergeSnapshots(lib(local), lib(remote), SyncStats());
      final v = ((out['movies'] as List).single['viewings'] as List).single;
      expect((v as Map)['drop'], {'min': 52, 'why': ['Скучно']});
    });

    test('«Досмотрел» на другом устройстве снимает пометку и здесь', () {
      final local = Viewing(id: 'a', date: march, drop: mark());
      final remote = Viewing(id: 'a', date: march, editedAt: may);
      final out = mergeSnapshots(lib(local), lib(remote), SyncStats());
      final v = ((out['movies'] as List).single['viewings'] as List).single;
      expect((v as Map).containsKey('drop'), isFalse);
    });
  });
}
