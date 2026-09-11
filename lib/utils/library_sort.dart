/// Сортировка библиотеки. Вынесена из экрана, чтобы фильмы и сериалы шли одним
/// списком: раньше сериалы приклеивались в конец и терялись за сотнями фильмов.
library;

enum LibSort {
  dateNew,
  dateOld,
  ratingHigh,
  scoreHigh,
  runtimeLong,
  runtimeShort,
  titleAz,
  yearNew,
}

/// Поля, по которым сортируется запись — общие для фильма и сериала.
class SortKeys {
  final String title;
  final int? year;

  /// Рейтинг источника (TMDB/ПоискКино) — чужая оценка.
  final double? rating;

  /// Моя оценка. Отдельно от [rating]: в «Буду смотреть» её обычно нет, а в
  /// «Просмотрено» сортировать хочется именно по ней.
  final double? score;
  final int? runtimeMin;
  final DateTime? addedAt;
  const SortKeys({
    required this.title,
    this.year,
    this.rating,
    this.score,
    this.runtimeMin,
    this.addedAt,
  });
}

/// Порядок записей для выбранного режима. Записи без нужного поля (сериал без
/// даты добавления, фильм без года) уходят вниз — сверху всегда осмысленные.
List<T> sortLibrary<T>(
  List<T> items,
  SortKeys Function(T) keysOf,
  LibSort mode,
) {
  final list = [...items];
  int byMissing(Object? a, Object? b) {
    if ((a == null) == (b == null)) return 0;
    return a == null ? 1 : -1;
  }

  switch (mode) {
    case LibSort.dateNew:
      list.sort((a, b) {
        final x = keysOf(a).addedAt, y = keysOf(b).addedAt;
        final miss = byMissing(x, y);
        return miss != 0 ? miss : y!.compareTo(x!);
      });
    case LibSort.dateOld:
      list.sort((a, b) {
        final x = keysOf(a).addedAt, y = keysOf(b).addedAt;
        final miss = byMissing(x, y);
        return miss != 0 ? miss : x!.compareTo(y!);
      });
    case LibSort.ratingHigh:
      list.sort((a, b) {
        final x = keysOf(a).rating, y = keysOf(b).rating;
        final miss = byMissing(x, y);
        return miss != 0 ? miss : y!.compareTo(x!);
      });
    case LibSort.scoreHigh:
      list.sort((a, b) {
        final x = keysOf(a).score, y = keysOf(b).score;
        final miss = byMissing(x, y);
        return miss != 0 ? miss : y!.compareTo(x!);
      });
    case LibSort.runtimeLong:
      list.sort((a, b) {
        final x = keysOf(a).runtimeMin, y = keysOf(b).runtimeMin;
        final miss = byMissing(x, y);
        return miss != 0 ? miss : y!.compareTo(x!);
      });
    case LibSort.runtimeShort:
      list.sort((a, b) {
        final x = keysOf(a).runtimeMin, y = keysOf(b).runtimeMin;
        final miss = byMissing(x, y);
        return miss != 0 ? miss : x!.compareTo(y!);
      });
    case LibSort.titleAz:
      list.sort(
        (a, b) => keysOf(
          a,
        ).title.toLowerCase().compareTo(keysOf(b).title.toLowerCase()),
      );
    case LibSort.yearNew:
      list.sort((a, b) {
        final x = keysOf(a).year, y = keysOf(b).year;
        final miss = byMissing(x, y);
        return miss != 0 ? miss : y!.compareTo(x!);
      });
  }
  return list;
}
