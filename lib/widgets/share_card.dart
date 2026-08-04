import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/locale_controller.dart';
import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/score.dart';
import '../utils/share_card_data.dart';
import '../utils/share_palette.dart';
import 'app_icon_preview.dart';

/// Стили карточки «Поделиться». Выбираются лентой в самом листе.
enum ShareCardStyle {
  /// Афиша: постер по центру, кадр фильма в фоне, крупная оценка.
  poster,

  /// Билет: кадр в шапке, перфорация, поля с датой и номером просмотра.
  ticket,

  /// Сторис 9:16 с линейкой оценки — под сторис мессенджеров.
  story,

  /// Тихая: почти чёрное поле, постер и текст в строку, цвет только в полоске.
  quiet,
}

/// Всё, что карточке нужно нарисовать. Картинки приходят уже раскодированными:
/// снимок делается сразу после сборки, ждать загрузку из сети поздно.
class ShareCardData {
  const ShareCardData({
    required this.title,
    required this.palette,
    required this.facts,
    required this.footerNote,
    required this.texture,
    this.meta,
    this.poster,
    this.backdrop,
  });

  final String title;
  final String? meta;
  final SharePalette palette;
  final ShareFacts facts;

  /// Правый угол подвала: дата просмотра, «в списке», номер пересмотра.
  final String footerNote;
  final ShareTexture texture;
  final ui.Image? poster;
  final ui.Image? backdrop;
}

/// Карточка фильма для картинки, которой делятся.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data, required this.style});

  final ShareCardData data;
  final ShareCardStyle style;

  /// Размер карточки в логических пикселях.
  static Size sizeOf(ShareCardStyle style) => switch (style) {
    ShareCardStyle.poster => const Size(360, 450),
    ShareCardStyle.ticket => const Size(360, 500),
    ShareCardStyle.story => const Size(360, 640),
    ShareCardStyle.quiet => const Size(360, 450),
  };

  /// Размер готового PNG: 1080 px по ширине при [pixelRatio] 3.
  static Size exportSize(ShareCardStyle style, {double pixelRatio = 3}) {
    final s = sizeOf(style);
    return Size(s.width * pixelRatio, s.height * pixelRatio);
  }

  @override
  Widget build(BuildContext context) {
    final size = sizeOf(style);
    final radius = switch (style) {
      ShareCardStyle.poster => 32.0,
      ShareCardStyle.ticket => 26.0,
      ShareCardStyle.story => 34.0,
      ShareCardStyle.quiet => 28.0,
    };
    return SizedBox(
      width: size.width,
      height: size.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: data.palette.deep,
          child: switch (style) {
            ShareCardStyle.poster => _PosterStyle(data: data),
            ShareCardStyle.ticket => _TicketStyle(data: data),
            ShareCardStyle.story => _StoryStyle(data: data),
            ShareCardStyle.quiet => _QuietStyle(data: data),
          },
        ),
      ),
    );
  }
}

// ───────────────────────────── общие детали ─────────────────────────────

