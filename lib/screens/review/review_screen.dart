import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../models/review.dart';
import '../../models/social.dart';
import '../../services/movie_repository.dart';
import '../../services/social/social_controller.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/review_markdown.dart';
import '../../widgets/review/markdown_view.dart';
import '../../widgets/review/review_parts.dart';
import '../../widgets/review/verdict_badge.dart';
import '../../widgets/user_avatar.dart';
import 'review_editor_screen.dart';
import 'review_target.dart';

/// Открывает рецензию: свою ([author] = null) или друга.
Future<void> openReview(BuildContext context, ReviewTarget target,
    {SocialUser? author}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ReviewScreen(target: target, author: author),
  ));
}

/// Рецензия как журнальная страница: кадр, подпись, заголовок, автор и
/// оценка, вердикт, текст, сильное и слабое, оценки по пунктам. У чужой —
/// сравнение с моими оценками и ответ своей рецензией.
class ReviewScreen extends StatefulWidget {
  final ReviewTarget target;

  /// Автор-друг. null — рецензия моя.
  final SocialUser? author;

  /// Превью из редактора: несохранённые текст, разбор и оценка.
  final String? previewText;
  final ReviewMeta? previewMeta;
  final double? previewScore;

  /// Моя библиотека для сравнения и ответа; по умолчанию — основная.
  final MovieRepository? myRepo;

  const ReviewScreen({
    super.key,
    required this.target,
    this.author,
    this.previewText,
    this.previewMeta,
    this.previewScore,
    this.myRepo,
  });

  bool get isPreview => previewMeta != null;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  ReviewTarget get t => widget.target;
  /// Чужая рецензия: автор-друг или read-only копия его библиотеки.
  bool get _isFriend => widget.author != null || !t.isMine;
  String get _friendName => widget.author?.displayName ?? tr('rv_friend');
  String? _backdrop;
  bool _spoilersOpen = false;

  @override
  void initState() {
    super.initState();
    _loadBackdrop();
  }

  Future<void> _loadBackdrop() async {
    final id = t.tmdbId;
    if (id == null) return;
    try {
      final url = t.isSeries
          ? (await TmdbService.tvExtra(id))?.backdropUrl
          : (await TmdbService.details(id))?.backdropUrl;
      if (mounted && url != null) setState(() => _backdrop = url);
    } catch (_) {/* без сети — градиент */}
  }

  String? get _text => widget.isPreview ? widget.previewText : t.text;
  ReviewMeta? get _meta => widget.isPreview ? widget.previewMeta : t.meta;
  double? get _score => widget.isPreview ? widget.previewScore : t.score;

