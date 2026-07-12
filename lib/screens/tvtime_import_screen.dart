import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/tvtime_import_service.dart';
import '../theme/app_theme.dart';

enum _Phase { idle, loading, done, error }

/// Экран переноса библиотеки из TV Time (Material 3 Expressive).
/// Выбор `gdpr-data.zip` → круговая волнистая анимация прогресса → сводка с
/// «тикающими» счётчиками → продолжение (онбординг ведёт к вводу ключа TMDB).
class TvTimeImportScreen extends StatefulWidget {
  /// Вызывается по «Продолжить» после успешного импорта. null (из настроек) —
  /// просто закрыть экран.
  final VoidCallback? onContinue;
  const TvTimeImportScreen({super.key, this.onContinue});

  @override
  State<TvTimeImportScreen> createState() => _TvTimeImportScreenState();
}

class _TvTimeImportScreenState extends State<TvTimeImportScreen>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.idle;
  TvTimeImportResult? _result;

  // Прогресс кольца (0..1) — анимируется плавно, не привязан жёстко к скорости
  // реальной работы (даёт «вау»-загрузку даже когда импорт быстрый).
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));
  // Непрерывная фаза волны (мерцание синусоиды).
  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();

  @override
  void dispose() {
    _ring.dispose();
    _wave.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final bytes = await TvTimeImportService.pickZipBytes();
    if (!mounted || bytes == null) return; // отмена выбора — остаёмся на idle
    setState(() {
      _phase = _Phase.loading;
      _result = null;
    });
    _ring.value = 0;
    // Кольцо плавно доходит до 92% за 2с; параллельно идёт реальный импорт.
    final ringFill = _ring.animateTo(0.92, curve: AppTheme.emphasized);
    final res = await TvTimeImportService.importFromZipBytes(bytes);
    try {
      await ringFill; // дождаться, чтобы загрузка всегда была плавной (≥2с)
    } catch (_) {}
    if (!mounted) return;
    _result = res;
    // Финальный штрих кольца до 100%.
    try {
      await _ring.animateTo(1,
          duration: const Duration(milliseconds: 480),
          curve: AppTheme.emphasizedDecelerate);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _phase = res.error != null ? _Phase.error : _Phase.done);
  }

  void _continue() {
    if (widget.onContinue != null) {
      widget.onContinue!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('tvtime_title')),
        automaticallyImplyLeading: _phase != _Phase.loading,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: AppTheme.emphasizedDecelerate,
          child: switch (_phase) {
            _Phase.idle => _idle(scheme),
            _Phase.loading => _loading(scheme),
            _Phase.done => _done(scheme),
            _Phase.error => _error(scheme),
          },
        ),
      ),
    );
  }

  // ------------------------------- IDLE -------------------------------
  Widget _idle(ColorScheme scheme) => ListView(
        key: const ValueKey('idle'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          // Логотип TV Time → Kadr.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B1B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Image.asset('assets/tvtime_logo.png', height: 30),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Icons.arrow_forward_rounded,
                      color: scheme.primary, size: 26),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset('assets/icon/app_icon.png',
                      height: 54, width: 54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(tr('tvtime_headline'),
              style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  height: 1.15,
                  color: scheme.onSurface)),
          const SizedBox(height: 8),
          Text(tr('tvtime_sub'),
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14.5,
                  height: 1.45,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          // Что переносится.
          _card(scheme, [
            _bullet(scheme, Icons.movie_rounded, tr('tvtime_what_movies')),
            _bullet(scheme, Icons.live_tv_rounded, tr('tvtime_what_series')),
            _bullet(scheme, Icons.star_rounded, tr('tvtime_what_ratings')),
            _bullet(scheme, Icons.bookmark_rounded, tr('tvtime_what_watchlist')),
            _bullet(scheme, Icons.playlist_add_check_rounded,
                tr('tvtime_what_lists')),
          ]),
          const SizedBox(height: 16),
          // Как получить файл.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    size: 20, color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr('tvtime_how'),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 13,
                          height: 1.45,
                          color: scheme.onTertiaryContainer)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _run,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: const Icon(Icons.folder_open_rounded, size: 20),
              label: Text(tr('tvtime_pick'),
                  style: const TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
          ),
        ],
      );

  // ------------------------------ LOADING ------------------------------
  Widget _loading(ColorScheme scheme) => Center(
        key: const ValueKey('loading'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: AnimatedBuilder(
                animation: Listenable.merge([_ring, _wave]),
                builder: (_, _) {
                  final p = _ring.value;
                  return CustomPaint(
                    painter: _WavyRingPainter(
                      progress: p,
                      phase: _wave.value * 2 * pi,
                      color: scheme.primary,
                      track: scheme.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: Text('${(p * 100).round()}%',
                          style: TextStyle(
                              fontFamily: AppTheme.displayFont,
                              fontWeight: FontWeight.w800,
                              fontSize: 34,
                              color: scheme.onSurface)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 34),
            AnimatedBuilder(
              animation: _ring,
              builder: (_, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _statusText(_ring.value),
                  key: ValueKey(_statusText(_ring.value)),
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 15,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      );

  String _statusText(double p) {
    if (p < 0.33) return tr('tvtime_st_unzip');
    if (p < 0.66) return tr('tvtime_st_read');
    if (p < 0.92) return tr('tvtime_st_import');
    return tr('tvtime_st_finish');
  }

  // ------------------------------- DONE -------------------------------
  Widget _done(ColorScheme scheme) {
    final r = _result!;
    return ListView(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      children: [
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: AppTheme.emphasizedDecelerate,
            builder: (_, v, child) =>
                Transform.scale(scale: 0.6 + 0.4 * v, child: child),
            child: Container(
              width: 92,
              height: 92,
              decoration:
                  BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded,
                  size: 52, color: scheme.onPrimaryContainer),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(tr('tvtime_done_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: scheme.onSurface)),
        const SizedBox(height: 6),
        Text(tr('tvtime_done_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 14,
                height: 1.4,
                color: scheme.onSurfaceVariant)),
        const SizedBox(height: 26),
        Row(
          children: [
            _stat(scheme, r.movies, tr('tvtime_stat_movies'), Icons.movie_rounded),
            const SizedBox(width: 12),
            _stat(scheme, r.series, tr('tvtime_stat_series'), Icons.live_tv_rounded),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _stat(scheme, r.episodes, tr('tvtime_stat_episodes'),
                Icons.playlist_play_rounded),
            const SizedBox(width: 12),
            _stat(scheme, r.moviesRated, tr('tvtime_stat_rated'), Icons.star_rounded),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Icon(Icons.image_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr('tvtime_posters_note'),
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _continue,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(
                widget.onContinue != null ? tr('tvtime_continue') : tr('done'),
                style: const TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ),
        ),
      ],
    );
  }

  // ------------------------------- ERROR ------------------------------
  Widget _error(ColorScheme scheme) => Center(
        key: const ValueKey('error'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 64, color: scheme.error),
              const SizedBox(height: 18),
              Text(tr('tvtime_error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: scheme.onSurface)),
              const SizedBox(height: 8),
              Text(tr('tvtime_error_sub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13.5,
                      height: 1.4,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => setState(() => _phase = _Phase.idle),
                child: Text(tr('tvtime_retry')),
              ),
            ],
          ),
        ),
      );

  // ------------------------------ helpers ------------------------------
  Widget _card(ColorScheme scheme, List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24)),
        child: Column(children: children),
      );

  Widget _bullet(ColorScheme scheme, IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 14.5,
                      color: scheme.onSurface)),
            ),
          ],
        ),
      );

  Widget _stat(ColorScheme scheme, int value, String label, IconData icon) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(22)),
          child: Column(
            children: [
              Icon(icon, color: scheme.primary, size: 24),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.toDouble()),
                duration: const Duration(milliseconds: 1100),
                curve: AppTheme.emphasizedDecelerate,
                builder: (_, v, _) => Text('${v.round()}',
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: scheme.onSurface)),
              ),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
}

/// Круговой волнистый индикатор прогресса (M3 Expressive «wavy»): активная дуга
/// рисуется синусоидой, амплитуда сглаживается к финишу, ведущая точка на конце.
class _WavyRingPainter extends CustomPainter {
  final double progress; // 0..1
  final double phase; // радианы (мерцание волны)
  final Color color;
  final Color track;

  _WavyRingPainter(
      {required this.progress,
      required this.phase,
      required this.color,
      required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const stroke = 7.0;
    final radius = size.width / 2 - stroke - 7;
    final p = progress.clamp(0.0, 1.0);
    // Амплитуда волны спадает к 100% (кольцо «разглаживается»).
    final amp = 5.5 * (1 - p * 0.85);

    // Трек (неактивная часть) — тонкое ровное кольцо.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.55
        ..strokeCap = StrokeCap.round,
    );

    if (p <= 0) return;

    // Активная волнистая дуга.
    const start = -pi / 2;
    final sweep = 2 * pi * p;
    const waves = 14;
    final steps = max(4, (p * 260).round());
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final a = start + sweep * t;
      final r = radius + amp * sin(waves * (sweep * t) + phase);
      final pt = center + Offset(cos(a) * r, sin(a) * r);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Ведущая точка на конце дуги.
    if (p < 1) {
      final a = start + sweep;
      final r = radius + amp * sin(waves * sweep + phase);
      canvas.drawCircle(center + Offset(cos(a) * r, sin(a) * r), stroke * 0.85,
          Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_WavyRingPainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.color != color ||
      old.track != track;
}
