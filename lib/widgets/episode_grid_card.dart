import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/episode_grid.dart';
import '../utils/share_palette.dart';
import 'share_card.dart';

/// Всё, что нужно сетке оценок. Постер приходит раскодированным, как у
/// карточки «Поделиться»: снимок делается сразу после сборки.
class EpisodeGridCardData {
  const EpisodeGridCardData({
    required this.title,
    required this.palette,
    required this.grid,
    required this.dateNote,
    this.year,
    this.poster,
    this.showNumbers = true,
  });

  final String title;
  final int? year;
  final SharePalette palette;
  final EpisodeGrid grid;

  /// Дата в подвале: когда картинку сделали.
  final String dateNote;
  final ui.Image? poster;

  /// Выключено — в клетках остаётся только цвет.
  final bool showNumbers;
}

/// Картинка «Сетка оценок», подача «Афиша» (утверждена по макету 2026-09-28):
/// постер во всю ширину сверху, название поверх него, средняя сезона над
/// столбцом, клетки по ступеням [ScoreStep].
///
/// Ширина 360 dp, высота из [GridLayout]: снимок с pixelRatio 3 даёт 1080 px.
class EpisodeGridCard extends StatelessWidget {
  const EpisodeGridCard({super.key, required this.data});

  final EpisodeGridCardData data;

