import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/library_tab.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/settings_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Три серии одним вечером: в ленте это одна сессия сериала.
MovieRepository _repo({SeriesAir? air}) {
  final series = LibrarySeries(
    tvShowId: 'got',
    title: 'Игра Престолов',
    air: air,
    episodes: [
      Episode(
        season: 7,
        number: 2,
        watchedAt: DateTime(2026, 9, 14, 19, 56),
        score: 8.5,
      ),
      Episode(
        season: 7,
        number: 3,
        watchedAt: DateTime(2026, 9, 14, 21, 57),
        score: 9,
      ),
      Episode(
        season: 7,
        number: 4,
        watchedAt: DateTime(2026, 9, 14, 22, 52),
        score: 9,
      ),
    ],
  );
  // Круг через JSON: так же данные попадают в ленту из файла.
  return MovieRepository.detached(
    jsonDecode(
          jsonEncode({
            'series': [series.toJson()],
          }),
        )
        as Map<String, dynamic>,
  );
}

Material _blockOf(WidgetTester tester, String text) => tester.widget<Material>(
  find.ancestor(of: find.text(text), matching: find.byType(Material)).first,
);

Rect _blockRect(WidgetTester tester, String text) => tester.getRect(
  find.ancestor(of: find.text(text), matching: find.byType(Material)).first,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('сессия сериала: шапка и каждая серия своим блоком', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: LibraryTab(
            mode: LibraryMode.watched,
            repository: _repo(),
            readOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const outer = Radius.circular(22);
    const inner = Radius.circular(SettingsGroup.innerRadius);
    expect(
      _blockOf(tester, 'Игра Престолов').borderRadius,
      const BorderRadius.vertical(top: outer, bottom: inner),
    );
    // Новые серии сверху, последней в группе идёт самая ранняя.
    expect(
      _blockOf(tester, 'S7·E4').borderRadius,
      const BorderRadius.vertical(top: inner, bottom: inner),
    );
    expect(
      _blockOf(tester, 'S7·E3').borderRadius,
      const BorderRadius.vertical(top: inner, bottom: inner),
    );
    expect(
      _blockOf(tester, 'S7·E2').borderRadius,
      const BorderRadius.vertical(top: inner, bottom: outer),
    );

    // Блоки разделяет зазор, линии между шапкой и сериями нет.
    final head = _blockRect(tester, 'Игра Престолов');
    final first = _blockRect(tester, 'S7·E4');
    final second = _blockRect(tester, 'S7·E3');
    expect(first.top - head.bottom, SettingsGroup.gap);
    expect(second.top - first.bottom, SettingsGroup.gap);
    expect(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Игра Престолов'),
              matching: find.byType(Material),
            )
            .first,
        matching: find.byType(Divider),
      ),
      findsNothing,
    );

    // У каждой серии круглый значок, как у пунктов настроек (вариант D1).
    for (final label in ['S7·E4', 'S7·E3', 'S7·E2']) {
      final block = find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first;
      final chip = find.descendant(
        of: block,
        matching: find.byType(SettingsIconChip),
      );
      expect(chip, findsOneWidget, reason: label);
      expect(tester.widget<SettingsIconChip>(chip).size, 40, reason: label);
      expect(
        find.descendant(
          of: chip,
          matching: find.byIcon(Icons.play_arrow_rounded),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
  });

  Future<ColorScheme> pumpFeed(WidgetTester tester, SeriesAir air) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final theme = AppTheme.dark(AppTheme.defaultSeed);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: LibraryTab(
            mode: LibraryMode.watched,
            repository: _repo(air: air),
            readOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return theme.colorScheme;
  }

  testWidgets('финал: шапка залита акцентом, вместо серий итог', (
    tester,
  ) async {
    final scheme = await pumpFeed(
      tester,
      const SeriesAir(status: 'Ended', aired: 3, lastSeason: 7),
    );
    expect(find.text('Финал · 3\u00A0серии за\u00A0один\u00A0день'), findsOneWidget);
    expect(find.textContaining('E2–E4'), findsNothing);
    expect(_blockOf(tester, 'Игра Престолов').color, scheme.primaryContainer);
    expect(find.byIcon(Icons.flag_rounded), findsWidgets);
    // Серии остаются обычными блоками.
    expect(_blockOf(tester, 'S7·E4').color, scheme.surfaceContainerHigh);
  });

  testWidgets('догнал: шапка тише финала и говорит, что ждём', (tester) async {
    final scheme = await pumpFeed(
      tester,
      const SeriesAir(status: 'Returning Series', aired: 3, lastSeason: 7),
    );
    expect(find.text('Догнал · ждём 8-й сезон'), findsOneWidget);
    expect(
      _blockOf(tester, 'Игра Престолов').color,
      scheme.surfaceContainerHighest,
    );
    expect(find.byIcon(Icons.update_rounded), findsWidgets);
  });

  testWidgets('сериал ещё смотрят: шапка как раньше', (tester) async {
    final scheme = await pumpFeed(
      tester,
      const SeriesAir(status: 'Returning Series', aired: 5, lastSeason: 7),
    );
    expect(find.textContaining('E2–E4'), findsOneWidget);
    expect(_blockOf(tester, 'Игра Престолов').color, scheme.surfaceContainerHigh);
  });

  testWidgets('финал: оценка в шапке по всему сериалу, а не за вечер', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final series = LibrarySeries(
      tvShowId: 'got',
      title: 'Игра Престолов',
      air: const SeriesAir(status: 'Ended', aired: 2, lastSeason: 1),
      episodes: [
        Episode(season: 1, number: 1, watchedAt: DateTime(2026, 9, 1, 20), score: 6),
        Episode(season: 1, number: 2, watchedAt: DateTime(2026, 9, 14, 20), score: 9),
      ],
    );
    final repo = MovieRepository.detached(
      jsonDecode(jsonEncode({'series': [series.toJson()]}))
          as Map<String, dynamic>,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: LibraryTab(
            mode: LibraryMode.watched,
            repository: repo,
            readOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final head = find
        .ancestor(
          of: find.textContaining('Финал'),
          matching: find.byType(Material),
        )
        .first;
    expect(find.descendant(of: head, matching: find.text('7.5')), findsOneWidget);
    expect(find.descendant(of: head, matching: find.text('9.0')), findsNothing);
  });
}
