import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/models/review.dart';
import 'package:kadr/screens/viewing/viewing_host.dart';
import 'package:kadr/screens/viewing/viewings_section.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Легенда об Аанге»: три просмотра с оценками 8.8, 8.5, 8.0.
LibraryMovie _aang() => LibraryMovie(
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
    Viewing(id: 'v3', date: DateTime(2026, 8, 16, 16, 49), score: 8.0),
  ],
  review: 'Текст',
  reviewMeta: ReviewMeta(title: 'Аанг вернулся', viewId: 'v1'),
  moreReviews: [
    ExtraReview(
      id: 'mr-1',
      review: 'Ещё текст',
      reviewMeta: ReviewMeta(title: 'На третий раз', viewId: 'v3'),
    ),
  ],
);

/// «Аватар»: четыре просмотра без даты с одной оценкой и два с датой.
LibraryMovie _avatar() => LibraryMovie(
  uuid: 'avatar',
  title: 'Аватар',
  status: LibraryStatus.watched,
  viewings: [
    for (var i = 0; i < 4; i++) Viewing(id: 'u$i', score: 10),
    Viewing(id: 'd5', date: DateTime(2025, 8, 20), score: 10),
    Viewing(id: 'd6', date: DateTime(2025, 10, 4), score: 10),
  ],
);

/// Пять просмотров с датами: больше, чем блок показывает сразу.
LibraryMovie _five() => LibraryMovie(
  uuid: 'five',
  title: 'Грань будущего',
  status: LibraryStatus.watched,
  viewings: [
    for (var i = 1; i <= 5; i++)
      Viewing(id: 'f$i', date: DateTime(2025, i, 10), score: 7.0 + i * 0.5),
  ],
);