/// Обесцвечивает картинку и перекрашивает её в один тон. Одна матрица вместо
/// пары слоёв: в offscreen-рендере (снимок в PNG) слоёные blend-режимы ведут
/// себя непредсказуемо, а матрица считается прямо на пикселях.
ColorFilter _duotone(Color tint, {double gain = 1.35}) {
  final r = tint.r * gain, g = tint.g * gain, b = tint.b * gain;
  return ColorFilter.matrix(<double>[
    0.2126 * r, 0.7152 * r, 0.0722 * r, 0, 0, //
    0.2126 * g, 0.7152 * g, 0.0722 * g, 0, 0, //
    0.2126 * b, 0.7152 * b, 0.0722 * b, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}

/// Слой фона: кадр фильма, размытый постер под кромками плёнки или название
/// во всю карточку. Что именно — решает [ShareTexture], уже приведённая к тому,
/// что у фильма есть.
class _Texture extends StatelessWidget {
  const _Texture({required this.data, this.blur = 2});

  final ShareCardData data;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final p = data.palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (data.texture == ShareTexture.frame && data.backdrop != null)
          _image(data.backdrop!, blur: blur, scale: 1.08)
        else if (data.texture == ShareTexture.film && data.poster != null)
          _image(data.poster!, blur: 26, scale: 1.4)
        else
          _letters(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                p.deep.withValues(alpha: 0.20),
                p.deep.withValues(alpha: 0.58),
                p.deep.withValues(alpha: 0.94),
              ],
              stops: const [0, 0.48, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -1.1),
              radius: 1.1,
              colors: [p.accent.withValues(alpha: 0.28), Colors.transparent],
            ),
          ),
        ),
        if (data.texture == ShareTexture.film) ...[
          const Align(alignment: Alignment.centerLeft, child: _FilmEdge()),
          const Align(alignment: Alignment.centerRight, child: _FilmEdge()),
        ],
        CustomPaint(painter: _GrainPainter(seed: data.title.hashCode)),
      ],
    );
  }

  Widget _image(
    ui.Image image, {
    required double blur,
    required double scale,
  }) => ImageFiltered(
    imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
    child: Transform.scale(
      scale: scale,
      child: ColorFiltered(
        colorFilter: _duotone(data.palette.accent),
        child: RawImage(image: image, fit: BoxFit.cover),
      ),
    ),
  );

  /// Название фильма крупно и полупрозрачно — фон для записи без картинок.
  Widget _letters() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(data.palette.deep, data.palette.accent, 0.28)!,
          data.palette.deep,
        ],
      ),
    ),
    child: OverflowBox(
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 5; i++)
            Text(
              data.title.toUpperCase(),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w900,
                fontSize: 62,
                height: 0.9,
                letterSpacing: -2,
                color: Colors.white.withValues(alpha: 0.075),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Кромка киноплёнки: тёмная полоса с окошками перфорации.
class _FilmEdge extends StatelessWidget {
  const _FilmEdge();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    child: ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: LayoutBuilder(
        builder: (context, c) {
          final count = math.max(4, (c.maxHeight / 34).round());
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < count; i++)
                Container(
                  width: 11,
                  height: 15,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// Плёночное зерно: тысячи еле заметных точек. Зерно детерминировано по
/// названию фильма, поэтому карточка одного фильма всегда одинаковая.
class _GrainPainter extends CustomPainter {
  const _GrainPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final count = (size.width * size.height / 26).round();
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < count; i++) {
      final p = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      (rnd.nextBool() ? light : dark).add(p);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.045)
        ..strokeWidth = 0.8,
    );
    canvas.drawPoints(
      ui.PointMode.points,
      dark,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.055)
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.seed != seed;
}

/// Постер с обводкой-волоском. Теней нет: глубину держит контур и тон.
class _Poster extends StatelessWidget {
  const _Poster({required this.image, this.width, this.radius = 20});

  final ui.Image? image;

  /// Ширина постера. `null` — постер занимает всё, что дал родитель: так
  /// «Афиша» ужимает его, когда снизу добавилась эмоция.
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final height = width == null ? null : width! * 3 / 2;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? null
          : RawImage(
              image: image,
              fit: BoxFit.cover,
              width: width,
              height: height,
            ),
    );
  }
}

/// Подпись: знак «Засечка» и слово Kadr.
class _Signature extends StatelessWidget {
  const _Signature({this.size = 15, this.fontSize = 13, this.alpha = 0.85});

  final double size;
  final double fontSize;
  final double alpha;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: ZasechkaPainter(
            mark: Colors.white.withValues(alpha: alpha),
            background: Colors.transparent,
            scale: 0.98,
          ),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        'Kadr',
        style: TextStyle(
          fontFamily: AppTheme.displayFont,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          letterSpacing: 0.2,
          color: Colors.white.withValues(alpha: alpha),
        ),
      ),
    ],
  );
}

