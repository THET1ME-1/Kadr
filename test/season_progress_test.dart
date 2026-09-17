import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/utils/season_progress.dart';
import 'package:kadr/widgets/season_pill.dart';

LibrarySeries _series(List<(int, int)> marks) => LibrarySeries(
  tvShowId: 's',
  title: 'Сериал',
  episodes: [
    for (final (season, number) in marks)
      Episode(season: season, number: number),
  ],
);

void main() {
  group('seasonProgress', () {
    test('ничего не отмечено', () {
      final p = seasonProgress(_series([]), 1, 10);
      expect(p.seen, 0);
      expect(p.total, 10);
      expect(p.fraction, 0);
      expect(p.done, isFalse);
    });

    test('начатый сезон', () {
      final p = seasonProgress(
        _series([(4, 1), (4, 2), (4, 3), (3, 5)]),
        4,
        10,
      );
      expect(p.seen, 3);
      expect(p.fraction, closeTo(0.3, 1e-9));
      expect(p.done, isFalse);
    });

    test('досмотренный сезон', () {
      final p = seasonProgress(
        _series([for (var n = 1; n <= 8; n++) (2, n)]),
        2,
        8,
      );
      expect(p.done, isTrue);
      expect(p.fraction, 1);
    });

    test('пересмотр и серии вне сезона не накручивают счёт', () {
      final p = seasonProgress(
        _series([(1, 1), (1, 1), (1, 2), (1, 0), (1, 11), (2, 3)]),
        1,
        10,
      );
      expect(p.seen, 2);
    });

    test('у сезона без серий нет ни доли, ни галочки', () {
      final p = seasonProgress(_series([(0, 1)]), 0, 0);
      expect(p.fraction, 0);
      expect(p.done, isFalse);
    });
  });

  group('SeasonPill', () {
    Future<void> pump(
      WidgetTester tester, {
      required double fraction,
      required bool done,
      bool selected = false,
      VoidCallback? onTap,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: Center(
            child: SeasonPill(
              label: 'Сезон 4',
              fraction: fraction,
              done: done,
              selected: selected,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    );

    ShapeDecoration decoration(WidgetTester tester) =>
        tester
                .widget<Ink>(
                  find.descendant(
                    of: find.byType(SeasonPill),
                    matching: find.byType(Ink),
                  ),
                )
                .decoration!
            as ShapeDecoration;

    testWidgets('досмотренный сезон с галочкой', (tester) async {
      await pump(tester, fraction: 1, done: true);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('начатый сезон заполнен на свою долю и без галочки', (
      tester,
    ) async {
      await pump(tester, fraction: 0.3, done: false);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      final g = decoration(tester).gradient! as LinearGradient;
      expect(g.stops, [0, 0.3, 0.3, 1]);
    });

    testWidgets('выбранный сезон обведён акцентом', (tester) async {
      await pump(tester, fraction: 0, done: false, selected: true);
      final scheme = AppTheme.dark(AppTheme.defaultSeed).colorScheme;
      final side = (decoration(tester).shape as StadiumBorder).side;
      expect(side.width, 2);
      expect(side.color, scheme.primary);

      await pump(tester, fraction: 0, done: false);
      expect((decoration(tester).shape as StadiumBorder).side, BorderSide.none);
    });

    testWidgets('нажатие выбирает сезон', (tester) async {
      var taps = 0;
      await pump(tester, fraction: 0.5, done: false, onTap: () => taps++);
      await tester.tap(find.text('Сезон 4'));
      expect(taps, 1);
    });
  });
}
