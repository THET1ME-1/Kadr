import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/share_export.dart';
import '../services/store.dart';
import '../theme/app_theme.dart';
import '../utils/episode_grid.dart';
import '../utils/format.dart';
import '../utils/share_palette.dart';
import '../widgets/episode_grid_card.dart';

/// Нижний лист «Поделиться сеткой»: превью картинки с оценками всех серий,
/// переключатель чисел в клетках и кнопка, которая снимает PNG.
///
/// [seasonSizes] — число серий в сезоне, как их показывает экран сериала.
Future<void> showEpisodeGridSheet(
  BuildContext context,
  LibrarySeries series,
  Map<int, int> seasonSizes,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _EpisodeGridSheet(series: series, seasonSizes: seasonSizes),
  );
}

class _EpisodeGridSheet extends StatefulWidget {
  const _EpisodeGridSheet({required this.series, required this.seasonSizes});

  final LibrarySeries series;
  final Map<int, int> seasonSizes;

  @override
  State<_EpisodeGridSheet> createState() => _EpisodeGridSheetState();
}

class _EpisodeGridSheetState extends State<_EpisodeGridSheet> {
  static const _numbersKey = 'gridShowNumbers';

  final _shotKey = GlobalKey();
  late final EpisodeGrid _grid = buildEpisodeGrid(
    widget.series,
    widget.seasonSizes,
  );

  bool _numbers = true;
  SharePalette _palette = SharePalette.fallback;
  ui.Image? _poster;
  bool _busy = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Store.instance.getBool(_numbersKey, def: true).then((v) {
      if (mounted) setState(() => _numbers = v);
    });
    _loadPoster();
  }

  @override
  void dispose() {
    _poster?.dispose();
    super.dispose();
  }

  Future<void> _loadPoster() async {
    final poster = await decodeShareImage(widget.series.displayPoster);
    final palette = poster == null
        ? SharePalette.fallback
        : await sharePaletteOfImage(poster);
    if (!mounted) {
      poster?.dispose();
      return;
    }
    setState(() {
      _poster = poster;
      _palette = palette;
      _ready = true;
    });
  }

  EpisodeGridCardData get _data {
    final now = DateTime.now();
    return EpisodeGridCardData(
      title: widget.series.displayTitle,
      year: widget.series.year,
      palette: _palette,
      grid: _grid,
      poster: _poster,
      showNumbers: _numbers,
      dateNote: '${dayMonth(now)} ${now.year}',
    );
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await shareBoundaryPng(
        _shotKey,
        fileName: 'kadr_grid_${widget.series.tvShowId}',
        subject: 'Kadr · ${widget.series.displayTitle}',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('share_failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleNumbers(bool v) {
    setState(() => _numbers = v);
    Store.instance.setBool(_numbersKey, v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final size = GridLayout.of(_grid).size;
    // Превью ужимается только по ширине: сетка длинного сериала выше экрана,
    // её листают внутри окна, а кнопка остаётся на месте.
    final scale = ((media.size.width - 44) / size.width).clamp(0.0, 1.0);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                tr('grid_sheet_title'),
                style: const TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.58),
            child: SingleChildScrollView(
              child: SizedBox(
                width: size.width * scale,
                height: size.height * scale,
                // OverflowBox возвращает карточке настоящий размер: Transform
                // ужимает только картинку на экране, а снимок берётся с полного
                // холста — иначе в PNG уехал бы размер превью, а не 1080 px.
                child: OverflowBox(
                  minWidth: size.width,
                  maxWidth: size.width,
                  minHeight: size.height,
                  maxHeight: size.height,
                  alignment: Alignment.topLeft,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      key: _shotKey,
                      child: _ready
                          ? EpisodeGridCard(data: _data)
                          : Container(
                              width: size.width,
                              height: size.height,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              alignment: Alignment.topCenter,
                              padding: const EdgeInsets.only(top: 120),
                              child: const CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _toggleNumbers(!_numbers),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('grid_numbers'),
                        style: const TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(value: _numbers, onChanged: _toggleNumbers),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || !_ready ? null : _share,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(
                  tr('share'),
                  style: const TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            trf('share_hint_size', {'w': (size.width * 3).round()}),
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
