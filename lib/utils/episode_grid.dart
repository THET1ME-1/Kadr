import 'package:flutter/painting.dart';

import '../models/library_entry.dart';

/// Ступень оценки для сетки серий.
///
/// Пороги сдвинуты вверх: личные оценки почти всегда выше 8, и на плавной
/// шкале приложения ([scoreColor]) 8,5 и 9,6 выходят одним золотом. Здесь
/// у верхних двух баллов три ступени.
enum ScoreStep { masterpiece, great, good, fine, mixed, poor }

ScoreStep scoreStep(double score) {
  if (score >= 9.5) return ScoreStep.masterpiece;
  if (score >= 9) return ScoreStep.great;
  if (score >= 8) return ScoreStep.good;
  if (score >= 7) return ScoreStep.fine;
  if (score >= 5) return ScoreStep.mixed;
  return ScoreStep.poor;
}

/// Заливка клетки. Цвета утверждены по макету «Сетка оценок» (2026-09-28).
Color scoreStepColor(ScoreStep step) => switch (step) {
  ScoreStep.masterpiece => const Color(0xFF17915F),
  ScoreStep.great => const Color(0xFF3FC47E),
  ScoreStep.good => const Color(0xFFA3D65C),
  ScoreStep.fine => const Color(0xFFF1CF4B),
  ScoreStep.mixed => const Color(0xFFF08B3B),
  ScoreStep.poor => const Color(0xFFDF4F3E),
};

/// Цифра поверх заливки: тёмная на светлых ступенях, белая на тёмных.
Color onScoreStepColor(ScoreStep step) =>
    scoreStepColor(step).computeLuminance() > 0.3
    ? const Color(0xFF0B1417)
    : const Color(0xFFFFFFFF);

/// Одна клетка: серия просмотрена или нет, и с какой оценкой.
class GridCell {
  const GridCell({this.watched = false, this.score, this.rewatched = false});

  final bool watched;

  /// Последняя поставленная оценка серии; `null` — не оценивали.
  final double? score;

  /// Серию смотрели больше одного раза.
  final bool rewatched;
}

class GridSeason {
  GridSeason(this.number, this.cells);

  final int number;
  final List<GridCell> cells;

  /// Средняя по оценённым сериям сезона.
  double? get average => _mean(cells);
}

class EpisodeGrid {
  EpisodeGrid(this.seasons);

  final List<GridSeason> seasons;

  Iterable<GridCell> get _cells => seasons.expand((s) => s.cells);

  int get total => _cells.length;
  int get watched => _cells.where((c) => c.watched).length;
  int get rated => _cells.where((c) => c.score != null).length;
  int get maxEpisodes =>
      seasons.fold(0, (m, s) => s.cells.length > m ? s.cells.length : m);
  bool get hasUnwatched => _cells.any((c) => !c.watched);
  bool get hasUnrated => _cells.any((c) => c.watched && c.score == null);

  /// Средняя по всем оценённым сериям.
  double? get average => _mean(_cells);
}

double? _mean(Iterable<GridCell> cells) {
  var sum = 0.0;
  var n = 0;
  for (final c in cells) {
    if (c.score == null) continue;
    sum += c.score!;
    n++;
  }
  return n == 0 ? null : sum / n;
}

/// Размеры карточки-сетки в dp. Считаются заранее, а не вёрсткой: превью в
/// листе ужимает карточку `Transform`'ом, и снимку нужен точный размер холста.
class GridLayout {
  GridLayout._({
    required this.seasons,
    required this.rows,
    required this.cellWidth,
    required this.rowHeight,
    required this.fontSize,
  });

  factory GridLayout.of(EpisodeGrid grid) {
    final n = grid.seasons.isEmpty ? 1 : grid.seasons.length;
    final rows = grid.maxEpisodes;
    // У сериала на пару сезонов клетка шире потолка не растёт: сетка
    // встаёт по центру, а не превращается в полосы во всю карточку.
    final cellWidth = ((width - 2 * padX - labelWidth - gap * n) / n).clamp(
      0.0,
      maxCellWidth,
    );
    // Больше 30 строк — ряды ниже, иначе длинный сезон тянет картинку на
    // несколько экранов.
    final long = rows > 30;
    final rowHeight = (cellWidth * 0.62)
        .clamp(long ? 12.0 : 18.0, long ? 14.0 : 34.0)
        .roundToDouble();
    final fontSize = cellWidth >= 44
        ? 12.0
        : cellWidth >= 32
        ? 10.5
        : cellWidth >= 24 && rowHeight >= 16
        ? 9.0
        : 0.0;
    return GridLayout._(
      seasons: n,
      rows: rows,
      cellWidth: cellWidth,
      rowHeight: rowHeight,
      fontSize: fontSize,
    );
  }

  static const double width = 360;
  static const double padX = 18;
  static const double gap = 4;
  static const double labelWidth = 22;
  static const double maxCellWidth = 72;
  static const double heroHeight = 238;
  static const double headerHeight = 34;
  static const double legendHeight = 34;
  static const double signatureHeight = 20;

  final int seasons;
  final int rows;
  final double cellWidth;
  final double rowHeight;

  /// Кегль числа в клетке; 0 — клетки слишком узкие, остаётся только цвет.
  final double fontSize;

  double get gridHeight => headerHeight + rows * (rowHeight + gap);

  /// Ширина сетки вместе с номерами серий; уже карточки, если клетки упёрлись
  /// в [maxCellWidth].
  double get gridWidth => labelWidth + seasons * (cellWidth + gap);

  Size get size => Size(
    width,
    heroHeight +
        14 +
        gridHeight +
        14 +
        legendHeight +
        16 +
        signatureHeight +
        16,
  );
}

/// Последняя поставленная оценка: у пересмотра своя, иначе остаётся прежняя.
double? _lastScore(Episode e) {
  double? last;
  for (final v in e.views) {
    final s = e.scoreOfView(v);
    if (v.score != null || last == null) last = s;
  }
  return last;
}

/// Собирает сетку сериала.
///
/// [seasonSizes] — число серий в сезоне по TMDB, как на экране сериала. Серии
/// вне этой структуры не показываются, спецвыпуски (сезон 0) тоже. Без TMDB
/// сезоны строятся по отмеченным сериям: до самого дальнего номера.
EpisodeGrid buildEpisodeGrid(LibrarySeries series, Map<int, int> seasonSizes) {
  final sizes = <int, int>{};
  if (seasonSizes.isNotEmpty) {
    seasonSizes.forEach((season, n) {
      if (season > 0 && n > 0) sizes[season] = n;
    });
  } else {
    for (final e in series.episodes) {
      final s = e.season, n = e.number;
      if (s == null || n == null || s <= 0 || n <= 0) continue;
      if (n > (sizes[s] ?? 0)) sizes[s] = n;
    }
  }

  final seasons = <GridSeason>[];
  for (final number in sizes.keys.toList()..sort()) {
    final cells = List<GridCell>.generate(sizes[number]!, (i) {
      final e = series.watchedEpisode(number, i + 1);
      if (e == null) return const GridCell();
      return GridCell(
        watched: true,
        score: _lastScore(e),
        rewatched: e.watchCount > 1,
      );
    });
    seasons.add(GridSeason(number, cells));
  }
  return EpisodeGrid(seasons);
}
