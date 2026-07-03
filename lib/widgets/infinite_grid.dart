import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import 'reveal.dart';

/// Бесконечная сетка постеров с ленивой подгрузкой по мере прокрутки.
///
/// [loader] отдаёт страницу элементов (1-based). Когда страница приходит пустой —
/// лента считается исчерпанной. Используется в «Обзоре»/«В кино», подборках по
/// жанру и т.п.
class InfiniteGrid<T> extends StatefulWidget {
  final Future<List<T>> Function(int page) loader;
  final Widget Function(BuildContext context, T item, double width) itemBuilder;

  /// При изменении сбрасывает ленту и грузит заново (напр. новый поисковый
  /// запрос). Загрузчик-замыкание пересоздаётся на каждый rebuild, поэтому
  /// сравнивать по нему нельзя — используем явный ключ.
  final Object? reloadKey;

  /// Доп. высота под подписью карточки (постер = width*1.5, плюс это).
  final double textExtra;
  final double minTile;
  final EdgeInsets padding;
  const InfiniteGrid({
    super.key,
    required this.loader,
    required this.itemBuilder,
    this.reloadKey,
    this.textExtra = 48,
    this.minTile = 130,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 96),
  });

  @override
  State<InfiniteGrid<T>> createState() => _InfiniteGridState<T>();
}

class _InfiniteGridState<T> extends State<InfiniteGrid<T>>
    with AutomaticKeepAliveClientMixin {
  final _sc = ScrollController();
  final List<T> _items = [];
  int _page = 0;
  bool _loading = false;
  bool _done = false;

  /// Поколение ленты: растёт при каждом сбросе, чтобы отбрасывать ответы
  /// страниц, прилетевшие уже после смены запроса.
  int _gen = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    _loadMore();
  }

  @override
  void didUpdateWidget(covariant InfiniteGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) _reset();
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_sc.position.pixels > _sc.position.maxScrollExtent - 700) _loadMore();
  }

  void _reset() {
    _gen++;
    setState(() {
      _items.clear();
      _page = 0;
      _done = false;
      _loading = false;
    });
    _loadMore();
    if (_sc.hasClients) _sc.jumpTo(0);
  }

  /// Pull-to-refresh: полный сброс и загрузка первой страницы заново.
  Future<void> _refresh() async {
    _gen++;
    _items.clear();
    _page = 0;
    _done = false;
    _loading = false;
    await _loadMore();
  }

  /// Догрузить ещё после «конца ленты» — сетевые сбои TmdbService выглядят как
  /// пустая страница, поэтому конец не считаем окончательным.
  void _retryMore() {
    _done = false;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    final gen = _gen;
    setState(() => _loading = true);
    final next = _page + 1;
    final list = await widget.loader(next);
    if (!mounted || gen != _gen) return; // лента уже сброшена — ответ устарел
    setState(() {
      _page = next;
      _loading = false;
      if (list.isEmpty) {
        _done = true;
      } else {
        _items.addAll(list);
      }
      // TMDB отдаёт максимум 500 страниц; страхуемся.
      if (next >= 500) _done = true;
    });
    // Контент короче экрана → скролл-событий не будет — догружаем сами,
    // пока лента не заполнит вьюпорт (или не закончится).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _done || _loading) return;
      if (_sc.hasClients && _sc.position.maxScrollExtent <= 0) _loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_page == 0 && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _done) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 52, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(tr('nothing_found'),
                style: const TextStyle(
                    fontFamily: AppTheme.bodyFont, fontSize: 15)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _reset, child: Text(tr('retry'))),
          ],
        ),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      const spacing = 12.0;
      final avail = c.maxWidth - widget.padding.horizontal;
      final cols = (avail / widget.minTile).floor().clamp(2, 6);
      final w = (avail - spacing * (cols - 1)) / cols;
      final tileHeight = w * 1.5 + widget.textExtra;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _sc,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: widget.padding,
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: 18,
                  mainAxisExtent: tileHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Reveal(
                    delay: Duration(milliseconds: (i % cols) * 40),
                    child: widget.itemBuilder(context, _items[i], w),
                  ),
                  childCount: _items.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 90, top: 4),
                child: Center(
                  child: _loading
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : (_done && _items.isNotEmpty
                          // Пустая страница может быть и сетевым сбоем —
                          // даём догрузить вручную.
                          ? TextButton.icon(
                              onPressed: _retryMore,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: Text(tr('load_more')),
                            )
                          : const SizedBox.shrink()),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
