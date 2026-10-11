import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../models/review.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/movie_reviews.dart';
import '../../widgets/review/review_rows.dart';
import '../../widgets/settings_kit.dart';

/// Лист «О каком просмотре»: у фильма с несколькими просмотрами рецензия
/// сначала спрашивает, о каком из них. Возвращает id просмотра.
///
/// Просмотр, на который рецензия уже написана, выбрать нельзя. [current] —
/// нынешний просмотр рецензии, которую переносят: он свободен и выбран.
Future<String?> showReviewViewingSheet(
  BuildContext context, {
  required LibraryMovie movie,
  String? current,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    // useSafeArea у листа бережёт только верх: низ держим сами.
    builder: (_) => SafeArea(
      top: false,
      child: _ViewingChoiceSheet(movie: movie, current: current),
    ),
  );
}

class _ViewingChoiceSheet extends StatefulWidget {
  final LibraryMovie movie;
  final String? current;
  const _ViewingChoiceSheet({required this.movie, this.current});

  @override
  State<_ViewingChoiceSheet> createState() => _ViewingChoiceSheetState();
}

class _ViewingChoiceSheetState extends State<_ViewingChoiceSheet> {
  late String? _picked = widget.current ?? _firstFree;

  LibraryMovie get m => widget.movie;

  /// Чужая рецензия на этом просмотре; своя ([current]) не мешает.
  HasReview? _taken(Viewing v) =>
      v.id == widget.current ? null : reviewOfViewing(m, v.id);

  /// Последний просмотр без рецензии: чаще всего пишут о свежем.
  String? get _firstFree {
    for (final v in m.orderedViewings.reversed) {
      if (_taken(v) == null) return v.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = m.orderedViewings;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('mrv_which_title'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1.15,
                    color: scheme.onSurface)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = list.length - 1; i >= 0; i--)
                Padding(
                  padding: EdgeInsets.only(
                      top: i == list.length - 1 ? 0 : SettingsGroup.gap),
                  child: _row(list, i),
                ),
            ],
          ),
          FilledButton(
            onPressed: _picked == null
                ? null
                : () => Navigator.of(context).pop(_picked),
            child: Text(tr('rv_next')),
          ),
        ],
      ),
    );
  }

  Widget _row(List<Viewing> list, int i) {
    final v = list[i];
    final taken = _taken(v);
    final String sub;
    if (taken != null) {
      final title = taken.reviewMeta?.title?.trim();
      sub = title == null || title.isEmpty
          ? tr('view_has_review')
          : trf('view_review_named', {'title': title});
    } else {
      sub = [
        if (v.score != null)
          trf('view_score_n', {'v': v.score!.toStringAsFixed(1)}),
        if (v.diary?.moods.isNotEmpty ?? false) v.diary!.moods.join(' '),
      ].join(' · ');
    }
    return ViewChoiceRow(
      ordinal: i + 1,
      title: v.date != null ? dateExactWithTime(v.date!) : tr('view_undated'),
      sub: sub,
      selected: v.id == _picked,
      taken: taken != null,
      // Строки идут сверху вниз от последнего просмотра к первому.
      radius: groupBlockRadius(list.length - 1 - i, list.length, outer: 22),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _picked = v.id);
      },
    );
  }
}
