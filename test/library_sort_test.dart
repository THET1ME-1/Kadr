import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/utils/library_sort.dart';

/// Сортировка списка «Буду смотреть». Фильмы и сериалы идут одним списком:
/// раньше сериалы приклеивались в самый конец и терялись за сотнями фильмов.
void main() {
  ({
    String title,
    int? year,
    double? rating,
    double? score,
    int? runtimeMin,
    DateTime? addedAt
  }) item(String title,
          {int? year,
          double? rating,
          double? score,
          int? runtimeMin,
          DateTime? addedAt}) =>
      (
        title: title,
        year: year,
        rating: rating,
        score: score,
        runtimeMin: runtimeMin,
        addedAt: addedAt
      );

  SortKeys keys(
          ({
            String title,
            int? year,
            double? rating,
            double? score,
            int? runtimeMin,
            DateTime? addedAt
          }) i) =>
      SortKeys(
          title: i.title,
          year: i.year,
          rating: i.rating,
          score: i.score,
          runtimeMin: i.runtimeMin,
          addedAt: i.addedAt);

  test('по алфавиту сериал встаёт между фильмами', () {
    final list = sortLibrary(
      [item('Гладиатор'), item('Аватар'), item('Дом Дракона')],
      keys,
      LibSort.titleAz,
    );
    expect(list.map((i) => i.title).toList(),
        ['Аватар', 'Гладиатор', 'Дом Дракона']);
  });

  test('новые сверху, запись без даты — в самый низ', () {
    final list = sortLibrary(
      [
        item('Без даты'),
        item('Старая', addedAt: DateTime(2024, 1, 1)),
        item('Свежая', addedAt: DateTime(2026, 8, 1)),
      ],
      keys,
      LibSort.dateNew,
    );
    expect(list.map((i) => i.title).toList(), ['Свежая', 'Старая', 'Без даты']);
  });

  test('старые сверху, запись без даты всё равно в самом низу', () {
    final list = sortLibrary(
      [
        item('Без даты'),
        item('Свежая', addedAt: DateTime(2026, 8, 1)),
        item('Старая', addedAt: DateTime(2024, 1, 1)),
      ],
      keys,
      LibSort.dateOld,
    );
    expect(list.map((i) => i.title).toList(), ['Старая', 'Свежая', 'Без даты']);
  });

  test('по рейтингу выше идут оценённые', () {
    final list = sortLibrary(
      [item('Без оценки'), item('Слабый', rating: 5.4), item('Сильный', rating: 8.9)],
      keys,
      LibSort.ratingHigh,
    );
    expect(list.map((i) => i.title).toList(),
        ['Сильный', 'Слабый', 'Без оценки']);
  });

  test('по году свежие сверху', () {
    final list = sortLibrary(
      [item('Старьё', year: 1999), item('Новьё', year: 2026), item('Без года')],
      keys,
      LibSort.yearNew,
    );
    expect(list.map((i) => i.title).toList(), ['Новьё', 'Старьё', 'Без года']);
  });

  test('моя оценка и рейтинг источника — разные сортировки', () {
    final list = sortLibrary(
      [
        item('Чужим нравится', rating: 9.1, score: 4.0),
        item('Мне нравится', rating: 5.0, score: 9.5),
      ],
      keys,
      LibSort.scoreHigh,
    );
    expect(list.first.title, 'Мне нравится');
    final byRating = sortLibrary(
      [
        item('Чужим нравится', rating: 9.1, score: 4.0),
        item('Мне нравится', rating: 5.0, score: 9.5),
      ],
      keys,
      LibSort.ratingHigh,
    );
    expect(byRating.first.title, 'Чужим нравится');
  });

  test('по моей оценке неоценённое уходит вниз', () {
    final list = sortLibrary(
      [
        item('Без оценки'),
        item('Слабый', score: 4.5),
        item('Сильный', score: 9.0),
      ],
      keys,
      LibSort.scoreHigh,
    );
    expect(list.map((i) => i.title).toList(),
        ['Сильный', 'Слабый', 'Без оценки']);
  });

  test('длинные сверху, длительность неизвестна — вниз', () {
    final list = sortLibrary(
      [
        item('Неизвестно'),
        item('Короткий', runtimeMin: 84),
        item('Эпос', runtimeMin: 201),
      ],
      keys,
      LibSort.runtimeLong,
    );
    expect(list.map((i) => i.title).toList(),
        ['Эпос', 'Короткий', 'Неизвестно']);
  });

  test('короткие сверху — для вечера на сорок минут', () {
    final list = sortLibrary(
      [
        item('Неизвестно'),
        item('Эпос', runtimeMin: 201),
        item('Короткий', runtimeMin: 84),
      ],
      keys,
      LibSort.runtimeShort,
    );
    expect(list.map((i) => i.title).toList(),
        ['Короткий', 'Эпос', 'Неизвестно']);
  });
}