  @override
  Widget build(BuildContext context) {
    final layout = GridLayout.of(data.grid);
    final size = layout.size;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: ColoredBox(
          color: data.palette.deep,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: GridLayout.heroHeight,
                    child: _Hero(data: data),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: SizedBox(
                      width: layout.gridWidth,
                      child: _Grid(data: data, layout: layout),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GridLayout.padX,
                    ),
                    child: _Legend(grid: data.grid),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GridLayout.padX,
                    ),
                    child: SizedBox(
                      height: GridLayout.signatureHeight,
                      child: Row(
                        children: [
                          const ShareSignature(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${tr('grid_my_scores')} · ${data.dateNote}',
                              maxLines: 1,
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: _body(11, Colors.white.withValues(alpha: 0.5)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: ShareGrainPainter(seed: data.title.hashCode),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _body(double size, Color color, {FontWeight w = FontWeight.w500}) =>
    TextStyle(
      fontFamily: AppTheme.bodyFont,
      fontSize: size,
      fontWeight: w,
      color: color,
      height: 1.2,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );

TextStyle _display(double size, Color color, {FontWeight w = FontWeight.w700}) =>
    TextStyle(
      fontFamily: AppTheme.displayFont,
      fontSize: size,
      fontWeight: w,
      color: color,
      height: 1.1,
    );

String _fmt(double v) => v >= 9.95 ? '10' : formatScore(v);

/// Верх: постер, затемнённый книзу в тон карточки, и текст поверх.
class _Hero extends StatelessWidget {
  const _Hero({required this.data});

  final EpisodeGridCardData data;

  @override
  Widget build(BuildContext context) {
    final deep = data.palette.deep;
    final grid = data.grid;
    final avg = grid.average;
    final long = data.title.length > 14;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (data.poster != null)
          RawImage(
            image: data.poster,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.64),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [data.palette.accent.withValues(alpha: 0.55), deep],
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.35, 1],
              colors: [
                Colors.black.withValues(alpha: 0.05),
                deep.withValues(alpha: 0),
                deep,
              ],
            ),
          ),
        ),
        Positioned(
          left: GridLayout.padX,
          right: GridLayout.padX,
          bottom: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.year == null
                          ? tr('grid_series')
                          : '${tr('grid_series')} · ${data.year}',
                      style: _body(
                        11,
                        Colors.white.withValues(alpha: 0.7),
                        w: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _display(
                        long ? 21 : 26,
                        Colors.white,
                        w: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${trn('grid_seasons', grid.seasons.length)} · '
                      '${trf('grid_watched_of', {'a': grid.watched, 'n': grid.total})}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _body(12, Colors.white.withValues(alpha: 0.72)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    avg == null ? '—' : _fmt(avg),
                    style: _display(
                      30,
                      avg == null
                          ? Colors.white.withValues(alpha: 0.4)
                          : scoreStepColor(scoreStep(avg)),
                      w: FontWeight.w800,
                    ).copyWith(letterSpacing: -1, height: 1),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tr('grid_my_average'),
                    style: _body(10.5, Colors.white.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Сетка: сезоны столбцами, серии строками. Каждая клетка и каждый ряд
/// стоят после зазора [GridLayout.gap], так высота сходится с расчётом.
class _Grid extends StatelessWidget {
  const _Grid({required this.data, required this.layout});

  final EpisodeGridCardData data;
  final GridLayout layout;

  @override
  Widget build(BuildContext context) {
    final seasons = data.grid.seasons;
    final dim = Colors.white.withValues(alpha: 0.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: GridLayout.headerHeight,
          child: Row(
            children: [
              const SizedBox(width: GridLayout.labelWidth),
              for (final s in seasons) ...[
                const SizedBox(width: GridLayout.gap),
                SizedBox(
                  width: layout.cellWidth,
                  child: _SeasonHead(
                    season: s,
                    narrow: layout.cellWidth < 30,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (var e = 0; e < layout.rows; e++) ...[
          const SizedBox(height: GridLayout.gap),
          SizedBox(
            height: layout.rowHeight,
            child: Row(
              children: [
                SizedBox(
                  width: GridLayout.labelWidth,
                  child: Text(
                    '${e + 1}',
                    maxLines: 1,
                    style: _body(
                      layout.rowHeight < 16 ? 8 : 10,
                      dim,
                      w: FontWeight.w600,
                    ),
                  ),
                ),
                for (final s in seasons) ...[
                  const SizedBox(width: GridLayout.gap),
                  // Высота задана явно: рамка без ребёнка иначе сжимается
                  // в ноль и непросмотренные серии пропадают.
                  SizedBox(
                    width: layout.cellWidth,
                    height: layout.rowHeight,
                    child: e < s.cells.length
                        ? _Cell(
                            cell: s.cells[e],
                            layout: layout,
                            showNumber: data.showNumbers,
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SeasonHead extends StatelessWidget {
  const _SeasonHead({required this.season, required this.narrow});

  final GridSeason season;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final avg = season.average;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'S${season.number}',
            style: _body(
              10,
              Colors.white.withValues(alpha: 0.5),
              w: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            avg == null ? '—' : _fmt(avg),
            style: _display(
              narrow ? 10 : 12,
              avg == null ? Colors.white.withValues(alpha: 0.3) : Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.cell,
    required this.layout,
    required this.showNumber,
  });

  final GridCell cell;
  final GridLayout layout;
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(layout.rowHeight < 16 ? 4 : 8);
    if (!cell.watched) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
      );
    }
    final score = cell.score;
    if (score == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: Colors.white.withValues(alpha: 0.16),
        ),
      );
    }
    final step = scoreStep(score);
    final ink = onScoreStepColor(step);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: scoreStepColor(step),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showNumber && layout.fontSize > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _fmt(score),
                    style: _display(layout.fontSize, ink, w: FontWeight.w600),
                  ),
                ),
              ),
            ),
          // Точка в углу: серию смотрели больше одного раза.
          if (cell.rewatched)
            Positioned(
              top: 3,
              right: 3,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ink.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Легенда: две строки по четыре подписи одинаковой ширины.
class _Legend extends StatelessWidget {
  const _Legend({required this.grid});

  final EpisodeGrid grid;

  static const _perRow = 4;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      for (final step in ScoreStep.values)
        _LegendItem(
          label: tr('grid_step_${step.name}'),
          fill: scoreStepColor(step),
        ),
      if (grid.hasUnwatched)
        _LegendItem(label: tr('grid_unwatched'), outlined: true),
      if (grid.hasUnrated)
        _LegendItem(
          label: tr('grid_unrated'),
          fill: Colors.white.withValues(alpha: 0.16),
        ),
    ];
    const width = GridLayout.width - 2 * GridLayout.padX;
    return SizedBox(
      height: GridLayout.legendHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < items.length; i += _perRow)
            Row(
              children: [
                for (final item in items.skip(i).take(_perRow))
                  SizedBox(width: width / _perRow, child: item),
              ],
            ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, this.fill, this.outlined = false});

  final String label;
  final Color? fill;
  final bool outlined;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(3),
          border: outlined
              ? Border.all(color: Colors.white.withValues(alpha: 0.3))
              : null,
        ),
      ),
      const SizedBox(width: 5),
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _body(10.5, Colors.white.withValues(alpha: 0.72)),
        ),
      ),
    ],
  );
}
