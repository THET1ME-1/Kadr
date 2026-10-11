import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../widgets/settings_kit.dart';
import '../../widgets/viewing/diary_form.dart';
import '../../widgets/viewing/view_chip.dart';
import 'viewing_delete.dart';
import 'viewing_host.dart';
import 'viewing_sheet.dart';

/// Блок «Просмотры» в карточке фильма и в окне серии: каждый просмотр
/// строкой с номером, датой, пометками дневника и рецензии и оценкой. Тап
/// открывает окно просмотра.
///
/// Свежие сверху, больше трёх строк сворачиваются в «ещё N». Одинаковые
/// просмотры без даты собраны в строку со счётчиком: плюс добавляет ещё
/// один («видел раньше»), и лента за сегодня не получает пять записей.
class ViewingsSection extends StatefulWidget {
  final ViewingHost host;

  /// Где показать «Вернуть» после удаления; по умолчанию экран под блоком.
  final ScaffoldMessengerState? messenger;

  const ViewingsSection({super.key, required this.host, this.messenger});

  /// Сколько строк видно, пока блок не развернули.
  static const int shown = 3;

  @override
  State<ViewingsSection> createState() => _ViewingsSectionState();
}

class _ViewingsSectionState extends State<ViewingsSection> {
  bool _expanded = false;

  ViewingHost get host => widget.host;

  /// Просмотры без даты, дневника и рецензии с одной оценкой: самая большая
  /// такая пачка от двух штук. Остальные идут обычными строками.
  List<Viewing> _undatedGroup(List<Viewing> list) {
    final byScore = <double?, List<Viewing>>{};
    for (final v in list) {
      if (v.date != null ||
          (v.diary?.isNotEmpty ?? false) ||
          host.hasReview(v)) {
        continue;
      }
      byScore.putIfAbsent(v.score, () => []).add(v);
    }
    var best = const <Viewing>[];
    for (final g in byScore.values) {
      if (g.length > best.length) best = g;
    }
    return best.length >= 2 ? best : const [];
  }

  void _open(Viewing v) =>
      showViewingSheet(context, host, viewId: v.id, messenger: widget.messenger);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: host.repo,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = host.ordered;
    if (list.isEmpty) return const SizedBox.shrink();
    final group = _undatedGroup(list);
    final groupIds = {for (final v in group) v.id};

    final rows = <Widget Function(BorderRadius)>[];
    var groupPlaced = false;
    for (var i = list.length - 1; i >= 0; i--) {
      final v = list[i];
      if (groupIds.contains(v.id)) {
        if (!groupPlaced) {
          groupPlaced = true;
          rows.add((r) => _GroupRow(
                radius: r,
                host: host,
                group: group,
                ordinals: [for (final g in group) host.ordinalOf(g)],
                messenger: widget.messenger,
                onOpen: () => _open(group.last),
              ));
        }
        continue;
      }
      rows.add((r) => _ViewRow(
            radius: r,
            host: host,
            viewing: v,
            ordinal: i + 1,
            latest: i == list.length - 1,
            onTap: () => _open(v),
          ));
    }

    final hidden =
        _expanded ? 0 : (rows.length - ViewingsSection.shown).clamp(0, 999);
    final visible = rows.length - hidden;
    final blocks = visible + (hidden > 0 ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 2, 10),
          // Заголовок слева, вывод справа; на узком экране вывод уходит на
          // вторую строку, а не обрезается.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(trf('view_list_title', {'n': list.length}),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: scheme.primary)),
              ?_trend(scheme, list),
            ],
          ),
        ),
        for (var i = 0; i < visible; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : SettingsGroup.gap),
            child: rows[i](groupBlockRadius(i, blocks, outer: 24)),
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: SettingsGroup.gap),
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: groupBlockRadius(blocks - 1, blocks, outer: 24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _expanded = true);
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 6,
                    children: [
                      Text(trf('view_more', {'n': hidden}),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: scheme.primary)),
                      Icon(Icons.expand_more_rounded,
                          size: 18, color: scheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// «-0.8 с первого раза» или «оценка та же»: первый оценённый просмотр
  /// против последнего. null, пока оценённых меньше двух.
  Widget? _trend(ColorScheme scheme, List<Viewing> list) {
    final rated = [
      for (final v in list)
        if (v.score != null) v.score!,
    ];
    if (rated.length < 2) return null;
    final d = ((rated.last - rated.first) * 10).round() / 10;
    final color = deltaColor(d, scheme);
    return _IconText(
      icon: d == 0
          ? Icons.trending_flat_rounded
          : (d > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded),
      iconSize: 20,
      text: d == 0
          ? tr('view_trend_same')
          : trf('view_trend', {'d': signedDelta(d)}),
      style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: color),
    );
  }
}

