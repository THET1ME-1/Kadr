import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/review/series_reviews_section.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/store.dart';
import 'package:kadr/services/tmdb_service.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seasons = [
  TmdbSeason(number: 1, name: 'Сезон 1', episodeCount: 25),
  TmdbSeason(number: 2, name: 'Сезон 2', episodeCount: 12),
  TmdbSeason(number: 3, name: 'Сезон 3', episodeCount: 22),
  TmdbSeason(number: 4, name: 'Сезон 4', episodeCount: 35),
];

ReviewMeta _m(String title, double v, {Verdict? verdict}) => ReviewMeta(
  title: title,
  criteria: {'story': v},
  verdict: verdict,
  publishedAt: DateTime(2026, 10, 7),
);

/// «Атака титанов» из макета.
MovieRepository _repo({bool parts = true}) {
  Episode ep(int s, int n, double sc) =>
      Episode(season: s, number: n, watchedAt: DateTime(2026, s, n), score: sc);
  return MovieRepository.detached({
    'series': [
      LibrarySeries(
        tvShowId: 'aot',
        title: 'Атака титанов',
        episodes: [
          ep(1, 1, 8.8), ep(2, 1, 9.0), ep(3, 1, 9.1), ep(4, 1, 9.3),
        ],
        review: 'Про весь сериал',
        reviewMeta: _m('Десять лет за стенами', 9.0, verdict: Verdict.must),
        seasonReviews: parts
            ? [
                SeasonReview(id: 'a', from: 1, to: 1, review: 'а',
                    reviewMeta: _m('Стены держат крепче сюжета', 8.6, verdict: Verdict.must)),
                SeasonReview(id: 'b', from: 2, to: 3, review: 'б',
                    reviewMeta: _m('Правда за стеной', 9.2, verdict: Verdict.masterpiece)),
                SeasonReview(id: 'c', from: 4, to: 4, review: 'в',
                    reviewMeta: _m('Финал, о котором спорят', 8.1, verdict: Verdict.worth)),
              ]
            : null,
      ).toJson(),
    ],
  });
}

