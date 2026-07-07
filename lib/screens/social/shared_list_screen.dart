import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/library_entry.dart';
import '../../models/social.dart';
import '../../services/movie_repository.dart';
import '../../services/social/social_api.dart';
import '../../services/social/social_controller.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/poster.dart';
import '../../widgets/user_avatar.dart';
import 'auth_screen.dart';

/// Экран совместного списка: участники, фильмы (добавляют все), приглашение
/// друга, выход/удаление. Все операции идут через бэкенд соц-слоя.
class SharedListScreen extends StatefulWidget {
  final String listId;
  final String initialName;
  const SharedListScreen(
      {super.key, required this.listId, required this.initialName});

  @override
  State<SharedListScreen> createState() => _SharedListScreenState();
}

class _SharedListScreenState extends State<SharedListScreen> {
  SharedListDetail? _list;
  bool _loading = true;
  String? _error;

  String? get _token => SocialController.instance.token;
  bool get _isOwner => _list?.owner == SocialController.instance.user?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = _token;
    if (t == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await SocialApi.instance.getList(t, widget.listId);
      if (!mounted) return;
      setState(() {
        _list = list;
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

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: Text(list?.name ?? widget.initialName),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_rounded),
            tooltip: tr('sl_invite'),
            onPressed: list == null ? null : _invite,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'rename') _rename();
              if (v == 'leave') _deleteOrLeave();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'rename', child: Text(tr('sl_rename'))),
              PopupMenuItem(
                value: 'leave',
                child: Text(_isOwner ? tr('sl_delete') : tr('sl_leave'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: list == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addMovie,
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('sl_add_movie')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : _content(list!),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: _load, child: Text(tr('retry'))),
            ],
          ),
        ),
      );

  Widget _content(SharedListDetail list) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          // Участники.
          Row(
            children: [
              for (final m in list.members)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: UserAvatar(user: m, size: 40),
                ),
              const SizedBox(width: 4),
              Text(trf('sl_members_n', {'n': list.members.length}),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 16),
          if (list.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.playlist_add_rounded,
                        size: 48, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(tr('sl_empty'),
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            for (final it in list.items) _itemTile(list, it),
        ],
      ),
    );
  }

  Widget _itemTile(SharedListDetail list, SharedListItem it) {
    final scheme = Theme.of(context).colorScheme;
    SocialUser? adder;
    for (final m in list.members) {
      if (m.id == it.addedBy) {
        adder = m;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _itemActions(it),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Poster(title: it.title, url: it.posterUrl, width: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              height: 1.1,
                              color: scheme.onSurface)),
                      if (it.year != null) ...[
                        const SizedBox(height: 3),
                        Text('${it.year}',
                            style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                if (adder != null) UserAvatar(user: adder, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------ действия ------------------------------

  void _itemActions(SharedListItem it) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.bookmark_add_rounded),
              title: Text(tr('sl_add_to_watchlist')),
              onTap: () {
                Navigator.pop(ctx);
                _addToMyWatchlist(it);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
              title: Text(tr('sl_remove_item'),
                  style: TextStyle(color: scheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _removeItem(it);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _addToMyWatchlist(SharedListItem it) async {
    if (it.tmdbId == null) return;
    final m = TmdbMovie(
        id: it.tmdbId!, title: it.title, posterUrl: it.posterUrl, year: it.year);
    await MovieRepository.instance.addFromTmdb(m, LibraryStatus.watchlist);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('sl_added_to_watchlist'))));
    }
  }

  Future<void> _removeItem(SharedListItem it) async {
    final t = _token;
    if (t == null) return;
    try {
      await SocialApi.instance.removeListItem(t, widget.listId, it.key);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    }
  }

  Future<void> _addMovie() async {
    final picked = await showModalBottomSheet<TmdbMovie>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => const _MovieSearchSheet(),
    );
    if (picked == null) return;
    final t = _token;
    if (t == null) return;
    try {
      await SocialApi.instance.addListItem(t, widget.listId, {
        'key': 'tmdb-${picked.id}',
        'title': picked.title,
        'year': picked.year,
        'posterUrl': picked.posterUrl,
        'tmdbId': picked.id,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    }
  }

  Future<void> _invite() async {
    final list = _list;
    if (list == null) return;
    final memberIds = list.members.map((m) => m.id).toSet();
    final candidates = SocialController.instance.friends.friends
        .where((f) => !memberIds.contains(f.user.id))
        .toList();
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('sl_invite'),
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: scheme.onSurface)),
              const SizedBox(height: 12),
              if (candidates.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(tr('sl_no_friends_to_invite'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          color: scheme.onSurfaceVariant)),
                )
              else
                ...candidates.map((f) => ListTile(
                      leading: UserAvatar(user: f.user, size: 40),
                      title: Text(f.user.displayName,
                          style: const TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.add_rounded),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _doInvite(f.user.id);
                      },
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doInvite(String userId) async {
    final t = _token;
    if (t == null) return;
    try {
      await SocialApi.instance.addListMember(t, widget.listId, userId: userId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    }
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _list?.name ?? '');
    final scheme = Theme.of(context).colorScheme;
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('sl_rename'),
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: scheme.onSurface)),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              decoration: InputDecoration(hintText: tr('list_name')),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, c.text.trim()),
                  child: Text(tr('save'))),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty) return;
    final t = _token;
    if (t == null) return;
    try {
      await SocialApi.instance.renameList(t, widget.listId, name);
      await _load();
    } catch (_) {}
  }

  Future<void> _deleteOrLeave() async {
    final owner = _isOwner;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(owner ? tr('sl_delete') : tr('sl_leave')),
        content: Text(owner ? tr('sl_delete_q') : tr('sl_leave_q')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(owner ? tr('sl_delete') : tr('sl_leave'))),
        ],
      ),
    );
    if (ok != true) return;
    final t = _token;
    if (t == null) return;
    try {
      await SocialApi.instance.deleteOrLeaveList(t, widget.listId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(socialErrorText(e))));
      }
    }
  }
}

/// Поиск фильма по TMDB для добавления в совместный список. Возвращает выбранный
/// [TmdbMovie] через Navigator.pop.
class _MovieSearchSheet extends StatefulWidget {
  const _MovieSearchSheet();

  @override
  State<_MovieSearchSheet> createState() => _MovieSearchSheetState();
}

class _MovieSearchSheetState extends State<_MovieSearchSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<TmdbMovie> _results = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = q.trim();
      if (query.isEmpty) {
        setState(() => _results = const []);
        return;
      }
      setState(() => _loading = true);
      try {
        final r = await TmdbService.searchMovies(query);
        if (mounted) {
          setState(() {
            _results = r;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _ctl,
                autofocus: true,
                onChanged: _onChanged,
                style: const TextStyle(fontFamily: AppTheme.bodyFont),
                decoration: InputDecoration(
                  hintText: tr('sl_search_hint'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final m = _results[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Material(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, m),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Poster(title: m.title, url: m.posterUrl, width: 44),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontFamily: AppTheme.displayFont,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14.5,
                                            color: scheme.onSurface)),
                                    if (m.year != null)
                                      Text('${m.year}',
                                          style: TextStyle(
                                              fontFamily: AppTheme.bodyFont,
                                              fontSize: 12,
                                              color: scheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              Icon(Icons.add_circle_outline_rounded,
                                  color: scheme.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
