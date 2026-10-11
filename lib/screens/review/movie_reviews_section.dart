import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/movie_repository.dart';
import '../../services/store.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/movie_reviews.dart';
import '../../utils/review_markdown.dart';
import '../../utils/score.dart';
import '../../widgets/review/review_parts.dart';
import '../../widgets/review/review_rows.dart';
import '../../widgets/review/reviews_table.dart';
import '../../widgets/settings_kit.dart';
import '../../widgets/viewing/view_chip.dart';
import 'review_editor_screen.dart';
import 'review_screen.dart';
import 'review_target.dart';
import 'review_viewing_sheet.dart';

/// Новая рецензия на фильм. С несколькими просмотрами сначала лист «О каком
/// просмотре», с одним — сразу редактор.
Future<void> startMovieReview(BuildContext context, LibraryMovie movie,
    {MovieRepository? repo}) async {
  if (movie.viewings.length < 2) {
    return openReviewEditor(
      context,
      ReviewTarget.movie(movie,
          repo: repo, viewId: movie.currentViewing?.id),
    );
  }
  if (unreviewedViewings(movie).isEmpty) return;
  final id = await showReviewViewingSheet(context, movie: movie);
  if (id == null || !context.mounted) return;
  await openReviewEditor(
      context, ReviewTarget.movie(movie, repo: repo, viewId: id));
}

/// Рецензии в карточке фильма, в том же виде, что на экране сериала: строки
/// с номером просмотра в таблетке, свод по пересмотрам и сворачивание в одну
/// строку. Стоит сразу под оценкой.
///
/// Свёрнутость одна на все фильмы, ключ в `Store`.
class MovieReviewsSection extends StatefulWidget {
  final LibraryMovie movie;
  final MovieRepository repo;

  const MovieReviewsSection(
      {super.key, required this.movie, required this.repo});

  static const collapsedKey = 'movieReviewsCollapsed';

  @override
  State<MovieReviewsSection> createState() => _MovieReviewsSectionState();
}

class _MovieReviewsSectionState extends State<MovieReviewsSection> {
  bool _collapsed = false;

