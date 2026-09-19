import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../data/critic_glossary.dart';
import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../utils/review_markdown.dart';

/// Рецензия в Markdown как журнальная страница: первый абзац крупнее (лид),
/// цитата выносом, спойлеры спрятаны до нажатия, термины из словаря критика
/// подчёркнуты пунктиром и открывают определение.
class MarkdownView extends StatelessWidget {
  final String data;

  /// Первый абзац крупнее остальных.
  final bool lead;

  const MarkdownView({super.key, required this.data, this.lead = true});

  @override
  Widget build(BuildContext context) {
    final nodes = parseReviewMarkdown(data);
    final blocks = <Widget>[];
    var first = true;
    for (final n in nodes) {
      final w = _block(context, n, isLead: lead && first);
      if (w == null) continue;
      blocks.add(w);
      first = false;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: blocks,
    );
  }

  Widget? _block(BuildContext context, md.Node node, {bool isLead = false}) {
    final scheme = Theme.of(context).colorScheme;
    final st = ReviewTextStyles.of(context);
    if (node is md.Text) {
      final t = node.text.trim();
      return t.isEmpty ? null : ReviewInline(nodes: [node], style: st.body);
    }
    if (node is! md.Element) return null;
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'p':
        final meaningful = children
            .where((c) => !(c is md.Text && c.text.trim().isEmpty))
            .toList();
        if (meaningful.length == 1 &&
            meaningful.first is md.Element &&
            (meaningful.first as md.Element).tag == 'spoiler') {
          return SpoilerBlock(
              nodes: (meaningful.first as md.Element).children ?? const []);
        }
        return ReviewInline(
            nodes: children, style: isLead ? st.lead : st.body);
      case 'h1':
        return ReviewInline(nodes: children, style: st.h1);
      case 'h2':
        return ReviewInline(nodes: children, style: st.h2);
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return ReviewInline(nodes: children, style: st.h3);
      case 'blockquote':
        return _quote(context, children);
      case 'ul':
      case 'ol':
        return _list(context, node);
      case 'hr':
        return Divider(height: 8, thickness: 1, color: scheme.outlineVariant);
      case 'pre':
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(node.textContent.trimRight(),
              style: st.body.copyWith(fontFamily: 'monospace', fontSize: 14)),
        );
      default:
        return ReviewInline(nodes: children, style: st.body);
    }
  }

  /// Цитата выносом: крупная кавычка и текст заголовочным шрифтом.
  Widget _quote(BuildContext context, List<md.Node> children) {
    final scheme = Theme.of(context).colorScheme;
    final st = ReviewTextStyles.of(context);
    final parts = <Widget>[];
    for (final c in children) {
      if (c is md.Element && c.tag == 'p') {
        parts.add(ReviewInline(nodes: c.children ?? const [], style: st.quote));
      } else if (c is md.Element) {
        final w = _block(context, c);
        if (w != null) parts.add(w);
      }
    }
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 34,
            child: Text('“',
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 60,
                    height: 1,
                    color: scheme.primary)),
          ),
          ...parts,
        ],
      ),
    );
  }

  Widget _list(BuildContext context, md.Element list) {
    final st = ReviewTextStyles.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ordered = list.tag == 'ol';
    final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    final items = (list.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((e) => e.tag == 'li')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (var i = 0; i < items.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: Text(ordered ? '${start + i}.' : '•',
                    style: st.body.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.w700)),
              ),
              Expanded(child: _listItem(context, items[i])),
            ],
          ),
      ],
    );
  }

  Widget _listItem(BuildContext context, md.Element li) {
    final st = ReviewTextStyles.of(context);
    final children = li.children ?? const <md.Node>[];
    final hasBlocks = children.any((c) =>
        c is md.Element && const {'p', 'ul', 'ol', 'blockquote'}.contains(c.tag));
    if (!hasBlocks) return ReviewInline(nodes: children, style: st.body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (final c in children) ?_block(context, c),
      ],
    );
  }
}

