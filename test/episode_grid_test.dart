import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/utils/episode_grid.dart';

LibrarySeries _series(List<Episode> eps) =>
    LibrarySeries(tvShowId: 's', title: 'S', episodes: eps);

void main() {
  layoutTests();
  group('scoreStep', () {
    test('Пороги сдвинуты вверх, к личным оценкам', () {
      expect(scoreStep(10), ScoreStep.masterpiece);
      expect(scoreStep(9.5), ScoreStep.masterpiece);
      expect(scoreStep(9.4), ScoreStep.great);
      expect(scoreStep(9.0), ScoreStep.great);
      expect(scoreStep(8.9), ScoreStep.good);
      expect(scoreStep(8.0), ScoreStep.good);
      expect(scoreStep(7.9), ScoreStep.fine);
      expect(scoreStep(7.0), ScoreStep.fine);
      expect(scoreStep(6.9), ScoreStep.mixed);
      expect(scoreStep(5.0), ScoreStep.mixed);
      expect(scoreStep(4.9), ScoreStep.poor);
      expect(scoreStep(1.0), ScoreStep.poor);
    });
  });

  group('buildEpisodeGrid', () {
    test('Структура берётся из размеров сезонов, пропуски пустые', () {
      final g = buildEpisodeGrid(
        _series([
          Episode(season: 1, number: 1, score: 9),
          Episode(season: 1, number: 3, score: 8),
          Episode(season: 2, number: 2, score: 7),
        ]),
        {1: 3, 2: 2},
      );
      expect(g.seasons.map((s) => s.number), [1, 2]);
      expect(g.seasons[0].cells.map((c) => c.score), [9, null, 8]);
      expect(g.seasons[0].cells.map((c) => c.watched), [true, false, true]);
      expect(g.seasons[1].cells.map((c) => c.watched), [false, true]);
      expect(g.total, 5);
      expect(g.watched, 3);
      expect(g.maxEpisodes, 3);
      expect(g.hasUnwatched, isTrue);
    });

    test('Серии вне структуры TMDB и спецвыпуски не считаются', () {
      final g = buildEpisodeGrid(
        _series([
          Episode(season: 1, number: 1, score: 9),
          Episode(season: 1, number: 5, score: 2),
          Episode(season: 0, number: 1, score: 2),
          Episode(season: 3, number: 1, score: 2),
          Episode(score: 2),
        ]),
        {1: 2},
      );
      expect(g.seasons.length, 1);
      expect(g.watched, 1);
      expect(g.average, 9);
    });

    test('Без TMDB сезоны строятся по отмеченным сериям', () {
      final g = buildEpisodeGrid(
        _series([
          Episode(season: 2, number: 4, score: 6),
          Episode(season: 1, number: 2, score: 8),
        ]),
        const {},
      );
      expect(g.seasons.map((s) => s.number), [1, 2]);
      expect(g.seasons[0].cells.length, 2);
      expect(g.seasons[1].cells.length, 4);
    });

    test('У пересмотренной серии берётся последняя оценка', () {
      final g = buildEpisodeGrid(
        _series([
          Episode(
            season: 1,
            number: 1,
            score: 6,
            rewatchViews: [Viewing(score: 9), Viewing()],
          ),
        ]),
        {1: 1},
      );
      final cell = g.seasons.single.cells.single;
      expect(cell.score, 9);
      expect(cell.rewatched, isTrue);
    });

    test('Просмотренная без оценки отличается от непросмотренной', () {
      final g = buildEpisodeGrid(
        _series([Episode(season: 1, number: 1)]),
        {1: 2},
      );
      final cells = g.seasons.single.cells;
      expect(cells[0].watched, isTrue);
      expect(cells[0].score, isNull);
      expect(cells[1].watched, isFalse);
      expect(g.hasUnrated, isTrue);
      expect(g.average, isNull);
      expect(g.seasons.single.average, isNull);
    });

    test('Средние считаются только по оценённым', () {
      final g = buildEpisodeGrid(
        _series([
          Episode(season: 1, number: 1, score: 9),
          Episode(season: 1, number: 2, score: 8),
          Episode(season: 1, number: 3),
          Episode(season: 2, number: 1, score: 4),
        ]),
        {1: 3, 2: 1},
      );
      expect(g.seasons[0].average, 8.5);
      expect(g.seasons[1].average, 4);
      expect(g.average, closeTo(7, 1e-9));
      expect(g.rated, 3);
    });

    test('Сезон без серий в структуре пропускается', () {
      final g = buildEpisodeGrid(
        _series([Episode(season: 1, number: 1, score: 9)]),
        {1: 1, 2: 0},
      );
      expect(g.seasons.map((s) => s.number), [1]);
    });
  });
}

EpisodeGrid _flat(List<int> sizes) => EpisodeGrid([
  for (var i = 0; i < sizes.length; i++)
    GridSeason(i + 1, List.filled(sizes[i], const GridCell(watched: true, score: 9))),
]);

void layoutTests() {
  group('GridLayout', () {
    test('Ширина всегда 360, клетки делят её поровну', () {
      final l = GridLayout.of(_flat(List.filled(6, 10)));
      expect(l.size.width, 360);
      expect(GridLayout.labelWidth + 6 * (l.cellWidth + GridLayout.gap),
          closeTo(360 - 2 * GridLayout.padX, 1e-6));
    });

    test('У короткого сериала клетки не растягиваются во всю ширину', () {
      final l = GridLayout.of(_flat([9, 10]));
      expect(l.cellWidth, GridLayout.maxCellWidth);
      expect(l.gridWidth, lessThan(360 - 2 * GridLayout.padX));
    });

    test('Высота растёт с числом серий', () {
      final short = GridLayout.of(_flat([8, 8]));
      final long = GridLayout.of(_flat([23, 23]));
      expect(long.size.height, greaterThan(short.size.height));
    });

    test('В узких клетках числа прячутся', () {
      expect(GridLayout.of(_flat([10, 10])).fontSize, greaterThan(0));
      expect(GridLayout.of(_flat(List.filled(16, 10))).fontSize, 0);
    });

    test('У длинного сериала строки ниже', () {
      final l = GridLayout.of(_flat([60]));
      expect(l.rowHeight, lessThan(18));
    });
  });
}
