import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'poster.dart';

/// Открывает постер на весь экран: затемнённый фон, зум/панорама, тап — закрыть.
void openPosterViewer(BuildContext context,
    {required String title, String? url, Object? heroTag}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      // Тап обрабатывает GestureDetector внутри (весь экран) — барьер
      // недостижим, а dismissible без semanticsLabel роняет debug-ассерт.
      pageBuilder: (_, anim, _) => FadeTransition(
        opacity: anim,
        child: _PosterViewer(title: title, url: url, heroTag: heroTag),
      ),
    ),
  );
}

class _PosterViewer extends StatelessWidget {
  final String title;
  final String? url;
  final Object? heroTag;
  const _PosterViewer({required this.title, this.url, this.heroTag});

  @override
  Widget build(BuildContext context) {
    Widget image = url != null && url!.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.contain,
            placeholder: (c, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white70)),
            errorWidget: (c, u, e) =>
                Poster(title: title, width: 260, radius: 20),
          )
        : Poster(title: title, width: 260, radius: 20);
    if (heroTag != null) image = Hero(tag: heroTag!, child: image);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: image,
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
