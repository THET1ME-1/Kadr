import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/season_pass.dart';
import '../../utils/season_reviews.dart';
import '../../widgets/review/review_parts.dart';
import '../../widgets/review/review_rows.dart';
import '../../widgets/settings_kit.dart';

/// Охват рецензии на сериал: сезоны [from]..[to] на их просмотр [pass];
/// оба сезона null — весь сериал.
typedef ReviewScope = ({int? from, int? to, int pass});

/// Сезоны для листа: из TMDB, без него — по отмеченным сериям.
Future<List<TmdbSeason>> reviewSeasons(LibrarySeries s) async {
  final id = s.tmdbId;
  if (id != null) {
    final list = await TmdbService.seasons(id);
    if (list.isNotEmpty) return list;
  }
  final count = <int, int>{};
  for (final e in s.episodes) {
    final n = e.season;
    if (n != null && n >= 1) count[n] = (count[n] ?? 0) + 1;
  }
  return [
    for (final n in count.keys.toList()..sort())
      TmdbSeason(number: n, name: 'S$n', episodeCount: count[n]!),
  ];
}

/// Лист «О чём рецензия»: один сезон, диапазон подряд или весь сериал. У
/// сезонов, которые смотрели не один раз, ниже выбирается просмотр.
/// Просмотр, на который рецензия уже есть, выбрать нельзя, а сезон занят,
/// когда заняты все его просмотры. [exceptPartId] — своя рецензия на
/// сезоны, её место свободно. [initial] — нынешний охват.
Future<ReviewScope?> showReviewScopeSheet(
  BuildContext context, {
  required LibrarySeries series,
  required List<TmdbSeason> seasons,
  String? exceptPartId,
  ReviewScope? initial,
}) =>
    showModalBottomSheet<ReviewScope>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ScopeSheet(
        series: series,
        seasons: seasons,
        exceptPartId: exceptPartId,
        initial: initial,
      ),
    );

enum _Mode { one, range, whole }

class _ScopeSheet extends StatefulWidget {
  final LibrarySeries series;
  final List<TmdbSeason> seasons;
  final String? exceptPartId;
  final ReviewScope? initial;
  const _ScopeSheet({
    required this.series,
    required this.seasons,
    this.exceptPartId,
    this.initial,
  });

