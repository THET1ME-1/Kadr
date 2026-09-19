import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/review.dart';
import '../../services/social/social_controller.dart';
import '../../services/store.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/score.dart';
import '../../widgets/poster.dart';
import '../../widgets/rating_slider.dart';
import '../../widgets/review/review_parts.dart';
import '../../widgets/review/verdict_badge.dart';
import '../../widgets/settings_kit.dart';
import 'review_screen.dart';
import 'review_target.dart';
import 'review_text_step.dart';

/// Открывает редактор рецензии. [step]: 0 — оценка, 1 — текст, 2 — публикация.
Future<void> openReviewEditor(BuildContext context, ReviewTarget target,
    {int step = 0}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ReviewEditorScreen(target: target, initialStep: step),
  ));
}

/// Ключ Store со списком пунктов, которые человек выбрал для разбора.
const String kReviewCriteriaKey = 'reviewCriteria';

/// Редактор рецензии в три шага: оценка и разбор → текст → публикация.
/// Всё, что введено, сохраняется при выходе: новая рецензия остаётся
/// черновиком, опубликованная обновляется.
class ReviewEditorScreen extends StatefulWidget {
  final ReviewTarget target;
  final int initialStep;
  const ReviewEditorScreen(
      {super.key, required this.target, this.initialStep = 0});

  @override
  State<ReviewEditorScreen> createState() => _ReviewEditorScreenState();
}

class _ReviewEditorScreenState extends State<ReviewEditorScreen> {
  ReviewTarget get t => widget.target;

  late final ReviewMeta _meta = _initialMeta();
  late final TextEditingController _title =
      TextEditingController(text: _meta.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: t.text ?? '');
  late int _step = widget.initialStep.clamp(0, 2);
  late double? _score = t.score;

  /// Была ли рецензия уже опубликована до этого захода.
  late final bool _wasPublished = t.item.hasReview && !_meta.draft;
  /// Правили ли разбор (вердикт, пункты, теги, переключатели).
  bool _metaChanged = false;
  late final String _startTitle = _title.text;
  late final String _startBody = _body.text;
  bool _done = false;
  List<String> _shown = kDefaultCriteria;
  List<String> _people = const [];
  String? _director;

  ReviewMeta _initialMeta() {
    final m = t.meta;
    if (m != null) return m.copy();
    // Рецензии до разбора писались приватными — такими и остаются, пока
    // человек сам не включит «Видят друзья».
    if (t.item.hasReviewText) return ReviewMeta(shared: false);
    return ReviewMeta(draft: true);
  }

