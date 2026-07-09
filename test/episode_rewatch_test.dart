import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';

/// Пересмотр серии в другой день должен давать ОТДЕЛЬНУЮ запись в ленте
/// (сессию), а не затирать вчерашний просмотр.
void main() {
  test('пересмотр в другой день = отдельная сессия, вчерашняя не пропадает', () {
    final yesterday = DateTime(2026, 7, 5, 20, 0);
    final today = DateTime(2026, 7, 6, 21, 0);

    final s = LibrarySeries(tvShowId: 't1', title: 'Test');
    // Посмотрел серию вчера.
    s.episodes.add(Episode(season: 1, number: 1, watchedAt: yesterday, score: 4));

    // Одна сессия (вчера).
    expect(s.sessions().length, 1);

    // Отметил пересмотр сегодня (как addEpisodeRewatch).
    s.episodes.first.rewatchCount += 1;
    s.episodes.first.rewatchViews.add(Viewing(date: today));

    final sessions = s.sessions();
    // Теперь ДВЕ сессии: вчерашняя и сегодняшняя.
    expect(sessions.length, 2, reason: 'вчерашний просмотр должен остаться');
    final dates = sessions.map((x) => x.start).toList()..sort();
    expect(dates.first, yesterday);
    expect(dates.last, today);
    // Каждая сессия — один просмотр серии.
    expect(sessions.every((x) => x.count == 1), true);
  });

  test('round-trip сохраняет rewatchDates', () {
    final e = Episode(
      season: 1,
      number: 1,
      watchedAt: DateTime(2026, 7, 5),
      rewatchCount: 1,
      rewatchViews: [Viewing(date: DateTime(2026, 7, 6))],
    );
    final back = Episode.fromJson(e.toJson());
    expect(back.rewatchViews.length, 1);
    expect(back.rewatchViews.first.date, DateTime(2026, 7, 6));
    expect(back.views.length, 2); // первый + повтор
  });

  test('у каждого просмотра серии своя оценка в ленте', () {
    final s = LibrarySeries(tvShowId: 't2', title: 'T');
    s.episodes.add(Episode(
      season: 1,
      number: 1,
      watchedAt: DateTime(2026, 7, 5, 20),
      score: 7.0,
      rewatchViews: [Viewing(date: DateTime(2026, 7, 6, 21), score: 9.0)],
    ));
    final sessions = s.sessions();
    expect(sessions.length, 2);
    final byDay = {
      for (final x in sessions) x.start!.day: x.episodes.first.score
    };
    expect(byDay[5], 7.0, reason: 'первый просмотр — оценка 7');
    expect(byDay[6], 9.0, reason: 'пересмотр — своя оценка 9');
  });

  test('легаси-повторы без дат материализуются, ×N = список просмотров', () {
    final e = Episode.fromJson({
      'season': 1,
      'number': 1,
      'watchedAt': '2026-07-05T20:00:00.000',
      'rewatchCount': 2, // старые повторы без дат
    });
    // Раньше расходилось: rewatchViews было пусто, views.length=1, а watchCount=3
    // (это и есть баг — ×N в карточке ≠ список «Оценки по просмотрам»). Теперь
    // недостающие повторы достраиваются как «без даты» → список = ×N, повторы
    // можно редактировать/удалять.
    expect(e.rewatchViews.length, 2);
    expect(e.rewatchViews.every((v) => v.date == null), true);
    expect(e.views.length, e.watchCount); // список записей = ×N
    expect(e.watchCount, 3);
  });

  test('недатированные повторы НЕ засоряют ленту «Просмотрено»', () {
    final e = Episode.fromJson({
      'season': 1,
      'number': 1,
      'watchedAt': '2026-07-05T20:00:00.000',
      'rewatchCount': 2,
    });
    final s = LibrarySeries(tvShowId: 't', title: 'T')..episodes.add(e);
    // В ленту (сессии с датой) попадает только датированный первый просмотр.
    final datedEvents = s
        .sessions()
        .where((x) => x.start != null)
        .fold<int>(0, (n, x) => n + x.count);
    expect(datedEvents, 1);
  });

  test('регрессия: watchedAt без даты + rewatchCount 5 + 1 датированный повтор', () {
    // Точный кейс из бага: ×6 в карточке, но в ленте/списке только 2 записи.
    final e = Episode.fromJson({
      'season': 1,
      'number': 11,
      'watchedAt': null, // «Неизвестная дата»
      'rewatchCount': 5, // счётчик обогнал реальные записи (пересмотр сезона/синк)
      'rewatchViews': [
        {'date': '2026-07-09T17:36:00.000', 'score': 10.0},
      ],
    });
    // Теперь всё сходится: 6 просмотров в списке = ×6 в карточке.
    expect(e.watchCount, 6);
    expect(e.views.length, 6);
    expect(e.views.length, e.watchCount);
    // Из шести только один датирован → в ленте одна запись.
    final s = LibrarySeries(tvShowId: 't', title: 'T')..episodes.add(e);
    final datedEvents = s
        .sessions()
        .where((x) => x.start != null)
        .fold<int>(0, (n, x) => n + x.count);
    expect(datedEvents, 1);
  });
}
