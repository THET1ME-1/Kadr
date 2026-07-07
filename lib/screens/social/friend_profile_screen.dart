import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/social.dart';
import '../../services/movie_repository.dart';
import '../../services/social/social_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';
import '../library_tab.dart';
import 'auth_screen.dart';
import 'profile_stats.dart';

/// Профиль друга: шапка (аватар/ник/код), его просмотры и желания ТОЧНО как на
/// экране «Просмотрено» (read-only), важная статистика и его друзья.
class FriendProfileScreen extends StatefulWidget {
  final SocialUser user;
  const FriendProfileScreen({super.key, required this.user});

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  MovieRepository? _repo;
  List<SocialUser> _friends = const [];
  bool _loading = true;
  String? _error;
  LibraryViewMode _viewMode = LibraryViewMode.list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lib = await SocialController.instance.friendLibrary(widget.user.id);
      final friends =
          await SocialController.instance.userFriends(widget.user.id);
      if (!mounted) return;
      setState(() {
        _repo = lib.repo;
        _friends = friends;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = socialErrorText(e);
      });
    }
  }

  void _cycleView() {
    setState(() {
      _viewMode = LibraryViewMode
          .values[(_viewMode.index + 1) % LibraryViewMode.values.length];
    });
  }

  IconData get _viewIcon => switch (_viewMode) {
        LibraryViewMode.list => Icons.view_agenda_rounded,
        LibraryViewMode.posters => Icons.grid_view_rounded,
        LibraryViewMode.banners => Icons.view_carousel_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.user.displayName),
          actions: [
            IconButton(
                onPressed: _cycleView,
                icon: Icon(_viewIcon),
                tooltip: tr('view_mode')),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor:
                Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 13.5),
            tabs: [
              Tab(text: tr('nav_watched')),
              Tab(text: tr('nav_watchlist')),
              Tab(text: tr('profile_about')),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView()
                : TabBarView(
                    children: [
                      LibraryTab(
                          mode: LibraryMode.watched,
                          repository: _repo,
                          readOnly: true,
                          viewMode: _viewMode),
                      LibraryTab(
                          mode: LibraryMode.watchlist,
                          repository: _repo,
                          readOnly: true,
                          viewMode: _viewMode),
                      _aboutTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: AppTheme.bodyFont)),
              const SizedBox(height: 18),
              FilledButton.tonal(
                  onPressed: _load, child: Text(tr('retry'))),
            ],
          ),
        ),
      );

  Widget _aboutTab() {
    final repo = _repo;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _header(),
        const SizedBox(height: 20),
        if (repo != null) ProfileStats(repo: repo),
        if (_friends.isNotEmpty) ...[
          const SizedBox(height: 22),
          _friendsSection(),
        ],
      ],
    );
  }

  Widget _header() {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        UserAvatar(user: widget.user, size: 72),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.user.displayName,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: scheme.onSurface)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tag_rounded,
                        size: 15, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(widget.user.friendCode,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 1,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _friendsSection() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('profile_friends'),
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: scheme.onSurface)),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _friends.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => _friendChip(_friends[i]),
          ),
        ),
      ],
    );
  }

  Widget _friendChip(SocialUser u) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openFriend(u),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            UserAvatar(user: u, size: 58),
            const SizedBox(height: 6),
            Text(u.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  void _openFriend(SocialUser u) {
    final ctl = SocialController.instance;
    if (u.id == ctl.user?.id) return; // это я
    if (ctl.isFriend(u.id)) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FriendProfileScreen(user: u)));
    } else {
      // Не мой друг — предложить добавить.
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(user: u, size: 64),
                const SizedBox(height: 12),
                Text(u.displayName,
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      try {
                        await ctl.addFriend(userId: u.id);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(tr('social_request_sent'))));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(socialErrorText(e))));
                        }
                      }
                    },
                    icon: const Icon(Icons.person_add_rounded),
                    label: Text(tr('social_add_friend')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}
