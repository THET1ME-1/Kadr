import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/social.dart';
import '../theme/app_theme.dart';

/// Круглый аватар пользователя: фото (если загружено) либо цветная заглушка с
/// первой буквой ника. Цвет заглушки детерминированно выводится из id — у
/// каждого свой стабильный оттенок.
class UserAvatar extends StatelessWidget {
  final SocialUser user;
  final double size;
  const UserAvatar({super.key, required this.user, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final url = user.avatarUrl;
    if (url != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (c, _) => _fallback(context),
          errorWidget: (c, _, _) => _fallback(context),
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    // Стабильный оттенок из id — приятная палитра, разные буквы разных цветов.
    final hue = (user.id.hashCode % 360).abs().toDouble();
    final bg = HSLColor.fromAHSL(1, hue, 0.5, 0.55).toColor();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        user.initial,
        style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.42,
          color: Colors.white,
        ),
      ),
    );
  }
}
