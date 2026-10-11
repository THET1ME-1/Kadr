import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/utils/season_pass.dart';

/// Серия [n] первого сезона с просмотрами в заданные дни 2026 года.
Episode _ep(int n, List<DateTime?> dates, {int season = 1}) => Episode(
      season: season,
      number: n,
      watchedAt: dates.first,
      rewatchViews: [for (final d in dates.skip(1)) Viewing(date: d)],
    );

LibrarySeries _series(List<Episode> eps) =>
    LibrarySeries(tvShowId: 's', title: 'Сериал', episodes: eps);

void main() {
  final d1 = DateTime(2023, 5, 29), d2 = DateTime(2023, 10, 2);
  final d3a = DateTime(2026, 8, 18), d3b = DateTime(2026, 8, 20);

  test('сезон не досмотрен: идёт первый просмотр', () {
    final s = _series([_ep(1, [d1]), _ep(2, [d1])]);
    final p = seasonPass(s, 1, [1, 2, 3]);
    expect(p.completed, 0);
    expect(p.current, 1);
    expect(p.done, 2);
    expect(p.total, 3);
    expect(p.left, 1);
  });

  test('сезон досмотрен один раз, пересмотр не начат', () {
    final s = _series([_ep(1, [d1]), _ep(2, [d1]), _ep(3, [d2])]);
    final p = seasonPass(s, 1, [1, 2, 3]);
    expect(p.completed, 1);
    expect(p.done, 0);
    expect(p.inProgress, isFalse);
    expect(p.from, d1);
    expect(p.to, d2);
  });

  test('идёт третий просмотр: 2 из 3, начат 18 августа', () {
    final s = _series([
      _ep(1, [d1, d2, d3a]),
      _ep(2, [d1, d2, d3b]),
      _ep(3, [d1, d2]),
    ]);
    final p = seasonPass(s, 1, [1, 2, 3]);
    expect(p.completed, 2);
    expect(p.current, 3);
    expect(p.done, 2);
    expect(p.left, 1);
    expect(p.inProgress, isTrue);
    expect(p.from, d3a);
    expect(p.to, d3b);
  });

  test('серия, которую смотрели пять раз, не тянет остальные', () {
    final s = _series([
      _ep(1, [d1, d2, d2, d3a, d3b]),
      _ep(2, [d1]),
      _ep(3, [d1]),
    ]);
    final p = seasonPass(s, 1, [1, 2, 3]);
    expect(p.completed, 1);
    expect(p.current, 2);
    expect(p.done, 1);
    expect(p.left, 2);
  });

  test('серии вне списка вышедших не считаются', () {
    final s = _series([_ep(1, [d1]), _ep(2, [d1]), _ep(9, [d1, d2])]);
    final p = seasonPass(s, 1, [1, 2]);
    expect(p.completed, 1);
    expect(p.done, 0);
    expect(p.total, 2);
  });

  test('просмотры охвата: сколько их и когда шли', () {
    final s = _series([
      _ep(1, [d1, d2, d3a]),
      _ep(2, [d1, d2, d3b]),
      _ep(1, [DateTime(2024, 11, 10), DateTime(2026, 8, 21)], season: 2),
      _ep(2, [DateTime(2024, 11, 23)], season: 2),
    ]);
    final one = scopePasses(s, 1, 1);
    expect(one.length, 3);
    expect(one[2].pass, 3);
    expect(one[2].from, d3a);
    expect(one[2].to, d3b);
    expect(one[2].complete, isTrue);
    final two = scopePasses(s, 2, 2);
    expect(two.length, 2);
    expect(two[1].complete, isFalse);
    // Весь сериал: просмотров столько, сколько у самой пересмотренной серии.
    expect(scopePasses(s, null, null).length, 3);
  });

  test('у сезона без отметок один просмотр без дат', () {
    final passes = scopePasses(_series([]), 1, 1);
    expect(passes.length, 1);
    expect(passes.single.from, isNull);
  });

  group('кнопка сезона и полоса пересмотра', () {
    SeasonPassState of(List<Episode> eps) =>
        seasonPass(_series(eps), 1, [1, 2, 3]);

    test('сезон не тронут: отметить весь, полосы нет', () {
      final p = of([]);
      expect(p.action, SeasonAction.markAll);
      expect(p.showsStrip, isFalse);
    });

    test('первый просмотр начат: отметить оставшиеся, полосы нет', () {
      final p = of([_ep(1, [d1])]);
      expect(p.action, SeasonAction.markRest);
      expect(p.left, 2);
      // Ход первого просмотра виден на таблетке сезона.
      expect(p.showsStrip, isFalse);
    });

    test('досмотрен один раз: пересмотреть, полосы нет', () {
      final p = of([_ep(1, [d1]), _ep(2, [d1]), _ep(3, [d1])]);
      expect(p.action, SeasonAction.rewatch);
      expect(p.showsStrip, isFalse);
    });

    test('пересмотр идёт: отметить оставшиеся, полоса с ходом', () {
      final p = of([_ep(1, [d1, d2]), _ep(2, [d1]), _ep(3, [d1])]);
      expect(p.action, SeasonAction.markRest);
      expect(p.left, 2);
      expect(p.showsStrip, isTrue);
    });

    test('досмотрен дважды: пересмотреть, полоса с итогом', () {
      final p = of([_ep(1, [d1, d2]), _ep(2, [d1, d2]), _ep(3, [d1, d2])]);
      expect(p.action, SeasonAction.rewatch);
      expect(p.showsStrip, isTrue);
    });
  });
}
