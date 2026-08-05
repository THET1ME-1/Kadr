import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/utils/library_sort.dart';

/// Сортировка списка «Буду смотреть». Фильмы и сериалы идут одним списком:
/// раньше сериалы приклеивались в самый конец и терялись за сотнями фильмов.
void main() {
  ({String title, int? year, double? rating, DateTime? addedAt}) item(
          String title,
          {int? year,
          double? rating,
          DateTime? addedAt}) =>
      (title: title, year: year, rating: rating, addedAt: addedAt);

  SortKeys keys(({String title, int? year, double? rating, DateTime? addedAt}) i) =>
      SortKeys(
          title: i.title, year: i.year, rating: i.rating, addedAt: i.addedAt);

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
}
