import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';

/// Общие действия «удалить из базы навсегда» с подтверждением и отменой.
/// Используются везде, где по удержанию можно снести мусорную/ненаходимую запись.

Future<bool> _confirm(BuildContext context, String title) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('delete_from_base')),
      content: Text(trf('delete_from_base_confirm', {'title': title})),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
              backgroundColor: scheme.error, foregroundColor: scheme.onError),
          child: Text(tr('delete')),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<void> deleteSeriesFromBase(BuildContext context, LibrarySeries s) async {
  if (!await _confirm(context, s.displayTitle)) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final snap = await MovieRepository.instance.deleteSeries(s.tvShowId);
  if (snap == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(tr('deleted_from_base')),
      action: SnackBarAction(
        label: tr('undo'),
        onPressed: () =>
            MovieRepository.instance.restoreFromSnapshot(const [], [snap]),
      ),
    ));
}

Future<void> deleteMovieFromBase(BuildContext context, LibraryMovie m) async {
  if (!await _confirm(context, m.displayTitle)) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final snap = await MovieRepository.instance.deleteMovie(m.uuid);
  if (snap == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(tr('deleted_from_base')),
      action: SnackBarAction(
        label: tr('undo'),
        onPressed: () =>
            MovieRepository.instance.restoreFromSnapshot([snap], const []),
      ),
    ));
}
