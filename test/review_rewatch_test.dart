import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/review/review_editor_screen.dart';
import 'package:kadr/screens/review/review_screen.dart';
import 'package:kadr/screens/review/review_target.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// «Легенда об Аанге» из макета: рецензии на первый и третий просмотр. Без
/// tmdbId, чтобы экраны не ходили в сеть.
MovieRepository _repo({bool third = true}) => MovieRepository.detached({
      'movies': [
        LibraryMovie(
          uuid: 'aang',
          title: 'Легенда об Аанге',
          year: 2026,
          status: LibraryStatus.watched,
          viewings: [
            Viewing(id: 'v1', date: DateTime(2026, 4, 15, 11, 22), score: 8.8),
            Viewing(id: 'v2', date: DateTime(2026, 5, 16, 22, 26), score: 8.5),
            Viewing(id: 'v3', date: DateTime(2026, 8, 16, 16, 49), score: 8.0),
          ],
          review: 'Первый раз.',
          reviewMeta: ReviewMeta(
            title: 'Аанг вернулся, и это главное',
            viewId: 'v1',
            criteria: _then,
            verdict: Verdict.must,
            publishedAt: DateTime(2026, 4, 15, 12),
          ),
          moreReviews: [
            if (third)
              ExtraReview(
                id: 'mr-3',
                review: 'Третий раз.',
                reviewMeta: ReviewMeta(
                  title: 'На третий раз видны швы',
                  viewId: 'v3',
                  criteria: _now,
                  verdict: Verdict.worth,
                  publishedAt: DateTime(2026, 8, 16, 18),
                ),
              ),
          ],
        ).toJson(),
      ],
      'series': [
        LibrarySeries(
          tvShowId: 'arcane',
          title: 'Аркейн',
          episodes: [
            Episode(
              season: 1,
              number: 1,
              watchedAt: DateTime(2023, 5, 29),
              rewatchViews: [Viewing(date: DateTime(2026, 8, 18))],
            ),
          ],
          seasonReviews: [
            SeasonReview(
              id: 'a1',
              from: 1,
              to: 1,
              review: 'текст',
              reviewMeta: ReviewMeta(
                title: 'Город из двух половин',
                criteria: {'story': 9.6},
                publishedAt: DateTime(2023, 6, 1),
              ),
            ),
            SeasonReview(
              id: 'a2',
              from: 1,
              to: 1,
              pass: 2,
              review: 'текст',
              reviewMeta: ReviewMeta(
                title: 'Трагедия, которая не стареет',
                criteria: {'story': 9.8},
                publishedAt: DateTime(2026, 8, 20),
              ),
            ),
          ],
        ).toJson(),
      ],
    });

ReviewTarget _target(MovieRepository repo, String viewId) =>
    ReviewTarget.movie(repo.byUuid('aang')!,
        repo: repo, mine: true, viewId: viewId);