  @override
  Widget build(BuildContext context) {
    // Своя рецензия перерисовывается после правки в редакторе.
    return ListenableBuilder(
      listenable: t.repo,
      builder: (context, _) => Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero(context)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  20, 0, 20, 40 + MediaQuery.paddingOf(context).bottom),
              sliver: SliverList.list(children: _content(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    Widget glass(IconData icon, String tip, VoidCallback onTap) => Material(
          color: Colors.black.withValues(alpha: 0.38),
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: onTap,
            tooltip: tip,
            icon: Icon(icon, color: Colors.white),
          ),
        );
    final url = _backdrop;
    return SizedBox(
      height: 240 + top,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.4),
                  scheme.surface.withValues(alpha: 0.1),
                  scheme.surface,
                ],
                stops: const [0, 0.4, 1],
              ),
            ),
          ),
          Positioned(
            top: top + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                glass(Icons.arrow_back_rounded,
                    MaterialLocalizations.of(context).backButtonTooltip,
                    () => Navigator.of(context).maybePop()),
                const Spacer(),
                if (!_isFriend && !widget.isPreview) ...[
                  glass(Icons.ios_share_rounded, tr('rv_share_text'), _share),
                  const SizedBox(width: 8),
                  glass(Icons.edit_rounded, tr('edit'),
                      () => openReviewEditor(context, t)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = _meta;
    final text = _text?.trim() ?? '';
    final title = meta?.title?.trim();
    final year = t.year != null ? ', ${t.year}' : '';
    final label = _isFriend
        ? trf('rv_label_friend', {'title': '${t.title}$year'})
        : trf('rv_label_mine', {'title': '${t.title}$year'});
    final gated = _isFriend && (meta?.spoilers ?? false) && !_spoilersOpen;
    return [
      Text(label.toUpperCase(),
          style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.4,
              letterSpacing: 1.1,
              color: scheme.primary)),
      const SizedBox(height: 10),
      Text(title == null || title.isEmpty ? t.title : title,
          style: TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w800,
              fontSize: 28,
              height: 1.12,
              color: scheme.onSurface)),
      const SizedBox(height: 18),
      _authorRow(context, text),
      if (meta?.verdict != null) ...[
        const SizedBox(height: 16),
        Align(
            alignment: Alignment.centerLeft,
            child: VerdictBadge(meta!.verdict!)),
      ],
      if (text.isNotEmpty) ...[
        const SizedBox(height: 22),
        if (gated) _spoilerGate(context) else MarkdownView(data: text),
      ],
      if (meta != null && (meta.pros.isNotEmpty || meta.cons.isNotEmpty)) ...[
        const SizedBox(height: 24),
        ProsConsBlock(pros: meta.pros, cons: meta.cons),
      ],
      ..._scoresCard(context),
      ..._actions(context),
    ];
  }

  Widget _authorRow(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    final me = SocialController.instance.user;
    final user = _isFriend ? widget.author : me;
    final name = _isFriend
        ? _friendName
        : (me?.displayName ?? tr('rv_you'));
    final date = _meta?.shownDate;
    final sub = [
      if (date != null) longDate(date),
      if (text.isNotEmpty)
        trf('rv_read_min', {'n': reviewReadMinutes(text)}),
    ].join(' · ');
    final score = _score;
    return Row(
      spacing: 12,
      children: [
        if (user != null)
          UserAvatar(user: user, size: 44)
        else
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primaryContainer,
            child: Icon(Icons.person_rounded, color: scheme.onPrimaryContainer),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: scheme.onSurface)),
              if (sub.isNotEmpty)
                Text(sub,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12,
                        color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        if (score != null) ReviewScoreCircle(score),
      ],
    );
  }

  Widget _spoilerGate(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(Icons.visibility_off_rounded, color: scheme.error),
          Text(tr('rv_gate_title'),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: scheme.onSurface)),
          Text(tr('rv_gate_sub'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  height: 1.4,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          FilledButton.tonal(
            onPressed: () => setState(() => _spoilersOpen = true),
            child: Text(tr('rv_gate_open')),
          ),
        ],
      ),
    );
  }

  /// «По пунктам» у своей, «Вы и друг» у чужой.
  List<Widget> _scoresCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = _meta;
    final crit = meta?.criteria ?? const <String, double>{};
    final mine = _isFriend ? t.mineCounterpart(mine: widget.myRepo) : null;
    final myCrit = mine?.meta?.criteria ?? const <String, double>{};
    final myScore = mine?.score;
    final friendScore = _score;
    final compare = _isFriend && (myScore != null || myCrit.isNotEmpty);
    if (crit.isEmpty && !(compare && friendScore != null && myScore != null)) {
      return const [];
    }

    Widget tile(String who, double? v, Color c, BorderRadius r) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration:
                BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12,
                        color: scheme.onSurfaceVariant)),
                Text(v?.toStringAsFixed(1) ?? '—',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: c)),
              ],
            ),
          ),
        );

    final divergence = compare ? _divergence(crit, myCrit) : null;
    return [
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Row(
              children: [
                Expanded(
                  child: compare
                      ? Text(
                          trf('rv_you_and',
                              {'name': _friendName}),
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: scheme.onSurface))
                      : ReviewCaps(tr('rv_criteria')),
                ),
                if (!compare && meta?.average != null)
                  Text(
                      trf('rv_avg_short',
                          {'v': meta!.average!.toStringAsFixed(1)}),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 12,
                          color: scheme.onSurfaceVariant)),
              ],
            ),
            if (compare)
              Row(
                spacing: 4,
                children: [
                  tile(_friendName, friendScore,
                      authorCompareColor(),
                      const BorderRadius.horizontal(
                          left: Radius.circular(20), right: Radius.circular(8))),
                  tile(tr('rv_you'), myScore, scheme.primary,
                      const BorderRadius.horizontal(
                          left: Radius.circular(8), right: Radius.circular(20))),
                ],
              ),
            if (crit.isNotEmpty)
              CriteriaBars(
                  criteria: crit,
                  other: compare && myCrit.isNotEmpty ? myCrit : null),
            if (divergence != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(divergence,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 13.5,
                        height: 1.4,
                        color: scheme.onTertiaryContainer)),
              ),
          ],
        ),
      ),
    ];
  }

  /// Пункт, где мы с другом расходимся сильнее всего (от 1 балла).
  String? _divergence(Map<String, double> a, Map<String, double> b) {
    String? best;
    var gap = 0.0;
    for (final id in a.keys) {
      final y = b[id];
      if (y == null) continue;
      final d = (a[id]! - y).abs();
      if (d > gap) {
        gap = d;
        best = id;
      }
    }
    if (best == null || gap < 1.0) return null;
    return trf('rv_divergence', {
      'crit': critLabel(best),
      'name': _friendName,
      'a': a[best]!.toStringAsFixed(1),
      'b': b[best]!.toStringAsFixed(1),
    });
  }

  List<Widget> _actions(BuildContext context) {
    if (widget.isPreview) return const [];
    if (!_isFriend) {
      return [
        const SizedBox(height: 28),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => openReviewEditor(context, t),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
                icon: const Icon(Icons.edit_rounded),
                label: Text(tr('edit')),
              ),
            ),
            IconButton.filledTonal(
              onPressed: _share,
              tooltip: tr('rv_share_text'),
              style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
              icon: const Icon(Icons.ios_share_rounded),
            ),
          ],
        ),
      ];
    }
    final mine = t.mineCounterpart(mine: widget.myRepo);
    if (mine != null && mine.canRate) {
      final has = mine.item.hasReview;
      return [
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: () => has
              ? openReview(context, mine)
              : openReviewEditor(context, mine),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          icon: Icon(has ? Icons.article_rounded : Icons.reply_rounded),
          label: Text(tr(has ? 'rv_open_mine' : 'rv_reply')),
        ),
      ];
    }
    // Фильм у меня уже в «Буду смотреть» или брошен: кнопка либо лишняя,
    // либо молча перенесёт брошенный в список желаний.
    final id = t.tmdbId;
    final listed =
        mine != null && mine.movie?.status != LibraryStatus.library;
    if (id == null || listed) return const [];
    return [
      const SizedBox(height: 28),
      FilledButton.tonalIcon(
        onPressed: () => _addToWatchlist(id),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        icon: const Icon(Icons.bookmark_add_rounded),
        label: Text(tr('sl_add_to_watchlist')),
      ),
    ];
  }

  Future<void> _addToWatchlist(int id) async {
    final repo = MovieRepository.instance;
    if (t.isSeries) {
      final s = repo.ensureSeriesFromTmdb(TmdbSeries(
          id: id, title: t.title, posterUrl: t.poster, year: t.year));
      if (!s.watchlist) await repo.toggleSeriesWatchlist(s.tvShowId);
    } else {
      await repo.addFromTmdb(
          TmdbMovie(id: id, title: t.title, posterUrl: t.poster, year: t.year),
          LibraryStatus.watchlist);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('sl_added_to_watchlist'))));
    }
  }

  Future<void> _share() async {
    final meta = _meta;
    final score = _score;
    final head = [
      if (meta?.title?.trim().isNotEmpty ?? false) meta!.title!.trim(),
      [
        '${t.title}${t.year != null ? ' (${t.year})' : ''}',
        if (score != null) '${score.toStringAsFixed(1)}/10',
        if (meta?.verdict != null) verdictLabel(meta!.verdict!),
      ].join(' · '),
    ].join('\n');
    final body = _text == null
        ? ''
        : reviewPlainText(_text!, spoilerMask: tr('rv_spoiler_mask'));
    await Share.share([head, if (body.isNotEmpty) body].join('\n\n'));
  }
}
