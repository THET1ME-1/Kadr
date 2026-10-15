import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/movie_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../widgets/rating_slider.dart';
import '../../widgets/review/tag_shelves.dart';
import 'mark_sheet.dart';

/// Ответ окна «Где бросили?».
class DropChoice {
  /// Когда бросили; null — «Не помню» (в ленту такая попытка не попадёт).
  final DateTime? date;
  final DropMark drop;
  const DropChoice({this.date, required this.drop});
}

/// Ответ окна «Где остановились?».
class PauseChoice {
  /// Когда остановился; null — «Не помню».
  final DateTime? date;

  /// Минута, на которой остановился; null — не ставили.
  final int? atMin;
  const PauseChoice({this.date, this.atMin});
}

/// Длина линейки минут, когда длительность фильма неизвестна.
const int kDropUnknownRuntime = 240;

/// Окно «Где бросили?» у кнопки «Бросить» (вариант О2 макета KADR-1): минута
/// крупно на линейке, причины полками по темам (вариант Б второго макета),
/// своё слово полем, дата и широкая красная кнопка.
///
/// С [initial] окно правит уже записанную попытку: даты в нём нет, кнопка
/// «Готово». [startMin] ставит минуту заранее, а без [withDate] нет даты:
/// так бросают начатый фильм, у попытки дата уже есть. [runtimeMin] —
/// длина фильма для линейки.
Future<DropChoice?> showDropSheet(
  BuildContext context, {
  required String subject,
  int? runtimeMin,
  DropMark? initial,
  int? startMin,
  bool withDate = true,
  MovieRepository? repo,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<DropChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SafeArea(
      top: false,
      child: _DropSheet(
        subject: subject,
        runtimeMin: runtimeMin,
        initial: initial,
        startMin: startMin,
        withDate: withDate,
        used: (repo ?? MovieRepository.instance).usedDropReasons,
      ),
    ),
  );
}

/// Окно «Где остановились?» у «Досмотрю потом» (вариант П1 макета «Фильм в
/// несколько заходов»): то же окно, что «Где бросили?», только в основном
/// цвете и без причин. [first] — фильм только начат, день подписан
/// «Начал»; у следующего захода «Когда», а минута стоит с прошлого раза
/// ([initialMin]). С [editing] окно правит минуту записанной паузы: даты в
/// нём нет, кнопка «Готово».
Future<PauseChoice?> showPauseSheet(
  BuildContext context, {
  required String subject,
  int? runtimeMin,
  int? initialMin,
  bool first = true,
  bool editing = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<PauseChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SafeArea(
      top: false,
      child: _DropSheet(
        subject: subject,
        runtimeMin: runtimeMin,
        initial: null,
        startMin: initialMin,
        withDate: true,
        used: const [],
        pause: true,
        firstPause: first,
        editPause: editing,
      ),
    ),
  );
}

class _DropSheet extends StatefulWidget {
  final String subject;
  final int? runtimeMin;
  final DropMark? initial;
  final int? startMin;
  final bool withDate;
  final List<String> used;

  /// Окно паузы «Где остановились?»: без причин, в основном цвете.
  final bool pause;
  final bool firstPause;

  /// Правка записанной паузы: без даты, кнопка «Готово».
  final bool editPause;
  const _DropSheet({
    required this.subject,
    required this.runtimeMin,
    required this.initial,
    required this.used,
    this.startMin,
    this.withDate = true,
    this.pause = false,
    this.firstPause = true,
    this.editPause = false,
  });

  @override
  State<_DropSheet> createState() => _DropSheetState();
}

class _DropSheetState extends State<_DropSheet> {
  late int? _min = widget.initial?.atMin ?? widget.startMin;
  double? _dragging;
  late final List<String> _reasons = [...?widget.initial?.reasons];
  final _own = TextEditingController();

  /// Когда бросили. Пока не выбирали — «Только что».
  DateTime? _date = DateTime.now();
  bool _justNow = true;

  bool get _editing => widget.initial != null || widget.editPause;

  /// Цвет окна: красный у «Бросить», основной у паузы.
  Color _accent(ColorScheme scheme) =>
      widget.pause ? scheme.primary : kDroppedColor;

  /// Длина линейки: длительность фильма, без неё четыре часа. Минута из
  /// прошлой правки за краем линейку растягивает.
  int get _max {
    final rt = widget.runtimeMin;
    final base = (rt != null && rt > 0 && rt <= 600) ? rt : kDropUnknownRuntime;
    return (_min ?? 0) > base ? _min! : base;
  }

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  void _toggle(String reason) => setState(() {
        if (!_reasons.remove(reason)) _reasons.add(reason);
      });

  /// Своё слово: совпало с готовой фразой — горит она, а не дубль.
  void _add(String text) {
    final v = matchTag(text, [...shelfLabels(kDropShelves), ...widget.used]);
    if (v == null) return;
    final lower = v.toLowerCase();
    if (_reasons.any((r) => r.toLowerCase() == lower)) return;
    setState(() => _reasons.add(v));
  }

