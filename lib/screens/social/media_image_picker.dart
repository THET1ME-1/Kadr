import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';

/// Один результат поиска (фильм или сериал) — только то, что нужно пикеру.
class _MediaResult {
  final String title;
  final int? year;
  final String? posterUrl;
  final String? backdropUrl;
  const _MediaResult(
      {required this.title, this.year, this.posterUrl, this.backdropUrl});
}

/// Открывает поиск по TMDB и возвращает URL выбранной картинки.
/// [backdrop] = false → постер (для аватара); true → кадр/бэкдроп (для баннера).
Future<String?> showMediaImagePicker(BuildContext context,
    {required bool backdrop}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => _MediaPickerSheet(backdrop: backdrop),
  );
}

class _MediaPickerSheet extends StatefulWidget {
  final bool backdrop;
  const _MediaPickerSheet({required this.backdrop});

  @override
  State<_MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<_MediaPickerSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<_MediaResult> _results = const [];
  bool _loading = false;
  int _reqId = 0; // отбрасываем ответы устаревших запросов

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 380), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    final id = ++_reqId;
    setState(() => _loading = true);
    try {
      // Фильмы и сериалы — параллельно.
      final moviesF = TmdbService.searchMovies(q);
      final tvF = TmdbService.searchTvShows(q);
      final movies = await moviesF;
      final tv = await tvF;
      if (id != _reqId || !mounted) return;
      final all = <_MediaResult>[
        for (final m in movies)
          _MediaResult(
              title: m.title,
              year: m.year,
              posterUrl: m.posterUrl,
              backdropUrl: m.backdropUrl),
        for (final s in tv)
          _MediaResult(
              title: s.title,
              year: s.year,
              posterUrl: s.posterUrl,
              backdropUrl: s.backdropUrl),
      ];
      // Оставляем только с нужной картинкой.
      final filtered = all
          .where((r) =>
              widget.backdrop ? r.backdropUrl != null : r.posterUrl != null)
          .toList();
      setState(() {
        _results = filtered;
        _loading = false;
      });
    } catch (_) {
      if (id != _reqId || !mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    widget.backdrop
                        ? tr('pick_media_title_backdrop')
                        : tr('pick_media_title_poster'),
                    style: TextStyle(
                        fontFamily: AppTheme.displayFont,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        color: scheme.primary)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: TextField(
                controller: _ctl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                style: const TextStyle(fontFamily: AppTheme.bodyFont),
                decoration: InputDecoration(
                  hintText: tr('pick_media_search'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(child: _body(scheme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_ctl.text.trim().isEmpty) {
      return _hint(scheme, Icons.movie_filter_rounded, tr('pick_media_hint'));
    }
    if (_results.isEmpty) {
      return _hint(scheme, Icons.search_off_rounded, tr('pick_media_empty'));
    }
    return widget.backdrop ? _backdropList() : _posterGrid();
  }

  Widget _hint(ColorScheme scheme, IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: scheme.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 14,
                      height: 1.35,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );

  /// Постеры сеткой (для аватара).
  Widget _posterGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final r = _results[i];
        return _tappableImage(
          url: r.posterUrl!,
          radius: 16,
          onTap: () => Navigator.pop(context, r.posterUrl),
        );
      },
    );
  }

  /// Кадры-бэкдропы списком (для баннера) с подписью.
  Widget _backdropList() {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final r = _results[i];
        return GestureDetector(
          onTap: () => Navigator.pop(context, r.backdropUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: r.backdropUrl!,
                    fit: BoxFit.cover,
                    placeholder: (c, _) =>
                        ColoredBox(color: scheme.surfaceContainerHighest),
                    errorWidget: (c, _, _) =>
                        ColoredBox(color: scheme.surfaceContainerHighest),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.0),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 10,
                    child: Text(
                      r.year != null ? '${r.title} · ${r.year}' : r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tappableImage(
      {required String url,
      required double radius,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (c, _) =>
              ColoredBox(color: scheme.surfaceContainerHighest),
          errorWidget: (c, _, _) =>
              ColoredBox(color: scheme.surfaceContainerHighest),
        ),
      ),
    );
  }
}
