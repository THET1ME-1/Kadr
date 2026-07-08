import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/social.dart';

/// Обложка профиля: загруженный баннер (если есть) либо мягкий M3-градиент,
/// детерминированно выведенный из id пользователя (у каждого свой стабильный
/// оттенок). Снизу — лёгкий скрим, чтобы наложенные аватар/имя читались.
class ProfileBanner extends StatelessWidget {
  final SocialUser user;
  final double height;
  final BorderRadius borderRadius;

  const ProfileBanner({
    super.key,
    required this.user,
    this.height = 168,
    this.borderRadius =
        const BorderRadius.vertical(bottom: Radius.circular(28)),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = user.bannerUrl;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (c, _) => _gradient(scheme),
                errorWidget: (c, _, _) => _gradient(scheme),
              )
            else
              _gradient(scheme),
            // Скрим снизу — для читаемости аватара/имени поверх светлой картинки.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.28),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Заглушка-градиент: два оттенка из стабильного hue пользователя, замешанные
  /// с primary текущей темы — вписывается и в светлую, и в тёмную схему.
  Widget _gradient(ColorScheme scheme) {
    final hue = (user.id.hashCode % 360).abs().toDouble();
    final a = HSLColor.fromAHSL(1, hue, 0.55, 0.42).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.30).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(scheme.primary.withValues(alpha: 0.22), a),
            b,
          ],
        ),
      ),
    );
  }
}
