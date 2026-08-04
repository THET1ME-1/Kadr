import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import '../utils/share_card_data.dart';
import '../utils/share_palette.dart';
import '../widgets/share_card.dart';

/// Нижний лист «Поделиться»: лента стилей карточки, живое превью и кнопка,
/// которая рендерит выбранный стиль в PNG и открывает системный «Поделиться».
///
/// [backdropUrl] приходит из карточки фильма (`TmdbDetails.backdropUrl`) — на
/// нём держатся фактура «Кадр», шапка «Билета» и верх «Сторис».
Future<void> showShareCardSheet(
  BuildContext context,
  LibraryMovie movie, {
  String? backdropUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ShareCardSheet(movie: movie, backdropUrl: backdropUrl),
  );
}

class _ShareCardSheet extends StatefulWidget {
  const _ShareCardSheet({required this.movie, this.backdropUrl});

  final LibraryMovie movie;
  final String? backdropUrl;

  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  static const _styleKey = 'shareCardStyle';
  static const _textureKey = 'shareCardTexture';

  final _shotKey = GlobalKey();

  ShareCardStyle _style = ShareCardStyle.poster;
  ShareTexture _texture = ShareTexture.frame;
  SharePalette _palette = SharePalette.fallback;
  ui.Image? _poster;
  ui.Image? _backdrop;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _restore();
    _loadImages();
  }

  @override
  void dispose() {
    _poster?.dispose();
    _backdrop?.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final style = await Store.instance.getString(_styleKey);
    final texture = await Store.instance.getString(_textureKey);
    if (!mounted) return;
    setState(() {
      _style = ShareCardStyle.values.firstWhere(
        (s) => s.name == style,
        orElse: () => _style,
      );
      _texture = ShareTexture.values.firstWhere(
        (t) => t.name == texture,
        orElse: () => _texture,
      );
    });
  }

  /// Раскодирует постер и кадр заранее: снимок делается за один кадр, ждать
  /// загрузку из сети в момент рендера уже поздно — в PNG попадёт пустота.
  Future<void> _loadImages() async {
    final poster = await _decode(widget.movie.displayPoster);
    final backdrop = await _decode(widget.backdropUrl);
    final palette = poster == null
        ? SharePalette.fallback
        : await _paletteOf(poster);
    if (!mounted) {
      poster?.dispose();
      backdrop?.dispose();
      return;
    }
    setState(() {
      _poster = poster;
      _backdrop = backdrop;
      _palette = palette;
      _ready = true;
    });
  }

  Future<ui.Image?> _decode(String? url) async {
    if (url == null || url.isEmpty) return null;
    final provider = url.startsWith('/')
        ? FileImage(File(url)) as ImageProvider
        : CachedNetworkImageProvider(url);
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (_, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => null,
    );
  }

  /// Палитра считается по прореженным пикселям: постер w342 — это 175 тысяч
  /// точек, каждая седьмая даёт тот же тон и не морозит кадр.
  Future<SharePalette> _paletteOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return SharePalette.fallback;
    return sharePaletteFromPixels(data.buffer.asUint8List(), stride: 7);
  }

  ShareCardData get _data {
    final m = widget.movie;
    return ShareCardData(
      title: m.displayTitle,
      meta: shareMetaLine(m),
      palette: _palette,
      facts: shareFactsOf(m),
      footerNote: shareFooterNote(m),
      texture: resolveShareTexture(
        _texture,
        hasBackdrop: _backdrop != null,
        hasPoster: _poster != null,
      ),
      poster: _poster,
      backdrop: _backdrop,
    );
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      // Кадр с превью уже отрисован, но дадим слоям фильтров осесть.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary =
          _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/kadr_${widget.movie.uuid}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png'),
      ], subject: 'Kadr · ${widget.movie.displayTitle}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('share_failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pick(ShareCardStyle style) {
    setState(() => _style = style);
    Store.instance.setString(_styleKey, style.name);
  }

  /// Фактура фона прячется в удержание на стиле: отдельной настройки она не
  /// заслуживает, а менять её хочется прямо здесь.
  Future<void> _pickTexture() async {
    final chosen = await showModalBottomSheet<ShareTexture>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 18),
            Text(
              tr('share_texture_title'),
              style: const TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 10),
            for (final t in ShareTexture.values)
              ListTile(
                leading: Icon(switch (t) {
                  ShareTexture.frame => Icons.image_rounded,
                  ShareTexture.film => Icons.movie_filter_rounded,
                  ShareTexture.letters => Icons.title_rounded,
                }),
                title: Text(_textureLabel(t)),
                trailing: _texture == t
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(t),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _texture = chosen);
    Store.instance.setString(_textureKey, chosen.name);
  }

  String _textureLabel(ShareTexture t) => switch (t) {
    ShareTexture.frame => tr('share_texture_frame'),
    ShareTexture.film => tr('share_texture_film'),
    ShareTexture.letters => tr('share_texture_letters'),
  };

  String _styleLabel(ShareCardStyle s) => switch (s) {
    ShareCardStyle.poster => tr('share_style_poster'),
    ShareCardStyle.ticket => tr('share_style_ticket'),
    ShareCardStyle.story => tr('share_style_story'),
    ShareCardStyle.quiet => tr('share_style_quiet'),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = ShareCard.sizeOf(_style);
    final media = MediaQuery.of(context);
    // Превью ужимается под ширину листа и под половину экрана по высоте:
    // «Сторис» вдвое выше «Афиши», и без потолка лист вырастает во весь экран.
    final scale = [
      (media.size.width - 44) / size.width,
      media.size.height * 0.46 / size.height,
      1.0,
    ].reduce((a, b) => a < b ? a : b);

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  tr('share_card_title'),
                  style: const TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 106,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                itemCount: ShareCardStyle.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final style = ShareCardStyle.values[i];
                  return _StyleThumb(
                    style: style,
                    label: _styleLabel(style),
                    selected: style == _style,
                    onTap: () => _pick(style),
                    onLongPress: _pickTexture,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: size.width * scale,
              height: size.height * scale,
              // OverflowBox возвращает карточке её настоящий размер: Transform
              // ужимает только картинку на экране, а снимок берётся с полного
              // холста — иначе в PNG уехал бы размер превью, а не 1080 px.
              child: OverflowBox(
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                alignment: Alignment.topLeft,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: _shotKey,
                    child: _ready
                        ? ShareCard(data: _data, style: _style)
                        : _Skeleton(
                            size: size,
                            color: scheme.surfaceContainerHigh,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || !_ready ? null : _share,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.ios_share_rounded),
                  label: Text(
                    tr('share'),
                    style: const TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              trf('share_hint_size', {
                'w': ShareCard.exportSize(_style).width.round(),
              }),
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('share_hint_texture'),
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

/// Пока грузится постер — подложка того же размера, чтобы лист не прыгал.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.size, required this.color});

  final Size size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size.width,
    height: size.height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(28),
    ),
    alignment: Alignment.center,
    child: const CircularProgressIndicator(strokeWidth: 2.4),
  );
}

/// Миниатюра стиля: схема композиции, а не уменьшенная копия карточки —
/// уменьшенная копия в 64 dp превращается в кашу.
class _StyleThumb extends StatelessWidget {
  const _StyleThumb({
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final ShareCardStyle style;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 80,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: CustomPaint(
                painter: _ThumbPainter(
                  style: style,
                  ink: scheme.onSurface,
                  accent: scheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Схема композиции стиля: прямоугольники вместо постера и текста.
class _ThumbPainter extends CustomPainter {
  const _ThumbPainter({
    required this.style,
    required this.ink,
    required this.accent,
  });

  final ShareCardStyle style;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final block = Paint()..color = ink.withValues(alpha: 0.24);
    final line = Paint()..color = ink.withValues(alpha: 0.34);
    final hot = Paint()..color = accent;
    final w = size.width, h = size.height;

    void rect(
      double x,
      double y,
      double rw,
      double rh,
      Paint p, [
      double r = 2,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, rw, rh),
          Radius.circular(r),
        ),
        p,
      );
    }

    switch (style) {
      case ShareCardStyle.poster:
        rect(w / 2 - 12, 0, 24, 34, block, 3);
        rect(w / 2 - 16, 40, 32, 4, line);
        rect(w / 2 - 10, 48, 20, 3, line);
        canvas.drawCircle(Offset(w / 2, h - 8), 7, hot);
      case ShareCardStyle.ticket:
        rect(0, 0, w, 22, block, 3);
        for (var x = 0.0; x < w; x += 6) {
          rect(x, 28, 3, 1.5, line, 1);
        }
        rect(0, 36, 16, 24, block, 2);
        rect(20, 36, w - 20, 6, hot);
        rect(20, 47, (w - 20) * 0.7, 3, line);
        rect(20, 54, (w - 20) * 0.5, 3, line);
      case ShareCardStyle.story:
        rect(0, 0, w, 26, block, 3);
        rect(0, 30, 16, 22, block, 2);
        rect(20, 32, w - 20, 4, line);
        rect(20, 40, (w - 20) * 0.6, 3, line);
        rect(0, h - 16, w, 3, line, 2);
        canvas.drawCircle(Offset(w * 0.62, h - 14.5), 6, hot);
      case ShareCardStyle.quiet:
        rect(0, 0, 22, 32, block, 2);
        rect(26, 2, w - 26, 4, line);
        rect(26, 10, (w - 26) * 0.66, 3, line);
        rect(w - 34, h - 22, 34, 9, line, 2);
        rect(w - 34, h - 9, 22, 3, hot);
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.style != style || old.ink != ink || old.accent != accent;
}
