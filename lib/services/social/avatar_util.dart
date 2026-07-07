import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Готовит аватар к загрузке: центр-кроп до квадрата и ресайз до [size]px в PNG.
/// Использует только dart:ui (без доп. пакетов). Так фото с телефона (несколько
/// МБ) ужимается до десятков КБ перед отправкой на сервер.
Future<Uint8List> resizeAvatarPng(Uint8List src, {int size = 256}) async {
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final img = frame.image;

  final side = math.min(img.width, img.height).toDouble();
  final srcRect = ui.Rect.fromLTWH(
    (img.width - side) / 2,
    (img.height - side) / 2,
    side,
    side,
  );
  final dstRect = ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
      img, srcRect, dstRect, ui.Paint()..filterQuality = ui.FilterQuality.high);
  final picture = recorder.endRecording();
  final out = await picture.toImage(size, size);
  img.dispose();

  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}
