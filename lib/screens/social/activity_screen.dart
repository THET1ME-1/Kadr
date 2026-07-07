import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../models/social.dart';
import '../../services/movie_repository.dart';
import '../../services/social/social_controller.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/score.dart';
import '../../widgets/poster.dart';
import '../../widgets/user_avatar.dart';
import 'friend_profile_screen.dart';

enum _Kind { watched, wishlist, series }

/// Событие в ленте активности друга.
class _Event {
  final SocialUser friend;
  final _Kind kind;
  final String title;
  final String? posterUrl;
  final int? year;
  final int? tmdbId;
  final DateTime date;
  final double? score;
  _Event(this.friend, this.kind, this.title, this.posterUrl, this.year,
      this.tmdbId, this.date, this.score);
}

/// Рекомендация: фильм, который друзья высоко оценили, а я не смотрел.
class _Rec {
  final String title;
  final String? posterUrl;
  final int? year;
  final int? tmdbId;
  final double score;
  final SocialUser by;
  _Rec(this.title, this.posterUrl, this.year, this.tmdbId, this.score, this.by);
}

/// Лента активности друзей: что они недавно посмотрели / оценили / добавили в
/// желания, и рекомендации (высокие оценки друзей, которые я ещё не смотрел).
/// Всё считается на клиенте из публичных проекций друзей.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  List<_Event> _events = const [];
  List<_Rec> _recs = const [];
  List<RecommendationItem> _fromFriends = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _key(String title, int? year) =>
      '${title.toLowerCase().trim()}|${year ?? 0}';

  Future<void> _load() async {
    setState(() => _loading = true);
    // Явные рекомендации «Тебе советуют» + библиотеки друзей (параллельно).
    final recsFuture = SocialController.instance.receivedRecommendations();
    final libs = await SocialController.instance.allFriendLibraries();
    _fromFriends = await recsFuture;

    // Что я уже смотрел — чтобы не советовать это.
    final mineWatched = {
      for (final m in MovieRepository.instance.watched)
        _key(m.ruTitle ?? m.title, m.year)
    };

    final events = <_Event>[];
    final recMap = <String, _Rec>{}; // ключ → лучшая рекомендация
    for (final lib in libs) {
      final f = lib.user;
      for (final m in lib.repo.watched) {
        final d = m.lastViewing;
        if (d != null) {
          events.add(_Event(f, _Kind.watched, m.displayTitle, m.posterUrl,
              m.year, m.tmdbId, d, m.currentScore));
        }
        // Рекомендация: оценка ≥ 8 и я не смотрел.
        final sc = m.currentScore;
        if (sc != null && sc >= 8 && !mineWatched.contains(_key(m.displayTitle, m.year))) {
          final k = _key(m.displayTitle, m.year);
          final prev = recMap[k];
          if (prev == null || sc > prev.score) {
            recMap[k] =
                _Rec(m.displayTitle, m.posterUrl, m.year, m.tmdbId, sc, f);
          }
        }
      }
      for (final m in lib.repo.watchlist) {
        final d = m.addedAt;
        if (d != null) {
          events.add(_Event(f, _Kind.wishlist, m.displayTitle, m.posterUrl,
              m.year, m.tmdbId, d, null));
        }
      }
      for (final s in lib.repo.series) {
        final d = s.lastWatch;
        if (d != null) {
          events.add(_Event(f, _Kind.series, s.displayTitle, s.posterUrl,
              s.year, s.tmdbId, d, s.displayScore));
        }
      }
    }
    events.sort((a, b) => b.date.compareTo(a.date));
    final recs = recMap.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (!mounted) return;
    setState(() {
      _events = events.take(120).toList();
      _recs = recs.take(20).toList();
      _loading = false;
    });
  }

  Future<void> _addToWatchlist(String title, int? year, String? poster,
      int? tmdbId) async {
    if (tmdbId == null) return;
    final m = TmdbMovie(id: tmdbId, title: title, posterUrl: poster, year: year);
    await MovieRepository.instance.addFromTmdb(m, LibraryStatus.watchlist);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('sl_added_to_watchlist'))));
    }
  }

  Future<void> _dismissRec(RecommendationItem r) async {
    setState(() =>
        _fromFriends = _fromFriends.where((x) => x.id != r.id).toList());
    try {
      await SocialController.instance.dismissRecommendation(r.id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('activity_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_events.isEmpty && _recs.isEmpty && _fromFriends.isEmpty)
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                    children: [
                      if (_fromFriends.isNotEmpty) _fromFriendsSection(context),
                      if (_recs.isNotEmpty) _recsRail(context),
                      if (_events.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(tr('activity_recent'),
                              style: TextStyle(
                                  fontFamily: AppTheme.displayFont,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color:
                                      Theme.of(context).colorScheme.onSurface)),
                        ),
                        for (final e in _events) _eventTile(context, e),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dynamic_feed_rounded,
                  size: 56,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(
                SocialController.instance.isLoggedIn
                    ? tr('activity_empty')
                    : tr('activity_login'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: AppTheme.bodyFont),
              ),
            ],
          ),
        ),
      );

  // ---------------------------- тебе советуют ----------------------------

  Widget _fromFriendsSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Icon(Icons.mark_email_unread_rounded,
                  size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(tr('rec_for_you'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: scheme.onSurface)),
            ],
          ),
        ),
        for (final r in _fromFriends) _fromFriendCard(context, r),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _fromFriendCard(BuildContext context, RecommendationItem r) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Poster(title: r.title, url: r.posterUrl, width: 48, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            UserAvatar(user: r.from, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                  trf('rec_from', {'name': r.from.displayName}),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontFamily: AppTheme.bodyFont,
                                      fontSize: 12.5,
                                      color: scheme.onSurfaceVariant)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(r.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                height: 1.1,
                                color: scheme.onSurface)),
                        if (r.note != null && r.note!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('«${r.note!}»',
                              style: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: scheme.onSurface)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        _addToWatchlist(r.title, r.year, r.posterUrl, r.tmdbId);
                        _dismissRec(r);
                      },
                      icon: const Icon(Icons.bookmark_add_rounded, size: 18),
                      label: Text(tr('sl_add_to_watchlist')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _dismissRec(r),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: tr('close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------- рекомендации -----------------------------

  Widget _recsRail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Icon(Icons.recommend_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(tr('activity_recs'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: scheme.onSurface)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Text(tr('activity_recs_sub'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant)),
        ),
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            itemCount: _recs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _recCard(context, _recs[i]),
          ),
        ),
      ],
    );
  }

  Widget _recCard(BuildContext context, _Rec r) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Poster(title: r.title, url: r.posterUrl, width: 116, radius: 14),
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: scoreColor(r.score),
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded,
                          size: 12, color: onScoreColor(r.score)),
                      const SizedBox(width: 2),
                      Text(r.score.toStringAsFixed(1),
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: onScoreColor(r.score))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.1,
                  color: scheme.onSurface)),
          const SizedBox(height: 2),
          Row(
            children: [
              UserAvatar(user: r.by, size: 16),
              const SizedBox(width: 5),
              Expanded(
                child: Text(r.by.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 11,
                        color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------- лента -------------------------------

  Widget _eventTile(BuildContext context, _Event e) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, verb) = switch (e.kind) {
      _Kind.watched => (Icons.check_circle_rounded, tr('activity_watched')),
      _Kind.wishlist => (Icons.bookmark_rounded, tr('activity_wishlisted')),
      _Kind.series => (Icons.live_tv_rounded, tr('activity_series')),
    };
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FriendProfileScreen(user: e.friend))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            Poster(title: e.title, url: e.posterUrl, width: 40, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      UserAvatar(user: e.friend, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant),
                            children: [
                              TextSpan(
                                  text: e.friend.displayName,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface)),
                              TextSpan(text: ' $verb'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: scheme.onSurface)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(height: 4),
                Text(numericDate(e.date),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 11,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
