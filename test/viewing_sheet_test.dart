import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/viewing/viewing_host.dart';
import 'package:kadr/screens/viewing/viewing_sheet.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Легенда об Аанге» из макета: три просмотра, у второго дневник, на первый
/// написана рецензия. Четвёртый, пустой, добавляется по [empty].
MovieRepository _repo({bool empty = false, bool unratedLast = false}) =>
    MovieRepository.detached({
      'movies': [
        LibraryMovie(
          uuid: 'aang',
          title: 'Легенда об Аанге',
          status: LibraryStatus.watched,
          viewings: [
            Viewing(id: 'v1', date: DateTime(2026, 4, 15, 11, 22), score: 8.8),
            Viewing(
              id: 'v2',
              date: DateTime(2026, 5, 16, 22, 26),
              score: 8.5,
              diary: DiaryEntry(moods: ['🥹', '🔥', '😍'], place: 'home'),
            ),
            Viewing(
              id: 'v3',
              date: DateTime(2026, 8, 16, 16, 49),
              score: unratedLast ? null : 8.0,
            ),
            if (empty) Viewing(id: 'v4', date: DateTime(2026, 9, 1)),
          ],
          review: 'Текст',
          reviewMeta: ReviewMeta(
            title: 'Аанг вернулся, и это главное',
            viewId: 'v1',
            publishedAt: DateTime(2026, 4, 15, 12),
          ),
        ).toJson(),
      ],
      'series': [
        LibrarySeries(
          tvShowId: 'arcane',
          title: 'Аркейн',
          episodes: [
            Episode(
              season: 1,
              number: 3,
              watchedAt: DateTime(2023, 5, 29, 13, 41),
              score: 10,
              rewatchViews: [
                Viewing(id: 'r2', date: DateTime(2023, 10, 2, 17, 44)),
                Viewing(id: 'r3', date: DateTime(2026, 8, 19, 13, 35)),
              ],
            ),
          ],
        ).toJson(),
      ],
    });

