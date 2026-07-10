import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/app_prefs.dart';
import '../services/tmdb_service.dart';

/// Лист «сделать любимым персонажем» — вызывается долгим нажатием на карточку
/// актёра в фильме/сериале. Любимый персонаж показывается в статистике.
Future<void> promptFavoriteCharacter(
    BuildContext context, TmdbCast c, String title) async {
  final p = AppPrefs.instance;
  final scheme = Theme.of(context).colorScheme;
  final charName = (c.character != null && c.character!.trim().isNotEmpty)
      ? c.character!.trim()
      : c.name;
  final cur = p.favoriteCharacter;
  final isFav = cur != null && cur.character == charName && cur.actor == c.name;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text('$charName · ${c.name}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: scheme.onSurface)),
          ),
          ListTile(
            leading: Icon(Icons.star_rounded, color: scheme.primary),
            title: Text(isFav ? tr('fav_char_remove') : tr('fav_char_set')),
            onTap: () => Navigator.pop(ctx, isFav ? 'unset' : 'set'),
          ),
        ],
      ),
    ),
  );
  if (action == null) return;
  if (action == 'unset') {
    await p.setFavoriteCharacter(null);
  } else {
    await p.setFavoriteCharacter(FavoriteCharacter(
      character: charName,
      actor: c.name,
      photoUrl: c.photoUrl,
      title: title,
    ));
  }
}
