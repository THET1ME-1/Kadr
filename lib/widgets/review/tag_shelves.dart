import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../utils/score.dart';
import 'review_parts.dart';

/// Полка подсказок: тема со значком и готовые фразы (ключи `tag_*`).
class TagShelf {
  final IconData icon;
  final String labelKey;
  final List<String> tagKeys;
  const TagShelf(this.icon, this.labelKey, this.tagKeys);
}

/// Почему бросили фильм. «Слабого финала» нет: финал брошенного не видели.
const List<TagShelf> kDropShelves = [
  TagShelf(Icons.auto_stories_rounded, 'shelf_story', [
    'tag_slow', 'tag_predictable', 'tag_dumb_plot', 'tag_confusing',
    'tag_plotholes', 'tag_cliches', //
  ]),
  TagShelf(Icons.theater_comedy_rounded, 'shelf_cast',
      ['tag_overacting', 'tag_flat_characters']),
  TagShelf(Icons.mood_bad_rounded, 'shelf_feel', [
    'tag_boring', 'tag_hard_to_watch', 'tag_not_funny', 'tag_not_my_genre', //
  ]),
  TagShelf(Icons.graphic_eq_rounded, 'shelf_look', ['tag_cgi', 'tag_bad_dub']),
];

/// «Слабое» в рецензии.
const List<TagShelf> kConsShelves = [
  TagShelf(Icons.auto_stories_rounded, 'shelf_story', [
    'tag_slow', 'tag_predictable', 'tag_dumb_plot', 'tag_confusing',
    'tag_plotholes', 'tag_weak_ending', 'tag_cliches', //
  ]),
  TagShelf(Icons.theater_comedy_rounded, 'shelf_cast',
      ['tag_overacting', 'tag_flat_characters']),
  TagShelf(Icons.mood_bad_rounded, 'shelf_feel',
      ['tag_boring', 'tag_hard_to_watch', 'tag_not_funny']),
  TagShelf(Icons.graphic_eq_rounded, 'shelf_look', ['tag_cgi', 'tag_bad_dub']),
];

/// «Сильное» в рецензии.
const List<TagShelf> kProsShelves = [
  TagShelf(Icons.auto_stories_rounded, 'shelf_story',
      ['tag_idea', 'tag_twist', 'tag_tension', 'tag_dialogues']),
  TagShelf(Icons.theater_comedy_rounded, 'shelf_cast',
      ['tag_acting', 'tag_characters']),
  TagShelf(Icons.mood_rounded, 'shelf_feel', ['tag_atmosphere', 'tag_humor']),
  TagShelf(Icons.graphic_eq_rounded, 'shelf_look', ['tag_visuals', 'tag_music']),
];

/// Тон выбранного чипа: «Слабое» и причины брошенного мягко-красные,
/// «Сильное» в цвете темы.
enum TagTone { bad, good }

/// Готовые фразы полок на языке интерфейса.
List<String> shelfLabels(List<TagShelf> shelves) => [
      for (final s in shelves)
        for (final k in s.tagKeys) tr(k),
    ];

/// Своё слово, сверенное с [known]: совпало без учёта регистра — та фраза,
/// иначе само слово без пробелов по краям; пустое — null.
String? matchTag(String text, Iterable<String> known) {
  final v = text.trim();
  if (v.isEmpty) return null;
  final lower = v.toLowerCase();
  for (final k in known) {
    if (k.toLowerCase() == lower) return k;
  }
  return v;
}

/// Подсказки по темам (вариант Б макета «Причины брошенного», KADR-1): каждая
/// тема — полка, которая листается вбок, выбранное горит на месте. Своё слово
/// пишется полем ниже и встаёт на полку «Свои» уже выбранным; совпало с
/// готовой фразой — горит она, а не дубль.
///
/// [extra] — свои фразы из прошлых записей, на «Своих» стоят невыбранными.
/// [people] — полка «Люди» (актёры и режиссёр) для «Сильного».
class TagShelves extends StatefulWidget {
  final String title;
  final List<TagShelf> shelves;
  final List<String> selected;
  final List<String> extra;
  final List<String> people;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onAdd;
  final TagTone tone;

