import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/viewing/episode_sheet.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/tmdb_service.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/utils/season_pass.dart';
import 'package:kadr/widgets/viewing/pass_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ep3 = TmdbEpisode(
  season: 1,
  number: 3,
  name: 'Без насилия не будет перемен',
  airDate: '2021-11-06',
  runtime: 44,
  overview: 'Описание серии.',
);

/// «Аркейн»: третью серию смотрели трижды, последний просмотр без оценки;
/// четвёртая отмечена один раз, пятая не отмечена.
MovieRepository _repo() => MovieRepository.detached({
      'series': [
        LibrarySeries(
          tvShowId: 'arcane',
          title: 'Аркейн',
          episodes: [
            Episode(
              season: 1,
              number: 3,
              watchedAt: DateTime(2023, 5, 29, 13, 41),
              score: 10,
              rewatchViews: [
                Viewing(id: 'r2', date: DateTime(2023, 10, 2, 17, 44)),
                Viewing(id: 'r3', date: DateTime(2026, 8, 19, 13, 35)),
              ],
            ),
            Episode(
              season: 1,
              number: 4,
              watchedAt: DateTime(2023, 5, 29, 14, 30),
              score: 9.5,
            ),
          ],
        ).toJson(),
      ],
    });

Future<int> _open(
  WidgetTester tester,
  MovieRepository repo, {
  TmdbEpisode ep = _ep3,
  bool canMark = true,
  String lang = 'ru',
  double width = 380,
}) async {
  tester.view.physicalSize = Size(width, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  var marks = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showEpisodeSheet(
                context,
                seriesId: 'arcane',
                seriesTitle: 'Аркейн',
                ep: ep,
                canMark: canMark,
                onMark: () => marks++,
                repo: repo,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return marks;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('окно серии собрано как карточка фильма', (tester) async {
    await _open(tester, _repo());
    expect(find.text('Без насилия не будет перемен'), findsOneWidget);
    expect(find.text('06.11.2021 · 44 мин'), findsOneWidget);
    // Карточка показывает последний просмотр: он третий и ещё не оценён.
    expect(find.text('Оценка · 3-й просмотр'), findsOneWidget);
    expect(find.text('Те же 10.0, что в первый раз'), findsOneWidget);
    expect(find.text('Смотрел ещё раз'), findsOneWidget);
    expect(find.text('Отменить просмотр'), findsOneWidget);
    expect(find.text('Просмотры · 3'), findsOneWidget);
    expect(find.text('19.08.2026 13:35'), findsOneWidget);
    expect(find.text('29.05.2023 13:41'), findsOneWidget);
    // Прежней плитки даты и списка «Оценки по просмотрам» больше нет.
    expect(find.text('Оценки по просмотрам'), findsNothing);
  });

  testWidgets('«Отменить просмотр» убирает только последний просмотр серии', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, repo);
    await tester.ensureVisible(find.text('Отменить просмотр'));
    await tester.tap(find.text('Отменить просмотр'));
    await tester.pumpAndSettle();
    final s = repo.seriesById('arcane')!;
    final e3 = s.watchedEpisode(1, 3)!;
    expect(e3.watchCount, 2);
    expect(e3.orderedViews.last.date, DateTime(2023, 10, 2, 17, 44));
    // Следующая серия не тронута: раньше снималась вместе с этой.
    expect(s.watchedEpisode(1, 4), isNotNull);
    // Плашка лежит поверх окна, а не под ним.
    expect(find.text('Просмотр удалён'), findsOneWidget);
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('arcane')!.watchedEpisode(1, 3)!.watchCount, 3);
  });

  testWidgets('единственный оценённый просмотр: спросит и снимет серию', (
    tester,
  ) async {
    final repo = _repo();
    const ep4 = TmdbEpisode(season: 1, number: 4, name: 'С Днём прогресса!');
    await _open(tester, repo, ep: ep4);
    expect(find.text('Оценка серии'), findsOneWidget);
    await tester.ensureVisible(find.text('Отменить просмотр'));
    await tester.tap(find.text('Отменить просмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Вместе с ним уйдёт оценка 9.5.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    final s = repo.seriesById('arcane')!;
    expect(s.watchedEpisode(1, 4), isNull);
    expect(s.watchedEpisode(1, 3), isNotNull);
    // Серия снова не отмечена: окно предлагает отметить.
    expect(find.text('Отметить просмотр'), findsOneWidget);
  });

  testWidgets('«Смотрел ещё раз» зовёт окно отметки, а не пишет «сейчас»', (
    tester,
  ) async {
    final repo = _repo();
    var marks = 0;
    tester.view.physicalSize = const Size(380, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: EpisodeSheet(
            seriesId: 'arcane',
            seriesTitle: 'Аркейн',
            ep: _ep3,
            canMark: true,
            onMark: () => marks++,
            repo: repo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Смотрел ещё раз'));
    await tester.tap(find.text('Смотрел ещё раз'));
    await tester.pumpAndSettle();
    expect(marks, 1);
    expect(repo.seriesById('arcane')!.watchedEpisode(1, 3)!.watchCount, 3);
  });

  testWidgets('невышедшую серию отметить нельзя', (tester) async {
    const ep5 = TmdbEpisode(season: 1, number: 5, name: 'Скоро');
    await _open(tester, _repo(), ep: ep5, canMark: false);
    expect(find.text('Отметить просмотр'), findsNothing);
    expect(find.text('Смотрел ещё раз'), findsNothing);
    expect(find.textContaining('Просмотры ·'), findsNothing);
  });

  group('полоса пересмотра сезона', () {
    Future<void> pump(WidgetTester tester, SeasonPassState st,
        {String lang = 'ru', double width = 380}) async {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PassStrip(state: st),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    final running = SeasonPassState(
      completed: 2,
      done: 5,
      total: 9,
      from: DateTime(2026, 8, 18),
      to: DateTime(2026, 8, 19),
    );
    final finished = SeasonPassState(
      completed: 3,
      done: 0,
      total: 9,
      from: DateTime(2026, 8, 18),
      to: DateTime(2026, 8, 20),
    );

    testWidgets('пересмотр идёт: номер, ход и дата начала', (tester) async {
      await pump(tester, running);
      expect(find.text('3-й просмотр · 5 из 9'), findsOneWidget);
      expect(find.text('начат 18.08.2026'), findsOneWidget);
      // Полоса хода залита на 5 из 9.
      final bar = tester.widget<FractionallySizedBox>(
          find.byType(FractionallySizedBox));
      expect(bar.widthFactor, closeTo(5 / 9, 0.001));
    });

    testWidgets('пересмотр закончен: сколько раз и когда в последний', (
      tester,
    ) async {
      await pump(tester, finished);
      expect(find.text('Сезон просмотрен 3 раза'), findsOneWidget);
      expect(find.text('в последний раз 18–20.08.2026'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing);
    });

    for (final lang in LocaleController.languages.map((l) => l.code)) {
      testWidgets('320 dp без переполнений, $lang', (tester) async {
        await pump(tester, running, lang: lang, width: 320);
        expect(tester.takeException(), isNull);
        await pump(tester, finished, lang: lang, width: 320);
        expect(tester.takeException(), isNull);
      });
    }
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('окно серии на 320 dp без переполнений, $lang', (tester) async {
      await _open(tester, _repo(), lang: lang, width: 320);
      expect(tester.takeException(), isNull);
    });
  }
}
