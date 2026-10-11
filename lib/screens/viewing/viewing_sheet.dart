import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/app_prefs.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/viewing/diary_form.dart';
import '../../widgets/viewing/score_card.dart';
import '../review/review_editor_screen.dart';
import '../review/review_screen.dart';
import 'viewing_delete.dart';
import 'viewing_host.dart';

/// Окно просмотра: оценка, дата, дневник и рецензия одного просмотра фильма
/// или серии. Если просмотров несколько, сверху переключатель.
///
/// [openDiary] открывает окно с раскрытым дневником (значок на постере в
/// ленте). Плашка «Вернуть» после удаления показывается на [messenger], по
/// умолчанию на экране под окном.
Future<void> showViewingSheet(
  BuildContext context,
  ViewingHost host, {
  required String viewId,
  bool openDiary = false,
  ScaffoldMessengerState? messenger,
}) {
  final scheme = Theme.of(context).colorScheme;
  final bar = messenger ?? ScaffoldMessenger.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    // useSafeArea у листа бережёт только верх: низ держим сами, чтобы
    // «Готово» не ушло под системные кнопки.
    builder: (_) => SafeArea(
      top: false,
      child: _ViewingSheet(
        host: host,
        viewId: viewId,
        openDiary: openDiary,
        messenger: bar,
      ),
    ),
  );
}

class _ViewingSheet extends StatefulWidget {
  final ViewingHost host;
  final String viewId;
  final bool openDiary;
  final ScaffoldMessengerState? messenger;
  const _ViewingSheet({
    required this.host,
    required this.viewId,
    required this.openDiary,
    required this.messenger,
  });

  @override
  State<_ViewingSheet> createState() => _ViewingSheetState();
}

class _ViewingSheetState extends State<_ViewingSheet> {
  late String _viewId = widget.viewId;
  late bool _diaryOpen = widget.openDiary;
  final _selectedKey = GlobalKey();

  /// Несохранённый дневник по id просмотра. Пишется в библиотеку при
  /// сворачивании, смене просмотра и закрытии окна, а не на каждую букву:
  /// запись перезаписывает весь файл библиотеки.
  final Map<String, DiaryEntry> _drafts = {};

  ViewingHost get host => widget.host;

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void dispose() {
    // Обычно дневник уже записан при закрытии; это страховка. В микрозадаче,
    // потому что запись будит слушателей, а дерево сейчас разбирается.
    if (_drafts.isNotEmpty) {
      final drafts = Map.of(_drafts);
      scheduleMicrotask(() => _write(drafts));
    }
    super.dispose();
  }

  void _write(Map<String, DiaryEntry> drafts) {
    for (final e in drafts.entries) {
      final v = host.byId(e.key);
      if (v != null) host.setDiary(v, e.value);
    }
  }

