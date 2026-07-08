import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../services/tmdb_service.dart';
import '../../theme/app_theme.dart';

/// Один результат поиска (фильм или сериал).
class _MediaResult {
  final int id;
  final bool isTv;
  final String title;
  final int? year;
  final String? posterUrl;
  const _MediaResult(
      {required this.id,
      required this.isTv,
      required this.title,
      this.year,
      this.posterUrl});
}

/// Открывает поиск по TMDB, затем — выбор конкретного КАДРА (backdrop) или
/// ПОСТЕРА выбранного фильма/сериала из нескольких вариантов. Возвращает URL
/// выбранной картинки. [backdrop] = false → постер (аватар); true → кадр (баннер).
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
  int _reqId = 0;

  // Второй уровень: выбранный тайтл и его картинки.
  _MediaResult? _selected;
  List<String> _images = const [];
  bool _loadingImages = false;

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
      final moviesF = TmdbService.searchMovies(q);
      final tvF = TmdbService.searchTvShows(q);
      final movies = await moviesF;
      final tv = await tvF;
      if (id != _reqId || !mounted) return;
      final all = <_MediaResult>[
        for (final m in movies)
          if (m.posterUrl != null)
            _MediaResult(
                id: m.id,
                isTv: false,
                title: m.title,
                year: m.year,
                posterUrl: m.posterUrl),
        for (final s in tv)
          if (s.posterUrl != null)
            _MediaResult(
                id: s.id,
                isTv: true,
                title: s.title,
                year: s.year,
                posterUrl: s.posterUrl),
      ];
      setState(() {
        _results = all;
        _loading = false;
      });
    } catch (_) {
      if (id != _reqId || !mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openImages(_MediaResult r) async {
    setState(() {
      _selected = r;
      _images = const [];
      _loadingImages = true;
    });
    final imgs = await TmdbService.imagesOf(r.id, tv: r.isTv);
    if (!mounted || _selected != r) return;
    setState(() {
      _images = widget.backdrop ? imgs.backdrops : imgs.posters;
      _loadingImages = false;
    });
  }

  void _back() => setState(() {
        _selected = null;
        _images = const [];
      });

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
            _header(scheme),
            Expanded(child: _selected == null ? _searchLevel(scheme) : _imagesLevel(scheme)),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final title = _selected != null
        ? _selected!.title
        : (widget.backdrop
            ? tr('pick_media_title_backdrop')
            : tr('pick_media_title_poster'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 20, 4),
      child: Row(
        children: [
          if (_selected != null)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: _back,
              tooltip: tr('cancel'),
            )
          else
            const SizedBox(width: 16),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    color: scheme.primary)),
          ),
        ],
      ),
    );
  }

  // ------------------------------ уровень поиска ------------------------------

  Widget _searchLevel(ColorScheme scheme) {
    return Column(
      children: [
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
        Expanded(child: _searchBody(scheme)),
      ],
    );
  }

  Widget _searchBody(ColorScheme scheme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_ctl.text.trim().isEmpty) {
      return _hint(scheme, Icons.movie_filter_rounded, tr('pick_media_hint'));
    }
    if (_results.isEmpty) {
      return _hint(scheme, Icons.search_off_rounded, tr('pick_media_empty'));
    }
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
          onTap: () => _openImages(r),
        );
      },
    );
  }

  // ------------------------------ уровень кадров ------------------------------

  Widget _imagesLevel(ColorScheme scheme) {
    if (_loadingImages) return const Center(child: CircularProgressIndicator());
    if (_images.isEmpty) {
      return _hint(scheme, Icons.image_not_supported_rounded,
          tr('pick_media_no_images'));
    }
    // Баннер — широкие кадры списком; аватар — постеры сеткой.
    if (widget.backdrop) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        itemCount: _images.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => Navigator.pop(context, _images[i]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: _images[i],
                fit: BoxFit.cover,
                placeholder: (c, _) =>
                    ColoredBox(color: scheme.surfaceContainerHighest),
                errorWidget: (c, _, _) =>
                    ColoredBox(color: scheme.surfaceContainerHighest),
              ),
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.66,
      ),
      itemCount: _images.length,
      itemBuilder: (context, i) => _tappableImage(
        url: _images[i],
        radius: 16,
        onTap: () => Navigator.pop(context, _images[i]),
      ),
    );
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
