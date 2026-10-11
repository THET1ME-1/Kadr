import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/movie_sheet.dart';
import 'package:kadr/services/app_prefs.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Карточка фильма листается вниз и обратно вверх.
///
/// Блок «Мои рецензии» узнавал, свёрнут ли он, уже после первого кадра.
/// Список карточки ленивый: ушедший далеко вверх блок выбрасывается, а при
/// возврате создаётся заново, развёрнутым. Через кадр он сворачивался, и всё
/// под ним подпрыгивало вверх на высоту рецензий. Блок снова оказывался
/// далеко, выбрасывался, и так по кругу: выше блока «Просмотры» страница не
/// шла, а каждый круг заново строил рецензии со сводом.
LibraryMovie _spider() => LibraryMovie(
      uuid: 'scroll',
      title: 'Человек-паук: Новый день',
      year: 2026,
      status: LibraryStatus.watched,
      viewings: [
        Viewing(id: 'v1', date: DateTime(2026, 9, 4, 16, 7), score: 9.5),
        Viewing(id: 'v2', date: DateTime(2026, 10, 10, 23, 32), score: 9.5),
      ],
      review: 'Первый раз.',
      reviewMeta: ReviewMeta(
        title: 'Начинается новый день',
        viewId: 'v1',
        criteria: {'story': 9.0, 'acting': 9.5, 'visuals': 9.0},
        publishedAt: DateTime(2026, 9, 4, 18),
      ),
      moreReviews: [
        ExtraReview(
          id: 'mr-2',
          review: 'Второй раз.',
          reviewMeta: ReviewMeta(
            title: 'Это прекрасно было',
            viewId: 'v2',
            criteria: {'story': 9.5, 'acting': 9.5, 'visuals': 9.5},
            publishedAt: DateTime(2026, 10, 10, 23, 44),
          ),
        ),
      ],
      // Длинный хвост страницы: без него блок рецензий не уходит далеко.
      emotions: [
        for (var i = 0; i < 160; i++)
          MovieEmotion(id: 'e$i', label: 'Эмоция $i', emoji: '🙂', score: 8),
      ],
    );

void main() {
  tearDown(() => AppPrefs.instance.setMovieReviewsCollapsed(false));

  Future<ScrollPosition> open(WidgetTester tester,
      {required bool collapsed}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await LocaleController.instance.setCode('ru');
      await AppPrefs.instance.setMovieReviewsCollapsed(collapsed);
    });
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        paths, (_) async => throw PlatformException(code: 'no-dir'));
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    final repo = MovieRepository.instance;
    await tester.runAsync(
        () => repo.restoreFromSnapshot([_spider().toJson()], const []));
    await http.runWithClient(
      () async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.dark(AppTheme.defaultSeed),
          home: MovieScreen(movie: repo.byUuid('scroll')!),
        ));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      },
      () => MockClient((_) async => http.Response('{}', 404)),
    );
    return tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
  }

  /// Тянет страницу на [dy] и ждёт, пока улягутся анимации.
  Future<void> drag(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> toBottom(WidgetTester tester, ScrollPosition position) async {
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      await drag(tester, -600);
    }
    expect(position.pixels, position.maxScrollExtent);
  }

  for (final collapsed in [true, false]) {
    final state = collapsed ? 'свёрнуты' : 'развёрнуты';
    testWidgets('рецензии $state: страница возвращается наверх', (
      tester,
    ) async {
      final position = await open(tester, collapsed: collapsed);
      final top = tester.getTopLeft(find.text('2 просмотра')).dy;
      expect(find.text('Начинается новый день'),
          collapsed ? findsNothing : findsOneWidget);
      await toBottom(tester, position);
      expect(find.text('2 просмотра'), findsNothing);

      // Обратно короткими шагами, как ведёт палец. Шагов с запасом: страница
      // втрое короче этого пути.
      for (var i = 0; i < 120 && position.pixels > 0; i++) {
        await drag(tester, 100);
      }
      expect(position.pixels, 0, reason: 'страница не дошла до верха');
      expect(tester.getTopLeft(find.text('2 просмотра')).dy, top,
          reason: 'верх страницы стоит не там, где был');
    });
  }

  testWidgets('блок, вернувшийся на экран, сразу свёрнут и не прыгает', (
    tester,
  ) async {
    final position = await open(tester, collapsed: true);
    await toBottom(tester, position);
    // Вверх до блока рецензий. После каждого шага заголовок просмотров
    // обязан остаться там, куда его привёл палец: без отскока.
    final header = find.text('Просмотры · 2');
    final reviews = find.text('Мои рецензии · 2');
    for (var i = 0; i < 80 && reviews.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
      await tester.pump();
      final before =
          header.evaluate().isEmpty ? null : tester.getTopLeft(header).dy;
      await tester.pump(const Duration(milliseconds: 400));
      if (before == null) continue;
      expect(header, findsOneWidget, reason: 'после шага $i блок пропал');
      expect(tester.getTopLeft(header).dy, before,
          reason: 'страницу отбросило после шага $i');
    }
    expect(reviews, findsOneWidget);
    expect(find.text('Начинается новый день'), findsNothing,
        reason: 'блок вернулся развёрнутым');
  });
}
