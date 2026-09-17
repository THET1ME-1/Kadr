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
MovieRepository _repo() {
  final series = LibrarySeries(
    tvShowId: 'got',
    title: 'Игра Престолов',
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
  });
}
