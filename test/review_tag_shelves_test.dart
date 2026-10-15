import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/review/review_editor_screen.dart';
import 'package:kadr/screens/review/review_target.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Сильное» и «Слабое» в редакторе рецензии полками по темам, как причины
/// брошенного фильма: готовое горит на месте, своё стоит на «Своих».
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  bool on(WidgetTester tester, Finder chip) =>
      tester.widget<FilterChip>(chip).selected;

  // Полка листается вбок: чип за краем построен, но для поиска он за кадром.
  Finder shelfChip(String text) => find.ancestor(
      of: find.text(text, skipOffstage: false),
      matching: find.byType(FilterChip, skipOffstage: false));

  testWidgets('готовое горит на своей полке, своё на «Своих», выбор сохраняется',
      (tester) async {
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = MovieRepository.detached({
      'movies': [
        LibraryMovie(
          uuid: 'm1',
          title: 'Остров проклятых',
          status: LibraryStatus.watched,
          viewings: [Viewing(date: DateTime(2024, 3, 12), score: 8.5)],
          reviewMeta: ReviewMeta(
            pros: ['Музыка', 'Финальный твист'],
            cons: ['Провисает середина'],
            draft: true,
          ),
        ).toJson(),
      ],
    });
    final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: ReviewEditorScreen(target: target),
    ));
    await tester.pumpAndSettle();

    expect(find.text('СИЛЬНОЕ'), findsOneWidget);
    expect(find.text('СЛАБОЕ'), findsOneWidget);
    // «Сюжет» есть и среди пунктов разбора, поэтому темы ищем по другой.
    expect(find.text('Картинка и звук'), findsNWidgets(2));
    expect(find.text('Люди'), findsNothing); // без tmdbId актёров нет
    expect(on(tester, shelfChip('Музыка')), isTrue);
    expect(
        on(tester, find.widgetWithText(FilterChip, 'Финальный твист')), isTrue);
    expect(on(tester, find.widgetWithText(FilterChip, 'Провисает середина')),
        isTrue);
    expect(find.text('Свои'), findsNWidgets(2));

    final slow = find.widgetWithText(FilterChip, 'Затянуто');
    await tester.ensureVisible(slow);
    await tester.pumpAndSettle();
    await tester.tap(slow);
    await tester.pumpAndSettle();
    expect(on(tester, slow), isTrue);
    // Автосохранение черновика.
    await tester.pump(const Duration(seconds: 2));
    expect(repo.byUuid('m1')!.reviewMeta!.cons,
        ['Провисает середина', 'Затянуто']);
  });
}
