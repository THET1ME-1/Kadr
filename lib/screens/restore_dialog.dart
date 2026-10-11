import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/movie_repository.dart';

/// Как поднять копию, когда в библиотеке уже есть записи.
enum RestoreMode {
  /// Сложить копию с библиотекой: ничего не пропадает.
  merge,

  /// Оставить только то, что в копии.
  replace,
}

/// Спрашивает, добавить копию к библиотеке или заменить библиотеку ею.
/// [when] — дата копии, если она известна. Пустую библиотеку спрашивать не
/// о чем: ответ сразу «заменить». null — человек передумал.
///
/// [hasData] подменяется в тестах; по умолчанию смотрит в библиотеку.
Future<RestoreMode?> askRestoreMode(
  BuildContext context, {
  String? when,
  bool? hasData,
}) async {
  if (!(hasData ?? MovieRepository.instance.hasData)) {
    return RestoreMode.replace;
  }
  final scheme = Theme.of(context).colorScheme;
  final body = [
    if (when != null) trf('restore_mode_when', {'when': when}),
    trf('restore_mode_body', {'add': tr('add'), 'replace': tr('replace')}),
  ].join('\n\n');
  return showDialog<RestoreMode>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('restore_confirm_title')),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, RestoreMode.replace),
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          child: Text(tr('replace')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, RestoreMode.merge),
          child: Text(tr('add')),
        ),
      ],
    ),
  );
}
