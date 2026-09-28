import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/utils/episode_grid.dart';
import 'package:kadr/utils/share_palette.dart';
import 'package:kadr/widgets/episode_grid_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

EpisodeGrid _grid(List<List<double?>> seasons, {List<int>? sizes}) =>
    EpisodeGrid([
      for (var i = 0; i < seasons.length; i++)
        GridSeason(i + 1, [
          for (var j = 0; j < (sizes?[i] ?? seasons[i].length); j++)
            j < seasons[i].length
                ? GridCell(watched: true, score: seasons[i][j])
                : const GridCell(),
        ]),
    ]);

EpisodeGridCardData _data(EpisodeGrid grid, {bool numbers = true}) =>
    EpisodeGridCardData(
      title: 'Игра престолов',
      year: 2011,
      palette: SharePalette.fallback,
      grid: grid,
      showNumbers: numbers,
      dateNote: '28 сентября 2026',
    );

void _roomy(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: Center(child: child)),
  ),
);

final _got = _grid(
  [
    List.filled(10, 9.5),
    [9, 9, 9, 9, 9, 9, 9.5, 9.5, 9.6, 8.8],
    [8.8, 8.8, 8.8, 8],
    [],
  ],
  sizes: [10, 10, 10, 7],
);

final _flash = _grid([
  for (final n in [23, 23, 23, 23, 22, 19, 18, 20, 13]) List.filled(n, 5.0),
]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Держит размер, который посчитал GridLayout', (tester) async {
    _roomy(tester);
    for (final g in [_got, _flash, _grid([[9, 8, null]])]) {
      await tester.pumpWidget(_wrap(EpisodeGridCard(data: _data(g))));
      expect(
        tester.getSize(find.byType(EpisodeGridCard)),
        GridLayout.of(g).size,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Название, средняя и подписи на месте', (tester) async {
    _roomy(tester);
    await tester.pumpWidget(_wrap(EpisodeGridCard(data: _data(_got))));

    expect(find.text('Игра престолов'), findsOneWidget);
    expect(find.text('Моя средняя'), findsOneWidget);
    expect(find.text('Шедевр'), findsOneWidget);
    expect(find.text('Не видел'), findsOneWidget);
    expect(find.textContaining('Просмотрено 24 из 37'), findsOneWidget);
    expect(find.textContaining('Kadr'), findsOneWidget);
    expect(find.text('S4'), findsOneWidget);
    expect(find.text('9,6'), findsOneWidget);
  });

  testWidgets('Непросмотренная серия — рамка во всю клетку', (tester) async {
    _roomy(tester);
    await tester.pumpWidget(_wrap(EpisodeGridCard(data: _data(_got))));
    final layout = GridLayout.of(_got);
    final frames = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border != null,
    );
    final sizes = tester
        .widgetList(frames)
        .map((w) => tester.getSize(find.byWidget(w)))
        .where((s) => s.width > 10);
    // 6 серий шестого сезона и 7 серий седьмого.
    expect(sizes.length, 13);
    for (final s in sizes) {
      expect(s, Size(layout.cellWidth, layout.rowHeight));
    }
  });

  testWidgets('Сетка короткого сериала стоит по центру', (tester) async {
    _roomy(tester);
    final g = _grid([[9, 8], [7, 6]]);
    await tester.pumpWidget(_wrap(EpisodeGridCard(data: _data(g))));
    final card = tester.getRect(find.byType(EpisodeGridCard));
    final first = tester.getRect(find.text('S1'));
    final last = tester.getRect(find.text('S2'));
    final left = first.center.dx - card.left;
    final right = card.right - last.center.dx;
    // Слева ещё колонка номеров серий, поэтому поля не равны, но близки.
    expect(
      (left - right).abs(),
      lessThan(GridLayout.labelWidth + GridLayout.gap + 1),
    );
  });

  testWidgets('«Только цвет» убирает числа из клеток', (tester) async {
    _roomy(tester);
    await tester.pumpWidget(
      _wrap(EpisodeGridCard(data: _data(_got, numbers: false))),
    );
    expect(find.text('9,6'), findsNothing);
  });

  testWidgets('Просмотренная без оценки попадает в легенду', (tester) async {
    _roomy(tester);
    await tester.pumpWidget(
      _wrap(EpisodeGridCard(data: _data(_grid([[9, null]])))),
    );
    expect(find.text('Без оценки'), findsOneWidget);
    expect(find.text('Не видел'), findsNothing);
  });

  for (final code in ['en', 'de', 'fr', 'es', 'it', 'pt']) {
    testWidgets('Собирается без переполнения на языке $code', (tester) async {
      _roomy(tester);
      await tester.runAsync(() => LocaleController.instance.setCode(code));
      addTearDown(() => LocaleController.instance.setCode('ru'));
      await tester.pumpWidget(_wrap(EpisodeGridCard(data: _data(_got))));
      expect(tester.takeException(), isNull);
    });
  }
}