  Future<void> _pickDate() async {
    final choice = await showMarkSheet(
      context,
      title: tr(widget.pause ? 'pause_title' : 'drop_when_q'),
      subject: widget.subject,
    );
    if (choice == null || !mounted) return;
    setState(() {
      _date = choice.date;
      final d = choice.date;
      _justNow = d != null && DateTime.now().difference(d).inMinutes.abs() < 1;
    });
  }

  void _done() {
    HapticFeedback.mediumImpact();
    if (widget.pause) {
      Navigator.of(context).pop(PauseChoice(date: _date, atMin: _min));
      return;
    }
    // Недописанная своя причина тоже уходит: кнопку «+» легко не заметить.
    _add(_own.text);
    Navigator.of(context).pop(DropChoice(
      date: _date,
      drop: DropMark(atMin: _min, reasons: [..._reasons]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr(widget.pause ? 'pause_title' : 'drop_title'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      height: 1.15,
                      color: _accent(scheme))),
            ),
            Text(widget.subject,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant)),
            _minuteCard(scheme),
            if (!widget.pause)
              TagShelves(
                title: tr('drop_why'),
                shelves: kDropShelves,
                selected: _reasons,
                extra: widget.used,
                controller: _own,
                onToggle: _toggle,
                onAdd: _add,
              ),
            if (!_editing && widget.withDate) _whenField(scheme),
            SizedBox(
              height: 56,
              child: _editing
                  ? FilledButton(onPressed: _done, child: Text(tr('done')))
                  : widget.pause
                      ? FilledButton.icon(
                          onPressed: _done,
                          icon: const Icon(Icons.pause_circle_rounded),
                          label: Text(tr('pause_later')),
                        )
                      : FilledButton.icon(
                          onPressed: _done,
                          icon: const Icon(Icons.heart_broken_rounded),
                          label: Text(tr('mark_dropped')),
                          style: FilledButton.styleFrom(
                            backgroundColor: kDroppedColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Минута крупно и линейка, как карточка оценки, только в тон «Брошено»
  /// (у паузы в основном цвете).
  Widget _minuteCard(ColorScheme scheme) {
    final accent = _accent(scheme);
    final shown = _dragging?.round() ?? _min;
    final rt = widget.runtimeMin;
    final knownRt = rt != null && rt > 0 && rt <= 600;
    final dim = scheme.onSurfaceVariant.withValues(alpha: 0.55);
    final foot = shown != null && knownRt
        ? [
            trf('drop_share', {'p': (shown * 100 / rt).round().clamp(0, 100)}),
            // Паузе важно, сколько осталось досмотреть.
            if (widget.pause && shown < rt)
              trf('pause_left', {'n': rt - shown}),
          ].join(' · ')
        : tr('drop_minute_skip');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            accent.withValues(alpha: 0.16), scheme.surfaceContainer),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(tr('drop_stopped_at'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(shown != null ? '$shown' : '—',
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 48,
                              height: 1,
                              color: shown != null ? accent : dim)),
                      const SizedBox(width: 8),
                      Text(
                          knownRt
                              ? trf('drop_of_min', {'m': rt})
                              : tr('drop_min'),
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              color: accent.withValues(alpha: 0.75))),
                    ],
                  ),
                ),
              ),
              if (_min != null)
                IconButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _min = null);
                  },
                  tooltip: tr('rv_remove'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 20, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 6),
          RatingSlider(
            value: (_dragging ?? _min ?? 0).toDouble(),
            rated: _min != null,
            min: 0,
            max: _max.toDouble(),
            step: 1,
            color: accent,
            onColor: widget.pause ? scheme.onPrimary : Colors.white,
            label: (v) => '${v.round()}',
            onChanged: (v) => setState(() => _dragging = v),
            onChangeEnd: (v) => setState(() {
              _dragging = null;
              _min = v.round();
            }),
          ),
          Text(foot,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// «Когда»: по умолчанию «Только что», тап открывает окно отметки.
  Widget _whenField(ColorScheme scheme) {
    final d = _date;
    final value = d == null
        ? tr('when_forgot')
        : (_justNow ? tr('when_now') : dateExactWithTime(d));
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _pickDate,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              spacing: 12,
              children: [
                Icon(Icons.event_rounded, size: 22, color: scheme.primary),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          tr(widget.pause && widget.firstPause
                              ? 'pause_started'
                              : 'view_when'),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 12,
                              color: scheme.onSurfaceVariant)),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: scheme.onSurface)),
                    ],
                  ),
                ),
                Icon(Icons.expand_more_rounded,
                    size: 22, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка паузы одной фразой: «на 52-й мин» или «Минута не указана».
String pauseSummary(PauseMark p) => p.atMin != null
    ? trf('drop_at_short', {'n': p.atMin!})
    : tr('pause_no_min');

/// Строка пометки одной фразой: «на 52-й мин · Затянуто, Тяжело смотреть».
/// Свои причины пишутся как есть, в них бывают имена. Пустая пометка —
/// «Минута и причины не указаны».
String dropSummary(DropMark d) {
  final parts = [
    if (d.atMin != null) trf('drop_at_short', {'n': d.atMin!}),
    if (d.reasons.isNotEmpty) d.reasons.join(', '),
  ];
  return parts.isEmpty ? tr('drop_no_details') : parts.join(' · ');
}
