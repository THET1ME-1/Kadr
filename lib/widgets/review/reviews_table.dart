import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../dashed_box.dart';

/// Столбец свода: одна рецензия.
class GridColumn {
  /// Номер просмотра в шапке: «3-й».
  final int ordinal;

  /// Общая оценка в шапке-плашке; без неё шапка — короткая подпись.
  final double? score;

  /// Подпись под оценкой: «авг 2026».
  final String? caption;

  /// Последняя рецензия: её столбец выделен.
  final bool highlight;
  const GridColumn({
    required this.ordinal,
    this.score,
    this.caption,
    this.highlight = false,
  });
}

/// Клетка свода.
class GridCell {
  final double? value;

  /// Выделенная клетка: столбец последней рецензии или рецензия, идущая в
  /// свод сериала.
  final bool highlight;

  /// «нет» пунктиром: сезон смотрели, а рецензию не писали.
  final bool missing;

  /// Пустое место: такого просмотра не было.
  final bool none;
  const GridCell(
      {this.value,
      this.highlight = false,
      this.missing = false,
      this.none = false});
}

/// Строка свода: пункт разбора или сезон.
class GridRowData {
  final String label;

  /// Разница между первой и последней рецензией; под подписью, цветом.
  final double? delta;

  /// Самая изменившаяся строка: подпись жирнее.
  final bool strong;
  final List<GridCell> cells;
  const GridRowData({
    required this.label,
    required this.cells,
    this.delta,
    this.strong = false,
  });
}

/// Свод таблицей: столбец на рецензию, строка на пункт разбора (у сериала —
/// на сезон). До пяти столбцов делят ширину поровну; шестой и дальше не
/// ужимают таблицу, столбцы листаются вбок, подписи строк стоят на месте.
class ReviewsGrid extends StatelessWidget {
  final List<GridColumn> columns;
  final List<GridRowData> rows;

  /// Шапка плашками с оценкой (свод фильма); иначе «👁 N-й» строкой.
  final bool boxedHeader;

  /// Подписи строк шрифтом заголовков («S1»), а не текста («Сюжет»).
  final bool displayLabels;
  final double? labelWidth;

  const ReviewsGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.boxedHeader = true,
    this.displayLabels = false,
    this.labelWidth,
  });

  static const double _gap = 4;
  static const double _rowHeight = 36;

  /// Столбцов, которые помещаются без прокрутки.
  static const int fit = 5;

  /// Ширина столбца, когда они листаются.
  static const double _scrollColumn = 52;

  @override
  Widget build(BuildContext context) {
    final n = columns.length;
    // С четырёх столбцов шапка и клетки мельче: иначе числа не помещаются
    // на телефоне шириной 320.
    final dense = n >= 4;
    final captions = boxedHeader && !dense && columns.any((c) => c.caption != null);
    final headerHeight =
        boxedHeader ? (dense ? 42.0 : (captions ? 66.0 : 52.0)) : 22.0;
    final labelW = labelWidth ?? (dense ? 76.0 : 84.0);

    Widget column(int i) => Column(
          children: [
            SizedBox(
              height: headerHeight,
              child: _Header(
                column: columns[i],
                boxed: boxedHeader,
                dense: dense,
                caption: captions,
              ),
            ),
            for (final r in rows) ...[
              const SizedBox(height: _gap),
              SizedBox(
                height: _rowHeight,
                child: _Cell(cell: r.cells[i], dense: dense),
              ),
            ],
          ],
        );

    final labels = SizedBox(
      width: labelW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: headerHeight),
          for (final r in rows) ...[
            const SizedBox(height: _gap),
            SizedBox(
              height: _rowHeight,
              child: _Label(row: r, display: displayLabels),
            ),
          ],
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labels,
        const SizedBox(width: _gap),
        Expanded(
          child: n <= fit
              ? Row(
                  spacing: _gap,
                  children: [
                    for (var i = 0; i < n; i++) Expanded(child: column(i)),
                  ],
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // Открываем на последних рецензиях: они важнее первых.
                  reverse: true,
                  child: Row(
                    spacing: _gap,
                    children: [
                      for (var i = 0; i < n; i++)
                        SizedBox(width: _scrollColumn, child: column(i)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final GridColumn column;
  final bool boxed;
  final bool dense;
  final bool caption;
  const _Header({
    required this.column,
    required this.boxed,
    required this.dense,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ord = ordinalShort(column.ordinal);
    if (!boxed) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 3,
        children: [
          Icon(Icons.visibility_rounded,
              size: 13, color: scheme.onSurfaceVariant),
          Flexible(
            child: Text(ord,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant)),
          ),
        ],
      );
    }
    final on = column.highlight;
    final fg = on ? scheme.onPrimaryContainer : scheme.onSurface;
    final s = column.score;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: on ? scheme.primaryContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 3,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 3,
            children: [
              if (!dense)
                Icon(Icons.visibility_rounded,
                    size: 13, color: fg.withValues(alpha: 0.85)),
              Flexible(
                child: Text(ord,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        height: 1.1,
                        color: fg.withValues(alpha: 0.85))),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(s != null ? s.toStringAsFixed(1) : '—',
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: dense ? 13.5 : 20,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: on || s == null ? fg : scoreColor(s))),
          ),
          if (caption)
            Text(column.caption ?? '',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w500,
                    fontSize: 10.5,
                    height: 1.1,
                    color: fg.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final GridRowData row;
  final bool display;
  const _Label({required this.row, required this.display});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = row.delta;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Длинное название пункта ужимается, а не переносится: высота строк
        // у подписей и клеток общая.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(row.label,
              maxLines: 1,
              style: display
                  ? TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.2,
                      color: scheme.onSurface)
                  : TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight:
                          row.strong ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                      height: 1.2,
                      color: scheme.onSurface)),
        ),
        if (d != null && d != 0)
          Text(signedDelta(d),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: deltaColor(d, scheme))),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  final GridCell cell;
  final bool dense;
  const _Cell({required this.cell, required this.dense});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (cell.none) return const SizedBox.expand();
    if (cell.missing) {
      return DashedBox(
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(tr('rvs_none'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant)),
          ),
        ),
      );
    }
    final v = cell.value;
    final on = cell.highlight;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on
            ? Color.alphaBlend(
                scheme.primaryContainer.withValues(alpha: 0.55),
                scheme.surfaceContainer)
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(v != null ? v.toStringAsFixed(1) : '—',
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: dense ? 11.5 : 13,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: v == null
                    ? scheme.onSurfaceVariant
                    : (on ? scheme.onPrimaryContainer : scoreColor(v)))),
      ),
    );
  }
}