  void _flushDiary() {
    if (_drafts.isEmpty) return;
    final drafts = Map.of(_drafts);
    _drafts.clear();
    _write(drafts);
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      final box = ctx?.findRenderObject();
      if (ctx == null || box == null) return;
      // Только лента переключателя: общий ensureVisible сдвинул бы и сам лист.
      Scrollable.of(ctx).position.ensureVisible(box,
          alignment: 0.5, duration: const Duration(milliseconds: 200));
    });
  }

  void _select(Viewing v) {
    if (v.id == _viewId) return;
    HapticFeedback.selectionClick();
    _flushDiary();
    setState(() => _viewId = v.id);
    _revealSelected();
  }

  Future<void> _pickDate(Viewing v) async {
    final now = DateTime.now();
    final initial = v.date ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    await host.setDate(
      v,
      time == null
          ? DateTime(picked.year, picked.month, picked.day)
          : DateTime(
              picked.year, picked.month, picked.day, time.hour, time.minute),
    );
  }

  Future<void> _delete(Viewing v) async {
    final ok = await deleteViewingFlow(context, host, v,
        messenger: widget.messenger);
    if (!ok) return;
    // Черновик дневника удалённого просмотра писать уже некуда. Убираем его
    // только после удаления: на «Отмена» правки остаются.
    _drafts.remove(v.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _openReview(Viewing v) {
    final target = host.reviewTarget(v);
    if (target == null) return;
    _flushDiary();
    final draft = target.meta?.draft ?? false;
    if (target.item.hasReview && !draft) {
      openReview(context, target);
    } else {
      openReviewEditor(context, target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flushDiary();
      },
      child: ListenableBuilder(
        listenable: host.repo,
        builder: (context, _) {
          final list = host.ordered;
          if (list.isEmpty) return const SizedBox(height: 1);
          final v = host.byId(_viewId) ?? list.last;
          if (v.id != _viewId) _viewId = v.id;
          return _body(context, list, v);
        },
      ),
    );
  }

  Widget _body(BuildContext context, List<Viewing> list, Viewing v) {
    final scheme = Theme.of(context).colorScheme;
    final prev = host.previousRated(v);
    final diaryShown =
        AppPrefs.instance.diaryEnabled || (v.diary?.isNotEmpty ?? false);
    final prevText = prev?.score.toStringAsFixed(1);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
              child: Text(
                  tr(host.isEpisode ? 'view_title_episode' : 'edit_viewing'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      height: 1.15,
                      color: scheme.onSurface)),
            ),
            if (list.length > 1) _switcher(scheme, list, v),
            ScoreCard(
              key: ValueKey('score-${v.id}'),
              label: tr('rate_this_viewing'),
              value: v.score,
              onChanged: (s) => host.setScore(v, s),
              footer: prevText == null
                  ? null
                  : trf('view_last_time', {'v': prevText}),
              sameAs: prev?.score,
              sameLabel: prevText == null
                  ? null
                  : trf(
                      prev!.ordinal == 1
                          ? 'view_same_first'
                          : 'view_same_last',
                      {'v': prevText}),
              onClear: () => host.setScore(v, null),
            ),
            _Field(
              icon: Icons.event_rounded,
              label: tr('view_when'),
              value: v.date != null
                  ? dateExactWithTime(v.date!)
                  : tr('view_undated'),
              onTap: () => _pickDate(v),
              trailing: v.date == null
                  ? Icon(Icons.edit_rounded,
                      size: 20, color: scheme.onSurfaceVariant)
                  : IconButton(
                      onPressed: () => host.setDate(v, null),
                      tooltip: tr('clear_date'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close_rounded,
                          size: 20, color: scheme.onSurfaceVariant),
                    ),
            ),
            if (diaryShown) _diary(scheme, v),
            if (!host.isEpisode) _review(scheme, v),
            Row(
              spacing: 10,
              children: [
                IconButton.filledTonal(
                  onPressed: () => _delete(v),
                  tooltip: tr('delete'),
                  style: IconButton.styleFrom(
                    fixedSize: const Size(48, 48),
                    backgroundColor: scheme.errorContainer,
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('done')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Переключатель просмотров: «2-й · 16.05». Год дописывается, когда
  /// просмотры из разных лет.
  Widget _switcher(ColorScheme scheme, List<Viewing> list, Viewing current) {
    final years = {
      for (final v in list)
        if (v.date != null) v.date!.year,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 6,
        children: [
          for (var i = 0; i < list.length; i++)
            _SwitchPill(
              key: list[i].id == current.id ? _selectedKey : null,
              label: '${ordinalShort(i + 1)} · '
                  '${list[i].date == null ? tr('view_undated_short') : dayMonthNumeric(list[i].date!, year: years.length > 1)}',
              selected: list[i].id == current.id,
              onTap: () => _select(list[i]),
            ),
        ],
      ),
    );
  }

  Widget _diary(ColorScheme scheme, Viewing v) {
    final entry = _drafts[v.id] ?? v.diary;
    if (!_diaryOpen) {
      final summary = diarySummary(entry);
      return _Field(
        icon: Icons.edit_note_rounded,
        label: tr('view_diary'),
        value: summary.isEmpty ? tr('view_diary_hint') : summary,
        dim: summary.isEmpty,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _diaryOpen = true);
        },
        trailing: Icon(
            summary.isEmpty ? Icons.add_rounded : Icons.expand_more_rounded,
            size: 20,
            color: scheme.onSurfaceVariant),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              _flushDiary();
              setState(() => _diaryOpen = false);
            },
            borderRadius: BorderRadius.circular(12),
            child: Row(
              spacing: 10,
              children: [
                Icon(Icons.edit_note_rounded, color: scheme.primary),
                Expanded(
                  child: Text(tr('view_diary'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: scheme.onSurface)),
                ),
                Icon(Icons.expand_less_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          DiaryForm(
            key: ValueKey('diary-${v.id}'),
            initial: entry,
            photoKey: host.photoKey(v),
            onChanged: (d) => _drafts[v.id] = d,
          ),
        ],
      ),
    );
  }

  Widget _review(ColorScheme scheme, Viewing v) {
    final target = host.reviewTarget(v);
    final has = target?.item.hasReview ?? false;
    if (!has) {
      return _Field(
        icon: Icons.rate_review_rounded,
        label: tr('view_review'),
        value: tr('view_review_none'),
        dim: true,
        trailing: TextButton(
          onPressed: () => _openReview(v),
          child: Text(tr('rvs_write')),
        ),
      );
    }
    final title = target!.meta?.title?.trim();
    final draft = target.meta?.draft ?? false;
    return _Field(
      icon: Icons.rate_review_rounded,
      label: draft
          ? '${tr('view_review')} · ${tr('rvs_draft')}'
          : tr('view_review'),
      value: title == null || title.isEmpty ? tr('rv_untitled') : title,
      onTap: () => _openReview(v),
      trailing: Icon(Icons.chevron_right_rounded,
          size: 22, color: scheme.onSurfaceVariant),
    );
  }
}

class _SwitchPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SwitchPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(label,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 13,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant)),
          ),
        ),
      ),
    );
  }
}

/// Поле окна: значок, подпись, значение и что-то справа.
class _Field extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  /// Значение приглушено: это подсказка, а не данные.
  final bool dim;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Field({
    required this.icon,
    required this.label,
    required this.value,
    this.dim = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, size: 22, color: scheme.primary),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 12,
                              color: scheme.onSurfaceVariant)),
                      Text(value,
                          maxLines: dim ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight:
                                  dim ? FontWeight.w500 : FontWeight.w600,
                              fontSize: dim ? 13.5 : 15,
                              color: dim
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface)),
                    ],
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: EdgeInsets.only(
                        right: trailing is Icon ? 6 : 0),
                    child: trailing,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
