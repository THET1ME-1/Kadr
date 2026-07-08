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

/// Готовит баннер профиля: центр-кроп до широкого [aspect] и ресайз в PNG.
/// PNG без потерь может быть тяжёлым, поэтому подбираем ширину сверху вниз, пока
/// результат не влезет в [maxBytes] (лимит сервера) — без доп. пакетов.
Future<Uint8List> resizeBannerPng(
  Uint8List src, {
  double aspect = 2.4,
  int maxBytes = 680 * 1024,
}) async {
  final codec = await ui.instantiateImageCodec(src);
  final frame = await codec.getNextFrame();
  final img = frame.image;

  // Центр-кроп до нужного соотношения сторон.
  final srcAspect = img.width / img.height;
  double cw, ch;
  if (srcAspect > aspect) {
    ch = img.height.toDouble();
    cw = ch * aspect;
  } else {
    cw = img.width.toDouble();
    ch = cw / aspect;
  }
  final srcRect = ui.Rect.fromLTWH(
      (img.width - cw) / 2, (img.height - ch) / 2, cw, ch);

  Future<Uint8List> render(int w) async {
    final h = (w / aspect).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(img, srcRect,
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high);
    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  }

  var result = await render(1080);
  for (final w in const [900, 760, 640, 540]) {
    if (result.length <= maxBytes) break;
    result = await render(w);
  }
  img.dispose();
  return result;
}