/// Значок и подпись одним текстом: длинная подпись переносится, а не
/// вылезает за край, как вылезла бы в строке из двух виджетов.
class _IconText extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final String text;
  final TextStyle style;
  const _IconText({
    required this.icon,
    required this.iconSize,
    required this.text,
    required this.style,
  });

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(icon, size: iconSize, color: style.color),
            ),
          ),
          TextSpan(text: text),
        ]),
        style: style,
      );
}

TextStyle _subStyle(Color c, {FontWeight weight = FontWeight.w400}) =>
    TextStyle(
        fontFamily: AppTheme.bodyFont,
        fontWeight: weight,
        fontSize: 12,
        color: c);

/// Строка одного просмотра.
class _ViewRow extends StatelessWidget {
  final BorderRadius radius;
  final ViewingHost host;
  final Viewing viewing;
  final int ordinal;
  final bool latest;
  final VoidCallback onTap;
  const _ViewRow({
    required this.radius,
    required this.host,
    required this.viewing,
    required this.ordinal,
    required this.latest,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = viewing;
    final prev = host.previousRated(v);
    final delta = v.score != null && prev != null
        ? ((v.score! - prev.score) * 10).round() / 10
        : 0.0;
    final diary = diarySummary(v.diary);
    final reviewed = host.hasReview(v);
    final dim = scheme.onSurfaceVariant;
    final sub = <Widget>[
      if (delta != 0)
        Text(signedDelta(delta),
            style: _subStyle(deltaColor(delta, scheme),
                weight: FontWeight.w700)),
      if (diary.isNotEmpty)
        Text(diary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _subStyle(dim)),
      if (reviewed)
        _IconText(
          icon: Icons.rate_review_rounded,
          iconSize: 14,
          text: tr('view_has_review'),
          style: _subStyle(dim),
        ),
    ];
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            spacing: 12,
            children: [
              ViewOrdinal(ordinal, latest: latest),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                        v.date != null
                            ? dateExactWithTime(v.date!)
                            : tr('view_undated'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: scheme.onSurface)),
                    if (sub.isNotEmpty)
                      Wrap(
                        spacing: 5,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (var i = 0; i < sub.length; i++) ...[
                            if (i > 0) Text('·', style: _subStyle(dim)),
                            sub[i],
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              ViewScorePill(v.score),
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка «Без даты» со счётчиком одинаковых просмотров.
class _GroupRow extends StatelessWidget {
  final BorderRadius radius;
  final ViewingHost host;
  final List<Viewing> group;
  final List<int> ordinals;
  final ScaffoldMessengerState? messenger;
  final VoidCallback onOpen;
  const _GroupRow({
    required this.radius,
    required this.host,
    required this.group,
    required this.ordinals,
    required this.messenger,
    required this.onOpen,
  });

  /// «1–4» у номеров подряд, иначе через запятую.
  String get _range {
    final sorted = [...ordinals]..sort();
    final contiguous = sorted.last - sorted.first == sorted.length - 1;
    return contiguous
        ? '${sorted.first}–${sorted.last}'
        : sorted.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = group.first.score;
    Widget step(IconData icon, String tip, VoidCallback onTap) =>
        IconButton.filledTonal(
          onPressed: onTap,
          tooltip: tip,
          iconSize: 20,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            fixedSize: const Size(36, 36),
            minimumSize: const Size(36, 36),
            backgroundColor: scheme.surfaceContainerHighest,
            foregroundColor: scheme.onSurface,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Icon(icon),
        );
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            spacing: 12,
            children: [
              const ViewOrdinal(0, icon: Icons.history_rounded),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(tr('view_undated'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: scheme.onSurface)),
                    Text(
                        [
                          trf('view_numbers', {'range': _range}),
                          if (score != null) score.toStringAsFixed(1),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _subStyle(scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  step(
                    Icons.remove_rounded,
                    tr('view_step_less'),
                    () => deleteViewingFlow(context, host, group.last,
                        messenger: messenger, ask: false),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text('${group.length}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                            color: scheme.onSurface)),
                  ),
                  step(Icons.add_rounded, tr('view_step_more'), () {
                    HapticFeedback.selectionClick();
                    host.addUndated(score);
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
