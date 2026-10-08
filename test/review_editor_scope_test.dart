import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/review/review_editor_screen.dart';
import 'package:kadr/screens/review/review_target.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сериал без tmdbId: редактор не ходит в сеть, сезоны берёт из отметок.
MovieRepository _repo({ReviewMeta? whole, List<SeasonReview>? parts}) =>
    MovieRepository.detached({
      'series': [
        LibrarySeries(
          tvShowId: 'aot',
          title: 'Атака титанов',
          episodes: [
            for (var s = 1; s <= 4; s++)
              Episode(season: s, number: 1, watchedAt: DateTime(2026, s), score: 9.1),
          ],
          review: whole == null ? null : 'Про весь сериал',
          reviewMeta: whole,
          seasonReviews: parts,
        ).toJson(),
      ],
    });

ReviewMeta _crit(Map<String, double> c) => ReviewMeta(criteria: c);

Widget _app(Widget home) =>
    MaterialApp(theme: AppTheme.dark(AppTheme.defaultSeed), home: home);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('рецензия на сезоны: охват и оценка из пунктов', (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo(parts: [
      SeasonReview(id: 'b', from: 2, to: 3, reviewMeta: _crit({'story': 9.6, 'acting': 8.8})),
    ]);
    final s = repo.seriesById('aot')!;
    final target = ReviewTarget.series(s, repo: repo, part: s.seasonReviews.single);
    await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Сезоны 2–3'), findsOneWidget);
    expect(find.text('9.2'), findsOneWidget);
    expect(find.text(tr('rvs_hint_part')), findsOneWidget);
    expect(find.textContaining('Выставить сериалу'), findsNothing);
  });

  testWidgets('рецензия на весь сериал выставляет оценку сериалу', (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo(whole: _crit({'story': 9.0}));
    final s = repo.seriesById('aot')!;
    await tester.pumpWidget(
        _app(ReviewEditorScreen(target: ReviewTarget.series(s, repo: repo))));
    await tester.pumpAndSettle();
    expect(find.text('Весь сериал'), findsOneWidget);
    await tester.tap(find.text('Выставить сериалу 9.0'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('aot')!.scoreSource, SeriesScoreSource.review);
    expect(repo.seriesById('aot')!.displayScore, 9.0);
  });

  testWidgets('«Изменить» переносит рецензию на другие сезоны', (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo(parts: [
      SeasonReview(id: 'a', from: 1, to: 1, reviewMeta: _crit({'story': 8.0})),
    ]);
    final s = repo.seriesById('aot')!;
    final target = ReviewTarget.series(s, repo: repo, part: s.seasonReviews.single);
    await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Диапазон'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S2'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Далее').last);
    await tester.pumpAndSettle();
    expect(find.text('Сезоны 1–2'), findsOneWidget);
    final p = repo.seriesById('aot')!.seasonReviews.single;
    expect((p.from, p.to), (1, 2));
  });

  testWidgets('новая рецензия на сезон записывается в свою часть', (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo();
    final s = repo.seriesById('aot')!;
    final target = ReviewTarget.series(s, repo: repo, from: 4, to: 4);
    await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
    await tester.pumpAndSettle();
    expect(find.text('Сезон 4'), findsOneWidget);
    await tester.tap(find.text('Далее').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Финал, о котором спорят');
    await tester.tap(find.text('Далее').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final parts = repo.seriesById('aot')!.seasonReviews;
    expect(parts, hasLength(1));
    expect((parts.single.from, parts.single.to), (4, 4));
    expect(parts.single.review, 'Финал, о котором спорят');
    expect(repo.seriesById('aot')!.hasReview, isFalse);
  });
}
