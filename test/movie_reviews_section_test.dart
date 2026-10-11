import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/review/movie_reviews_section.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/services/store.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReviewMeta _meta(String title, String viewId, Map<String, double> criteria,
        {Verdict? verdict, DateTime? at, bool draft = false}) =>
    ReviewMeta(
      title: title,
      viewId: viewId,
      criteria: criteria,
      verdict: verdict,
      draft: draft,
      publishedAt: draft ? null : (at ?? DateTime(2026, 8, 16)),
      createdAt: at ?? DateTime(2026, 8, 16),
    );

/// «Легенда об Аанге» из макета: три просмотра, рецензии на первый и третий.
LibraryMovie _aang({bool second = true}) => LibraryMovie(
  uuid: 'aang',
  title: 'Легенда об Аанге',
  status: LibraryStatus.watched,
  viewings: [
    Viewing(id: 'v1', date: DateTime(2026, 4, 15, 11, 22), score: 8.8),
    Viewing(id: 'v2', date: DateTime(2026, 5, 16, 22, 26), score: 8.5),
    Viewing(id: 'v3', date: DateTime(2026, 8, 16, 16, 49), score: 8.0),
  ],
  review: 'Первый раз. ' * 80,
  reviewMeta: _meta(
    'Аанг вернулся, и это главное',
    'v1',
    {'story': 8.4, 'direction': 8.8, 'pace': 8.0},
    verdict: Verdict.must,
    at: DateTime(2026, 4, 15, 12),
  ),
  moreReviews: [
    if (second)
      ExtraReview(
        id: 'mr-3',
        review: 'Третий раз. ' * 60,
        reviewMeta: _meta(
          'На третий раз видны швы',
          'v3',
          {'story': 6.8, 'direction': 8.0, 'pace': 6.8},
          verdict: Verdict.worth,
          at: DateTime(2026, 8, 16, 18),
        ),
      ),
  ],
);

/// Пять просмотров и пять рецензий: оценка росла с 7.5 до 9.2.
LibraryMovie _five() {
  const scores = [7.5, 8.0, 8.6, 9.0, 9.2];
  const pace = [6.0, 7.0, 8.0, 8.5, 9.0];
  ReviewMeta meta(int i) => _meta(
    'Рецензия ${i + 1}',
    'f$i',
    {'story': 7.0 + i * 0.5, 'pace': pace[i]},
    at: DateTime(2025, i + 1, 11),
  );
  return LibraryMovie(
    uuid: 'five',
    title: 'Грань будущего',
    status: LibraryStatus.watched,
    viewings: [
      for (var i = 0; i < 5; i++)
        Viewing(id: 'f$i', date: DateTime(2025, i + 1, 10), score: scores[i]),
    ],
    review: 'Текст',
    reviewMeta: meta(0),
    moreReviews: [
      for (var i = 1; i < 5; i++)
        ExtraReview(id: 'mr-$i', review: 'Текст', reviewMeta: meta(i)),
    ],
  );
}

