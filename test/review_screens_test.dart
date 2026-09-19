import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/models/social.dart';
import 'package:kadr/screens/review/review_editor_screen.dart';
import 'package:kadr/screens/review/review_screen.dart';
import 'package:kadr/screens/review/review_target.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:kadr/widgets/review/markdown_view.dart';
import 'package:kadr/widgets/review/review_parts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _text = '''Скорсезе снимает [нуар](term:noir) по всем правилам жанра: шторм, остров, маршал с тёмным прошлым.

Первые полчаса работают как **классический детектив**, а финал _переворачивает_ всё.

> Каждый санитар отвечает на вопросы на полсекунды позже, чем нужно.

||Тедди Дэниелс оказывается пациентом.||

- музыка Пендерецкого
- мокрый камень и низкое небо''';

/// Библиотека из одного просмотренного фильма, без tmdbId: экраны не
/// ходят в сеть. [meta] — готовая рецензия.
MovieRepository _repo({ReviewMeta? meta, String? text}) =>
    MovieRepository.detached({
      'movies': [
        LibraryMovie(
          uuid: 'm1',
          title: 'Остров проклятых',
          year: 2010,
          status: LibraryStatus.watched,
          viewings: [Viewing(date: DateTime(2024, 3, 12), score: 8.5)],
          review: text,
          reviewMeta: meta,
        ).toJson(),
      ],
    });

ReviewMeta _fullMeta({bool spoilers = false}) => ReviewMeta(
      title: 'Маяк, который светит внутрь',
      criteria: {
        'story': 9.0,
        'direction': 9.3,
        'acting': 9.1,
        'visuals': 8.6,
        'sound': 8.8,
        'pace': 6.8,
      },
      verdict: Verdict.must,
      pros: ['Финальный твист', 'Атмосфера острова', 'Музыка'],
      cons: ['Провисает середина'],
      spoilers: spoilers,
      publishedAt: DateTime(2026, 9, 19),
    );

const _friend = SocialUser(
    id: 'u2', displayName: 'Марина', avatarVer: 0, friendCode: 'MARINA');

Widget _app(Widget home) => MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: home,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void phone(WidgetTester tester, {double h = 2400}) {
    tester.view.physicalSize = Size(320, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('редактор: три шага на 320 dp без переполнений, $lang',
        (tester) async {
      phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      final repo = _repo(meta: _fullMeta(), text: _text);
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);

      await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(tr('verdict_must')), findsOneWidget);

      for (var step = 1; step <= 2; step++) {
        await tester.tap(find.text(tr('rv_next')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'шаг $step');
      }
      expect(find.widgetWithText(FilledButton, tr('rv_publish')), findsNothing,
          reason: 'без входа в аккаунт кнопка сохраняет, а не публикует');
      expect(find.widgetWithText(FilledButton, tr('rv_save')), findsOneWidget);
    });

    testWidgets('чтение рецензии друга на 320 dp, $lang', (tester) async {
      phone(tester, h: 3400);
      await tester.runAsync(() => LocaleController.instance.setCode(lang));
      final repo = _repo(meta: _fullMeta(), text: _text);
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);

      await tester.pumpWidget(
          _app(ReviewScreen(target: target, author: _friend)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Маяк, который светит внутрь'), findsOneWidget);
      expect(find.text(tr('verdict_must')), findsOneWidget);
    });
  }

  testWidgets('публикация сохраняет разбор и открывает рецензию',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo();
    final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);

    await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Шедевр'));
    await tester.tap(find.text('Шедевр'));
    await tester.pump();

    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Заголовок');
    await tester.enterText(find.byType(TextField).last, 'Первый абзац.');
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Сохранить'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final m = repo.byUuid('m1')!;
    expect(m.review, 'Первый абзац.');
    expect(m.reviewMeta!.verdict, Verdict.masterpiece);
    expect(m.reviewMeta!.title, 'Заголовок');
    expect(m.reviewMeta!.draft, isFalse);
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.text('Заголовок'), findsOneWidget);
  });

  testWidgets('уход без публикации оставляет черновик', (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo();
    final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);

    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => openReviewEditor(context, target),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Мимо'));
    await tester.tap(find.text('Мимо'));
    await tester.pump();
    await tester.tap(find.byTooltip(tr('close')));
    await tester.pumpAndSettle();

    final meta = repo.byUuid('m1')!.reviewMeta!;
    expect(meta.verdict, Verdict.miss);
    expect(meta.draft, isTrue);
    expect(find.text(tr('rv_draft_saved')), findsOneWidget);
  });

  testWidgets('системное «назад» на втором шаге возвращает на первый',
      (tester) async {
    phone(tester);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo();
    final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);
    await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(find.text(tr('rv_mode_edit')), findsOneWidget);

    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text(tr('rv_overall').toUpperCase()), findsOneWidget);
  });

  testWidgets('спойлеры в чужой рецензии закрыты, пока не нажмёшь',
      (tester) async {
    phone(tester, h: 3400);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo(meta: _fullMeta(spoilers: true), text: _text);
    final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);

    await tester.pumpWidget(
        _app(ReviewScreen(target: target, author: _friend)));
    await tester.pumpAndSettle();
    expect(find.text(tr('rv_gate_title')), findsOneWidget);
    expect(find.byType(MarkdownView), findsNothing);

    await tester.tap(find.text(tr('rv_gate_open')));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownView), findsOneWidget);
  });

  testWidgets('своя рецензия со спойлерами открыта сразу', (tester) async {
    phone(tester, h: 3400);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    final repo = _repo(meta: _fullMeta(spoilers: true), text: _text);
    final target =
        ReviewTarget.movie(repo.byUuid('m1')!, repo: repo, mine: true);

    await tester.pumpWidget(_app(ReviewScreen(target: target)));
    await tester.pumpAndSettle();
    expect(find.text(tr('rv_gate_title')), findsNothing);
    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.text(tr('edit')), findsOneWidget);
  });

  testWidgets('термин открывает определение нижней панелью', (tester) async {
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app(const Scaffold(
        body: MarkdownView(data: 'Чистый [нуар](term:noir) тут.'))));
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('нуар'));
    await tester.pumpAndSettle();
    expect(find.text('Нуар'), findsOneWidget);
    expect(find.textContaining('Мрачный детектив'), findsOneWidget);
  });

  testWidgets('спойлер в строке открывается нажатием', (tester) async {
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(_app(const Scaffold(
        body: MarkdownView(data: 'Финал: ||он **пациент**|| и всё.'))));
    await tester.pumpAndSettle();
    final para = tester.widget<RichText>(find.byType(RichText).first);
    Color? colorOf(String word) {
      Color? found;
      para.text.visitChildren((s) {
        if (s is TextSpan && (s.text?.contains(word) ?? false)) {
          found = s.style?.color;
          return false;
        }
        return true;
      });
      return found;
    }

    final hidden = colorOf('он');
    // У спрятанного спойлера подпись для чтения с экрана заменяет текст,
    // поэтому жмём по координатам: «Финал: » — семь знаков тестового шрифта
    // шириной в кегль 16.
    final origin = tester.getTopLeft(find.byType(RichText).first);
    await tester.tapAt(origin + const Offset(7 * 16 + 24, 10));
    await tester.pumpAndSettle();
    final shown = tester.widget<RichText>(find.byType(RichText).first);
    var bold = false;
    shown.text.visitChildren((s) {
      if (s is TextSpan && s.text == 'пациент') {
        bold = s.style?.fontWeight == FontWeight.w700;
      }
      return true;
    });
    expect(hidden, isNotNull);
    expect(bold, isTrue, reason: 'после открытия видно разметку внутри');
  });

  group('после ревью', () {
    testWidgets('превью чужой рецензии со спойлерами не показывает текст',
        (tester) async {
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      await tester.pumpWidget(_app(Scaffold(
        body: SingleChildScrollView(
          child: ReviewPreviewCard(
            text: 'Скорсезе прячет главное в мелочах.',
            meta: _fullMeta(spoilers: true),
            guardSpoilers: true,
            onOpen: () {},
          ),
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Скорсезе'), findsNothing);
      expect(find.text(tr('rv_gate_title')), findsOneWidget);
    });

    MovieRepository mineWith(LibraryStatus status) =>
        MovieRepository.detached({
          'movies': [
            LibraryMovie(
                    uuid: 'x', title: 'Остров', tmdbId: 11324, status: status)
                .toJson(),
          ],
        });

    MovieRepository friendRepo() => MovieRepository.detached({
          'movies': [
            LibraryMovie(
              uuid: 'm1',
              title: 'Остров проклятых',
              tmdbId: 11324,
              status: LibraryStatus.watched,
              review: 'Текст',
              reviewMeta: _fullMeta(),
            ).toJson(),
          ],
        });

    for (final status in [LibraryStatus.watchlist, LibraryStatus.dropped]) {
      testWidgets('чужая рецензия: мой фильм в «${status.name}» — без кнопки',
          (tester) async {
        phone(tester, h: 3400);
        await tester.runAsync(() => LocaleController.instance.setCode('ru'));
        final repo = friendRepo();
        await tester.pumpWidget(_app(ReviewScreen(
          target: ReviewTarget.movie(repo.byUuid('m1')!, repo: repo),
          author: _friend,
          myRepo: mineWith(status),
        )));
        await tester.pump();
        expect(find.text(tr('sl_add_to_watchlist')), findsNothing);
      });
    }

    testWidgets('чужая рецензия: фильма у меня нет — предлагаем в список',
        (tester) async {
      phone(tester, h: 3400);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      final repo = friendRepo();
      await tester.pumpWidget(_app(ReviewScreen(
        target: ReviewTarget.movie(repo.byUuid('m1')!, repo: repo),
        author: _friend,
        myRepo: MovieRepository.detached(const {}),
      )));
      await tester.pump();
      expect(find.text(tr('sl_add_to_watchlist')), findsOneWidget);
    });

    testWidgets('заход в редактор без правок не трогает рецензию',
        (tester) async {
      phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      final stamp = DateTime(2026, 9, 1, 12);
      final repo = _repo(
          meta: _fullMeta()..updatedAt = stamp, text: 'Готовый текст.');
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);

      await tester.pumpWidget(_app(ReviewEditorScreen(
          target: target, initialStep: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Готовый текст.'));
      await tester.pump();
      await tester.tap(find.byTooltip(tr('close')));
      await tester.pumpAndSettle();
      expect(repo.byUuid('m1')!.reviewMeta!.updatedAt, stamp);
    });

    testWidgets('старая рецензия без разбора остаётся без разбора',
        (tester) async {
      phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      final repo = _repo(text: 'Старая рецензия.');
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);
      await tester.pumpWidget(_app(ReviewEditorScreen(
          target: target, initialStep: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Старая рецензия.'));
      await tester.pump();
      await tester.tap(find.byTooltip(tr('close')));
      await tester.pumpAndSettle();
      expect(repo.byUuid('m1')!.reviewMeta, isNull);
    });
  });

  group('правки с телефона', () {
    testWidgets('у поля текста нет рамки и в фокусе', (tester) async {
      phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      final repo = _repo(text: 'Кайф');
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);
      await tester.pumpWidget(
          _app(ReviewEditorScreen(target: target, initialStep: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кайф'));
      await tester.pump();
      for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
        final d = f.decoration!;
        expect(d.focusedBorder, InputBorder.none);
        expect(d.enabledBorder, InputBorder.none);
        expect(d.filled, isFalse);
      }
    });

    testWidgets('нажатие на число пункта открывает калькулятор',
        (tester) async {
      phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      final repo = _repo(meta: _fullMeta(), text: _text);
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);
      await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('6.8'));
      await tester.tap(find.text('6.8'));
      await tester.pumpAndSettle();
      expect(find.text(tr('enter_score')), findsOneWidget);
      final pad = find.byType(BottomSheet);
      for (final k in ['7', '.', '4']) {
        await tester.tap(find.descendant(of: pad, matching: find.text(k)));
        await tester.pump();
      }
      await tester.tap(find.descendant(of: pad, matching: find.text(tr('done'))));
      await tester.pumpAndSettle();
      expect(find.text('7.4'), findsOneWidget);
      expect(find.text('6.8'), findsNothing);
    });

    testWidgets('удержание числа сбрасывает пункт', (tester) async {
      phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      final repo = _repo(meta: _fullMeta(), text: _text);
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);
      await tester.pumpWidget(_app(ReviewEditorScreen(target: target)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('6.8'));
      await tester.longPress(find.text('6.8'));
      await tester.pumpAndSettle();
      expect(find.text('6.8'), findsNothing);
      expect(find.text(tr('enter_score')), findsNothing);
    });

    testWidgets('черновик сохраняется сам, пока пишешь', (tester) async {
      phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      final repo = _repo();
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);
      await tester.pumpWidget(
          _app(ReviewEditorScreen(target: target, initialStep: 1)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Закрутили петли');
      await tester.pump(const Duration(seconds: 3));

      final m = repo.byUuid('m1')!;
      expect(m.review, 'Закрутили петли');
      expect(m.reviewMeta!.draft, isTrue);
    });

    testWidgets('сворачивание приложения сохраняет правку опубликованной',
        (tester) async {
      phone(tester);
      await tester.runAsync(() => LocaleController.instance.setCode('ru'));
      final repo = _repo(meta: _fullMeta(), text: 'Было.');
      final target = ReviewTarget.movie(repo.byUuid('m1')!, repo: repo);
      await tester.pumpWidget(
          _app(ReviewEditorScreen(target: target, initialStep: 1)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Стало.');
      await tester.pump(const Duration(seconds: 3));
      // Опубликованную не переписываем на лету: друзья видели бы опечатки.
      expect(repo.byUuid('m1')!.review, 'Было.');

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(repo.byUuid('m1')!.review, 'Стало.');
      expect(repo.byUuid('m1')!.reviewMeta!.draft, isFalse);
    });
  });
}
