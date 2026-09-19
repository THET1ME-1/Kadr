// Markdown рецензии: разбор в дерево и плоский текст для превью и подсчётов.
//
// Пакет `markdown` здесь только парсер, в виджеты дерево переводит
// `widgets/review/markdown_view.dart`. Свои расширения:
//   * `||текст||` — спойлер (как в Telegram и Discord);
//   * `[слово](term:id)` — термин из словаря критика, у читателя по нажатию
//     открывается определение на его языке.
// HTML не поддерживается: теги остаются видимым текстом.

import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

/// Спойлер `||…||` поверх правил вложенности, как у `**жирного**`.
class SpoilerSyntax extends md.DelimiterSyntax {
  SpoilerSyntax()
      : super(
          r'\|+',
          requiresDelimiterRun: true,
          allowIntraWord: true,
          startCharacter: 0x7C, // |
          tags: [md.DelimiterTag('spoiler', 2)],
        );
}

/// Блоки, которые понимает рецензия. Без HTML-блоков, кода с отступом (на
/// телефоне четыре пробела в начале строки выходят случайно) и заголовков
/// с подчёркиванием `---`, которые путаются с линией.
List<md.BlockSyntax> _blocks() => const [
      md.EmptyBlockSyntax(),
      md.HeaderSyntax(),
      md.FencedCodeBlockSyntax(),
      md.BlockquoteSyntax(),
      md.HorizontalRuleSyntax(),
      md.UnorderedListSyntax(),
      md.OrderedListSyntax(),
      md.ParagraphSyntax(),
    ];

md.Document _document() => md.Document(
      extensionSet: md.ExtensionSet.none,
      blockSyntaxes: _blocks(),
      withDefaultBlockSyntaxes: false,
      inlineSyntaxes: [
        md.StrikethroughSyntax(),
        SpoilerSyntax(),
        md.AutolinkExtensionSyntax(),
      ],
      encodeHtml: false,
    );

/// Дерево рецензии. Одиночный перенос строки остаётся `\n` внутри текста:
/// на телефоне люди жмут Enter, чтобы начать строку, а не абзац.
List<md.Node> parseReviewMarkdown(String source) =>
    _document().parse(source.replaceAll('\r\n', '\n'));

/// id термина из ссылки `term:id`, иначе null.
String? termIdOf(String? href) {
  if (href == null || !href.startsWith('term:')) return null;
  final id = href.substring(5).trim();
  return id.isEmpty ? null : id;
}

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol', 'li',
  'pre', 'hr',
};

String _plain(md.Node node, String? mask) {
  if (node is md.Text) return node.text;
  if (node is! md.Element) return node.textContent;
  if (node.tag == 'spoiler' && mask != null) return mask;
  if (node.tag == 'br') return '\n';
  if (node.tag == 'hr') return '';
  final children = node.children ?? const <md.Node>[];
  final hasBlocks =
      children.any((c) => c is md.Element && _blockTags.contains(c.tag));
  return children.map((c) => _plain(c, mask)).join(hasBlocks ? '\n' : '');
}

/// Текст без разметки: блоки через перевод строки, пустые строки выкинуты.
/// [spoilerMask] заменяет содержимое спойлеров (для превью в ленте); null
/// оставляет их как есть (для подсчёта слов).
String reviewPlainText(String source, {String? spoilerMask}) {
  final text = parseReviewMarkdown(source)
      .map((n) => _plain(n, spoilerMask))
      .join('\n');
  return text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}

final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

int reviewWordCount(String source) {
  if (source.trim().isEmpty) return 0;
  return reviewPlainText(source)
      .split(RegExp(r'\s+'))
      .where((w) => _word.hasMatch(w))
      .length;
}

/// Минуты чтения при 180 словах в минуту, не меньше одной.
int reviewReadMinutes(String source) {
  final m = (reviewWordCount(source) / 180).ceil();
  return m < 1 ? 1 : m;
}

// ------------------------------ панель разметки ------------------------------

/// Кнопки панели над клавиатурой.
enum ReviewFormat { bold, italic, spoiler, heading, quote, list }

/// Применяет разметку к полю. Строчные (жирный, курсив, спойлер) оборачивают
/// выделение, а без него ставят пару знаков и курсор между ними. Строковые
/// (заголовок, цитата, список) ставят или снимают префикс у каждой строки
/// выделения.
TextEditingValue applyReviewFormat(TextEditingValue value, ReviewFormat f) {
  return switch (f) {
    ReviewFormat.bold => _wrap(value, '**'),
    ReviewFormat.italic => _wrap(value, '_'),
    ReviewFormat.spoiler => _wrap(value, '||'),
    ReviewFormat.heading => _prefixLines(value, '## '),
    ReviewFormat.quote => _prefixLines(value, '> '),
    ReviewFormat.list => _prefixLines(value, '- '),
  };
}

/// Вставляет термин словаря: выделенное слово становится ссылкой на термин,
/// без выделения вставляется его название.
TextEditingValue applyReviewTerm(
    TextEditingValue value, String id, String name) {
  final sel = _safeSelection(value);
  final picked = value.text.substring(sel.start, sel.end);
  final label = picked.trim().isEmpty ? name : picked;
  final insert = '[$label](term:$id)';
  final text = value.text.replaceRange(sel.start, sel.end, insert);
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: sel.start + insert.length),
  );
}

TextSelection _safeSelection(TextEditingValue v) {
  final s = v.selection;
  if (!s.isValid) return TextSelection.collapsed(offset: v.text.length);
  return TextSelection(
    baseOffset: s.start.clamp(0, v.text.length),
    extentOffset: s.end.clamp(0, v.text.length),
  );
}

TextEditingValue _wrap(TextEditingValue value, String mark) {
  final sel = _safeSelection(value);
  final inner = value.text.substring(sel.start, sel.end);
  final text =
      value.text.replaceRange(sel.start, sel.end, '$mark$inner$mark');
  final start = sel.start + mark.length;
  return TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: start, extentOffset: start + inner.length),
  );
}

TextEditingValue _prefixLines(TextEditingValue value, String prefix) {
  final sel = _safeSelection(value);
  final text = value.text;
  final from = text.lastIndexOf('\n', sel.start == 0 ? 0 : sel.start - 1);
  final lineStart = sel.start == 0 ? 0 : (from < 0 ? 0 : from + 1);
  var lineEnd = text.indexOf('\n', sel.end);
  if (lineEnd < 0) lineEnd = text.length;
  final lines = text.substring(lineStart, lineEnd).split('\n');
  // Префикс уже стоит у всех строк — снимаем, иначе ставим.
  final remove = lines.every((l) => l.startsWith(prefix));
  final changed = [
    for (final l in lines)
      remove ? l.substring(prefix.length) : '$prefix$l',
  ].join('\n');
  final delta = changed.length - (lineEnd - lineStart);
  final perLine = remove ? -prefix.length : prefix.length;
  final newText = text.replaceRange(lineStart, lineEnd, changed);
  final base = (sel.start + perLine).clamp(lineStart, newText.length);
  final extent = (sel.end + delta).clamp(lineStart, newText.length);
  return TextEditingValue(
    text: newText,
    selection: sel.isCollapsed
        ? TextSelection.collapsed(offset: base)
        : TextSelection(baseOffset: base, extentOffset: extent),
  );
}