Future<MovieRepository> _pump(WidgetTester tester,
    {bool parts = true, String lang = 'ru', double width = 380,
    bool collapsed = false}) async {
  // Store держит один экземпляр настроек на весь прогон: пишем через него.
  await tester.runAsync(() => Store.instance
      .setBool(SeriesReviewsSection.collapsedKey, collapsed));
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  final repo = _repo(parts: parts);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(AppTheme.defaultSeed),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: repo,
          builder: (_, _) => SeriesReviewsSection(
            series: repo.seriesById('aot')!,
            repo: repo,
            seasons: _seasons,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('список: рецензии на сезоны по порядку, весь сериал последним',
      (tester) async {
    await _pump(tester);
    expect(find.text('Мои рецензии · 4'), findsOneWidget);
    final titles = [
      'Стены держат крепче сюжета',
      'Правда за стеной',
      'Финал, о котором спорят',
      'Десять лет за стенами',
    ];
    final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect(ys, [...ys]..sort());
    // Таблетка охвата у рецензии; S1 и S4 есть ещё в строках сравнения.
    expect(find.text('S2–S3'), findsOneWidget);
    expect(find.text('S1'), findsNWidgets(2));
    expect(find.text('S4'), findsNWidgets(2));
    expect(find.textContaining('не входит в свод'), findsOneWidget);
  });

  testWidgets('свод: две средние, вывод и «Выставить сериалу»', (tester) async {
    final repo = await _pump(tester);
    expect(find.text(tr('rvs_summary').toUpperCase()), findsOneWidget);
    expect(find.text('9.1'), findsWidgets);
    expect(find.text('8.8'), findsWidgets);
    expect(
      find.text('Рецензии строже серий на 0.3. Сильнее всего разошёлся 4-й сезон.'),
      findsOneWidget,
    );
    expect(find.textContaining('весит втрое'), findsNothing,
        reason: 'пояснение под сводом убрано');
    await tester.ensureVisible(find.text('Выставить сериалу 8.8'));
    await tester.tap(find.text('Выставить сериалу 8.8'));
    await tester.pumpAndSettle();
    // Сначала подтверждение: отмена ничего не меняет.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(tr('cancel')));
    await tester.pumpAndSettle();
    expect(repo.seriesById('aot')!.scoreSource, SeriesScoreSource.episodes);
    await tester.tap(find.text('Выставить сериалу 8.8'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, tr('rvs_set_confirm_ok')));
    await tester.pumpAndSettle();
    expect(repo.seriesById('aot')!.scoreSource, SeriesScoreSource.reviews);
    expect(find.text('Выставить сериалу 8.8'), findsNothing);
    expect(find.text(tr('rvs_score_from_summary')), findsOneWidget);
  });

  testWidgets('без рецензий на сезоны свода нет', (tester) async {
    await _pump(tester, parts: false);
    expect(find.text('Мои рецензии · 1'), findsOneWidget);
    expect(find.text(tr('rvs_summary').toUpperCase()), findsNothing);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('320 dp без переполнений, $lang', (tester) async {
      await _pump(tester, lang: lang, width: 320);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('дата с годом и короткая подпись «По сериям», как в макете',
      (tester) async {
    await _pump(tester);
    expect(find.textContaining('7 окт 2026'), findsWidgets);
    expect(find.text('По сериям'), findsOneWidget);
  });

  testWidgets('блок сворачивается и помнит это', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip(tr('rvs_collapse')));
    await tester.pumpAndSettle();
    expect(find.text('Правда за стеной'), findsNothing);
    expect(find.text(tr('rvs_summary').toUpperCase()), findsNothing);
    expect(find.text('S2–S3'), findsOneWidget);
    expect(find.text('9.2'), findsOneWidget);
    expect(find.text('Свод 8.8'), findsOneWidget);
    expect(await tester.runAsync(
        () => Store.instance.getBool(SeriesReviewsSection.collapsedKey)), isTrue);

    await tester.tap(find.byTooltip(tr('rvs_expand')));
    await tester.pumpAndSettle();
    expect(find.text('Правда за стеной'), findsOneWidget);
    expect(await tester.runAsync(
        () => Store.instance.getBool(SeriesReviewsSection.collapsedKey)), isFalse);
  });

  testWidgets('свёрнутый с прошлого раза открывается свёрнутым', (tester) async {
    await _pump(tester, collapsed: true);
    expect(find.text('Правда за стеной'), findsNothing);
    expect(find.text('Мои рецензии · 4'), findsOneWidget);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('свёрнутый на 320 dp без переполнений, $lang', (tester) async {
      await _pump(tester, lang: lang, width: 320, collapsed: true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('крестик прячет кнопку после подтверждения, значок её возвращает',
      (tester) async {
    await tester.runAsync(() => Store.instance.setStringList(
        SeriesReviewsSection.hiddenSetKey, const []));
    await _pump(tester);
    await tester.ensureVisible(find.byTooltip(tr('rvs_hide_set')));
    await tester.tap(find.byTooltip(tr('rvs_hide_set')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, tr('rvs_hide_ok')));
    await tester.pumpAndSettle();
    expect(find.text('Выставить сериалу 8.8'), findsNothing);
    expect(
      await tester.runAsync(() =>
          Store.instance.getStringList(SeriesReviewsSection.hiddenSetKey)),
      ['aot'],
    );

    await tester.tap(find.byTooltip(tr('rvs_show_set')));
    await tester.pumpAndSettle();
    expect(find.text('Выставить сериалу 8.8'), findsOneWidget);
    expect(
      await tester.runAsync(() =>
          Store.instance.getStringList(SeriesReviewsSection.hiddenSetKey)),
      isEmpty,
    );
  });

  group('рецензии на пересмотр', () {
    const seasons = [
      TmdbSeason(number: 1, name: 'Сезон 1', episodeCount: 9),
      TmdbSeason(number: 2, name: 'Сезон 2', episodeCount: 9),
    ];

    /// «Аркейн» из макета: первый сезон смотрен трижды (рецензии на первый
    /// и третий просмотр), второй дважды (рецензии на оба).
    MovieRepository arcane() {
      Episode ep(int s, int n, int views) => Episode(
            season: s,
            number: n,
            watchedAt: DateTime(2023, 5, 29),
            score: 10,
            rewatchViews: [
              for (var i = 1; i < views; i++)
                Viewing(date: DateTime(2023 + i, 8, 18)),
            ],
          );
      SeasonReview rv(String id, int season, int pass, String title, double v) =>
          SeasonReview(
            id: id,
            from: season,
            to: season,
            pass: pass,
            review: 'текст',
            reviewMeta: _m(title, v, verdict: Verdict.must),
          );
      return MovieRepository.detached({
        'series': [
          LibrarySeries(
            tvShowId: 'arcane',
            title: 'Аркейн',
            episodes: [ep(1, 1, 3), ep(1, 2, 3), ep(2, 1, 2)],
            seasonReviews: [
              rv('a1', 1, 1, 'Город из двух половин', 9.6),
              rv('a3', 1, 3, 'Трагедия, которая не стареет', 9.8),
              rv('b1', 2, 1, 'Слишком быстро к финалу', 8.4),
              rv('b2', 2, 2, 'Подряд работает лучше', 9.0),
            ],
          ).toJson(),
        ],
      });
    }

    Future<MovieRepository> pump(WidgetTester tester,
        {String lang = 'ru', double width = 380, bool collapsed = false}) async {
      await tester.runAsync(() => Store.instance
          .setBool(SeriesReviewsSection.collapsedKey, collapsed));
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      final repo = arcane();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: repo,
              builder: (_, _) => SeriesReviewsSection(
                series: repo.seriesById('arcane')!,
                repo: repo,
                seasons: seasons,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('последняя рецензия строкой, прошлые короткой строкой под ней',
        (tester) async {
      await pump(tester);
      expect(find.text('Мои рецензии · 4'), findsOneWidget);
      // У последних рецензий номер просмотра стоит таблеткой рядом с охватом.
      expect(find.text('3-й'), findsOneWidget);
      expect(find.text('2-й'), findsOneWidget);
      expect(find.text('1-й'), findsNWidgets(2));
      final ys = [
        for (final t in [
          'Трагедия, которая не стареет',
          'Город из двух половин',
          'Подряд работает лучше',
          'Слишком быстро к финалу',
        ])
          tester.getTopLeft(find.text(t)).dy,
      ];
      expect(ys, [...ys]..sort());
      // Вердикт и подпись есть только у полной строки.
      expect(find.text('Обязательно'), findsNWidgets(2));
    });

    testWidgets('в свод идёт последняя рецензия каждого сезона', (tester) async {
      await pump(tester);
      // (9.8 + 9.0) / 2
      expect(find.text('Выставить сериалу 9.4'), findsOneWidget);
    });

    testWidgets('вкладка «Пересмотры»: сезоны по просмотрам', (tester) async {
      await pump(tester);
      expect(find.text('Серии и рецензии'), findsOneWidget);
      // Первая вкладка открыта как раньше.
      expect(find.text('По сериям'), findsOneWidget);
      await tester.tap(find.text('Пересмотры'));
      await tester.pumpAndSettle();
      expect(find.text('По сериям'), findsNothing);
      expect(find.text('Первый раз'), findsOneWidget);
      expect(find.text('Последний раз'), findsOneWidget);
      // (9.6 + 8.4) / 2 против (9.8 + 9.0) / 2
      expect(find.text('9.0'), findsWidgets);
      expect(find.text('9.4'), findsWidgets);
      expect(
        find.text('При пересмотре сериал вырос на 0.4. '
            'Сильнее всего изменился сезон 2.'),
        findsOneWidget,
      );
      expect(find.text('+0.2'), findsOneWidget);
      expect(find.text('+0.6'), findsOneWidget);
      // Второй просмотр первого сезона был, а рецензии на него нет.
      expect(find.text('нет'), findsOneWidget);
      expect(find.textContaining('она идёт в свод'), findsOneWidget);
      // Кнопка общая для обеих вкладок.
      expect(find.text('Выставить сериалу 9.4'), findsOneWidget);
    });

    testWidgets('в свёрнутой строке от сезона одна рецензия, последняя',
        (tester) async {
      await pump(tester, collapsed: true);
      expect(find.text('S1'), findsOneWidget);
      expect(find.text('S2'), findsOneWidget);
      expect(find.text('9.8'), findsOneWidget);
      expect(find.text('9.6'), findsNothing);
      expect(find.text('Свод 9.4'), findsOneWidget);
    });

    for (final lang in LocaleController.languages.map((l) => l.code)) {
      testWidgets('320 dp, вкладка «Пересмотры», $lang', (tester) async {
        await pump(tester, lang: lang, width: 320);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(tr('rvs_tab_passes')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
