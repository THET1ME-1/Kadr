import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/share_palette.dart';

/// Общее у картинок, которыми делятся: карточки фильма и сетки оценок.

/// Раскодирует постер или кадр заранее: снимок делается за один кадр, ждать
/// загрузку из сети в момент рендера уже поздно — в PNG попадёт пустота.
/// Локальный путь (свой постер) читается с диска.
Future<ui.Image?> decodeShareImage(String? url) async {
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
Future<SharePalette> sharePaletteOfImage(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return SharePalette.fallback;
  return sharePaletteFromPixels(data.buffer.asUint8List(), stride: 7);
}

/// Снимает [RepaintBoundary] под ключом [key] в PNG (1080 px при ширине
/// 360 dp) и открывает системный «Поделиться». `false` — снять не вышло.
Future<bool> shareBoundaryPng(
  GlobalKey key, {
  required String fileName,
  required String subject,
}) async {
  // Кадр с превью уже отрисован, но дадим слоям фильтров осесть.
  await Future<void>.delayed(const Duration(milliseconds: 80));
  final boundary = key.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
  if (boundary == null) return false;
  final image = await boundary.toImage(pixelRatio: 3);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) return false;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  await Share.shareXFiles([
    XFile(file.path, mimeType: 'image/png'),
  ], subject: subject);
  return true;
}
