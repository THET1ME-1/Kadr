import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/utils/share_card_data.dart';
import 'package:kadr/utils/share_palette.dart';
import 'package:kadr/widgets/share_card.dart';

ShareCardData _data({
  ShareFacts facts = const ShareFacts(score: 6.9, viewNumber: 1),
  String footerNote = '3 августа 2026',
  ShareTexture texture = ShareTexture.letters,
}) =>
    ShareCardData(
      title: 'Колония',
      meta: '2026 · Ужасы, триллер · 1 ч 58 мин',
      palette: SharePalette.fallback,
      facts: facts,
      footerNote: footerNote,
      texture: texture,
    );

/// Тестовая поверхность по умолчанию 800×600 — «Сторис» в неё не влезает и
/// сжимается, поэтому даём карточкам полный простор.
void _roomy(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );

void main() {
  for (final style in ShareCardStyle.values) {
    testWidgets('стиль ${style.name}: название, метаданные и оценка на месте',
        (tester) async {
      _roomy(tester);
      await tester.pumpWidget(
          _wrap(ShareCard(data: _data(), style: style)));

      expect(find.text('Колония'), findsOneWidget);
      expect(find.textContaining('6,9'), findsWidgets);
      expect(find.textContaining('Kadr'), findsOneWidget);
    });

    testWidgets('стиль ${style.name}: держит заявленный размер',
        (tester) async {
      _roomy(tester);
      await tester.pumpWidget(
          _wrap(ShareCard(data: _data(), style: style)));

      expect(tester.getSize(find.byType(ShareCard)), ShareCard.sizeOf(style));
    });
  }

  testWidgets('фильм без оценки показывает, что его хотят посмотреть',
      (tester) async {
    _roomy(tester);
    await tester.pumpWidget(_wrap(ShareCard(
      data: _data(
        facts: const ShareFacts(wantToWatch: true),
        footerNote: 'в списке',
      ),
      style: ShareCardStyle.poster,
    )));

    expect(find.text('Хочу посмотреть'), findsOneWidget);
    expect(find.textContaining('6,9'), findsNothing);
  });

  testWidgets('пересмотр и эмоция видны на карточке', (tester) async {
    await tester.pumpWidget(_wrap(ShareCard(
      data: _data(
        facts: const ShareFacts(
          score: 8.2,
          viewNumber: 2,
          emotion: MovieEmotion(
              id: 'wow', label: 'Взрыв мозга', emoji: '🤯', score: 9),
        ),
        footerNote: '2-й просмотр · 3 августа',
      ),
      style: ShareCardStyle.story,
    )));

    expect(find.textContaining('Взрыв мозга'), findsOneWidget);
  });

  for (final style in ShareCardStyle.values) {
    testWidgets('стиль ${style.name}: полные данные не ломают вёрстку',
        (tester) async {
      _roomy(tester);
      await tester.pumpWidget(_wrap(ShareCard(
        data: _data(
          facts: const ShareFacts(
            score: 6.9,
            viewNumber: 3,
            emotion: MovieEmotion(
                id: 'wow', label: 'Взрыв мозга', emoji: '🤯', score: 9),
          ),
          footerNote: '3-й просмотр · 3 августа 2026',
        ),
        style: style,
      )));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('билет пишет дату числами, а не длинной подписью',
      (tester) async {
    _roomy(tester);
    await tester.pumpWidget(_wrap(ShareCard(
      data: ShareCardData(
        title: 'Колония',
        meta: '2026 · Ужасы, триллер',
        palette: SharePalette.fallback,
        facts: ShareFacts(
          score: 6.9,
          viewNumber: 1,
          watchedAt: DateTime(2026, 8, 3),
        ),
        footerNote: '3 августа 2026',
        texture: ShareTexture.letters,
      ),
      style: ShareCardStyle.ticket,
    )));

    expect(find.text('03.08.2026'), findsOneWidget);
    expect(find.text('3 августа 2026'), findsNothing);
  });

  testWidgets('сторис не повторяет номер просмотра дважды', (tester) async {
    _roomy(tester);
    await tester.pumpWidget(_wrap(ShareCard(
      data: ShareCardData(
        title: 'Колония',
        palette: SharePalette.fallback,
        facts: ShareFacts(
          score: 6.9,
          viewNumber: 2,
          watchedAt: DateTime(2026, 8, 3),
        ),
        footerNote: '2-й просмотр · 3 августа 2026',
        texture: ShareTexture.letters,
      ),
      style: ShareCardStyle.story,
    )));

    expect(find.textContaining('2-й просмотр'), findsOneWidget);
    expect(find.text('3 августа 2026'), findsOneWidget);
  });

  testWidgets('размер экспорта считается от масштаба', (tester) async {
    expect(ShareCard.exportSize(ShareCardStyle.poster, pixelRatio: 3).width,
        1080);
    expect(ShareCard.exportSize(ShareCardStyle.story, pixelRatio: 3).height,
        1920);
  });
}
