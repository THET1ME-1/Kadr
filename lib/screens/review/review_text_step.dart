import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/critic_glossary.dart';
import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../utils/review_markdown.dart';
import '../../widgets/review/markdown_view.dart';

/// Второй шаг редактора: заголовок и текст рецензии в Markdown. Сверху
/// переключатель «Правка / Просмотр», снизу панель разметки над клавиатурой.
class ReviewTextStep extends StatefulWidget {
  final TextEditingController title;
  final TextEditingController body;
  const ReviewTextStep({super.key, required this.title, required this.body});

  @override
  State<ReviewTextStep> createState() => _ReviewTextStepState();
}

class _ReviewTextStepState extends State<ReviewTextStep> {
  final FocusNode _bodyFocus = FocusNode();
  bool _preview = false;

  @override
  void dispose() {
    _bodyFocus.dispose();
    super.dispose();
  }

  void _apply(ReviewFormat f) {
    HapticFeedback.selectionClick();
    widget.body.value = applyReviewFormat(widget.body.value, f);
    _bodyFocus.requestFocus();
  }

  Future<void> _insertTerm() async {
    final term = await showGlossaryPicker(context);
    if (term == null) return;
    widget.body.value =
        applyReviewTerm(widget.body.value, term.id, term.localName);
    _bodyFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(tr('rv_mode_edit'))),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: Text(tr('rv_mode_preview'))),
              ],
              selected: {_preview},
              onSelectionChanged: (s) {
                FocusScope.of(context).unfocus();
                setState(() => _preview = s.first);
              },
            ),
          ),
        ),
        Expanded(child: _preview ? _previewView(context) : _editor(context)),
        if (!_preview) _toolbar(scheme),
      ],
    );
  }

  Widget _editor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final st = ReviewTextStyles.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: widget.title,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _bodyFocus.requestFocus(),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 24,
                height: 1.2,
                color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: tr('rv_title_hint'),
              border: InputBorder.none,
              filled: false,
              isCollapsed: true,
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 14),
          TextField(
            controller: widget.body,
            focusNode: _bodyFocus,
            minLines: 12,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: st.body.copyWith(color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: tr('rv_body_hint'),
              hintMaxLines: 6,
              border: InputBorder.none,
              filled: false,
              isCollapsed: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.title.text.trim();
    final body = widget.body.text.trim();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, 32 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [
          if (title.isNotEmpty)
            Text(title,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    height: 1.15,
                    color: scheme.onSurface)),
          if (body.isNotEmpty)
            MarkdownView(data: body)
          else
            Text(tr('rv_preview_empty'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 15,
                    color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _toolbar(ColorScheme scheme) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) => Expanded(
          child: IconButton(
            onPressed: onTap,
            tooltip: tip,
            icon: Icon(icon),
            color: scheme.onSurfaceVariant,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 48),
          ),
        );
    return Container(
      padding: EdgeInsets.fromLTRB(
          4, 8, 4, 4 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.body,
              builder: (context, v, _) {
                final words = reviewWordCount(v.text);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        '${trn('rv_words', words, {'n': words})} · '
                        '${trf('rv_minutes', {'n': reviewReadMinutes(v.text)})}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 12,
                            color: scheme.onSurfaceVariant)),
                    ),
                  ],
                );
              },
            ),
          ),
          Row(
            children: [
              btn(Icons.format_bold_rounded, tr('rv_fmt_bold'),
                  () => _apply(ReviewFormat.bold)),
              btn(Icons.format_italic_rounded, tr('rv_fmt_italic'),
                  () => _apply(ReviewFormat.italic)),
              btn(Icons.title_rounded, tr('rv_fmt_heading'),
                  () => _apply(ReviewFormat.heading)),
              btn(Icons.format_quote_rounded, tr('rv_fmt_quote'),
                  () => _apply(ReviewFormat.quote)),
              btn(Icons.format_list_bulleted_rounded, tr('rv_fmt_list'),
                  () => _apply(ReviewFormat.list)),
              btn(Icons.visibility_off_rounded, tr('rv_spoiler'),
                  () => _apply(ReviewFormat.spoiler)),
              btn(Icons.menu_book_rounded, tr('rv_fmt_term'), _insertTerm),
              btn(Icons.help_outline_rounded, tr('rv_fmt_help'),
                  () => showMarkdownHelp(context)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Словарь критика: поиск, группы и «Вставить».
Future<CriticTerm?> showGlossaryPicker(BuildContext context) {
  return showModalBottomSheet<CriticTerm>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _GlossarySheet(),
  );
}

class _GlossarySheet extends StatefulWidget {
  const _GlossarySheet();

  @override
  State<_GlossarySheet> createState() => _GlossarySheetState();
}

class _GlossarySheetState extends State<_GlossarySheet> {
  TermGroup? _group;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _q.trim().toLowerCase();
    final terms = kCriticTerms.where((t) {
      if (_group != null && t.group != _group) return false;
      if (q.isEmpty) return true;
      return t.localName.toLowerCase().contains(q) ||
          t.localDef.toLowerCase().contains(q);
    }).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Text(tr('rv_glossary'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: scheme.onSurface)),
                  Text(tr('rv_glossary_sub'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: tr('rv_glossary_search'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final g in [null, ...TermGroup.values])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(g == null
                            ? tr('rv_glossary_all')
                            : tr('term_group_${g.name}')),
                        selected: _group == g,
                        onSelected: (_) => setState(() => _group = g),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                    16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
                itemCount: terms.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, i) {
                  final t = terms[i];
                  final r = BorderRadius.vertical(
                    top: Radius.circular(i == 0 ? 20 : 8),
                    bottom: Radius.circular(i == terms.length - 1 ? 20 : 8),
                  );
                  return Material(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: r,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                      child: Row(
                        spacing: 10,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 4,
                              children: [
                                Text(t.localName,
                                    style: TextStyle(
                                        fontFamily: AppTheme.displayFont,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: scheme.onSurface)),
                                Text(t.localDef,
                                    style: TextStyle(
                                        fontFamily: AppTheme.bodyFont,
                                        fontSize: 13,
                                        height: 1.4,
                                        color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () => Navigator.of(context).pop(t),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            child: Text(tr('rv_insert')),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Шпаргалка по разметке: что писать и как это выглядит.
Future<void> showMarkdownHelp(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final rows = [
    ('**${tr('rv_fmt_bold').toLowerCase()}**', tr('rv_fmt_bold')),
    ('_${tr('rv_fmt_italic').toLowerCase()}_', tr('rv_fmt_italic')),
    ('## ${tr('rv_fmt_heading')}', tr('rv_fmt_heading')),
    ('> ${tr('rv_fmt_quote')}', tr('rv_fmt_quote')),
    ('- ${tr('rv_fmt_list')}', tr('rv_fmt_list')),
    ('||${tr('rv_spoiler').toLowerCase()}||', tr('rv_spoiler')),
    ('~~${tr('rv_fmt_strike').toLowerCase()}~~', tr('rv_fmt_strike')),
    ('---', tr('rv_fmt_rule')),
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text(tr('rv_fmt_help'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: scheme.onSurface)),
            Text(tr('rv_help_sub'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final (code, label) in rows)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Text(code,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: scheme.onSurface)),
                    ),
                    Text(label,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
