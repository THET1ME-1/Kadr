// Превью просмотров и рецензий по пересмотрам в PNG:
// `FLUTTER_ROOT=<корень flutter> flutter test test/preview_viewings.dart`
// кладёт build/preview/viewings_*.png. Без суффикса `_test`, в обычный
// прогон не попадает. Данные повторяют макет: «Человек-паук: Новый день»,
// «Легенда об Аанге», «Аватар», «Аркейн».
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/movie_sheet.dart';
import 'package:kadr/screens/review/movie_reviews_section.dart';
import 'package:kadr/screens/review/review_editor_screen.dart';
import 'package:kadr/screens/review/review_scope_sheet.dart';
import 'package:kadr/screens/review/review_screen.dart';
import 'package:kadr/screens/review/review_target.dart';
import 'package:kadr/screens/review/review_viewing_sheet.dart';
import 'package:kadr/screens/review/series_reviews_section.dart';
import 'package:kadr/screens/viewing/episode_sheet.dart';
import 'package:kadr/screens/viewing/mark_sheet.dart';
import 'package:kadr/screens/viewing/viewing_delete.dart';
import 'package:kadr/screens/viewing/viewing_host.dart';
import 'package:kadr/screens/viewing/viewing_sheet.dart';
import 'package:kadr/screens/viewing/viewings_section.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/app_prefs.dart';
import 'package:kadr/services/tmdb_service.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/utils/season_pass.dart';
import 'package:kadr/widgets/viewing/pass_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'build/preview';

