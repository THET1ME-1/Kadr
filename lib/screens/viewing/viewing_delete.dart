import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../widgets/undo_snack.dart';
import 'viewing_host.dart';

/// Плашка «Просмотр удалён · Вернуть». Появляется после любого удаления.
void showViewingDeletedSnack(
    ScaffoldMessengerState? messenger, ViewingUndo undo) {
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(undoSnackBar(
      text: tr('viewing_deleted'),
      label: tr('view_restore'),
      onUndo: undo,
    ));
}

/// Что пропадёт вместе с просмотром: «оценка 8.5», «запись дневника»,
/// «рецензия».
List<String> _losses(ViewingHost host, Viewing v) => [
      if (v.score != null)
        trf('view_part_score', {'v': v.score!.toStringAsFixed(1)}),
      if (v.diary?.isNotEmpty ?? false) tr('view_part_diary'),
      if (host.hasReview(v)) tr('view_part_review'),
    ];

/// Удаляет просмотр [v]. Пустой уходит сразу, просмотр с оценкой, дневником
/// или рецензией сначала спрашивает ([ask] = false пропускает вопрос: так
/// убирается один из одинаковых просмотров без даты). Снятие по порядку
/// спрашивает всегда: вместе с серией уходят серии после неё. После удаления
/// на [messenger] появляется плашка «Вернуть». true — просмотр удалён.
Future<bool> deleteViewingFlow(
  BuildContext context,
  ViewingHost host,
  Viewing v, {
  ScaffoldMessengerState? messenger,
  bool ask = true,
}) async {
  final bar = messenger ?? ScaffoldMessenger.maybeOf(context);
  final losses = _losses(host, v);
  final cascade = host.cascadeOf(v);
  if (cascade > 0 || (ask && losses.isNotEmpty)) {
    final ok = await _confirm(context, v, losses, cascade);
    if (ok != true) return false;
  }
  HapticFeedback.mediumImpact();
  final undo = await host.remove(v);
  if (undo == null) return false;
  showViewingDeletedSnack(bar, undo);
  return true;
}

/// Где отключается снятие по порядку: «Отметки просмотра» → «Снимать серии
/// по порядку».
String unmarkCascadeHint() => trf('unmark_cascade_hint', {
      'page': tr('set_group_tracking'),
      'row': tr('unmark_seq'),
    });

Future<bool?> _confirm(
    BuildContext context, Viewing v, List<String> losses, int cascade) {
  final scheme = Theme.of(context).colorScheme;
  final date = v.date;
  final body = [
    if (losses.isNotEmpty)
      switch (losses.length) {
        1 => trf('view_delete_body_1', {'a': losses[0]}),
        2 => trf('view_delete_body_2', {'a': losses[0], 'b': losses[1]}),
        _ => trf('view_delete_body_3',
            {'a': losses[0], 'b': losses[1], 'c': losses[2]}),
      },
    if (cascade > 0) ...[
      trf('unmark_cascade_ep', {'eps': trn('ss_episodes', cascade)}),
      unmarkCascadeHint(),
    ],
  ].join('\n\n');
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
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
            Text(
                date == null
                    ? tr('view_delete_q_undated')
                    : trf('view_delete_q', {'date': numericDate(date)}),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    height: 1.2,
                    color: scheme.onSurface)),
            Text(body,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    color: scheme.onSurfaceVariant)),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: kDroppedColor,
                foregroundColor: scheme.surface,
              ),
              child: Text(tr('delete')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(tr('cancel')),
            ),
          ],
        ),
      ),
    ),
  );
}
