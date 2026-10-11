import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/review/review_scope_sheet.dart';
import 'package:kadr/services/tmdb_service.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seasons = [
  TmdbSeason(number: 1, name: 'Сезон 1', episodeCount: 25),
  TmdbSeason(number: 2, name: 'Сезон 2', episodeCount: 12),
  TmdbSeason(number: 3, name: 'Сезон 3', episodeCount: 22),
  TmdbSeason(number: 4, name: 'Сезон 4', episodeCount: 35),
];

LibrarySeries _series({bool whole = false}) => LibrarySeries(
  tvShowId: 'aot',
  title: 'Атака титанов',
  review: whole ? 'Про весь сериал' : null,
  reviewMeta: whole ? ReviewMeta(title: 'Итог') : null,
  seasonReviews: [
    SeasonReview(
      id: 'a',
      from: 1,
      to: 1,
      reviewMeta: ReviewMeta(title: 'Стены держат крепче сюжета'),
    ),
  ],
);

/// Открывает лист и возвращает то, что он отдал по «Далее».
Future<ReviewScope?> _run(
  WidgetTester tester,
  LibrarySeries s,
  Future<void> Function() act, {
  String? exceptPartId,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode('ru'));
  ReviewScope? result;
  var closed = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                result = await showReviewScopeSheet(
                  context,
                  series: s,
                  seasons: _seasons,
                  exceptPartId: exceptPartId,
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await act();
  await tester.pumpAndSettle();
  expect(closed, isTrue, reason: 'лист должен закрыться по «Далее»');
  return result;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('диапазон: первый и последний сезон', (tester) async {
    final r = await _run(tester, _series(), () async {
      await tester.tap(find.text('Диапазон'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('S2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('S3'));
      await tester.pumpAndSettle();
      expect(find.text('Сезоны 2–3 · 34 серии'), findsOneWidget);
      await tester.tap(find.text('Далее'));
    });
    expect(r, (from: 2, to: 3, pass: 1));
  });

  testWidgets('занятый сезон не выбирается и подписан, где он', (tester) async {
    final r = await _run(tester, _series(), () async {
      expect(find.text('занят'), findsOneWidget);
      expect(find.textContaining('Стены держат крепче сюжета'), findsOneWidget);
      await tester.tap(find.text('S1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('S4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Далее'));
    });
    expect(r, (from: 4, to: 4, pass: 1));
  });

  testWidgets('свою рецензию лист считает свободной', (tester) async {
    final r = await _run(tester, _series(), exceptPartId: 'a', () async {
      expect(find.text('занят'), findsNothing);
      await tester.tap(find.text('S1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Далее'));
    });
    expect(r, (from: 1, to: 1, pass: 1));
  });

  testWidgets('весь сериал', (tester) async {
    final r = await _run(tester, _series(), () async {
      await tester.tap(find.text('Весь сериал'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Далее'));
    });
    expect(r, (from: null, to: null, pass: 1));
  });

  testWidgets('рецензия на весь сериал уже есть: режим недоступен', (
    tester,
  ) async {
    final r = await _run(tester, _series(whole: true), () async {
      await tester.tap(find.text('Весь сериал'));
      await tester.pumpAndSettle();
      expect(find.text('Рецензия на весь сериал уже есть'), findsOneWidget);
      await tester.tap(find.text('S2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Далее'));
    });
    expect(r, (from: 2, to: 2, pass: 1));
  });

  group('просмотр сезона', () {
    /// Первый сезон смотрели дважды, рецензия есть на первый просмотр.
    LibrarySeries rewatched() => _series()
      ..episodes.addAll([
        for (var n = 1; n <= 3; n++)
          Episode(
            season: 1,
            number: n,
            watchedAt: DateTime(2023, 5, 29, 12, n),
            rewatchViews: [Viewing(date: DateTime(2026, 8, 18, 20, n))],
          ),
        Episode(season: 2, number: 1, watchedAt: DateTime(2023, 6, 1)),
      ]);

    testWidgets('пересмотренный сезон не занят: выбран свободный просмотр', (
      tester,
    ) async {
      final r = await _run(tester, rewatched(), () async {
        // Рецензия на первый просмотр сезон целиком не занимает.
        expect(find.text('занят'), findsNothing);
        await tester.tap(find.text('S1'));
        await tester.pumpAndSettle();
        expect(find.text('КАКОЙ ПРОСМОТР'), findsOneWidget);
        expect(find.text('2-й просмотр'), findsOneWidget);
        expect(find.text('1-й просмотр'), findsOneWidget);
        // Занятый просмотр назван рецензией, которая его занимает.
        expect(
          find.textContaining('рецензия «Стены держат крепче сюжета»'),
          findsOneWidget,
        );
        expect(find.textContaining('Сезон 1 · 2-й просмотр'), findsOneWidget);
        // Тап по занятому просмотру выбор не меняет.
        await tester.tap(find.text('1-й просмотр'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Далее'));
        await tester.tap(find.text('Далее'));
      });
      expect(r, (from: 1, to: 1, pass: 2));
    });

    testWidgets('у сезона с одним просмотром выбора просмотра нет', (
      tester,
    ) async {
      final r = await _run(tester, rewatched(), () async {
        await tester.tap(find.text('S2'));
        await tester.pumpAndSettle();
        expect(find.text('КАКОЙ ПРОСМОТР'), findsNothing);
        expect(find.text('Сезон 2 · 12 серий'), findsOneWidget);
        await tester.tap(find.text('Далее'));
      });
      expect(r, (from: 2, to: 2, pass: 1));
    });
  });
}