Future<void> _loadFonts() async {
  for (final family in ['Unbounded', 'Onest']) {
    final loader = FontLoader(family)
      ..addFont(File('assets/fonts/$family.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final icons =
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icons.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(icons.readAsBytes().then((b) => ByteData.view(b.buffer)));
  await loader.load();
}

ReviewMeta _meta(String title, String viewId, Map<String, double> crit,
        Verdict verdict, DateTime at) =>
    ReviewMeta(
      title: title,
      viewId: viewId,
      criteria: crit,
      verdict: verdict,
      createdAt: at,
      publishedAt: at,
    );

const _then = {
  'story': 8.4,
  'direction': 8.8,
  'acting': 9.0,
  'visuals': 9.6,
  'sound': 9.0,
  'pace': 8.0,
};
const _now = {
  'story': 6.8,
  'direction': 8.0,
  'acting': 8.8,
  'visuals': 9.4,
  'sound': 8.8,
  'pace': 6.8,
};

LibraryMovie _spider() => LibraryMovie(
      uuid: 'sp',
      title: 'Человек-паук: Новый день',
      year: 2026,
      runtimeMin: 144,
      status: LibraryStatus.watched,
      viewings: [
        Viewing(id: 's1', date: DateTime(2026, 9, 4, 16, 7), score: 9.5),
        Viewing(id: 's2', date: DateTime(2026, 10, 10, 23, 32), score: 9.5),
      ],
      reviewMeta: _meta(
        'Это прекрасно было.',
        's2',
        {'story': 9.0, 'direction': 10.0, 'acting': 9.5},
        Verdict.masterpiece,
        DateTime(2026, 10, 10, 23, 44),
      ),
    );

LibraryMovie _aang() => LibraryMovie(
      uuid: 'aang',
      title: 'Легенда об Аанге: Последний маг воздуха',
      year: 2026,
      runtimeMin: 98,
      status: LibraryStatus.watched,
      viewings: [
        Viewing(id: 'v1', date: DateTime(2026, 4, 15, 11, 22), score: 8.8),
        Viewing(
          id: 'v2',
          date: DateTime(2026, 5, 16, 22, 26),
          score: 8.5,
          diary: DiaryEntry(moods: ['🥹', '🔥', '😍'], place: 'home'),
        ),
        Viewing(id: 'v3', date: DateTime(2026, 8, 16, 16, 49), score: 8.0),
      ],
      review: 'Первый раз. ' * 240,
      reviewMeta: _meta('Аанг вернулся, и это главное', 'v1', _then,
          Verdict.must, DateTime(2026, 4, 15, 12)),
      moreReviews: [
        ExtraReview(
          id: 'mr-3',
          review: 'Третий раз. ' * 170,
          reviewMeta: _meta('На третий раз видны швы', 'v3', _now,
              Verdict.worth, DateTime(2026, 8, 16, 18)),
        ),
      ],
    );

LibraryMovie _five() {
  const scores = [7.5, 8.0, 8.6, 9.0, 9.2];
  const rows = {
    'story': [7.0, 7.5, 8.5, 9.0, 9.5],
    'direction': [8.0, 8.0, 8.5, 9.0, 9.0],
    'acting': [8.5, 8.5, 9.0, 9.0, 9.5],
    'visuals': [9.0, 9.0, 9.0, 9.5, 9.5],
    'sound': [8.0, 8.5, 8.5, 9.0, 9.0],
    'pace': [6.0, 7.0, 8.0, 8.5, 9.0],
  };
  ReviewMeta meta(int i) => _meta(
        'Рецензия на ${i + 1}-й просмотр',
        'f$i',
        {for (final e in rows.entries) e.key: e.value[i]},
        Verdict.must,
        DateTime(2025, i + 1, 11),
      );
  return LibraryMovie(
    uuid: 'five',
    title: 'Грань будущего',
    status: LibraryStatus.watched,
    viewings: [
      for (var i = 0; i < 5; i++)
        Viewing(id: 'f$i', date: DateTime(2025, i + 1, 10), score: scores[i]),
    ],
    review: 'Текст',
    reviewMeta: meta(0),
    moreReviews: [
      for (var i = 1; i < 5; i++)
        ExtraReview(id: 'mr-$i', review: 'Текст', reviewMeta: meta(i)),
    ],
  );
}

LibraryMovie _avatar() => LibraryMovie(
      uuid: 'avatar',
      title: 'Аватар',
      status: LibraryStatus.watched,
      viewings: [
        for (var i = 0; i < 4; i++) Viewing(id: 'u$i', score: 10),
        Viewing(id: 'd5', date: DateTime(2025, 8, 20), score: 10),
        Viewing(id: 'd6', date: DateTime(2025, 10, 4), score: 10),
      ],
    );

LibrarySeries _arcane() {
  Episode ep(int s, int n, int views) => Episode(
        season: s,
        number: n,
        watchedAt: DateTime(2023, 5, 29, 13, 30 + n),
        score: 10,
        rewatchViews: [
          if (views >= 2) Viewing(date: DateTime(2023, 10, 2, 17, 30 + n)),
          if (views >= 3) Viewing(date: DateTime(2026, 8, 18 + n ~/ 4, 13, n)),
        ],
      );
  SeasonReview rv(String id, int season, int pass, String title, double v,
          Verdict verdict, DateTime at) =>
      SeasonReview(
        id: id,
        from: season,
        to: season,
        pass: pass,
        review: 'текст',
        reviewMeta: ReviewMeta(
          title: title,
          criteria: {'story': v},
          verdict: verdict,
          publishedAt: at,
        ),
      );
  return LibrarySeries(
    tvShowId: 'arcane',
    title: 'Аркейн',
    episodes: [
      for (var n = 1; n <= 9; n++) ep(1, n, n <= 5 ? 3 : 2),
      for (var n = 1; n <= 9; n++) ep(2, n, 2),
    ],
    review: 'Про весь сериал',
    reviewMeta: ReviewMeta(
      title: 'Аркейн целиком',
      criteria: {'story': 9.4},
      verdict: Verdict.must,
      publishedAt: DateTime(2026, 8, 24),
    ),
    seasonReviews: [
      rv('a1', 1, 1, 'Город из двух половин', 9.6, Verdict.must,
          DateTime(2023, 6, 1)),
      rv('a3', 1, 3, 'Трагедия, которая не стареет', 9.8, Verdict.masterpiece,
          DateTime(2026, 8, 20)),
      rv('b1', 2, 1, 'Слишком быстро к финалу', 8.4, Verdict.worth,
          DateTime(2024, 11, 24)),
      rv('b2', 2, 2, 'Подряд работает лучше', 9.0, Verdict.must,
          DateTime(2026, 8, 23)),
    ],
  );
}

MovieRepository _repo() => MovieRepository.detached({
      'movies': [
        _spider().toJson(),
        _aang().toJson(),
        _five().toJson(),
        _avatar().toJson(),
      ],
      'series': [_arcane().toJson()],
    });

const _seasons = [
  TmdbSeason(number: 1, name: 'Сезон 1', episodeCount: 9),
  TmdbSeason(number: 2, name: 'Сезон 2', episodeCount: 9),
];

late bool _light;

Future<void> _shoot(WidgetTester tester, String name, Widget screen,
    {double height = 844, Future<void> Function()? act}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _light
          ? AppTheme.light(AppTheme.defaultSeed)
          : AppTheme.dark(AppTheme.defaultSeed),
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
  if (act != null) {
    await act();
    await tester.pumpAndSettle();
  }
  await tester.runAsync(() async {
    await Directory(_out).create(recursive: true);
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File('$_out/viewings_${name}_${_light ? 'light' : 'dark'}.png')
        .writeAsBytes(data!.buffer.asUint8List());
  });
  // Закрываем листы и плашки прошлого снимка.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

/// Экран с одной кнопкой: по ней открывается лист, который снимаем.
Widget _opener(Future<void> Function(BuildContext) open) => Builder(
      builder: (context) => Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 60),
            child: FilledButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Widget _page(List<Widget> children) => Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: children,
        ),
      ),
    );

Future<void> _all(WidgetTester tester) async {
  Future<void> tapOpen() => tester.tap(find.text('open'));

  // Карточка фильма целиком: рецензии под оценкой, просмотры под кнопками.
  // Экран читает основную библиотеку, поэтому фильмы кладём в неё (запись
  // на диск в тестах молча не срабатывает).
  await tester.runAsync(() => MovieRepository.instance
      .restoreFromSnapshot([_spider().toJson(), _aang().toJson()], const []));
  final main = MovieRepository.instance;
  await _shoot(tester, '01_movie_spider',
      MovieScreen(movie: main.byUuid('sp')!),
      height: 1500);
  await _shoot(tester, '01_movie_aang',
      MovieScreen(movie: main.byUuid('aang')!),
      height: 2300);
  var repo = _repo();

  // Блок рецензий со сводом по пересмотрам и блок «Просмотры».
  repo = _repo();
  await _shoot(
    tester,
    '02_aang_sections',
    _page([
      ListenableBuilder(
        listenable: repo,
        builder: (_, _) =>
            MovieReviewsSection(movie: repo.byUuid('aang')!, repo: repo),
      ),
      ViewingsSection(host: MovieViewingHost('aang', repo: repo)),
    ]),
    height: 1250,
  );

  repo = _repo();
  await _shoot(
    tester,
    '03_five_reviews',
    _page([
      MovieReviewsSection(movie: repo.byUuid('five')!, repo: repo),
    ]),
    height: 1150,
  );

  await tester.runAsync(() => AppPrefs.instance.setMovieReviewsCollapsed(true));
  repo = _repo();
  await _shoot(
    tester,
    '04_folded_and_undated',
    _page([
      MovieReviewsSection(movie: repo.byUuid('aang')!, repo: repo),
      ViewingsSection(host: MovieViewingHost('avatar', repo: repo)),
    ]),
    height: 640,
  );
  await tester.runAsync(
      () => AppPrefs.instance.setMovieReviewsCollapsed(false));

  // Окно отметки: фильм и сезон.
  await _shoot(
    tester,
    '05_mark_film',
    _opener((c) => showMarkSheet(c,
        title: 'Когда посмотрели?',
        subject: 'Легенда об Аанге',
        ordinal: 4)),
    act: tapOpen,
  );
  await _shoot(
    tester,
    '06_mark_season',
    _opener((c) => showMarkSheet(c,
        title: 'Когда досмотрели сезон?',
        subject: 'Сезон 1 · осталось 4 серии из 9',
        ordinal: 3,
        dangerLabel: 'Снять все просмотры сезона')),
    act: tapOpen,
  );

  // Окно просмотра.
  repo = _repo();
  var host = MovieViewingHost('aang', repo: repo);
  await _shoot(
    tester,
    '07_view_film',
    _opener((c) => showViewingSheet(c, host, viewId: 'v2')),
    act: tapOpen,
  );
  await _shoot(
    tester,
    '08_view_diary',
    _opener((c) => showViewingSheet(c, host, viewId: 'v2', openDiary: true)),
    height: 1100,
    act: tapOpen,
  );
  final epHost = EpisodeViewingHost('arcane', 1, 3, repo: repo);
  // Третий просмотр серии без оценки.
  await epHost.setScore(epHost.ordered.last, null);
  for (final v in epHost.ordered.skip(1)) {
    await epHost.setScore(v, null);
  }
  await _shoot(
    tester,
    '09_view_episode',
    _opener((c) =>
        showViewingSheet(c, epHost, viewId: epHost.ordered.last.id)),
    act: tapOpen,
  );
  await _shoot(
    tester,
    '10_view_delete',
    _opener((c) => deleteViewingFlow(c, host, host.byId('v2')!)),
    act: tapOpen,
  );

  // Окно серии и полоса пересмотра сезона.
  await _shoot(
    tester,
    '11_episode_sheet',
    _opener((c) => showEpisodeSheet(
          c,
          seriesId: 'arcane',
          seriesTitle: 'Аркейн',
          ep: const TmdbEpisode(
            season: 1,
            number: 3,
            name: 'Без насилия не будет перемен',
            airDate: '2021-11-06',
            runtime: 44,
            overview: 'Вай и Паудер решают, как поступить с добычей.',
          ),
          canMark: true,
          onMark: () {},
          repo: repo,
        )),
    height: 1150,
    act: tapOpen,
  );
  final arcane = repo.seriesById('arcane')!;
  await _shoot(
    tester,
    '12_pass_strip',
    _page([
      PassStrip(
          state: seasonPass(arcane, 1, [for (var n = 1; n <= 9; n++) n])),
      PassStrip(
          state: seasonPass(arcane, 2, [for (var n = 1; n <= 9; n++) n])),
    ]),
    height: 300,
  );

  // Рецензии сериала: прошлые строкой, вкладка «Пересмотры», лист охвата.
  repo = _repo();
  await _shoot(
    tester,
    '13_series_reviews',
    Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 48),
        child: SeriesReviewsSection(
          series: repo.seriesById('arcane')!,
          repo: repo,
          seasons: _seasons,
        ),
      ),
    ),
    height: 1250,
    act: () => tester.tap(find.text('Пересмотры')),
  );
  await _shoot(
    tester,
    '14_scope_sheet',
    _opener((c) => showReviewScopeSheet(c,
        series: repo.seriesById('arcane')!, seasons: _seasons)),
    height: 900,
    act: () async {
      await tapOpen();
      await tester.pumpAndSettle();
      await tester.tap(find.text('S1'));
    },
  );

  // Рецензия на пересмотр: страница, редактор, выбор просмотра.
  repo = _repo();
  ReviewTarget t(String viewId) => ReviewTarget.movie(repo.byUuid('aang')!,
      repo: repo, mine: true, viewId: viewId);
  // Текст длинный: высоты хватает, чтобы карточка сравнения попала в кадр.
  await _shoot(tester, '15_then_now', ReviewScreen(target: t('v3')),
      height: 4400);
  await _shoot(tester, '16_editor', ReviewEditorScreen(target: t('v3')),
      height: 1250);
  await _shoot(
    tester,
    '17_which_viewing',
    _opener(
        (c) => showReviewViewingSheet(c, movie: repo.byUuid('aang')!)),
    act: tapOpen,
  );
}

void main() {
  testWidgets('рендер просмотров и рецензий', (tester) async {
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await _loadFonts();
      await LocaleController.instance.setCode('ru');
    });
    for (final light in [true, false]) {
      _light = light;
      await _all(tester);
    }
  });
}