/// Оценка как крупное число: «6,9 / 10» цветом [scoreColor].
class _BigScore extends StatelessWidget {
  const _BigScore({required this.score, this.size = 48, this.withStar = true});

  final double score;
  final double size;
  final bool withStar;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (withStar) ...[
          Icon(Icons.star_rounded, size: size * 0.46, color: scoreColor(score)),
          const SizedBox(width: 8),
        ],
        Text(
          formatScore(score),
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: size,
            height: 1,
            letterSpacing: -1,
            color: scoreColor(score),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '/ 10',
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontWeight: FontWeight.w600,
            fontSize: size * 0.34,
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
      ],
    ),
  );
}

/// «Хочу посмотреть» — вместо оценки у фильма из списка.
class _WantChip extends StatelessWidget {
  const _WantChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(100),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.34),
        width: 1.5,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bookmark_rounded, size: 16, color: Colors.white),
        const SizedBox(width: 8),
        Text(
          tr('share_want_to_watch'),
          style: const TextStyle(
            fontFamily: AppTheme.bodyFont,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

/// Оценка 6.9 → «6,9» на русском и «6.9» на остальных языках.
String formatScore(double score) {
  final s = score.toStringAsFixed(1);
  return LocaleController.instance.code == 'ru' ? s.replaceAll('.', ',') : s;
}

// ─────────────────────────────── A. Афиша ───────────────────────────────

class _PosterStyle extends StatelessWidget {
  const _PosterStyle({required this.data});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    final f = data.facts;
    return Stack(
      fit: StackFit.expand,
      children: [
        _Texture(data: data),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
          child: Column(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _Poster(image: data.poster),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                data.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  height: 1.06,
                  color: Colors.white,
                ),
              ),
              if (data.meta != null) ...[
                const SizedBox(height: 8),
                Text(
                  data.meta!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (f.score != null)
                _BigScore(score: f.score!)
              else
                const _WantChip(),
              if (f.emotion != null) ...[
                const SizedBox(height: 10),
                _EmotionChip(emotion: f.emotion!),
              ],
              const SizedBox(height: 16),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _Signature(),
                  Flexible(
                    child: Text(
                      data.footerNote,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmotionChip extends StatelessWidget {
  const _EmotionChip({required this.emotion});

  final MovieEmotion emotion;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Text(
      '${emotion.emoji} ${emotion.label}',
      style: TextStyle(
        fontFamily: AppTheme.bodyFont,
        fontSize: 12.5,
        color: Colors.white.withValues(alpha: 0.88),
      ),
    ),
  );
}

// ─────────────────────────────── B. Билет ───────────────────────────────

class _TicketStyle extends StatelessWidget {
  const _TicketStyle({required this.data});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    final f = data.facts;
    final p = data.palette;
    return Column(
      children: [
        SizedBox(
          height: 198,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (data.backdrop != null)
                RawImage(image: data.backdrop!, fit: BoxFit.cover)
              else
                _Texture(data: data, blur: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      p.deep.withValues(alpha: 0.15),
                      p.deep.withValues(alpha: 0.55),
                      p.deep,
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 0, 26, 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (f.wantToWatch
                              ? tr('share_ticket_planned')
                              : tr('share_ticket_watched'))
                          .toUpperCase(),
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                        letterSpacing: 1.6,
                        color: p.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        height: 1.04,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 26,
          child: CustomPaint(
            painter: _PerforationPainter(deep: p.deep),
            child: const SizedBox.expand(),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Poster(image: data.poster, width: 92, radius: 14),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                        tr('share_field_score'),
                        child: f.score != null
                            ? _BigScore(
                                score: f.score!,
                                size: 36,
                                withStar: false,
                              )
                            : Text(
                                tr('share_in_list'),
                                style: const TextStyle(
                                  fontFamily: AppTheme.displayFont,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Дате нужно больше места: «03.08.2026» длиннее
                          // короткого номера просмотра.
                          Flexible(
                            flex: 3,
                            child: _field(
                              tr('share_field_date'),
                              // В поле билета длинная подпись обрезается,
                              // поэтому дата идёт числами.
                              value: f.watchedAt == null
                                  ? data.footerNote
                                  : numericDate(f.watchedAt!),
                            ),
                          ),
                          if (f.isRewatch) ...[
                            const SizedBox(width: 16),
                            Flexible(
                              flex: 2,
                              child: _field(
                                tr('share_field_view'),
                                value: trf('share_view_short', {
                                  'n': '${f.viewNumber}',
                                }),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (data.meta != null)
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              data.meta!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 150,
                height: 32,
                child: CustomPaint(
                  painter: _BarcodePainter(seed: data.title.hashCode),
                ),
              ),
              const _Signature(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String label, {String? value, Widget? child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 1.4,
          color: Colors.white.withValues(alpha: 0.42),
        ),
      ),
      const SizedBox(height: 4),
      child ??
          Text(
            value ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTheme.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
    ],
  );
}

/// Линия отрыва билета: пунктир и два круглых выреза по краям. Вырезы не
/// прозрачные — мессенджеры подставляют под альфу свой фон, и дырка стала бы
/// белым пятном.
class _PerforationPainter extends CustomPainter {
  const _PerforationPainter({required this.deep});

  final Color deep;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..strokeWidth = 2;
    for (var x = 26.0; x < size.width - 26; x += 13) {
      canvas.drawLine(Offset(x, y), Offset(x + 6, y), dash);
    }
    final cut = Paint()..color = Color.lerp(deep, Colors.black, 0.5)!;
    canvas.drawCircle(Offset(0, y), 13, cut);
    canvas.drawCircle(Offset(size.width, y), 13, cut);
  }

  @override
  bool shouldRepaint(_PerforationPainter old) => old.deep != deep;
}

/// Штрих-код из хэша фильма: у каждой карточки свой рисунок.
class _BarcodePainter extends CustomPainter {
  const _BarcodePainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.75);
    var x = 0.0;
    while (x < size.width) {
      final w = rnd.nextBool() ? 2.0 : 4.0;
      final h = 10 + rnd.nextDouble() * (size.height - 10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, w, h),
          const Radius.circular(1),
        ),
        paint,
      );
      x += w + 2.5;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.seed != seed;
}

// ─────────────────────────────── C. Сторис ──────────────────────────────

class _StoryStyle extends StatelessWidget {
  const _StoryStyle({required this.data});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    final f = data.facts;
    final p = data.palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        _Texture(data: data, blur: 16),
        Column(
          children: [
            SizedBox(
              height: 246,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (data.backdrop != null)
                    RawImage(image: data.backdrop!, fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          p.deep.withValues(alpha: 0),
                          p.deep.withValues(alpha: 0.72),
                          p.deep,
                        ],
                        stops: const [0.3, 0.74, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -86),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Poster(image: data.poster, width: 118, radius: 16),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              data.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppTheme.displayFont,
                                fontWeight: FontWeight.w800,
                                fontSize: 25,
                                height: 1.05,
                                color: Colors.white,
                              ),
                            ),
                            if (data.meta != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                data.meta!,
                                maxLines: 2,
                                style: TextStyle(
                                  fontFamily: AppTheme.bodyFont,
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(34, 0, 34, 26),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (f.score != null) ...[
                _RulerScore(score: f.score!),
                const SizedBox(height: 26),
              ] else ...[
                const _WantChip(),
                const SizedBox(height: 26),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (f.watchedAt != null)
                    _fact(Icons.event_rounded, longDate(f.watchedAt!))
                  else if (data.footerNote.isNotEmpty)
                    _fact(Icons.event_rounded, data.footerNote),
                  if (f.isRewatch)
                    _fact(
                      Icons.repeat_rounded,
                      trf('share_view_nth', {'n': '${f.viewNumber}'}),
                    ),
                ],
              ),
              if (f.emotion != null) ...[
                const SizedBox(height: 14),
                Text(
                  '${f.emotion!.emoji} ${f.emotion!.label}',
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              const _Signature(size: 17, fontSize: 14, alpha: 0.9),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fact(IconData icon, String text) => ConstrainedBox(
    // Ширина карточки минус поля: длинная дата не должна распирать чип.
    constraints: const BoxConstraints(maxWidth: 292),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.86),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Оценка «линейкой» — дорожка с делениями и круглый бегунок, как в слайдере
/// оценки внутри приложения.
class _RulerScore extends StatelessWidget {
  const _RulerScore({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final t = ((score - 1) / 9).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr('share_my_score').toUpperCase(),
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: 1.5,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
            Text(
              '10',
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: 1.5,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              alignment: Alignment.centerLeft,
              children: [
                CustomPaint(
                  size: Size(c.maxWidth, 56),
                  painter: _RulerPainter(fill: t, color: scoreColor(score)),
                ),
                Positioned(
                  left: (c.maxWidth * t - 32).clamp(0.0, c.maxWidth - 64),
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scoreColor(score),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      formatScore(score),
                      style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.5,
                        color: onScoreColor(score),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({required this.fill, required this.color});

  final double fill;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const ticks = 37;
    final y = size.height / 2;
    for (var i = 0; i < ticks; i++) {
      final x = size.width * i / (ticks - 1);
      final major = i % 4 == 0;
      canvas.drawLine(
        Offset(x, y - (major ? 11 : 6)),
        Offset(x, y + (major ? 11 : 6)),
        Paint()
          ..color = Colors.white.withValues(alpha: major ? 0.38 : 0.22)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width * fill, y),
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.fill != fill || old.color != color;
}

// ─────────────────────────────── D. Тихая ───────────────────────────────

class _QuietStyle extends StatelessWidget {
  const _QuietStyle({required this.data});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) {
    final f = data.facts;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Color.lerp(data.palette.deep, Colors.black, 0.55)!),
        if (data.poster != null)
          Opacity(
            opacity: 0.34,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Transform.scale(
                scale: 1.3,
                child: ColorFiltered(
                  colorFilter: _duotone(data.palette.accent, gain: 0.9),
                  child: RawImage(image: data.poster, fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        CustomPaint(painter: const _GridPainter()),
        CustomPaint(painter: _GrainPainter(seed: data.title.hashCode)),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Poster(image: data.poster, width: 140, radius: 14),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w700,
                              fontSize: 22,
                              height: 1.08,
                              color: Colors.white,
                            ),
                          ),
                          if (data.meta != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              data.meta!.replaceAll(' · ', '\n'),
                              style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontSize: 12.5,
                                height: 1.6,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (f.score != null) ...[
                            Text(
                              tr('share_my_score').toUpperCase(),
                              style: TextStyle(
                                fontFamily: AppTheme.bodyFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 1.6,
                                color: Colors.white.withValues(alpha: 0.38),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    formatScore(f.score!),
                                    style: const TextStyle(
                                      fontFamily: AppTheme.displayFont,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 50,
                                      height: 0.9,
                                      letterSpacing: -1.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Text(
                                    '/ 10',
                                    style: TextStyle(
                                      fontFamily: AppTheme.displayFont,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ScoreBar(score: f.score!),
                          ] else
                            const _WantChip(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _Signature(alpha: 0.8),
                  Flexible(
                    child: Text(
                      data.footerNote,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Полоска под оценкой: её длина и есть оценка.
class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 4,
      child: Stack(
        children: [
          ColoredBox(
            color: Colors.white.withValues(alpha: 0.12),
            child: const SizedBox.expand(),
          ),
          // Цветной кусок обязан растянуться сам: ColoredBox без ребёнка
          // схлопывается в ноль и полоска остаётся пустой.
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (score / 10).clamp(0.0, 1.0),
            child: ColoredBox(
              color: scoreColor(score),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Чертёжная сетка — фон «Тихой».
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 26) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