  LibraryMovie get m => widget.movie;
  MovieRepository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    Store.instance.getBool(MovieReviewsSection.collapsedKey).then((v) {
      if (mounted && v != _collapsed) setState(() => _collapsed = v);
    });
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _collapsed = !_collapsed);
    Store.instance.setBool(MovieReviewsSection.collapsedKey, _collapsed);
  }

  void _write() => startMovieReview(context, m, repo: repo);

  ReviewTarget _target(MovieReviewRef r) =>
      ReviewTarget.ofRef(m, r, repo: repo);

  void _open(MovieReviewRef r) {
    final t = _target(r);
    (r.meta?.draft ?? false)
        ? openReviewEditor(context, t)
        : openReview(context, t);
  }

  /// Оценка рецензии в списке: оценка просмотра, без неё средняя по пунктам.
  double? _scoreOf(MovieReviewRef r) => r.viewing?.score ?? r.meta?.average;

  @override
  Widget build(BuildContext context) {
    final refs = movieReviews(m);
    if (refs.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: _write,
          icon: const Icon(Icons.rate_review_rounded),
          label: Text(tr('write_review')),
        ),
      );
    }
    // Номер просмотра в таблетке нужен, только когда просмотров несколько.
    final many = m.viewings.length >= 2;
    final free = unreviewedViewings(m);
    final table = movieReviewsTable(m);
    // Свежие сверху; рецензии без просмотра в самом низу.
    final rows = [
      ...refs.where((r) => r.ordinal > 0).toList().reversed,
      ...refs.where((r) => r.ordinal == 0),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewsHeader(
          count: refs.length,
          collapsed: _collapsed,
          onToggle: _toggle,
          onWrite: free.isEmpty ? null : _write,
        ),
        const SizedBox(height: 4),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: AppTheme.emphasized,
          alignment: Alignment.topCenter,
          child: _collapsed
              ? ReviewsFolded(
                  items: [
                    for (final r in refs)
                      (
                        chip: r.ordinal > 0
                            ? ViewChip(ordinalShort(r.ordinal),
                                tone: ViewChipTone.review)
                            : const SizedBox.shrink(),
                        score: _scoreOf(r),
                      ),
                  ],
                  total: table?.scoreDelta == null
                      ? null
                      : trf('mrv_diff',
                          {'d': signedDelta(table!.scoreDelta!)}),
                  onOpen: _toggle,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < rows.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                            top: i == 0 ? 0 : SettingsGroup.gap),
                        child: _row(rows[i], many,
                            groupBlockRadius(i, rows.length, outer: 24)),
                      ),
                    if (table != null) ...[
                      const SizedBox(height: 12),
                      _Summary(
                        table: table,
                        free: free,
                        movie: m,
                        onWriteFor: (v) => openReviewEditor(context,
                            ReviewTarget.movie(m, repo: repo, viewId: v.id)),
                        onWrite: _write,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _row(MovieReviewRef r, bool many, BorderRadius radius) {
    final meta = r.meta;
    final text = r.item.review?.trim() ?? '';
    var title = meta?.title?.trim() ?? '';
    // Старые рецензии писались без заголовка: вместо «Без заголовка» у них
    // стоит начало текста.
    if (title.isEmpty && text.isNotEmpty) {
      title = reviewPlainText(text, spoilerMask: tr('rv_spoiler_mask'))
          .split('\n')
          .first
          .trim();
    }
    final date = meta?.shownDate;
    final sub = [
      if (date != null) '${dayMonth(date)} ${date.year}',
      if (text.isNotEmpty) trf('rv_read_min', {'n': reviewReadMinutes(text)}),
      if (meta?.draft ?? false) tr('rvs_draft'),
    ].join(' · ');
    return ReviewRowTile(
      chips: [
        if (many && r.ordinal > 0)
          ViewChip(ordinalShort(r.ordinal), tone: ViewChipTone.review),
      ],
      verdict: meta?.verdict,
      title: title.isEmpty ? tr('rv_untitled') : title,
      sub: sub,
      score: _scoreOf(r),
      radius: radius,
      onTap: () => _open(r),
    );
  }
}

/// Вывод под сводом: насколько оценка изменилась между рецензиями и какой
/// пункт изменился сильнее всего.
String reviewsTableLine(ReviewsTableData table) {
  final n = table.columns.length;
  final span = n == 2 ? tr('mrv_between') : trn('mrv_over', n);
  final d = table.scoreDelta ?? 0;
  final head = d == 0
      ? trf('mrv_score_same', {'span': span})
      : trf(d < 0 ? 'mrv_score_down' : 'mrv_score_up',
          {'span': span, 'd': d.abs().toStringAsFixed(1)});
  final strongest = table.strongest;
  if (strongest == null) return head;
  return '$head ${trf('mrv_strongest', {'crit': critLabel(strongest)})}';
}

/// Карточка «Свод по пересмотрам»: столбец на рецензию, строка на пункт,
/// вывод и просмотры без рецензии.
class _Summary extends StatelessWidget {
  final ReviewsTableData table;
  final List<Viewing> free;
  final LibraryMovie movie;
  final ValueChanged<Viewing> onWriteFor;
  final VoidCallback onWrite;
  const _Summary({
    required this.table,
    required this.free,
    required this.movie,
    required this.onWriteFor,
    required this.onWrite,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cols = table.columns;
    final last = cols.length - 1;
    final String? missing = free.isEmpty
        ? null
        : free.length == 1
            ? trf('mrv_missing_one', {
                'view': trf('viewing_n', {'n': movie.ordinalOf(free.single)}),
              })
            : trf('mrv_missing_many', {
                'list': [
                  for (final v in free) ordinalShort(movie.ordinalOf(v)),
                ].join(', '),
              });
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          ReviewCaps(tr('mrv_summary')),
          if (table.criteria.isNotEmpty || cols.any((c) => c.score != null))
            ReviewsGrid(
              columns: [
                for (var i = 0; i < cols.length; i++)
                  GridColumn(
                    ordinal: cols[i].ordinal,
                    score: cols[i].score,
                    caption: cols[i].date == null
                        ? null
                        : monthYearShort(cols[i].date!),
                    highlight: i == last,
                  ),
              ],
              rows: [
                for (final id in table.criteria)
                  GridRowData(
                    label: critLabel(id),
                    delta: table.deltas[id],
                    strong: id == table.strongest,
                    cells: [
                      for (var i = 0; i < cols.length; i++)
                        GridCell(
                            value: cols[i].criteria[id], highlight: i == last),
                    ],
                  ),
              ],
            ),
          Text(reviewsTableLine(table),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant)),
          if (missing != null)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                spacing: 10,
                children: [
                  Icon(Icons.info_rounded, size: 18, color: scheme.primary),
                  Expanded(
                    child: Text(missing,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: scheme.onSurfaceVariant)),
                  ),
                  TextButton(
                    onPressed: free.length == 1
                        ? () => onWriteFor(free.single)
                        : onWrite,
                    child: Text(tr('rvs_write')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
