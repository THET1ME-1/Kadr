import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/youtube_parts.dart';
import 'movie_sheet.dart';
import 'series_screen.dart';

/// Ссылка на YouTube в поиске «Обзора» (макет «Циклы с YouTube», А1): вместо
/// фильмов найденный цикл или ролик. Цикл добавляется через окно «Что уже
/// посмотрел?», ролик без цикла — фильмом.
class YouTubeLinkResult extends StatefulWidget {
  final String text;
  final MovieRepository? repo;
  const YouTubeLinkResult({super.key, required this.text, this.repo});

  @override
  State<YouTubeLinkResult> createState() => _YouTubeLinkResultState();
}

class _YouTubeLinkResultState extends State<YouTubeLinkResult> {
  late final YtLink? _link = YouTubeService.parseLink(widget.text);
  late final Future<YtFound?> _found =
      _link == null ? Future.value(null) : YouTubeService.resolve(_link);
  bool _busy = false;

  MovieRepository get _repo => widget.repo ?? MovieRepository.instance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<YtFound?>(
      future: _found,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _note(scheme, tr('yt_searching'), loading: true);
        }
        final f = snap.data;
        if (f == null) return _note(scheme, tr('yt_not_found'));
        return ListenableBuilder(
          listenable: _repo,
          builder: (context, _) => ListView(
            padding:
                EdgeInsets.fromLTRB(16, 10, 16, bottomListTail(context)),
            children: [
              f.cycle != null ? _cycleCard(scheme, f) : _videoCard(scheme, f),
            ],
          ),
        );
      },
    );
  }

  Widget _note(ColorScheme scheme, String text, {bool loading = false}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 16,
            children: [
              if (loading)
                const CircularProgressIndicator()
              else
                Icon(Icons.smart_display_rounded,
                    size: 40, color: scheme.onSurfaceVariant),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 14,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );

  // ------------------------------ цикл ------------------------------

  Widget _cycleCard(ColorScheme scheme, YtFound f) {
    final p = f.cycle!;
    final id = 'yt:${p.id}';
    final have = _repo.seriesById(id);
    final total = p.videos.fold<int>(0, (s, v) => s + (v.durSec ?? 0));
    DateTime? last;
    for (final v in p.videos) {
      final d = v.published;
      if (d != null && (last == null || d.isAfter(last))) last = d;
    }
    final at = f.video == null
        ? -1
        : p.videos.indexWhere((v) => v.id == f.video!.id);
    final meta = [
      trn('yt_issues_n', p.videos.length),
      if (total > 0) humanDuration(Duration(seconds: total)),
      if (last != null) trf('yt_last', {'date': longDate(last)}),
    ].join(' · ');
    return _card(
      scheme,
      cover: p.videos.first.cover,
      badge: _badge(Icons.smart_display_rounded,
          trn('yt_issues_n', p.videos.length)),
      hint: at < 0
          ? null
          : trf('yt_link_hint', {'n': _label(p.videos, at + 1)}),
      title: p.title,
      channel: p.channelName,
      avatar: p.avatar,
      meta: meta,
      button: have != null
          ? FilledButton.icon(
              onPressed: () => _openSeries(have),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(tr('yt_open')),
            )
          : FilledButton.icon(
              onPressed: _busy ? null : () => _addCycle(p, at),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('yt_add_cycle')),
            ),
      extra: f.video == null || have != null
          ? null
          : TextButton(
              onPressed: _busy ? null : () => _addVideo(f.video!, p.avatar),
              child: Text(tr('yt_add_only_video')),
            ),
    );
  }

  /// Подпись выпуска по месту в плейлисте: «№4» из названия или место.
  static String _label(List<YtEntry> videos, int number) =>
      '№${ytIssueNumber(videos[number - 1].title) ?? number}';

  Future<void> _addCycle(YtPlaylistInfo p, int linkAt) async {
    final labels = [for (var n = 1; n <= p.videos.length; n++) _label(p.videos, n)];
    final choice = await showYouTubeCycleSheet(
      context,
      title: p.title,
      labels: labels,
      // Ссылка на выпуск: всё до него, скорее всего, уже посмотрено.
      initial: linkAt < 0 ? 0 : linkAt,
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    final s = await _repo.addYouTubeCycle(
      p.id,
      title: p.title,
      channelId: p.channelId,
      channelName: p.channelName,
      avatar: p.avatar,
      videos: p.videos,
      watchedUpTo: choice.upTo,
      notify: choice.notify,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.mediumImpact();
    _openSeries(s);
  }

  void _openSeries(LibrarySeries s) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s)));

  // ------------------------------ ролик ------------------------------

  Widget _videoCard(ColorScheme scheme, YtFound f) {
    final v = f.video!;
    final have = _repo.byUuid('yt:${v.id}');
    final meta = [
      if (v.durSec != null) humanDuration(Duration(seconds: v.durSec!)),
      if (v.published != null) longDate(v.published!),
    ].join(' · ');
    return _card(
      scheme,
      cover: v.thumb ?? ytCover(v.id),
      badge: v.durSec == null ? null : YtDurationBadge(v.durSec!),
      hint: null,
      title: v.title,
      channel: v.channelName,
      avatar: null,
      meta: meta,
      button: have != null
          ? FilledButton.icon(
              onPressed: () => _openMovie(have),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(tr('yt_open')),
            )
          : FilledButton.icon(
              onPressed: _busy ? null : () => _addVideo(v, null),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('yt_add_video')),
            ),
    );
  }

  Future<void> _addVideo(YtVideoInfo v, String? avatar) async {
    setState(() => _busy = true);
    final m = await _repo.addYouTubeVideo(
      videoId: v.id,
      title: v.title,
      channelId: v.channelId,
      channelName: v.channelName,
      avatar: avatar,
      durSec: v.durSec,
      published: v.published,
      thumb: v.thumb,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.mediumImpact();
    _openMovie(m);
  }

  void _openMovie(LibraryMovie m) => showMovieSheet(context, m);

  // ------------------------------ карточка ------------------------------

  Widget _badge(IconData icon, String text) => Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            Text(text,
                style: const TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.white)),
          ],
        ),
      );

  Widget _card(
    ColorScheme scheme, {
    required String cover,
    required Widget? badge,
    required String? hint,
    required String title,
    required String channel,
    required String? avatar,
    required String meta,
    required Widget button,
    Widget? extra,
  }) {
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  placeholder: (c, _) =>
                      ColoredBox(color: scheme.surfaceContainerHighest),
                  errorWidget: (c, u, e) =>
                      ColoredBox(color: scheme.surfaceContainerHighest),
                ),
                if (badge != null)
                  Positioned(right: 10, bottom: 10, child: badge),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                if (hint != null)
                  Row(
                    spacing: 6,
                    children: [
                      Icon(Icons.link_rounded, size: 16, color: scheme.primary),
                      Expanded(
                        child: Text(hint,
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                color: scheme.primary)),
                      ),
                    ],
                  ),
                Text(title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        height: 1.1,
                        color: scheme.onSurface)),
                Row(
                  spacing: 8,
                  children: [
                    ClipOval(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: avatar == null
                            ? ColoredBox(
                                color: scheme.surfaceContainerHighest,
                                child: Icon(Icons.smart_display_rounded,
                                    size: 15, color: scheme.onSurfaceVariant))
                            : CachedNetworkImage(
                                imageUrl: avatar,
                                fit: BoxFit.cover,
                                placeholder: (c, _) => ColoredBox(
                                    color: scheme.surfaceContainerHighest),
                                errorWidget: (c, u, e) => ColoredBox(
                                    color: scheme.surfaceContainerHighest),
                              ),
                      ),
                    ),
                    Expanded(
                      child: Text(channel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: scheme.onSurfaceVariant)),
                    ),
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(meta,
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                SizedBox(height: 56, child: button),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Окно «Что уже посмотрел?» перед добавлением цикла (макет «Циклы с
/// YouTube», А2): последний просмотренный выпуск и пуш о новых. [labels] —
/// подписи выпусков по порядку, [initial] — сколько выпусков отмечено
/// заранее.
Future<({int upTo, bool notify})?> showYouTubeCycleSheet(
  BuildContext context, {
  required String title,
  required List<String> labels,
  int initial = 0,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<({int upTo, bool notify})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SafeArea(
      top: false,
      child: _CycleSheet(title: title, labels: labels, initial: initial),
    ),
  );
}

class _CycleSheet extends StatefulWidget {
  final String title;
  final List<String> labels;
  final int initial;
  const _CycleSheet(
      {required this.title, required this.labels, required this.initial});

  @override
  State<_CycleSheet> createState() => _CycleSheetState();
}

class _CycleSheetState extends State<_CycleSheet> {
  late int _upTo = widget.initial.clamp(0, widget.labels.length);
  bool _notify = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget pill(int n) {
      final on = n > 0 && n <= _upTo;
      final end = n == _upTo;
      return ChoiceChip(
        label: Text(n == 0 ? tr('yt_nothing') : widget.labels[n - 1]),
        selected: end,
        showCheckmark: false,
        onSelected: (_) {
          HapticFeedback.selectionClick();
          setState(() => _upTo = n);
        },
        // Выпуски до выбранного горят тоном: они тоже встанут просмотренными.
        backgroundColor: on ? scheme.primaryContainer : null,
        labelStyle: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
          color: end
              ? scheme.onPrimary
              : on
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
        ),
        selectedColor: scheme.primary,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      );
    }

    return SingleChildScrollView(
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
            child: Text(tr('yt_seen_q'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1.15,
                    color: scheme.primary)),
          ),
          Text('${widget.title} · ${trn('yt_issues_n', widget.labels.length)}',
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w500,
                  fontSize: 13.5,
                  color: scheme.onSurfaceVariant)),
          Text(tr('yt_last_seen').toUpperCase(),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.1,
                  color: scheme.onSurfaceVariant)),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (var n = 0; n <= widget.labels.length; n++) pill(n)],
          ),
          if (_upTo > 0)
            Text(trf('yt_upto_hint', {'n': widget.labels[_upTo - 1]}),
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: scheme.onSurfaceVariant)),
          Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile(
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
              secondary: Icon(Icons.notifications_active_rounded,
                  color: scheme.primary),
              title: Text(tr('yt_new_issues'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant)),
              subtitle: Text(tr('yt_new_issues_sub'),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: scheme.onSurface)),
            ),
          ),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).pop((upTo: _upTo, notify: _notify));
              },
              child: Text(tr('yt_add')),
            ),
          ),
        ],
      ),
    );
  }
}