Future<MovieRepository> _pump(
  WidgetTester tester,
  LibraryMovie movie, {
  String lang = 'ru',
  double width = 380,
  bool collapsed = false,
}) async {
  // Store держит один экземпляр настроек на весь прогон: пишем через него.
  await tester.runAsync(
    () => Store.instance.setBool(MovieReviewsSection.collapsedKey, collapsed),
  );
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  final repo = MovieRepository.detached({
    'movies': [movie.toJson()],
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ListenableBuilder(
            listenable: repo,
            builder: (_, _) => MovieReviewsSection(
              movie: repo.byUuid(movie.uuid)!,
              repo: repo,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('без рецензий: одна кнопка «Написать рецензию»', (tester) async {
    final m = LibraryMovie(
      uuid: 'm',
      title: 'Мэйдэй',
      status: LibraryStatus.watched,
      viewings: [Viewing(id: 'a', date: DateTime(2026, 9, 4), score: 7)],
    );
    await _pump(tester, m);
    expect(find.text(tr('write_review')), findsOneWidget);
    expect(find.textContaining('Мои рецензии'), findsNothing);
  });

  testWidgets('строки как у сериала: номер просмотра, вердикт, заголовок', (
    tester,
  ) async {
    await _pump(tester, _aang());
    expect(find.text('Мои рецензии · 2'), findsOneWidget);
    // Свежая рецензия сверху.
    expect(
      tester.getTopLeft(find.text('На третий раз видны швы')).dy,
      lessThan(tester.getTopLeft(find.text('Аанг вернулся, и это главное')).dy),
    );
    expect(find.text('Стоит времени'), findsOneWidget);
    expect(find.text('Обязательно'), findsOneWidget);
    expect(find.textContaining('16 авг 2026'), findsOneWidget);
    expect(find.textContaining('мин чтения'), findsNWidgets(2));
    // Оценка строки — оценка просмотра, о котором рецензия.
    expect(find.text('8.0'), findsWidgets);
    expect(find.text('8.8'), findsWidgets);
  });

  testWidgets('у фильма с одним просмотром номера в таблетке нет', (
    tester,
  ) async {
    final m = LibraryMovie(
      uuid: 'm',
      title: 'Мэйдэй',
      status: LibraryStatus.watched,
      viewings: [Viewing(id: 'a', date: DateTime(2026, 9, 4), score: 7)],
      review: 'Текст',
      reviewMeta: _meta('Мейдей, мейдей', 'a', {'story': 7}),
    );
    await _pump(tester, m);
    expect(find.text('Мои рецензии · 1'), findsOneWidget);
    expect(find.text('1-й'), findsNothing);
    // Писать больше не о чем: рецензия на единственный просмотр уже есть.
    expect(find.text(tr('rvs_write')), findsNothing);
    expect(find.text(tr('mrv_summary').toUpperCase()), findsNothing);
  });

  testWidgets('старая рецензия без заголовка показана началом текста', (
    tester,
  ) async {
    final m = LibraryMovie(
      uuid: 'm',
      title: 'Побег из тюрьмы',
      status: LibraryStatus.watched,
      viewings: [Viewing(id: 'a', date: DateTime(2026, 9, 4), score: 9)],
      review: 'Легендарный конец легендарной истории.\nPress F',
    );
    await _pump(tester, m);
    expect(find.text('Легендарный конец легендарной истории.'), findsOneWidget);
    expect(find.text(tr('rv_untitled')), findsNothing);
  });

  testWidgets('свод: столбец на рецензию, разница, просмотр без рецензии', (
    tester,
  ) async {
    await _pump(tester, _aang());
    expect(find.text(tr('mrv_summary').toUpperCase()), findsOneWidget);
    // Номер просмотра стоит и в строке списка, и в шапке свода.
    expect(find.text('1-й'), findsNWidgets(2));
    expect(find.text('3-й'), findsNWidgets(2));
    expect(find.text('апр 2026'), findsOneWidget);
    expect(find.text('авг 2026'), findsOneWidget);
    expect(find.text('Сюжет'), findsOneWidget);
    expect(find.text('-1.6'), findsOneWidget);
    expect(find.text('-0.8'), findsOneWidget);
    expect(find.text('-1.2'), findsOneWidget);
    expect(
      find.text('Между рецензиями оценка упала на 0.8. '
          'Сильнее всего изменился пункт «Сюжет».'),
      findsOneWidget,
    );
    expect(find.text('2-й просмотр без рецензии'), findsOneWidget);
  });

  testWidgets('одна рецензия на два просмотра: свода нет, номер есть', (
    tester,
  ) async {
    await _pump(tester, _aang(second: false));
    expect(find.text('Мои рецензии · 1'), findsOneWidget);
    expect(find.text('1-й'), findsOneWidget);
    expect(find.text(tr('mrv_summary').toUpperCase()), findsNothing);
    expect(find.text(tr('rvs_write')), findsOneWidget);
  });

  testWidgets('пять рецензий: пять столбцов и вывод с числом', (tester) async {
    await _pump(tester, _five());
    expect(find.text('Мои рецензии · 5'), findsOneWidget);
    for (final n in ['1-й', '2-й', '3-й', '4-й', '5-й']) {
      expect(find.text(n), findsNWidgets(2), reason: n);
    }
    expect(
      find.text('За 5 рецензий оценка выросла на 1.7. '
          'Сильнее всего изменился пункт «Темп».'),
      findsOneWidget,
    );
    expect(find.text('+3.0'), findsOneWidget);
    // На все просмотры рецензии есть: писать не о чем.
    expect(find.text(tr('rvs_write')), findsNothing);
    expect(find.textContaining('без рецензии'), findsNothing);
  });

  testWidgets('семь рецензий: столбцы листаются вбок, подписи на месте', (
    tester,
  ) async {
    final m = LibraryMovie(
      uuid: 'seven',
      title: 'Грань будущего',
      status: LibraryStatus.watched,
      viewings: [
        for (var i = 0; i < 7; i++)
          Viewing(id: 's$i', date: DateTime(2025, i + 1, 10), score: 7.0 + i * 0.3),
      ],
      review: 'Текст',
      reviewMeta: _meta('Рецензия 1', 's0', {'story': 7.0},
          at: DateTime(2025, 1, 11)),
      moreReviews: [
        for (var i = 1; i < 7; i++)
          ExtraReview(
            id: 'mr-$i',
            review: 'Текст',
            reviewMeta: _meta('Рецензия ${i + 1}', 's$i', {'story': 7.0 + i * 0.4},
                at: DateTime(2025, i + 1, 11)),
          ),
      ],
    );
    await _pump(tester, m, width: 320);
    expect(tester.takeException(), isNull);
    // Таблица открыта на последних рецензиях, первая ушла за край.
    final scroll = find.descendant(
      of: find.byType(MovieReviewsSection),
      matching: find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
    );
    expect(scroll, findsOneWidget);
    final box = tester.getRect(scroll);
    final last = tester.getRect(find.text('7-й').last);
    expect(last.right, lessThanOrEqualTo(box.right + 0.5));
    expect(last.left, greaterThanOrEqualTo(box.left - 0.5));
    // Подпись пункта стоит левее прокрутки и никуда не уезжает.
    expect(tester.getRect(find.text('Сюжет')).right,
        lessThanOrEqualTo(box.left + 0.5));
    expect(
      find.text('За 7 рецензий оценка выросла на 1.8. '
          'Сильнее всего изменился пункт «Сюжет».'),
      findsOneWidget,
    );
  });

  testWidgets('черновик в свод не идёт', (tester) async {
    final m = _aang(second: false)
      ..moreReviews.add(ExtraReview(
        id: 'mr-d',
        review: 'Набросок',
        reviewMeta: _meta('Черновик', 'v3', {'story': 5}, draft: true),
      ));
    await _pump(tester, m);
    expect(find.text('Мои рецензии · 2'), findsOneWidget);
    expect(find.textContaining('черновик'), findsOneWidget);
    expect(find.text(tr('mrv_summary').toUpperCase()), findsNothing);
  });

  testWidgets('блок сворачивается в строку с разницей и помнит это', (
    tester,
  ) async {
    await _pump(tester, _aang());
    await tester.tap(find.byTooltip(tr('rvs_collapse')));
    await tester.pumpAndSettle();
    expect(find.text('На третий раз видны швы'), findsNothing);
    expect(find.text(tr('mrv_summary').toUpperCase()), findsNothing);
    expect(find.text('1-й'), findsOneWidget);
    expect(find.text('3-й'), findsOneWidget);
    expect(find.text('Разница -0.8'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => Store.instance.getBool(MovieReviewsSection.collapsedKey),
      ),
      isTrue,
    );
    await tester.tap(find.byTooltip(tr('rvs_expand')));
    await tester.pumpAndSettle();
    expect(find.text('На третий раз видны швы'), findsOneWidget);
  });

  testWidgets('свёрнутый с прошлого раза открывается свёрнутым', (
    tester,
  ) async {
    await _pump(tester, _five(), collapsed: true);
    expect(find.text('Рецензия 5'), findsNothing);
    expect(find.text('Разница +1.7'), findsOneWidget);
  });

  testWidgets('«Написать» спрашивает просмотр, занятые выбрать нельзя', (
    tester,
  ) async {
    await _pump(tester, _aang());
    await tester.tap(find.text(tr('rvs_write')).first);
    await tester.pumpAndSettle();
    expect(find.text('О каком просмотре'), findsOneWidget);
    expect(find.text('16.05.2026 22:26'), findsOneWidget);
    expect(find.text('оценка 8.5'), findsOneWidget);
    expect(
      find.text('рецензия «Аанг вернулся, и это главное»'),
      findsOneWidget,
    );
    expect(find.text('рецензия «На третий раз видны швы»'), findsOneWidget);
    // Свободен только второй просмотр: он и выбран, «Далее» доступно.
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, tr('rv_next')),
    );
    expect(next.onPressed, isNotNull);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('320 dp без переполнений, $lang', (tester) async {
      await _pump(tester, _aang(), lang: lang, width: 320);
      expect(tester.takeException(), isNull);
    });
    testWidgets('320 dp: пять столбцов, $lang', (tester) async {
      await _pump(tester, _five(), lang: lang, width: 320);
      expect(tester.takeException(), isNull);
    });
    testWidgets('320 dp: свёрнутый, $lang', (tester) async {
      await _pump(tester, _five(), lang: lang, width: 320, collapsed: true);
      expect(tester.takeException(), isNull);
    });
  }
}
