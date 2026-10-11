import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../services/movie_repository.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../widgets/poster_viewer.dart';
import '../../widgets/viewing/score_card.dart';
import 'viewing_delete.dart';
import 'viewing_host.dart';
import 'viewings_section.dart';

/// Открывает окно серии нижней панелью. [onMark] — окно отметки: первый
/// просмотр серии или ещё один; [canMark] — серия уже вышла.
Future<void> showEpisodeSheet(
  BuildContext context, {
  required String seriesId,
  required String seriesTitle,
  required TmdbEpisode ep,
  required bool canMark,
  required VoidCallback onMark,
  MovieRepository? repo,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: scheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => EpisodeSheet(
      seriesId: seriesId,
      seriesTitle: seriesTitle,
      ep: ep,
      canMark: canMark,
      onMark: onMark,
      repo: repo,
    ),
  );
}

/// Окно одной серии, собранное как карточка фильма: кадр, оценка последнего
/// просмотра, «Смотрел ещё раз» и «Отменить просмотр», список просмотров,
/// описание.
///
/// «Отменить просмотр» убирает только последний просмотр этой серии: серии
/// после неё не трогает. Дата, дневник и прошлые просмотры правятся в окне
/// просмотра из списка.
class EpisodeSheet extends StatefulWidget {
  final String seriesId;
  final String seriesTitle;
  final TmdbEpisode ep;
  final bool canMark;
  final VoidCallback onMark;
  final MovieRepository? repo;

  const EpisodeSheet({
    super.key,
    required this.seriesId,
    required this.seriesTitle,
    required this.ep,
    required this.canMark,
    required this.onMark,
    this.repo,
  });

  @override
  State<EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<EpisodeSheet> {
  late final MovieRepository _repo = widget.repo ?? MovieRepository.instance;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  TmdbEpisode get ep => widget.ep;

  Episode? get _we =>
      _repo.seriesById(widget.seriesId)?.watchedEpisode(ep.season, ep.number);

  EpisodeViewingHost get _host => EpisodeViewingHost(
      widget.seriesId, ep.season, ep.number,
      runtimeMin: ep.runtime, repo: _repo);

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _messenger.currentState?.showSnackBar(SnackBar(
        content: Text(tr('copied')), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          // Свой ScaffoldMessenger: плашка «Вернуть» должна лечь поверх
          // окна, а не под него.
          builder: (context, controller) => ScaffoldMessenger(
            key: _messenger,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: _content(Theme.of(context).colorScheme),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _content(ColorScheme scheme) {
    final we = _we;
    final watched = we != null;
    final meta = [
      if (ep.airDate != null && DateTime.tryParse(ep.airDate!) != null)
        numericDate(DateTime.parse(ep.airDate!)),
      if (ep.runtime != null && ep.runtime! > 0)
        humanDuration(Duration(minutes: ep.runtime!)),
    ].join(' · ');
    return [
      Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2)),
        ),
      ),
      const SizedBox(height: 16),
      // Кадр серии → фулскрин по тапу.
      GestureDetector(
        onTap: ep.stillUrl != null
            ? () => openPosterViewer(context,
                title: ep.name,
                url: ep.stillUrl,
                heroTag: 'ep-${widget.seriesId}-${ep.season}-${ep.number}')
            : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ep.stillUrl != null
                ? Hero(
                    tag: 'ep-${widget.seriesId}-${ep.season}-${ep.number}',
                    child: CachedNetworkImage(
                      imageUrl: ep.stillUrl!,
                      fit: BoxFit.cover,
                      placeholder: (c, _) =>
                          Container(color: scheme.surfaceContainerHighest),
                      errorWidget: (c, u, e) =>
                          Container(color: scheme.surfaceContainerHighest),
                    ),
                  )
                : Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.tv_rounded,
                        size: 44, color: scheme.onSurfaceVariant)),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text('${widget.seriesTitle}  ·  S${ep.season}·E${ep.number}',
          style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: scheme.primary)),
      const SizedBox(height: 4),
      GestureDetector(
        onLongPress: () => _copy(ep.name),
        child: Text(ep.name,
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                height: 1.1,
                color: scheme.onSurface)),
      ),
      if (meta.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(meta,
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                color: scheme.onSurfaceVariant)),
      ],
      const SizedBox(height: 18),
      _scoreCard(scheme, we),
      if (we != null && we.orderedViews.last.score != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () => _host.setScore(we.orderedViews.last, null),
            icon: const Icon(Icons.star_outline_rounded),
            label: Text(tr('remove_score')),
            style: FilledButton.styleFrom(
                backgroundColor: kDroppedColor.withValues(alpha: 0.16),
                foregroundColor: kDroppedColor),
          ),
        ),
      ],
      const SizedBox(height: 12),
      ..._watchButtons(scheme, watched),
      if (watched) ...[
        const SizedBox(height: 12),
        ViewingsSection(host: _host),
      ],
      if (ep.overview != null && ep.overview!.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(tr('overview'),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: scheme.primary)),
        const SizedBox(height: 6),
        GestureDetector(
          onLongPress: () => _copy(ep.overview!),
          child: Text(ep.overview!,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  height: 1.45,
                  color: scheme.onSurface)),
        ),
      ],
    ];
  }

  List<Widget> _watchButtons(ColorScheme scheme, bool watched) {
    if (!watched) {
      // Невышедшую серию отметить нельзя — показываем подсказку.
      if (!widget.canMark) {
        return [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.schedule_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(tr('episode_not_aired'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ];
      }
      return [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.onMark,
            icon: const Icon(Icons.check_rounded),
            label: Text(tr('mark_watched')),
          ),
        ),
      ];
    }
    final host = _host;
    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.onMark,
          icon: const Icon(Icons.repeat_rounded),
          label: Text(tr('watch_again')),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: () {
            final last = host.ordered.lastOrNull;
            if (last == null) return;
            deleteViewingFlow(context, host, last,
                messenger: _messenger.currentState);
          },
          icon: const Icon(Icons.remove_done_rounded),
          label: Text(tr('undo_watch')),
          style: FilledButton.styleFrom(
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundColor: scheme.onSurfaceVariant),
        ),
      ),
    ];
  }

  /// Карточка оценки последнего просмотра серии, как в карточке фильма.
  Widget _scoreCard(ColorScheme scheme, Episode? we) {
    if (we == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24)),
        child: Column(children: [
          Icon(Icons.star_border_rounded,
              size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(tr('rate_after_watch_ep'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: scheme.onSurfaceVariant)),
        ]),
      );
    }
    final host = _host;
    final last = we.orderedViews.last;
    final prev = host.previousRated(last);
    final prevText = prev?.score.toStringAsFixed(1);
    final footer = [
      if (last.date != null) numericDate(last.date!),
      if (prevText != null) trf('view_last_time', {'v': prevText}),
    ].join(' · ');
    return ScoreCard(
      key: ValueKey('score-${last.id}'),
      label: we.watchCount >= 2
          ? trf('score_of_view', {
              'view': trf('viewing_n', {'n': we.watchCount}),
            })
          : tr('episode_score'),
      value: last.score,
      onChanged: (v) => host.setScore(last, v),
      footer: footer.isEmpty ? null : footer,
      sameAs: prev?.score,
      sameLabel: prevText == null
          ? null
          : trf(prev!.ordinal == 1 ? 'view_same_first' : 'view_same_last',
              {'v': prevText}),
    );
  }
}
