import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/utils/series_finale.dart';
import 'package:kadr/widgets/series_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

LibrarySeries _series(SeriesAir air) => LibrarySeries(
  tvShowId: 'hotd',
  title: 'Дом Дракона',
  air: air,
  episodes: [
    Episode(season: 3, number: 1, watchedAt: DateTime(2026, 10, 1, 21)),
    Episode(season: 3, number: 2, watchedAt: DateTime(2026, 10, 7, 21, 40)),
  ],
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.runAsync(() => LocaleController.instance.setCode('ru'));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('таблетка статуса на экране сериала', () {
    testWidgets('досмотрел: дата финала', (tester) async {
      await _pump(
        tester,
        SeriesStatusPill(
          series: _series(const SeriesAir(status: 'Ended', aired: 2)),
        ),
      );
      expect(find.text('Досмотрел 7 октября 2026'), findsOneWidget);
      expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    });

    testWidgets('догнал: чего ждём', (tester) async {
      await _pump(
        tester,
        SeriesStatusPill(
          series: _series(
            const SeriesAir(
              status: 'Returning Series',
              aired: 2,
              lastSeason: 3,
            ),
          ),
        ),
      );
      expect(find.text('Догнал · ждём 4-й сезон'), findsOneWidget);
      expect(find.byIcon(Icons.update_rounded), findsOneWidget);
    });

    testWidgets('сериал смотрят: таблетки нет', (tester) async {
      await _pump(
        tester,
        SeriesStatusPill(
          series: _series(
            const SeriesAir(status: 'Returning Series', aired: 5),
          ),
        ),
      );
      expect(find.byType(Text), findsNothing);
    });
  });

  group('значок на постере', () {
    testWidgets('досмотрел: флажок вместо кольца', (tester) async {
      await _pump(
        tester,
        const SeriesProgressPill(seen: 94, total: 94, run: SeriesRun.finished),
      );
      expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('94'), findsOneWidget);
    });

    testWidgets('догнал: стрелки и счёт вышедших', (tester) async {
      await _pump(
        tester,
        const SeriesProgressPill(seen: 28, total: 28, run: SeriesRun.caughtUp),
      );
      expect(find.byIcon(Icons.update_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('28/28'), findsOneWidget);
    });

    testWidgets('смотрю: кольцо как раньше', (tester) async {
      await _pump(tester, const SeriesProgressPill(seen: 12, total: 24));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('12/24'), findsOneWidget);
    });
  });
}
