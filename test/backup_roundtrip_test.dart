import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/services/backup_service.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/sync/sync_merge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сторож полноты копии. Библиотека, у которой заполнено каждое поле,
/// проходит круг «копия → восстановление» и слияние при синхронизации, и ни
/// одно поле не теряется.
///
/// Добавил поле в модель: допиши его в образец ниже и в список ключей.
/// Тогда тест сам проверит, что поле читается из файла и переживает слияние.
/// Так уже терялись «Буду смотреть», год и постер сериала.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final at = DateTime(2026, 4, 15, 11, 22, 33);
  final later = DateTime(2026, 8, 16, 16, 49);

  DiaryEntry diary(String note) => DiaryEntry(
        moods: ['🔥', '😍'],
        withWhom: 'с Мариной',
        friendIds: ['u2'],
        place: 'cinema',
        photoFile: 'p_diary_$note.jpg',
        note: note,
      );

  ReviewMeta meta({String? viewId}) => ReviewMeta(
        title: 'Аанг вернулся',
        criteria: {'story': 8.4, 'acting': 9.0},
        verdict: Verdict.must,
        pros: ['Музыка'],
        cons: ['Середина'],
        spoilers: true,
        shared: false,
        draft: true,
        createdAt: at,
        updatedAt: later,
        publishedAt: later,
        viewId: viewId,
      );

  LibraryMovie fullMovie() => LibraryMovie(
        uuid: 'm',
        title: 'The Last Airbender',
        ruTitle: 'Легенда об Аанге',
        titleLang: 'ru',
        kpRating: 7.7,
        enrichTried: true,
        tmdbId: 10196,
        year: 2026,
        runtimeMin: 103,
        status: LibraryStatus.watched,
        addedAt: at,
        viewings: [
          Viewing(
              id: 'v1', date: at, score: 8.8, diary: diary('первый'), editedAt: later),
          Viewing(id: 'v2', date: later, score: 8.0, diary: diary('второй')),
        ],
        emotions: [
          const MovieEmotion(id: 'wow', label: 'Вау', emoji: '🤩', score: 9),
        ],
        favorite: true,
        lists: ['Любимое'],
        review: 'Первый раз.',
        reviewMeta: meta(viewId: 'v1'),
        moreReviews: [
          ExtraReview(
              id: 'mr-1', review: 'Второй раз.', reviewMeta: meta(viewId: 'v2')),
        ],
        kinopoiskId: 409424,
        tvdbId: 77,
        imdbId: 'tt0938283',
        posterUrl: 'https://image.example/aang.jpg',
        posterFile: 'p_m.jpg',
        genres: ['фэнтези'],
        countries: ['США'],
        detailsTried: true,
      );

  LibrarySeries fullSeries() => LibrarySeries(
        tvShowId: 's',
        title: 'Arcane',
        ruTitle: 'Аркейн',
        titleLang: 'ru',
        addedAt: at,
        favorite: true,
        watchlist: true,
        dropped: true,
        finished: true,
        totalEpisodes: 18,
        year: 2021,
        air: SeriesAir(
          status: 'Returning Series',
          aired: 18,
          lastSeason: 2,
          nextSeason: 3,
          nextNumber: 1,
          nextDate: '2027-11-06',
          checkedAt: later,
        ),
        caughtUpAt: [later],
        seasonReviews: [
          SeasonReview(
            id: 'sr-1',
            from: 1,
            to: 2,
            pass: 2,
            review: 'Про два сезона.',
            reviewMeta: meta(),
          ),
        ],
        scoreSource: SeriesScoreSource.reviews,
        scoreSourceAt: later,
        score: 9.1,
        review: 'Про весь сериал.',
        reviewMeta: meta(),
        kinopoiskId: 1289334,
        tmdbId: 94605,
        tvdbId: 371028,
        imdbId: 'tt11126994',
        kpRating: 8.9,
        enrichTried: true,
        posterUrl: 'https://image.example/arcane.jpg',
        posterFile: 'p_s.jpg',
        episodes: [
          Episode(
            season: 1,
            number: 3,
            watchedAt: at,
            runtimeMin: 44,
            score: 10,
            epId: 'ep-3',
            vid: 'first',
            diary: diary('серия'),
            editedAt: later,
            rewatchViews: [
              Viewing(
                  id: 'r1',
                  date: later,
                  score: 9.5,
                  diary: diary('повтор'),
                  editedAt: later),
            ],
          ),
        ],
      );

  const fullList =
      MovieList(name: 'Любимое', movieUuids: ['m'], public: true);

  Map<String, dynamic> plain(Object o) =>
      jsonDecode(jsonEncode(o)) as Map<String, dynamic>;

  Map<String, dynamic> library() => plain({
        'movies': [fullMovie().toJson()],
        'series': [fullSeries().toJson()],
        'lists': [fullList.toJson()],
      });

  /// Пустое значение в образце: поле есть, но круг его не проверит.
  bool blank(Object? v) =>
      v == null ||
      v == false ||
      v == '' ||
      (v is List && v.isEmpty) ||
      (v is Map && v.isEmpty);

  group('образец', () {
    // Ключи, которые модель пишет в файл. Новый ключ роняет тест нарочно:
    // его надо заполнить в образце, иначе круг ниже его не проверит.
    final expected = <String, List<String>>{
      'фильм': [
        'uuid', 'title', 'ruTitle', 'titleLang', 'kpRating', 'enrichTried',
        'year', 'runtimeMin', 'status', 'addedAt', 'viewings', 'rewatchCount',
        'score', 'emotions', 'favorite', 'lists', 'review', 'reviewMeta',
        'moreReviews', 'kinopoiskId', 'tmdbId', 'tvdbId', 'imdbId',
        'posterUrl', 'posterFile', 'genres', 'countries', 'detailsTried', //
      ],
      'просмотр': ['id', 'date', 'score', 'diary', 'edited'],
      'дневник': [
        'moods', 'withWhom', 'friendIds', 'place', 'photoFile', 'note', //
      ],
      'разбор': [
        'title', 'criteria', 'verdict', 'pros', 'cons', 'spoilers', 'shared',
        'draft', 'createdAt', 'updatedAt', 'publishedAt', 'viewId', //
      ],
      'доп. рецензия': ['id', 'review', 'reviewMeta'],
      'эмоция': ['id', 'label', 'emoji', 'score'],
      'сериал': [
        'tvShowId', 'title', 'ruTitle', 'titleLang', 'episodes', 'addedAt',
        'favorite', 'watchlist', 'dropped', 'finished', 'totalEpisodes',
        'year', 'air', 'caughtUpAt', 'seasonReviews', 'scoreSource',
        'scoreSourceAt', 'score', 'review', 'reviewMeta', 'kinopoiskId',
        'tmdbId', 'tvdbId', 'imdbId', 'kpRating', 'enrichTried', 'posterUrl',
        'posterFile', //
      ],
      'серия': [
        'season', 'number', 'watchedAt', 'runtimeMin', 'score', 'epId', 'vid',
        'rewatchCount', 'rewatchViews', 'diary', 'vEdited', //
      ],
      'рецензия на сезоны': [
        'id', 'from', 'to', 'pass', 'review', 'reviewMeta', //
      ],
      'выход сериала': [
        'status', 'aired', 'lastSeason', 'nextSeason', 'nextNumber',
        'nextDate', 'checkedAt', //
      ],
      'список': ['name', 'movieUuids', 'public'],
    };

    // Общая оценка фильма в образце пуста намеренно: она живёт в просмотре.
    // «Видят друзья» у разбора выключено: включено оно по умолчанию, и круг
    // проверяет как раз выключенное.
    const blankOk = {
      'фильм': {'score'},
      'разбор': {'shared'},
    };

    final movie = plain(fullMovie().toJson());
    final series = plain(fullSeries().toJson());
    final episode = (series['episodes'] as List).single as Map<String, dynamic>;
    final parts = <String, Map<String, dynamic>>{
      'фильм': movie,
      'просмотр': (movie['viewings'] as List).first as Map<String, dynamic>,
      'дневник': ((movie['viewings'] as List).first as Map)['diary']
          as Map<String, dynamic>,
      'разбор': movie['reviewMeta'] as Map<String, dynamic>,
      'доп. рецензия':
          (movie['moreReviews'] as List).single as Map<String, dynamic>,
      'эмоция': (movie['emotions'] as List).single as Map<String, dynamic>,
      'сериал': series,
      'серия': episode,
      'рецензия на сезоны':
          (series['seasonReviews'] as List).single as Map<String, dynamic>,
      'выход сериала': series['air'] as Map<String, dynamic>,
      'список': plain(fullList.toJson()),
    };

    for (final e in expected.entries) {
      test('${e.key}: в образце заполнено каждое поле модели', () {
        final json = parts[e.key]!;
        expect(json.keys.toSet(), e.value.toSet(),
            reason: 'модель «${e.key}» пишет другие поля, чем ждёт сторож: '
                'допиши новое поле в образец и в этот список');
        final allowed = blankOk[e.key] ?? const <String>{};
        final empty = [
          for (final k in json.keys)
            if (blank(json[k]) && !allowed.contains(k)) k,
        ];
        expect(empty, isEmpty,
            reason: 'поля образца «${e.key}» пусты, круг их не проверит');
      });
    }
  });

  test('копия и восстановление возвращают библиотеку поле в поле', () async {
    final source = MovieRepository.detached(library());
    final raw = BackupService.exportJson(repo: source);
    final target = MovieRepository.detached(const {});
    final res =
        await BackupService.restore(raw, merge: false, repo: target);
    expect(res.ok, isTrue);
    expect(res.skipped, 0);
    expect(plain(target.toJson()), plain(source.toJson()));
    expect(plain(target.toJson()), library());
  });

  test('добавление копии к пустой библиотеке тоже ничего не теряет',
      () async {
    final raw =
        BackupService.exportJson(repo: MovieRepository.detached(library()));
    final target = MovieRepository.detached(const {});
    await BackupService.restore(raw, merge: true, repo: target);
    expect(plain(target.toJson()), library());
  });

  group('слияние при синхронизации не теряет полей', () {
    // Вторая сторона знает о записи только её ключ.
    final bare = <String, dynamic>{
      'movies': [
        {'uuid': 'm', 'title': ''},
      ],
      'series': [
        {'tvShowId': 's', 'title': '', 'episodes': const []},
      ],
      'lists': [
        {'name': 'Любимое', 'movieUuids': const []},
      ],
    };

    Map<String, dynamic> body(Map<String, dynamic> merged) => {
          for (final k in ['movies', 'series', 'lists']) k: merged[k],
        };

    test('полная запись локальна', () {
      expect(body(plain(mergeSnapshots(library(), bare, SyncStats()))),
          library());
    });

    test('полная запись пришла с другого устройства', () {
      expect(body(plain(mergeSnapshots(bare, library(), SyncStats()))),
          library());
    });

    test('обе стороны полные: результат тот же', () {
      expect(body(plain(mergeSnapshots(library(), library(), SyncStats()))),
          library());
    });
  });
}
