import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/utils/review_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// Разбор Markdown рецензии: свои расширения и плоский текст для превью.
void main() {
  md.Element firstBlock(String src) =>
      parseReviewMarkdown(src).first as md.Element;

  List<md.Node> inline(String src) => firstBlock(src).children!;

  test('||текст|| даёт элемент spoiler', () {
    final nodes = inline('Финал: ||он пациент|| и всё.');
    final spoiler = nodes.whereType<md.Element>().single;
    expect(spoiler.tag, 'spoiler');
    expect(spoiler.textContent, 'он пациент');
  });

  test('внутри спойлера работает жирный', () {
    final spoiler =
        inline('||это **важно**||').whereType<md.Element>().single;
    expect(spoiler.tag, 'spoiler');
    expect(spoiler.children!.whereType<md.Element>().single.tag, 'strong');
  });

  test('одиночная черта остаётся текстом', () {
    final p = firstBlock('a | b');
    expect(p.textContent, 'a | b');
    expect(p.children!.whereType<md.Element>(), isEmpty);
  });

  test('термин — ссылка со схемой term:', () {
    final a = inline('Это [нуар](term:noir) чистой воды.')
        .whereType<md.Element>()
        .single;
    expect(a.tag, 'a');
    expect(a.attributes['href'], 'term:noir');
    expect(termIdOf(a.attributes['href']), 'noir');
    expect(termIdOf('https://kadr.app'), isNull);
  });

  test('HTML не исполняется и остаётся текстом', () {
    expect(firstBlock('<b>жирный</b>').textContent, '<b>жирный</b>');
  });

  test('заголовки, цитаты, списки и линия разбираются', () {
    final tags = parseReviewMarkdown(
            '## Итог\n\n> Цитата\n\n- раз\n- два\n\n---\n\n1. первый')
        .whereType<md.Element>()
        .map((e) => e.tag)
        .toList();
    expect(tags, ['h2', 'blockquote', 'ul', 'hr', 'ol']);
  });

  test('одиночный перенос строки сохраняется в тексте', () {
    expect(firstBlock('строка один\nстрока два').textContent,
        'строка один\nстрока два');
  });

  group('плоский текст', () {
    test('снимает разметку и прячет спойлер', () {
      final plain = reviewPlainText(
          '## Заголовок\n\nЭто **жирный** и [нуар](term:noir). ||Финал||',
          spoilerMask: '[спойлер]');
      expect(plain, 'Заголовок\nЭто жирный и нуар. [спойлер]');
    });

    test('слова и минуты чтения', () {
      final text = List.filled(400, 'слово').join(' ');
      expect(reviewWordCount(text), 400);
      expect(reviewReadMinutes(text), 3); // 400 / 180 → 3 минуты
      expect(reviewReadMinutes('коротко'), 1);
      expect(reviewWordCount('**жирный** _курсив_ ||тайна||'), 3);
      expect(reviewWordCount(''), 0);
    });
  });

  group('панель разметки', () {
    TextEditingValue v(String text, int start, [int? end]) => TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: start, extentOffset: end ?? start));

    test('жирный оборачивает выделение и сохраняет его', () {
      final r = applyReviewFormat(v('очень сильно', 6, 12), ReviewFormat.bold);
      expect(r.text, 'очень **сильно**');
      expect(r.selection, const TextSelection(baseOffset: 8, extentOffset: 14));
    });

    test('без выделения ставит пару знаков и курсор между ними', () {
      final r = applyReviewFormat(v('абв', 3), ReviewFormat.spoiler);
      expect(r.text, 'абв||||');
      expect(r.selection, const TextSelection.collapsed(offset: 5));
    });

    test('курсив — подчёркивания', () {
      expect(applyReviewFormat(v('слово', 0, 5), ReviewFormat.italic).text,
          '_слово_');
    });

    test('заголовок ставится и снимается в начале строки', () {
      final on = applyReviewFormat(v('раз\nдва', 5), ReviewFormat.heading);
      expect(on.text, 'раз\n## два');
      expect(on.selection, const TextSelection.collapsed(offset: 8));
      final off = applyReviewFormat(on, ReviewFormat.heading);
      expect(off.text, 'раз\nдва');
    });

    test('цитата и список ставятся на каждую выделенную строку', () {
      expect(applyReviewFormat(v('а\nб', 0, 3), ReviewFormat.quote).text,
          '> а\n> б');
      expect(applyReviewFormat(v('а\nб', 0, 3), ReviewFormat.list).text,
          '- а\n- б');
    });

    test('термин оборачивает выделение ссылкой', () {
      final r = applyReviewTerm(v('чистый нуар тут', 7, 11), 'noir', 'Нуар');
      expect(r.text, 'чистый [нуар](term:noir) тут');
    });

    test('термин без выделения вставляет название', () {
      final r = applyReviewTerm(v('Это ', 4), 'noir', 'Нуар');
      expect(r.text, 'Это [Нуар](term:noir)');
      expect(r.selection, const TextSelection.collapsed(offset: 21));
    });

    test('при невалидном курсоре вставка идёт в конец', () {
      final r = applyReviewFormat(
          const TextEditingValue(text: 'ab'), ReviewFormat.bold);
      expect(r.text, 'ab****');
    });
  });
}
