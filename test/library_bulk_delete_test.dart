import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/library_tab.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Оценка, дневник и рецензия живут в просмотре. Удаляя отметки пачкой из
/// ленты, человек теряет и их, поэтому вопрос перед удалением говорит об
/// этом прямо.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  MovieRepository repo({double? score, DiaryEntry? diary, String? review}) {
    final v = Viewing(
      id: 'v1',
      date: DateTime(2026, 9, 14, 20),
      score: score,
      diary: diary,
    );
    final movie = LibraryMovie(
      uuid: 'm',
      title: 'Дюна',
      status: LibraryStatus.watched,
      enrichTried: true,
      viewings: [v],
      review: review,
      reviewMeta: review == null ? null : ReviewMeta(viewId: 'v1'),
    );
    return MovieRepository.detached(
      jsonDecode(jsonEncode({
        'movies': [movie.toJson()],
      })) as Map<String, dynamic>,
    );
  }

  Future<void> askToDelete(WidgetTester tester, MovieRepository repo) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(
          body: LibraryTab(mode: LibraryMode.watched, repository: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Дюна'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text(tr('delete_selected_title')), findsOneWidget);
  }

  final warning = find.textContaining(tr('delete_selected_losses'));

  testWidgets('просмотр с оценкой: вопрос предупреждает о потере', (
    tester,
  ) async {
    await askToDelete(tester, repo(score: 8.5));
    expect(warning, findsOneWidget);
  });

  testWidgets('просмотр с дневником: вопрос предупреждает о потере', (
    tester,
  ) async {
    await askToDelete(tester, repo(diary: DiaryEntry(note: 'в кино')));
    expect(warning, findsOneWidget);
  });

  testWidgets('просмотр с рецензией: вопрос предупреждает о потере', (
    tester,
  ) async {
    await askToDelete(tester, repo(review: 'Песок и черви'));
    expect(warning, findsOneWidget);
  });

  testWidgets('пустая отметка удаляется без лишних слов', (tester) async {
    await askToDelete(tester, repo());
    expect(warning, findsNothing);
  });
}