/// Кегли рецензии, общие для чтения, превью и редактора.
class ReviewTextStyles {
  final TextStyle lead, body, h1, h2, h3, quote;
  const ReviewTextStyles._(
      this.lead, this.body, this.h1, this.h2, this.h3, this.quote);

  factory ReviewTextStyles.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    TextStyle display(double size, FontWeight w, Color c) => TextStyle(
        fontFamily: AppTheme.displayFont,
        fontWeight: w,
        fontSize: size,
        height: 1.25,
        color: c);
    return ReviewTextStyles._(
      TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 18.5,
          height: 1.5,
          color: scheme.onSurface),
      TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontSize: 16,
          height: 1.62,
          color: scheme.onSurface.withValues(alpha: 0.88)),
      display(22, FontWeight.w800, scheme.onSurface),
      display(19, FontWeight.w800, scheme.onSurface),
      display(16, FontWeight.w700, scheme.onSurface),
      display(19, FontWeight.w600, scheme.onPrimaryContainer)
          .copyWith(height: 1.38),
    );
  }
}

/// Строка текста рецензии: жирный, курсив, зачёркнутый, код, ссылки,
/// термины и спойлеры внутри абзаца.
class ReviewInline extends StatefulWidget {
  final List<md.Node> nodes;
  final TextStyle style;
  const ReviewInline({super.key, required this.nodes, required this.style});

  @override
  State<ReviewInline> createState() => _ReviewInlineState();
}

class _ReviewInlineState extends State<ReviewInline> {
  final Set<int> _revealed = {};
  final List<GestureRecognizer> _recognizers = [];
  int _spoilerIndex = 0;

  void _dropRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _dropRecognizers();
    super.dispose();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  /// Нажатие ловит только кусок с самим текстом, а не родитель с детьми,
  /// поэтому обработчик раздаём каждому листу.
  TextSpan _tappable(List<InlineSpan> children, GestureRecognizer r) {
    InlineSpan give(InlineSpan s) {
      if (s is! TextSpan) return s;
      return TextSpan(
        text: s.text,
        style: s.style,
        semanticsLabel: s.semanticsLabel,
        recognizer: s.recognizer ?? (s.text != null ? r : null),
        children: s.children?.map(give).toList(),
      );
    }

    return TextSpan(children: children.map(give).toList());
  }

