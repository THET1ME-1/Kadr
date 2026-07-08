import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../theme/app_theme.dart';
import '../utils/score.dart';
import '../widgets/poster.dart';

/// Нижний лист «Поделиться»: превью красивой карточки фильма (постер + оценка) и
/// кнопка, которая рендерит её в PNG и открывает системный «Поделиться».
Future<void> showShareCardSheet(BuildContext context, LibraryMovie movie) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _ShareCardSheet(movie: movie),
  );
}

class _ShareCardSheet extends StatefulWidget {
  final LibraryMovie movie;
  const _ShareCardSheet({required this.movie});

  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  final _shotKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      // Дадим кадру дорисоваться (постер) до захвата.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final boundary = _shotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kadr_${widget.movie.uuid}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: 'Kadr · ${widget.movie.displayTitle}',
      );
    } catch (_) {/* молча */} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            RepaintBoundary(
              key: _shotKey,
              child: _card(scheme),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _share,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2))
                    : const Icon(Icons.ios_share_rounded),
                label: Text(tr('share'),
                    style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(ColorScheme scheme) {
    final m = widget.movie;
    final score = m.currentScore;
    // Тёмный градиент из акцентов темы — белый текст читается в любой теме.
    final c1 = Color.lerp(scheme.primary, Colors.black, 0.28)!;
    final c2 = Color.lerp(scheme.tertiary, Colors.black, 0.5)!;
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c1, c2]),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(16),
            shadowColor: Colors.black54,
            child: Poster(
                title: m.displayTitle,
                url: m.posterUrl,
                width: 150,
                radius: 16),
          ),
          const SizedBox(height: 18),
          Text(m.displayTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  height: 1.1,
                  color: Colors.white)),
          if (m.year != null) ...[
            const SizedBox(height: 4),
            Text('${m.year}',
                style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.8))),
          ],
          const SizedBox(height: 16),
          if (score != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                  color: scoreColor(score),
                  borderRadius: BorderRadius.circular(30)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 22, color: onScoreColor(score)),
                  const SizedBox(width: 6),
                  Text('${score.toStringAsFixed(1)} / 10',
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: onScoreColor(score))),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(30)),
              child: Text(tr('share_want_to_watch'),
                  style: const TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.white)),
            ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.movie_rounded,
                  size: 16, color: Colors.white.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Text('Kadr',
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: 0.5,
                      color: Colors.white.withValues(alpha: 0.95))),
            ],
          ),
        ],
      ),
    );
  }
}
