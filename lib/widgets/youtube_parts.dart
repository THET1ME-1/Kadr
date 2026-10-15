import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Открывает ролик или плейлист в приложении YouTube (или в браузере).
Future<void> openYouTube(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// «29:14» или «1:02:03».
String ytClock(int sec) {
  final h = sec ~/ 3600, m = sec % 3600 ~/ 60, s = sec % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Строка канала в шапке: аватар и название, белым поверх кадра.
class YtChannelLine extends StatelessWidget {
  final String name;
  final String? avatar;
  const YtChannelLine({super.key, required this.name, this.avatar});

  @override
  Widget build(BuildContext context) {
    final url = avatar;
    return Row(
      spacing: 7,
      children: [
        ClipOval(
          child: SizedBox(
            width: 20,
            height: 20,
            child: url == null
                ? const ColoredBox(
                    color: Colors.white24,
                    child: Icon(Icons.smart_display_rounded,
                        size: 14, color: Colors.white),
                  )
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (c, u, e) =>
                        const ColoredBox(color: Colors.white24),
                  ),
          ),
        ),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// Длина ролика в углу кадра, как на YouTube.
class YtDurationBadge extends StatelessWidget {
  final int sec;
  const YtDurationBadge(this.sec, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          ytClock(sec),
          style: const TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
            height: 1.4,
            color: Colors.white,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
}