  /// Поле своего слова; без него окно не узнает недописанное.
  final TextEditingController? controller;

  const TagShelves({
    super.key,
    required this.title,
    required this.shelves,
    required this.selected,
    required this.onToggle,
    required this.onAdd,
    this.extra = const [],
    this.people = const [],
    this.tone = TagTone.bad,
    this.controller,
  });

  @override
  State<TagShelves> createState() => _TagShelvesState();
}

class _TagShelvesState extends State<TagShelves> {
  TextEditingController? _own;
  TextEditingController get _field =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  /// Всё, что уже стоит на полках: готовые фразы и люди.
  List<String> get _known => [...shelfLabels(widget.shelves), ...widget.people];

  void _submit() {
    final v = matchTag(_field.text, [..._known, ...widget.extra]);
    _field.clear();
    if (v == null) return;
    final lower = v.toLowerCase();
    if (widget.selected.any((s) => s.toLowerCase() == lower)) return;
    HapticFeedback.selectionClick();
    if ([..._known, ...widget.extra].contains(v)) {
      widget.onToggle(v);
    } else {
      widget.onAdd(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final known = {for (final k in _known) k.toLowerCase()};
    final picked = {for (final s in widget.selected) s.toLowerCase()};
    // «Свои»: выбранное, которого нет на полках, потом прошлые свои фразы.
    final own = <String>[
      for (final s in widget.selected)
        if (!known.contains(s.toLowerCase())) s,
      for (final s in widget.extra)
        if (!known.contains(s.toLowerCase()) &&
            !picked.contains(s.toLowerCase()))
          s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        ReviewCaps(widget.title),
        for (final s in widget.shelves)
          _shelf(scheme, s.icon, tr(s.labelKey), [for (final k in s.tagKeys) tr(k)]),
        if (widget.people.isNotEmpty)
          _shelf(scheme, Icons.person_rounded, tr('shelf_people'), widget.people),
        if (own.isNotEmpty)
          _shelf(scheme, Icons.history_rounded, tr('shelf_own'), own),
        TextField(
          controller: _field,
          maxLength: 48,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          style: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 14),
          decoration: InputDecoration(
            hintText: tr('rv_add_hint'),
            counterText: '',
            filled: true,
            fillColor: scheme.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              tooltip: tr('rv_add'),
              icon: const Icon(Icons.add_rounded),
              onPressed: _submit,
            ),
          ),
        ),
      ],
    );
  }

  /// Одна тема: подпись со значком и чипы, листается вбок. Край гаснет,
  /// чтобы было видно, что полка продолжается.
  Widget _shelf(
      ColorScheme scheme, IconData icon, String label, List<String> tags) {
    final picked = {for (final s in widget.selected) s.toLowerCase()};
    final (bg, fg) = switch (widget.tone) {
      TagTone.bad => (
          Color.alphaBlend(
              kDroppedColor.withValues(alpha: 0.24), scheme.surfaceContainer),
          kDroppedColor,
        ),
      TagTone.good => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    return SizedBox(
      height: 40,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.9, 1],
        ).createShader(r),
        // Чип кладёт под себя Material цвета canvas (это surface), и в листе
        // невыбранный выглядел тёмной дырой. Прозрачный canvas оставляет контур.
        child: Theme(
          data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
          child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 28),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Icon(icon, size: 18, color: scheme.primary),
                    Text(label,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            for (final t in tags) ...[
              const SizedBox(width: 8),
              Center(
                child: FilterChip(
                  label: Text(t),
                  selected: picked.contains(t.toLowerCase()),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    widget.onToggle(t);
                  },
                  showCheckmark: true,
                  checkmarkColor: fg,
                  // Невыбранный — только контур, как на макете.
                  color: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected)
                          ? bg
                          : Colors.transparent),
                  side: picked.contains(t.toLowerCase())
                      ? BorderSide.none
                      : BorderSide(color: scheme.outlineVariant),
                  labelStyle: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: picked.contains(t.toLowerCase())
                        ? fg
                        : scheme.onSurface,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}