Widget _app(Widget home) => MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: home,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester, {double w = 380, double h = 3000}) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('цель рецензии', () {
    test('рецензия привязана к своему просмотру и знает прошлую', () {
      final repo = _repo();
      final third = _target(repo, 'v3');
      expect(third.meta!.title, 'На третий раз видны швы');
      expect(third.ordinal, 3);
      expect(third.score, 8.0);
      expect(third.previous!.meta!.title, 'Аанг вернулся, и это главное');
      expect(third.previous!.ordinal, 1);
      expect(_target(repo, 'v1').previous, isNull);
    });

    test('новая рецензия на свободный просмотр пустая, занятый не берётся',
        () async {
      final repo = _repo();
      final second = _target(repo, 'v2');
      expect(second.item.hasReview, isFalse);
      expect(second.score, 8.5);
      // Перенос на занятый просмотр отклонён.
      expect(await second.setViewing('v3'), isFalse);
      expect(second.viewId, 'v2');
      await second.save('Второй раз.', ReviewMeta(title: 'Середина'));
      final m = repo.byUuid('aang')!;
      expect(m.moreReviews.length, 2);
      expect(_target(repo, 'v2').meta!.title, 'Середина');
      // Первая рецензия осталась в старых полях: её читают старые версии.
      expect(m.reviewMeta!.title, 'Аанг вернулся, и это главное');
    });

    test('оценка рецензии пишется в её просмотр, а не в последний', () async {
      final repo = _repo();
      await _target(repo, 'v1').setScore(9.2);
      final m = repo.byUuid('aang')!;
      expect(m.viewingById('v1')!.score, 9.2);
      expect(m.viewingById('v3')!.score, 8.0);
    });

    // Редактор открыт, приложение свернули и вернули: синхронизация
    // пересоздала объекты библиотеки, а цель держит прежние.
    test('оценка пишется и после синхронизации под открытым редактором',
        () async {
      final repo = _repo();
      final t = _target(repo, 'v1');
      await repo.mergeSyncSnapshot(const {});
      await t.setScore(9.5);
      expect(repo.byUuid('aang')!.viewingById('v1')!.score, 9.5);
    });

    // Две рецензии на один просмотр: вторая остаётся без него, и строка
    // такой рецензии обязана открывать и удалять её саму.
    test('рецензия без просмотра открывает себя, а не первую рецензию',
        () async {
      final repo = MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'x',
            title: 'Мэйдэй',
            status: LibraryStatus.watched,
            viewings: [Viewing(id: 'a', date: DateTime(2026, 1, 1))],
            review: 'главная',
            reviewMeta: ReviewMeta(viewId: 'a', title: 'Главная'),
            moreReviews: [
              ExtraReview(
                id: 'mr-dup',
                review: 'лишняя',
                reviewMeta: ReviewMeta(viewId: 'a', title: 'Лишняя'),
              ),
            ],
          ).toJson(),
        ],
      });
      final loose = ReviewTarget.publicReviews(repo)
          .firstWhere((t) => t.meta!.title == 'Лишняя');
      expect(loose.text, 'лишняя');
      await loose.delete();
      final m = repo.byUuid('x')!;
      expect(m.review, 'главная');
      expect(m.moreReviews, isEmpty);
    });

    test('без указания просмотра цель берёт последнюю рецензию', () {
      final repo = _repo();
      final t = ReviewTarget.movie(repo.byUuid('aang')!, repo: repo);
      expect(t.viewId, 'v3');
      expect(t.meta!.title, 'На третий раз видны швы');
      // Без рецензий — последний просмотр.
      final clean = MovieRepository.detached({
        'movies': [
          LibraryMovie(
            uuid: 'x',
            title: 'Мэйдэй',
            status: LibraryStatus.watched,
            viewings: [
              Viewing(id: 'a', date: DateTime(2026, 1, 1)),
              Viewing(id: 'b', date: DateTime(2026, 2, 1)),
            ],
          ).toJson(),
        ],
      });
      expect(ReviewTarget.movie(clean.byUuid('x')!, repo: clean).viewId, 'b');
    });

    test('рецензия на пересмотр сезона знает рецензию на прошлый просмотр',
        () {
      final repo = _repo();
      final s = repo.seriesById('arcane')!;
      final second =
          ReviewTarget.series(s, repo: repo, part: s.seasonReviews.last);
      expect(second.pass, 2);
      expect(second.previous!.meta!.title, 'Город из двух половин');
      final first =
          ReviewTarget.series(s, repo: repo, part: s.seasonReviews.first);
      expect(first.previous, isNull);
    });

    test('друг видит каждую открытую рецензию фильма отдельно', () {
      final repo = _repo();
      final titles = [
        for (final t in ReviewTarget.publicReviews(repo))
          if (!t.isSeries) t.meta!.title,
      ];
      expect(titles, [
        'На третий раз видны швы',
        'Аанг вернулся, и это главное',
      ]);
    });
  });

  testWidgets('страница рецензии: «Тогда и сейчас» вместо «По пунктам»',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo();
    await tester.pumpWidget(_app(ReviewScreen(target: _target(repo, 'v3'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('3-Й ПРОСМОТР'), findsOneWidget);
    expect(find.text('Тогда и сейчас'), findsOneWidget);
    expect(find.text(tr('rv_criteria').toUpperCase()), findsNothing);
    expect(find.text('1-й · апр 2026'), findsOneWidget);
    expect(find.text('3-й · авг 2026'), findsOneWidget);
    expect(
      find.text('Сильнее всего изменился пункт «Сюжет»: было 8.4, стало 6.8.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Рецензия на 1-й просмотр'));
    await tester.tap(find.text('Рецензия на 1-й просмотр'));
    await tester.pumpAndSettle();
    expect(find.text('Аанг вернулся, и это главное'), findsOneWidget);
  });

  testWidgets('первая рецензия: обычные «По пунктам», сравнения нет',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo();
    await tester.pumpWidget(_app(ReviewScreen(target: _target(repo, 'v1'))));
    await tester.pumpAndSettle();
    expect(find.text('Тогда и сейчас'), findsNothing);
    expect(find.text(tr('rv_criteria').toUpperCase()), findsOneWidget);
    expect(find.textContaining('1-Й ПРОСМОТР'), findsOneWidget);
  });

  testWidgets('редактор: полоса просмотра и метки прошлой рецензии',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo();
    await tester
        .pumpWidget(_app(ReviewEditorScreen(target: _target(repo, 'v3'))));
    await tester.pumpAndSettle();
    expect(find.text('3-й просмотр'), findsOneWidget);
    expect(find.text('16.08.2026 · в прошлой рецензии 8.8'), findsOneWidget);
    expect(find.text('оценка из рецензии на 1-й просмотр'), findsOneWidget);
    // «Изменить» открывает лист выбора просмотра.
    await tester.tap(find.text(tr('rvs_change')));
    await tester.pumpAndSettle();
    expect(find.text('О каком просмотре'), findsOneWidget);
  });

  testWidgets('редактор: рецензия переносится на свободный просмотр',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo();
    await tester
        .pumpWidget(_app(ReviewEditorScreen(target: _target(repo, 'v3'))));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('rvs_change')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16.05.2026 22:26'));
    await tester.pumpAndSettle();
    // «Далее» есть и в шапке редактора под листом: нужна кнопка листа.
    await tester.tap(find.widgetWithText(FilledButton, tr('rv_next')).last);
    await tester.pumpAndSettle();
    expect(find.text('2-й просмотр'), findsOneWidget);
    final m = repo.byUuid('aang')!;
    expect(m.moreReviews.single.reviewMeta!.viewId, 'v2');
  });

  testWidgets('у фильма с одним просмотром полосы просмотра нет',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = MovieRepository.detached({
      'movies': [
        LibraryMovie(
          uuid: 'x',
          title: 'Мэйдэй',
          status: LibraryStatus.watched,
          viewings: [Viewing(id: 'a', date: DateTime(2026, 1, 1), score: 7)],
        ).toJson(),
      ],
    });
    final target =
        ReviewTarget.movie(repo.byUuid('x')!, repo: repo, mine: true);
    await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
    await tester.pumpAndSettle();
    expect(find.text(tr('rvs_change')), findsNothing);
    expect(find.textContaining('оценка из рецензии'), findsNothing);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('320 dp: «Тогда и сейчас», $lang', (tester) async {
      phone(tester, w: 320);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      final repo = _repo();
      await tester.pumpWidget(_app(ReviewScreen(target: _target(repo, 'v3'))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('320 dp: редактор с полосой просмотра, $lang', (tester) async {
      phone(tester, w: 320);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      final repo = _repo();
      await tester
          .pumpWidget(_app(ReviewEditorScreen(target: _target(repo, 'v3'))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
