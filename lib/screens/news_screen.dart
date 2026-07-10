import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../services/news_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';

/// Раздел «Кино-новости»: лента из Google News RSS по языку интерфейса.
/// Тап по новости открывает статью во внешнем браузере.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  bool _loading = true;
  List<NewsItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await NewsService.fetch();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('drawer_news'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? EmptyState(
                  icon: Icons.newspaper_rounded,
                  title: tr('news_empty_title'),
                  subtitle: tr('news_empty_sub'),
                  action: FilledButton.tonal(
                      onPressed: _load, child: Text(tr('retry'))),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (c, i) => _row(scheme, _items[i]),
                  ),
                ),
    );
  }

  Widget _row(ColorScheme scheme, NewsItem n) {
    final meta = [
      if (n.source != null && n.source!.isNotEmpty) n.source!,
      if (n.date != null) _rel(n.date!),
    ].join(' · ');
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            launchUrl(Uri.parse(n.link), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.title,
                  style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      height: 1.25,
                      color: scheme.onSurface)),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(meta,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 12,
                        color: scheme.primary)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _rel(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inHours < 1) return tr('news_recent');
    if (diff.inHours < 24) return trf('news_hours_ago', {'n': diff.inHours});
    return trf('news_days_ago', {'n': diff.inDays});
  }
}
