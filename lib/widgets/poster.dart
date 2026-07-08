import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Постер фильма. Если [url] задан — грузит из сети (kinopoisk.dev), иначе
/// рисует выразительную плашку-заглушку: градиент по хэшу названия + инициалы.
class Poster extends StatelessWidget {
  final String? url;
  final String title;
  final double width;
  final double radius;

  /// Тег для shared-element анимации (Hero): постер «летит» и меняет размер из
  /// списка в карточку фильма/сериала. null — без анимации.
  final String? heroTag;

  const Poster({
    super.key,
    required this.title,
    this.url,
    this.width = 64,
    this.radius = 16,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final content = _content(context);
    return heroTag != null ? Hero(tag: heroTag!, child: content) : content;
  }

  Widget _content(BuildContext context) {
    final height = width * 3 / 2;
    final border = BorderRadius.circular(radius);
    if (url != null && url!.isNotEmpty) {
      // Декодируем постер под фактический размер на экране (в пикселях), а не в
      // полном разрешении — иначе прокрутка списка/сетки лагает на декодинге.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final decodeW = (width * dpr).round();
      return ClipRRect(
        borderRadius: border,
        child: CachedNetworkImage(
          imageUrl: url!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          memCacheWidth: decodeW,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (c, _) => _placeholder(c),
          errorWidget: (c, url, error) => _placeholder(c),
        ),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final height = width * 3 / 2;
    final hue = (title.hashCode % 360).abs().toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.45, 0.42).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.45, 0.28).toColor();
    final initials = title.isEmpty
        ? '?'
        : title
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w.characters.first)
            .join()
            .toUpperCase();
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_rounded,
              size: width * 0.34, color: Colors.white.withValues(alpha: 0.85)),
          if (width >= 56) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                initials,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: width * 0.22,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