  @override
  State<_ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends State<_ScopeSheet> {
  late _Mode _mode;
  int? _from, _to;

  /// Выбранный просмотр сезонов. null, пока сезоны не выбраны и когда
  /// свободных просмотров у них не осталось.
  int? _pass;

  /// Рецензия на весь сериал уже есть, а эта — не она.
  late final bool _wholeTaken = widget.series.hasReview &&
      !(widget.initial != null && widget.initial!.from == null);
  bool _wholeNote = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null && i.from == null) {
      _mode = _Mode.whole;
    } else if (i != null) {
      _from = i.from;
      _to = i.to;
      _pass = i.pass;
      _mode = i.from == i.to ? _Mode.one : _Mode.range;
    } else {
      _mode = _Mode.one;
    }
  }

  /// Свободен ли просмотр [pass] сезонов [a]..[b] для этой рецензии.
  bool _free(int a, int b, int pass) =>
      canCover(widget.series, a, b, exceptId: widget.exceptPartId, pass: pass);

  /// Просмотры сезонов [a]..[b], на которые рецензии ещё нет.
  List<int> _freePasses(int a, int b) => [
        for (final p in scopePasses(widget.series, a, b))
          if (_free(a, b, p.pass)) p.pass,
      ];

  /// Рецензия, из-за которой сезон [n] выбрать нельзя: заняты все его
  /// просмотры. null, пока свободен хотя бы один.
  SeasonReview? _taken(int n) {
    if (_freePasses(n, n).isNotEmpty) return null;
    final passes = scopePasses(widget.series, n, n);
    return takenBy(widget.series, n,
        exceptId: widget.exceptPartId, pass: passes.last.pass);
  }

  /// После смены сезонов: прежний просмотр, если он свободен, иначе самый
  /// поздний свободный.
  void _repick() {
    final a = _from, b = _to;
    if (a == null || b == null) return;
    final free = _freePasses(a, b);
    if (_pass != null && free.contains(_pass)) return;
    _pass = free.isEmpty ? null : free.last;
  }

  void _setMode(_Mode m) {
    HapticFeedback.selectionClick();
    if (m == _Mode.whole && _wholeTaken) {
      setState(() => _wholeNote = true);
      return;
    }
    setState(() {
      _wholeNote = false;
      _mode = m;
      if (m == _Mode.one && _from != null) _to = _from;
      _repick();
    });
  }

  void _tapSeason(int n) {
    if (_taken(n) != null || _mode == _Mode.whole) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_mode == _Mode.one || _from == null || _from != _to) {
        _from = _to = n;
        _repick();
        return;
      }
      // Второй тап в диапазоне — конец; через занятый сезон не тянем.
      final a = n < _from! ? n : _from!, b = n < _from! ? _from! : n;
      if (_freePasses(a, b).isNotEmpty) {
        _from = a;
        _to = b;
      } else {
        _from = _to = n;
      }
      _repick();
    });
  }

  bool get _ready =>
      _mode == _Mode.whole || (_from != null && _to != null && _pass != null);

  int _episodes(int a, int b) => widget.seasons
      .where((s) => s.number >= a && s.number <= b)
      .fold(0, (sum, s) => sum + s.episodeCount);

  String get _summary {
    if (_mode == _Mode.whole) {
      final all = widget.seasons.fold(0, (sum, s) => sum + s.episodeCount);
      return '${tr('scope_whole')} · ${trn('ss_episodes', all)}';
    }
    final many = scopePasses(widget.series, _from, _to).length > 1;
    return [
      scopeLong(_from, _to),
      if (many) trf('viewing_n', {'n': _pass!}),
      trn('ss_episodes', _episodes(_from!, _to!)),
    ].join(' · ');
  }

  /// «Какой просмотр»: строка на каждый просмотр выбранных сезонов, свежие
  /// сверху. Пусто, если сезоны смотрели один раз.
  List<Widget> _passSection() {
    final a = _from, b = _to;
    if (_mode == _Mode.whole || a == null || b == null) return const [];
    final passes = scopePasses(widget.series, a, b);
    if (passes.length < 2) return const [];
    final rows = passes.reversed.toList();
    return [
      ReviewCaps(tr('rvs_which_pass')),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : SettingsGroup.gap),
              child: _passRow(
                  rows[i], a, b, groupBlockRadius(i, rows.length, outer: 22)),
            ),
        ],
      ),
    ];
  }

  Widget _passRow(ScopePass p, int a, int b, BorderRadius radius) {
    final free = _free(a, b, p.pass);
    SeasonReview? by;
    if (!free) {
      for (var n = a; n <= b && by == null; n++) {
        by = takenBy(widget.series, n,
            exceptId: widget.exceptPartId, pass: p.pass);
      }
    }
    final title = by?.reviewMeta?.title?.trim();
    final sub = [
      if (p.from != null && p.to != null) dateRangeNumeric(p.from!, p.to!),
      if (by != null)
        title == null || title.isEmpty
            ? tr('view_has_review')
            : trf('view_review_named', {'title': title}),
    ].join(' · ');
    return ViewChoiceRow(
      ordinal: p.pass,
      title: trf('viewing_n', {'n': p.pass}),
      sub: sub,
      selected: free && p.pass == _pass,
      taken: !free,
      radius: radius,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _pass = p.pass);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final takenNotes = <String>[];
    final seen = <String>{};
    for (final s in widget.seasons) {
      final p = _taken(s.number);
      if (p == null || !seen.add(p.id)) continue;
      final title = p.reviewMeta?.title?.trim();
      takenNotes.add(trf('rvs_taken_in', {
        'season': scopeShort(p.from, p.to),
        'title': title == null || title.isEmpty ? tr('rv_untitled') : title,
      }));
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Text(tr('rvs_scope_title'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: scheme.onSurface)),
            _segments(scheme),
            if (_wholeNote)
              Text(tr('rvs_whole_taken'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13.5,
                      color: scheme.error)),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _mode == _Mode.whole ? 0.4 : 1,
              child: _grid(scheme),
            ),
            if (takenNotes.isNotEmpty && _mode != _Mode.whole)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 10,
                  children: [
                    Icon(Icons.info_rounded, size: 18, color: scheme.primary),
                    Expanded(
                      child: Text(takenNotes.join('\n'),
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 13,
                              color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            ..._passSection(),
            if (_ready)
              Text(_summary,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: scheme.onSurface))
            else if (_mode == _Mode.range)
              Text(tr('rvs_range_hint'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 14,
                      color: scheme.onSurfaceVariant)),
            FilledButton(
              onPressed: _ready
                  ? () => Navigator.of(context).pop<ReviewScope>(
                      _mode == _Mode.whole
                          ? (from: null, to: null, pass: 1)
                          : (from: _from, to: _to, pass: _pass!))
                  : null,
              child: Text(tr('rv_next')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segments(ColorScheme scheme) {
    Widget seg(_Mode m, String label) {
      final on = _mode == m;
      final off = m == _Mode.whole && _wholeTaken;
      return Expanded(
        child: Material(
          color: on ? scheme.primaryContainer : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _setMode(m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: on
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant
                              .withValues(alpha: off ? 0.5 : 1))),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        spacing: 4,
        children: [
          seg(_Mode.one, tr('rvs_mode_one')),
          seg(_Mode.range, tr('rvs_mode_range')),
          seg(_Mode.whole, tr('scope_whole')),
        ],
      ),
    );
  }

  Widget _grid(ColorScheme scheme) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final w = (box.maxWidth - gap * 3) / 4;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final s in widget.seasons) _tile(scheme, s, w),
        ],
      );
    });
  }

  Widget _tile(ColorScheme scheme, TmdbSeason s, double w) {
    final n = s.number;
    final taken = _taken(n) != null;
    final inRange = _mode != _Mode.whole &&
        _from != null &&
        n >= _from! &&
        n <= _to!;
    final isEnd = inRange && (n == _from || n == _to);
    final Color bg = taken
        ? Colors.transparent
        : isEnd
            ? scheme.primary
            : inRange
                ? scheme.primaryContainer
                : scheme.surfaceContainerHigh;
    final Color fg = isEnd
        ? scheme.onPrimary
        : inRange
            ? scheme.onPrimaryContainer
            : scheme.onSurface;
    return SizedBox(
      width: w,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: taken
              ? BorderSide(color: scheme.outlineVariant, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: taken ? null : () => _tapSeason(n),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              spacing: 3,
              children: [
                Text('S$n',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: taken
                            ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                            : fg)),
                Text(
                    taken
                        ? tr('rvs_taken')
                        : trf('rvs_eps_short', {'n': s.episodeCount}),
                    maxLines: 1,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: taken
                            ? scheme.onSurfaceVariant
                            : fg.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
