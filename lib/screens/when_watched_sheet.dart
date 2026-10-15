import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/social/social_controller.dart';
import 'viewing/mark_sheet.dart';

/// Отмечает просмотр фильма: открывает окно отметки и записывает просмотр
/// с выбранной датой. Если фильм уже смотрели, это пересмотр, и окно сразу
/// показывает его номер. С «Посмотрел с другом» просмотр уходит и друзьям.
Future<void> showWhenWatchedSheet(
    BuildContext context, LibraryMovie movie) async {
  final messenger = ScaffoldMessenger.of(context);
  final repo = MovieRepository.instance;
  final m = repo.byUuid(movie.uuid) ?? movie;
  final choice = await showMarkSheet(
    context,
    title: tr('mark_q'),
    subject: m.displayTitle,
    // Брошенные и начатые попытки номер не двигают: досмотр после них —
    // первый.
    ordinal: m.viewings.where((v) => v.isFull).length + 1,
    coWatch: true,
  );
  if (choice == null) return;
  final wasRewatch = await repo.addViewing(m.uuid, choice.date);
  if (choice.friends.isEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text(tr(wasRewatch ? 'rewatch_added' : 'viewing_added')),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  await _sendCoWatch(m, choice, messenger);
}

/// «Досмотрел»: начатая или брошенная попытка [viewing] становится
/// просмотром. Окно «Когда досмотрели?» берёт день досмотра, день, когда
/// начал, остаётся в ленте строкой. С «Посмотрел с другом» просмотр уходит
/// и друзьям.
Future<void> showFinishSheet(
    BuildContext context, LibraryMovie movie, Viewing viewing,
    {MovieRepository? repo}) async {
  final messenger = ScaffoldMessenger.of(context);
  final r = repo ?? MovieRepository.instance;
  final m = r.byUuid(movie.uuid) ?? movie;
  final choice = await showMarkSheet(
    context,
    title: tr('finish_q'),
    subject: m.displayTitle,
    ordinal: m.viewings.where((v) => v.isFull).length + 1,
    coWatch: true,
  );
  if (choice == null) return;
  await r.finishViewing(m.uuid, viewing, choice.date);
  if (choice.friends.isEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text(tr('viewing_added')),
      behavior: SnackBarBehavior.floating,
    ));
    return;
  }
  await _sendCoWatch(m, choice, messenger);
}

Future<void> _sendCoWatch(LibraryMovie m, MarkChoice choice,
    ScaffoldMessengerState messenger) async {
  for (final f in choice.friends) {
    try {
      await SocialController.instance.sendMovieCoWatch(
        toUserId: f.id,
        title: m.displayTitle,
        origTitle: m.title,
        year: m.year,
        tmdbId: m.tmdbId,
        posterUrl: m.posterUrl,
        watchedAt: choice.date,
      );
    } catch (_) {/* пропускаем этого друга */}
  }
  messenger.showSnackBar(SnackBar(
    content: Text(trf('cowatch_marked', {'n': choice.friends.length})),
    behavior: SnackBarBehavior.floating,
  ));
}