Future<void> _open(
  WidgetTester tester,
  ViewingHost host,
  String viewId, {
  bool openDiary = false,
  String lang = 'ru',
  double width = 380,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showViewingSheet(context, host,
                  viewId: viewId, openDiary: openDiary),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('фильм: переключатель, оценка, дата, дневник строкой, рецензия', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v2');
    expect(find.text('Просмотр'), findsOneWidget);
    // Все просмотры в одном году: в переключателе день и месяц.
    expect(find.text('1-й · 15.04'), findsOneWidget);
    expect(find.text('2-й · 16.05'), findsOneWidget);
    expect(find.text('3-й · 16.08'), findsOneWidget);
    expect(find.text('Оценка просмотра'), findsOneWidget);
    expect(find.text('8.5'), findsWidgets);
    expect(find.text('в прошлый раз 8.8'), findsOneWidget);
    expect(find.text('16.05.2026 22:26'), findsOneWidget);
    expect(find.text('🥹 🔥 😍 · дом'), findsOneWidget);
    expect(find.text('На этот просмотр пока нет'), findsOneWidget);
  });

  testWidgets('переключатель открывает другой просмотр с его рецензией', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v2');
    // Переключатель листается вбок: выбранный просмотр стоит по центру.
    await tester.ensureVisible(find.text('1-й · 15.04'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1-й · 15.04'));
    await tester.pumpAndSettle();
    expect(find.text('15.04.2026 11:22'), findsOneWidget);
    expect(find.text('Аанг вернулся, и это главное'), findsOneWidget);
    // У первого просмотра прошлого раза нет.
    expect(find.textContaining('в прошлый раз'), findsNothing);
  });

  testWidgets('неоценённый просмотр: прочерк и кнопка прошлой оценки', (
    tester,
  ) async {
    final repo = _repo(unratedLast: true);
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v3');
    expect(find.text('—'), findsOneWidget);
    // Бегунок без оценки нейтральный, с вопросом: «1.0» читалось бы как
    // поставленная единица.
    expect(find.text('?'), findsOneWidget);
    expect(find.text('1.0'), findsNothing);
    expect(find.text('Те же 8.5, что в прошлый раз'), findsOneWidget);
    await tester.tap(find.text('Те же 8.5, что в прошлый раз'));
    await tester.pumpAndSettle();
    expect(repo.byUuid('aang')!.viewingById('v3')!.score, 8.5);
    expect(find.text('в прошлый раз 8.5'), findsOneWidget);
  });

  testWidgets('«Убрать оценку» снимает оценку только этого просмотра', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v2');
    await tester.tap(find.text(tr('remove_score')));
    await tester.pumpAndSettle();
    final m = repo.byUuid('aang')!;
    expect(m.viewingById('v2')!.score, isNull);
    expect(m.viewingById('v1')!.score, 8.8);
    expect(m.viewingById('v3')!.score, 8.0);
  });

  testWidgets('крестик у даты делает просмотр «без даты», и он первый', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v2');
    await tester.tap(find.byTooltip(tr('clear_date')));
    await tester.pumpAndSettle();
    final m = repo.byUuid('aang')!;
    expect(m.viewingById('v2')!.date, isNull);
    // Просмотр без даты считается самым ранним: номер пересчитался.
    expect(m.ordinalOf(m.viewingById('v2')!), 1);
    expect(find.text('1-й · без даты'), findsOneWidget);
    expect(find.text('Без даты'), findsOneWidget);
  });

  testWidgets('дневник раскрывается, настроение пишется при «Готово»', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v3');
    await tester.tap(find.text('Настроение, где, с кем, фото, заметка'));
    await tester.pumpAndSettle();
    expect(find.text('НАСТРОЕНИЕ'), findsOneWidget);
    await tester.tap(find.text('🤯'));
    await tester.tap(find.text('Кино'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Готово'));
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    final diary = repo.byUuid('aang')!.viewingById('v3')!.diary!;
    expect(diary.moods, ['🤯']);
    expect(diary.place, 'cinema');
  });

  testWidgets('значок дневника в ленте открывает окно с раскрытым дневником', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v2',
        openDiary: true);
    expect(find.text('НАСТРОЕНИЕ'), findsOneWidget);
    expect(find.text('ГДЕ'), findsOneWidget);
  });

  testWidgets('удаление просмотра с оценкой и дневником спрашивает', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v2');
    await tester.ensureVisible(find.byTooltip(tr('delete')));
    await tester.tap(find.byTooltip(tr('delete')));
    await tester.pumpAndSettle();
    expect(find.text('Удалить просмотр 16.05.2026?'), findsOneWidget);
    expect(
      find.text('Вместе с ним уйдут оценка 8.5 и запись дневника.'),
      findsOneWidget,
    );
    // «Отмена» ничего не трогает.
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(repo.byUuid('aang')!.viewings.length, 3);

    await tester.tap(find.byTooltip(tr('delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(repo.byUuid('aang')!.viewings.length, 2);
    expect(repo.byUuid('aang')!.viewingById('v2'), isNull);
    // Окно закрылось, висит плашка с возвратом.
    expect(find.text('Оценка просмотра'), findsNothing);
    expect(find.text('Просмотр удалён'), findsOneWidget);
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    final back = repo.byUuid('aang')!.viewingById('v2')!;
    expect(back.score, 8.5);
    expect(back.diary!.moods, ['🥹', '🔥', '😍']);
  });

  testWidgets('удаление просмотра с рецензией называет её и убирает', (
    tester,
  ) async {
    final repo = _repo();
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v1');
    await tester.ensureVisible(find.byTooltip(tr('delete')));
    await tester.tap(find.byTooltip(tr('delete')));
    await tester.pumpAndSettle();
    expect(
      find.text('Вместе с ним уйдут оценка 8.8 и рецензия.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    expect(repo.byUuid('aang')!.hasReview, isFalse);
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    expect(repo.byUuid('aang')!.reviewMeta!.title,
        'Аанг вернулся, и это главное');
  });

  testWidgets('пустой просмотр удаляется без вопроса, плашка остаётся', (
    tester,
  ) async {
    final repo = _repo(empty: true);
    await _open(tester, MovieViewingHost('aang', repo: repo), 'v4');
    await tester.ensureVisible(find.byTooltip(tr('delete')));
    await tester.tap(find.byTooltip(tr('delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Удалить просмотр'), findsNothing);
    expect(repo.byUuid('aang')!.viewings.length, 3);
    expect(find.text('Просмотр удалён'), findsOneWidget);
  });

  testWidgets('серия: то же окно без рецензии, годы в переключателе', (
    tester,
  ) async {
    final repo = _repo();
    final host = EpisodeViewingHost('arcane', 1, 3, repo: repo);
    await _open(tester, host, 'r3');
    expect(find.text('Просмотр серии'), findsOneWidget);
    // Просмотры из разных лет: к дню и месяцу дописан год.
    expect(find.text('1-й · 29.05.23'), findsOneWidget);
    expect(find.text('3-й · 19.08.26'), findsOneWidget);
    expect(find.text('Те же 10.0, что в первый раз'), findsOneWidget);
    expect(find.text(tr('view_review')), findsNothing);
    await tester.tap(find.text('Те же 10.0, что в первый раз'));
    await tester.pumpAndSettle();
    final ep = repo.seriesById('arcane')!.watchedEpisode(1, 3)!;
    expect(ep.rewatchViews.last.score, 10);
    // Первый просмотр и второй не тронуты.
    expect(ep.score, 10);
    expect(ep.rewatchViews.first.score, isNull);
  });

  testWidgets('серия: удаление первого просмотра оставляет остальные', (
    tester,
  ) async {
    final repo = _repo();
    final host = EpisodeViewingHost('arcane', 1, 3, repo: repo);
    await _open(tester, host, host.ordered.first.id);
    await tester.ensureVisible(find.byTooltip(tr('delete')));
    await tester.tap(find.byTooltip(tr('delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
    await tester.pumpAndSettle();
    final ep = repo.seriesById('arcane')!.watchedEpisode(1, 3)!;
    expect(ep.watchCount, 2);
    expect(ep.watchedAt, DateTime(2023, 10, 2, 17, 44));
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    expect(repo.seriesById('arcane')!.watchedEpisode(1, 3)!.watchCount, 3);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('320 dp без переполнений, $lang', (tester) async {
      final repo = _repo();
      await _open(tester, MovieViewingHost('aang', repo: repo), 'v2',
          lang: lang, width: 320, openDiary: true);
      expect(tester.takeException(), isNull);
    });
    testWidgets('320 dp: серия без оценки, $lang', (tester) async {
      final repo = _repo();
      await _open(tester, EpisodeViewingHost('arcane', 1, 3, repo: repo), 'r3',
          lang: lang, width: 320);
      expect(tester.takeException(), isNull);
    });
  }
}