  @override
  void initState() {
    super.initState();
    // Запоминаем исходный текст до первой правки.
    _startTitle;
    _startBody;
    _loadCriteria();
    _loadPeople();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Есть что сохранять. Сравниваем текст, а не ловим события поля: поле
  /// шлёт их и при смене курсора, и пустой заход сдвигал бы `updatedAt`,
  /// а синхронизация по нему выбирает свежую версию.
  bool get _dirty =>
      _metaChanged || _title.text != _startTitle || _body.text != _startBody;

  void _change(VoidCallback fn) {
    setState(fn);
    _metaChanged = true;
  }

  Future<void> _loadCriteria() async {
    final saved = await Store.instance.getStringList(kReviewCriteriaKey);
    final valid = [for (final id in saved) if (kCriteria.contains(id)) id];
    if (valid.isNotEmpty && mounted) setState(() => _shown = valid);
  }

  /// Актёры и режиссёр — подсказки для «Сильного» и строка под названием.
  Future<void> _loadPeople() async {
    final id = t.tmdbId;
    if (id == null) return;
    try {
      if (t.isSeries) {
        final x = await TmdbService.tvExtra(id);
        if (!mounted || x == null) return;
        setState(() => _people = [for (final c in x.cast.take(4)) c.name]);
      } else {
        final d = await TmdbService.details(id);
        if (!mounted || d == null) return;
        setState(() {
          _director = d.director;
          _people = [
            for (final c in d.cast.take(4)) c.name,
            ?d.director,
          ];
        });
      }
    } catch (_) {/* без сети — без подсказок */}
  }

  bool get _hasContent =>
      _body.text.trim().isNotEmpty ||
      _title.text.trim().isNotEmpty ||
      !_meta.isEmptyContent;

  ReviewMeta _snapshot() {
    final m = _meta.copy();
    final title = _title.text.trim();
    m.title = title.isEmpty ? null : title;
    return m;
  }

  Future<void> _persist({required bool publish}) async {
    final m = _snapshot();
    if (publish) m.draft = false;
    if (!_hasContent) {
      if (t.item.hasReview) await t.delete();
      return;
    }
    await t.save(_body.text, m);
  }

  /// Уход с экрана без «Опубликовать»: введённое не пропадает.
  void _saveOnLeave() {
    if (_done || !_dirty) return;
    _done = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final draft = !_wasPublished && _hasContent;
    _persist(publish: false);
    if (draft) {
      messenger?.showSnackBar(SnackBar(content: Text(tr('rv_draft_saved'))));
    }
  }

  Future<void> _publish() async {
    if (!_hasContent) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('rv_empty'))));
      return;
    }
    HapticFeedback.mediumImpact();
    _done = true;
    await _persist(publish: true);
    if (!mounted) return;
    final shared = _meta.shared && SocialController.instance.isLoggedIn;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(shared ? 'rv_published' : 'rv_saved'))));
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReviewScreen(target: t)));
  }

  Future<void> _delete() async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(tr('rv_delete_q'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: scheme.onSurface)),
              Text(tr('rv_delete_sub'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 14,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: kDroppedColor,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(tr('rv_delete')),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(tr('cancel')),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    _done = true;
    await t.delete();
    if (mounted) Navigator.of(context).pop();
  }

  void _goto(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step.clamp(0, 2));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _saveOnLeave();
        } else {
          _goto(_step - 1);
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _topBar(context),
              _stepper(context),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: AppTheme.emphasizedDecelerate,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                              begin: const Offset(0.04, 0), end: Offset.zero)
                          .animate(a),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => _rateStep(context),
                      1 => ReviewTextStep(title: _title, body: _body),
                      _ => _publishStep(context),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------- шапка -------------------------------

  Widget _topBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: tr('close'),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(tr('rv_editor_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: scheme.onSurface)),
          ),
          if (t.item.hasReview)
            IconButton(
              onPressed: _delete,
              tooltip: tr('rv_delete'),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          if (_step < 2)
            FilledButton(
              onPressed: () => _goto(_step + 1),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: Text(tr('rv_next')),
            ),
        ],
      ),
    );
  }

  Widget _stepper(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = [tr('rv_step_rate'), tr('rv_step_text'), tr('rv_step_publish')];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        spacing: 4,
        children: [
          for (var i = 0; i < names.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == _step,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _goto(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 6,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: AppTheme.emphasized,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i <= _step
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Text(names[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12,
                                fontWeight: i == _step
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: i == _step
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --------------------------- шаг 1: оценка ---------------------------

  Widget _rateStep(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottom),
      children: [
        _mediaRow(context),
        const SizedBox(height: 26),
        _overall(context),
        const SizedBox(height: 26),
        _criteria(context),
        const SizedBox(height: 26),
        _verdicts(context),
        const SizedBox(height: 26),
        _tags(context, positive: true),
        const SizedBox(height: 22),
        _tags(context, positive: false),
        const SizedBox(height: 28),
        FilledButton.tonalIcon(
          onPressed: () => _goto(1),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(tr('rv_to_text')),
        ),
      ],
    );
  }

  Widget _mediaRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (t.year != null) '${t.year}',
      ?_director,
      tr(t.isSeries ? 'rv_kind_series' : 'rv_kind_movie'),
    ].join(' · ');
    return Row(
      spacing: 12,
      children: [
        Poster(title: t.title, url: t.poster, width: 44, radius: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: scheme.onSurface)),
              Text(meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _overall(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sc = _score;
    final avg = _meta.average;
    final canSet = t.canRate && !t.scoreLocked;
    final suggest = canSet && avg != null && (sc == null || (avg - sc).abs() >= 0.05);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        ReviewCaps(tr('rv_overall')),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 220),
              tween: ColorTween(
                  end: sc != null ? scoreColor(sc) : scheme.onSurfaceVariant),
              builder: (context, c, _) => Text(
                  sc != null ? sc.toStringAsFixed(1) : '—',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 48,
                      height: 1,
                      color: c)),
            ),
            Text(' / 10',
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
        if (!t.canRate)
          Text(tr('rate_after_watch'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  color: scheme.onSurfaceVariant))
        else if (t.scoreLocked)
          Text(tr('avg_of_episodes'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  color: scheme.onSurfaceVariant))
        else
          RatingSlider(
            value: sc ?? 1.0,
            onChanged: (v) => setState(() => _score = v),
            onChangeEnd: (v) => t.setScore(v),
          ),
        if (suggest)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: tr('rv_avg_is')),
                      TextSpan(
                          text: ' ${avg.toStringAsFixed(1)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: scoreColor(avg))),
                    ]),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13.5,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _score = avg);
                    t.setScore(avg);
                  },
                  child: Text(trf('rv_set_avg', {'v': avg.toStringAsFixed(1)})),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _criteria(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ids = orderedCriteria({..._shown, ..._meta.criteria.keys});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          children: [
            Expanded(child: ReviewCaps(tr('rv_criteria'))),
            TextButton.icon(
              onPressed: _pickCriteria,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(tr('rv_customize')),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            children: [
              for (final id in ids)
                _CriterionRow(
                  label: critLabel(id),
                  value: _meta.criteria[id],
                  onChanged: (v) => _change(() => _meta.criteria[id] = v),
                  onClear: () => _change(() => _meta.criteria.remove(id)),
                ),
            ],
          ),
        ),
        Text(tr('rv_criteria_hint'),
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color: scheme.onSurfaceVariant)),
      ],
    );
  }

  Future<void> _pickCriteria() async {
    final picked = {..._shown};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final scheme = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  Text(tr('rv_customize_title'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: scheme.onSurface)),
                  Text(tr('rv_customize_sub'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in kCriteria)
                        FilterChip(
                          label: Text(critLabel(id)),
                          selected: picked.contains(id),
                          onSelected: (on) {
                            if (!on && picked.length == 1) return;
                            setSheet(() => on ? picked.add(id) : picked.remove(id));
                          },
                        ),
                    ],
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(tr('done')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    final list = [for (final id in kCriteria) if (picked.contains(id)) id];
    if (!mounted) return;
    setState(() => _shown = list);
    await Store.instance.setStringList(kReviewCriteriaKey, list);
  }

  Widget _verdicts(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sc = _score;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 12,
          children: [
            ReviewCaps(tr('rv_verdict')),
            if (sc != null)
              Expanded(
                child: Text(
                    trf('rv_verdict_hint',
                        {'v': verdictLabel(suggestVerdict(sc))}),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12,
                        color: scheme.onSurfaceVariant)),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in Verdict.values)
              _VerdictChip(
                verdict: v,
                selected: _meta.verdict == v,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _change(() => _meta.verdict = _meta.verdict == v ? null : v);
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _tags(BuildContext context, {required bool positive}) {
    final scheme = Theme.of(context).colorScheme;
    final bad = verdictTone(Verdict.miss, scheme);
    final list = positive ? _meta.pros : _meta.cons;
    final bg = positive ? scheme.primaryContainer : bad.container;
    final fg = positive ? scheme.onPrimaryContainer : bad.onContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        ReviewCaps(tr(positive ? 'rv_pros' : 'rv_cons')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in list)
              InputChip(
                label: Text(s),
                labelStyle: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w500,
                    color: fg),
                backgroundColor: bg,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                deleteIconColor: fg,
                onDeleted: () => _change(() => list.remove(s)),
                deleteButtonTooltipMessage: tr('rv_remove'),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ActionChip(
              avatar: Icon(Icons.add_rounded, color: scheme.primary),
              label: Text(tr('rv_add')),
              shape: StadiumBorder(
                  side: BorderSide(color: scheme.outlineVariant)),
              onPressed: () => _addTags(positive),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addTags(bool positive) async {
    final list = positive ? _meta.pros : _meta.cons;
    final ctl = TextEditingController();
    final presets = [
      for (final k in positive ? _kProsPresets : _kConsPresets) tr(k),
      if (positive) ..._people,
    ];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final scheme = Theme.of(ctx).colorScheme;
        void add(String s) {
          final v = s.trim();
          if (v.isEmpty || list.contains(v)) return;
          HapticFeedback.selectionClick();
          setSheet(() => list.add(v));
          _change(() {});
        }

        final left = [for (final p in presets) if (!list.contains(p)) p];
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Text(tr(positive ? 'rv_add_pro' : 'rv_add_con'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: scheme.onSurface)),
                TextField(
                  controller: ctl,
                  autofocus: true,
                  maxLength: 48,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) {
                    add(v);
                    ctl.clear();
                  },
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
                      onPressed: () {
                        add(ctl.text);
                        ctl.clear();
                      },
                    ),
                  ),
                ),
                if (left.isNotEmpty) ...[
                  ReviewCaps(tr('rv_suggestions')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in left)
                        ActionChip(label: Text(p), onPressed: () => add(p)),
                    ],
                  ),
                ],
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(tr('done')),
                ),
              ],
            ),
          ),
        );
      }),
    );
    ctl.dispose();
  }

  // ------------------------- шаг 3: публикация -------------------------

  Widget _publishStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loggedIn = SocialController.instance.isLoggedIn;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final willShare = _meta.shared && loggedIn;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottom),
      children: [
        ReviewCaps(tr(willShare ? 'rv_preview_friends' : 'rv_preview_me')),
        const SizedBox(height: 12),
        if (_hasContent)
          ReviewPreviewCard(
            text: _body.text,
            meta: _snapshot(),
            showFooter: false,
          )
        else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Text(tr('rv_empty'),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    color: scheme.onSurfaceVariant)),
          ),
        if (_hasContent)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReviewScreen(
                    target: t,
                    previewText: _body.text,
                    previewMeta: _snapshot(),
                    previewScore: _score),
              )),
              icon: const Icon(Icons.open_in_full_rounded, size: 18),
              label: Text(tr('rv_preview_full')),
            ),
          ),
        const SizedBox(height: 16),
        SettingsGroup([
          SettingsSwitchRow(
            icon: Icons.group_rounded,
            title: tr('rv_share'),
            subtitle: tr(loggedIn ? 'rv_share_sub' : 'rv_share_login'),
            value: _meta.shared,
            onChanged: (v) => _change(() => _meta.shared = v),
          ),
          SettingsSwitchRow(
            icon: Icons.visibility_off_rounded,
            title: tr('rv_spoilers'),
            subtitle: tr('rv_spoilers_sub'),
            value: _meta.spoilers,
            onChanged: (v) => _change(() => _meta.spoilers = v),
          ),
        ]),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _publish,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          icon: Icon(willShare ? Icons.send_rounded : Icons.check_rounded),
          label: Text(tr(willShare ? 'rv_publish' : 'rv_save')),
        ),
        if (!_wasPublished) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('rv_keep_draft')),
          ),
        ],
      ],
    );
  }
}