  @override
  Widget build(BuildContext context) {
    _dropRecognizers();
    _spoilerIndex = 0;
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [for (final n in widget.nodes) _span(context, scheme, n, null)],
      ),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }

  InlineSpan _span(BuildContext context, ColorScheme scheme, md.Node node,
      TextStyle? style) {
    if (node is md.Text) return TextSpan(text: node.text, style: style);
    if (node is! md.Element) {
      return TextSpan(text: node.textContent, style: style);
    }
    final base = style ?? const TextStyle();
    List<InlineSpan> kids(TextStyle s) => [
          for (final c in node.children ?? const <md.Node>[])
            _span(context, scheme, c, s),
        ];
    switch (node.tag) {
      case 'strong':
        return TextSpan(
            children: kids(base.copyWith(fontWeight: FontWeight.w700)));
      case 'em':
        return TextSpan(
            children: kids(base.copyWith(fontStyle: FontStyle.italic)));
      case 'del':
        return TextSpan(
            children:
                kids(base.copyWith(decoration: TextDecoration.lineThrough)));
      case 'code':
        return TextSpan(
          text: node.textContent,
          style: base.copyWith(
              fontFamily: 'monospace',
              backgroundColor: scheme.surfaceContainerHighest),
        );
      case 'br':
        return const TextSpan(text: '\n');
      case 'img':
        return TextSpan(text: node.attributes['alt'] ?? '', style: style);
      case 'a':
        return _link(context, scheme, node, base, kids);
      case 'spoiler':
        return _spoiler(scheme, node, base, kids);
      default:
        return TextSpan(children: kids(base));
    }
  }

  InlineSpan _link(BuildContext context, ColorScheme scheme, md.Element node,
      TextStyle base, List<InlineSpan> Function(TextStyle) kids) {
    final href = node.attributes['href'];
    final term = criticTerm(termIdOf(href));
    if (term != null) {
      return _tappable(
        kids(base.copyWith(
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: scheme.primary,
          decorationThickness: 2,
        )),
        _tap(() => showCriticTermSheet(context, term)),
      );
    }
    final uri = Uri.tryParse(href ?? '');
    final web = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    if (!web) return TextSpan(children: kids(base));
    return _tappable(
      kids(base.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary,
      )),
      _tap(() => launchUrl(uri, mode: LaunchMode.externalApplication)),
    );
  }

  InlineSpan _spoiler(ColorScheme scheme, md.Element node, TextStyle base,
      List<InlineSpan> Function(TextStyle) kids) {
    final i = _spoilerIndex++;
    if (_revealed.contains(i)) {
      return _tappable(
        kids(base.copyWith(backgroundColor: scheme.surfaceContainerHighest)),
        _tap(() => setState(() => _revealed.remove(i))),
      );
    }
    // Спрятанный спойлер — плашка по длине текста: цвет букв совпадает с
    // фоном плашки, поэтому их не видно, а ширина фразы сохраняется.
    // Плашка непрозрачная: полупрозрачные буквы поверх полупрозрачного фона
    // просвечивают, и спойлер читается.
    final mask = Color.alphaBlend(
        scheme.onSurfaceVariant.withValues(alpha: 0.45), scheme.surface);
    return TextSpan(
      text: node.textContent,
      recognizer: _tap(() => setState(() => _revealed.add(i))),
      semanticsLabel: tr('rv_spoiler_hidden'),
      style: base.copyWith(
        color: mask,
        backgroundColor: mask,
        decoration: TextDecoration.none,
      ),
    );
  }
}

/// Абзац-спойлер целиком: полосатая плашка, текст размыт до нажатия.
class SpoilerBlock extends StatefulWidget {
  final List<md.Node> nodes;
  const SpoilerBlock({super.key, required this.nodes});

  @override
  State<SpoilerBlock> createState() => _SpoilerBlockState();
}

class _SpoilerBlockState extends State<SpoilerBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final st = ReviewTextStyles.of(context);
    final warn = scheme.error;
    Widget text = ReviewInline(nodes: widget.nodes, style: st.body);
    if (!_open) {
      text = ExcludeSemantics(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: text,
        ),
      );
    }
    return Semantics(
      button: true,
      label: _open ? null : tr('rv_spoiler_hidden'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          child: CustomPaint(
            painter: _StripesPainter(
                scheme.surfaceContainer, scheme.surfaceContainerLow),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      Icon(
                          _open
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 18,
                          color: warn),
                      Text(tr('rv_spoiler').toUpperCase(),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 1.1,
                              color: warn)),
                    ],
                  ),
                  text,
                  if (!_open)
                    Text(tr('rv_tap_to_reveal'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: scheme.primary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Диагональные полосы — фон спойлера, чтобы его было видно издалека.
class _StripesPainter extends CustomPainter {
  final Color a, b;
  const _StripesPainter(this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final p = Paint()
      ..color = b
      ..strokeWidth = 10;
    for (var x = -size.height; x < size.width; x += 20) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => old.a != a || old.b != b;
}

/// Определение термина нижней панелью.
Future<void> showCriticTermSheet(BuildContext context, CriticTerm term) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Text(tr('term_group_${term.group.name}').toUpperCase(),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.1,
                    color: scheme.primary)),
            Text(term.localName,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    height: 1.2,
                    color: scheme.onSurface)),
            Text(term.localDef,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 16,
                    height: 1.5,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    ),
  );
}