Future<MovieRepository> _pump(
  WidgetTester tester,
  LibraryMovie movie, {
  String lang = 'ru',
  double width = 380,
}) async {
  tester.view.physicalSize = Size(width, 1600);
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
          child: ViewingsSection(
            host: MovieViewingHost(movie.uuid, repo: repo),
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

  testWidgets('строки свежие сверху, номера по дате', (tester) async {
    await _pump(tester, _aang());
    expect(find.text('Просмотры · 3'), findsOneWidget);
    final ys = [
      for (final t in ['16.08.2026 16:49', '16.05.2026 22:26', '15.04.2026 11:22'])
        tester.getTopLeft(find.text(t)).dy,
    ];
    expect(ys, [...ys]..sort());
    // Номер просмотра стоит в строке своей даты.
    for (final (n, date) in [
      ('3', '16.08.2026 16:49'),
      ('2', '16.05.2026 22:26'),
      ('1', '15.04.2026 11:22'),
    ]) {
      expect(
        (tester.getCenter(find.text(n)).dy - tester.getCenter(find.text(date)).dy)
            .abs(),
        lessThan(40),
        reason: 'номер $n не в строке $date',
      );
    }
  });

  testWidgets('подпись строки: разница с прошлым разом, дневник, рецензия', (
    tester,
  ) async {
    await _pump(tester, _aang());
    // Подписи со значком собраны одним текстом: ищем по вхождению.
    expect(find.textContaining('-0.8 с первого раза'), findsOneWidget);
    expect(find.text('-0.5'), findsOneWidget);
    expect(find.text('-0.3'), findsOneWidget);
    expect(find.text('🥹 🔥 😍 · дом'), findsOneWidget);
    expect(find.textContaining('есть рецензия'), findsNWidgets(2));
    expect(find.text('8.8'), findsOneWidget);
    expect(find.text('8.0'), findsOneWidget);
  });

  testWidgets('оценка не менялась: «оценка та же», разниц в строках нет', (
    tester,
  ) async {
    final m = LibraryMovie(
      uuid: 'sp',
      title: 'Человек-паук: Новый день',
      status: LibraryStatus.watched,
      viewings: [
        Viewing(id: 'a', date: DateTime(2026, 9, 4, 16, 7), score: 9.5),
        Viewing(id: 'b', date: DateTime(2026, 10, 10, 23, 32), score: 9.5),
      ],
    );
    await _pump(tester, m);
    expect(find.textContaining('оценка та же'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);
    expect(find.textContaining('-0'), findsNothing);
  });

  testWidgets('один оценённый просмотр: сравнивать не с чем', (tester) async {
    final m = LibraryMovie(
      uuid: 'one',
      title: 'Мэйдэй',
      status: LibraryStatus.watched,
      viewings: [Viewing(id: 'a', date: DateTime(2026, 9, 4), score: 7)],
    );
    await _pump(tester, m);
    expect(find.text('Просмотры · 1'), findsOneWidget);
    expect(find.textContaining('с первого раза'), findsNothing);
    expect(find.textContaining('оценка та же'), findsNothing);
  });

  testWidgets('больше трёх строк сворачиваются в «ещё N»', (tester) async {
    await _pump(tester, _five());
    expect(find.text('Просмотры · 5'), findsOneWidget);
    expect(find.text('10.05.2025'), findsOneWidget);
    expect(find.text('10.03.2025'), findsOneWidget);
    expect(find.text('10.02.2025'), findsNothing);
    expect(find.text('ещё 2'), findsOneWidget);
    await tester.tap(find.text('ещё 2'));
    await tester.pumpAndSettle();
    expect(find.text('10.02.2025'), findsOneWidget);
    expect(find.text('10.01.2025'), findsOneWidget);
    expect(find.text('ещё 2'), findsNothing);
  });

  testWidgets('просмотры без даты с одной оценкой собраны в строку', (
    tester,
  ) async {
    await _pump(tester, _avatar());
    expect(find.text('Просмотры · 6'), findsOneWidget);
    expect(find.text('Без даты'), findsOneWidget);
    expect(find.text('номера 1–4 · 10.0'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    // Шесть просмотров уместились в три строки: «ещё» не нужно.
    expect(find.textContaining('ещё'), findsNothing);
  });

  testWidgets('плюс добавляет «видел раньше», минус убирает без вопроса', (
    tester,
  ) async {
    final repo = await _pump(tester, _avatar());
    await tester.tap(find.byTooltip(tr('view_step_more')));
    await tester.pumpAndSettle();
    var m = repo.byUuid('avatar')!;
    expect(m.viewings.length, 7);
    // Новый просмотр без даты и с той же оценкой: в ленту не попадёт.
    expect(m.viewings.where((v) => v.date == null).length, 5);
    expect(m.viewings.where((v) => v.date == null).every((v) => v.score == 10),
        isTrue);
    expect(find.text('номера 1–5 · 10.0'), findsOneWidget);
    expect(find.text('Просмотры · 7'), findsOneWidget);

    await tester.tap(find.byTooltip(tr('view_step_less')));
    await tester.pumpAndSettle();
    m = repo.byUuid('avatar')!;
    expect(m.viewings.length, 6);
    expect(find.textContaining('Удалить просмотр'), findsNothing);
    expect(find.text('Просмотр удалён'), findsOneWidget);
    await tester.tap(find.text('Вернуть'));
    await tester.pumpAndSettle();
    expect(repo.byUuid('avatar')!.viewings.length, 7);
  });

  testWidgets('просмотр без даты с дневником в общую строку не уходит', (
    tester,
  ) async {
    final m = _avatar()
      ..viewings.first.diary = DiaryEntry(moods: ['🔥']);
    await _pump(tester, m);
    // Три одинаковых собраны, четвёртый стоит своей строкой (она четвёртая
    // по счёту, поэтому спрятана за «ещё 1»).
    expect(find.text('номера 2–4 · 10.0'), findsOneWidget);
    await tester.tap(find.text('ещё 1'));
    await tester.pumpAndSettle();
    expect(find.text('Без даты'), findsNWidgets(2));
    expect(find.text('🔥'), findsOneWidget);
  });

  testWidgets('тап по строке открывает окно просмотра', (tester) async {
    await _pump(tester, _aang());
    await tester.tap(find.text('16.05.2026 22:26'));
    await tester.pumpAndSettle();
    expect(find.text('Оценка просмотра'), findsOneWidget);
    expect(find.text('2-й · 16.05'), findsOneWidget);
  });

  for (final lang in LocaleController.languages.map((l) => l.code)) {
    testWidgets('320 dp без переполнений, $lang', (tester) async {
      await _pump(tester, _aang(), lang: lang, width: 320);
      expect(tester.takeException(), isNull);
    });
    testWidgets('320 dp: строка «Без даты», $lang', (tester) async {
      await _pump(tester, _avatar(), lang: lang, width: 320);
      expect(tester.takeException(), isNull);
    });
  }
}