const _kProsPresets = [
  'tag_twist',
  'tag_atmosphere',
  'tag_acting',
  'tag_visuals',
  'tag_music',
  'tag_dialogues',
  'tag_tension',
  'tag_characters',
  'tag_humor',
  'tag_idea',
];

const _kConsPresets = [
  'tag_slow',
  'tag_predictable',
  'tag_plotholes',
  'tag_weak_ending',
  'tag_overacting',
  'tag_cgi',
  'tag_flat_characters',
  'tag_cliches',
  'tag_boring',
];

/// Строка пункта: подпись, тонкий слайдер цвета оценки, число. Пока пункт
/// не оценён, стоит прочерк, а первое касание ставит значение. Нажатие на
/// число сбрасывает пункт.
class _CriterionRow extends StatelessWidget {
  final String label;
  final double? value;
  final ValueChanged<double> onChanged;
  final VoidCallback onClear;

  const _CriterionRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = value;
    final c = v != null ? scoreColor(v) : scheme.outline;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 14,
                    height: 1.2,
                    color: scheme.onSurface)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor: c,
                inactiveTrackColor: scheme.surfaceContainerHighest,
                thumbColor: v != null ? c : scheme.surfaceContainerHighest,
                overlayColor: c.withValues(alpha: 0.14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                trackShape: const RoundedRectSliderTrackShape(),
                tickMarkShape: SliderTickMarkShape.noTickMark,
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Semantics(
                label: label,
                child: Slider(
                  value: v ?? 1.0,
                  min: 1,
                  max: 10,
                  divisions: 90,
                  onChanged: (x) {
                    final r = clampScore(x);
                    if (r != v) HapticFeedback.selectionClick();
                    onChanged(r);
                  },
                ),
              ),
            ),
          ),
          Tooltip(
            message: tr('rv_clear'),
            child: InkWell(
              onTap: v == null ? null : onClear,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text(v != null ? v.toStringAsFixed(1) : '—',
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: v != null ? c : scheme.onSurfaceVariant)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Выбор вердикта: у выбранного тональная заливка и «печенье» со значком.
class _VerdictChip extends StatelessWidget {
  final Verdict verdict;
  final bool selected;
  final VoidCallback onTap;
  const _VerdictChip(
      {required this.verdict, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = verdictTone(verdict, scheme);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? tone.container : scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.fromLTRB(selected ? 5 : 12, 5, 16, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                if (selected)
                  CookieIcon(
                      icon: verdictIcon(verdict),
                      size: 30,
                      color: tone.color,
                      iconColor: tone.onColor)
                else
                  SizedBox(
                    height: 30,
                    child: Icon(verdictIcon(verdict),
                        size: 18, color: scheme.onSurfaceVariant),
                  ),
                Flexible(
                  child: Text(verdictLabel(verdict),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14,
                          color:
                              selected ? tone.onContainer : scheme.onSurface)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
