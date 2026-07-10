import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../l10n/locale_controller.dart';

/// Одна кино-новость из ленты.
class NewsItem {
  final String title;
  final String link;
  final String? source;
  final DateTime? date;
  const NewsItem(
      {required this.title, required this.link, this.source, this.date});
}

/// Кино-новости через Google News RSS — бесплатно, без ключа, по языку и
/// региону интерфейса. Возвращает пустой список при ошибке сети.
class NewsService {
  /// Поисковый запрос под язык интерфейса (кино/фильмы/сериалы).
  static const Map<String, String> _queries = {
    'ru': 'кино OR сериалы OR фильмы',
    'en': 'movies OR "TV series" OR cinema',
    'de': 'Kino OR Filme OR Serien',
    'fr': 'cinéma OR films OR séries',
    'es': 'cine OR películas OR series',
    'it': 'cinema OR film OR serie TV',
    'pt': 'cinema OR filmes OR séries',
  };

  static Future<List<NewsItem>> fetch() async {
    final lang = LocaleController.instance.code;
    final region = LocaleController.instance.tmdbRegion;
    final query = _queries[lang] ?? 'movies OR series OR cinema';
    final uri = Uri.parse('https://news.google.com/rss/search').replace(
      queryParameters: {
        'q': query,
        'hl': lang,
        'gl': region,
        'ceid': '$region:$lang',
      },
    );
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return [];
      final doc = XmlDocument.parse(utf8.decode(resp.bodyBytes));
      final out = <NewsItem>[];
      for (final item in doc.findAllElements('item').take(40)) {
        final title = item.getElement('title')?.innerText.trim() ?? '';
        final link = item.getElement('link')?.innerText.trim() ?? '';
        if (title.isEmpty || link.isEmpty) continue;
        out.add(NewsItem(
          title: title,
          link: link,
          source: item.getElement('source')?.innerText.trim(),
          date: _parseDate(item.getElement('pubDate')?.innerText.trim()),
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return HttpDate.parse(s).toLocal(); // RFC 822 (Google News)
    } catch (_) {
      return null;
    }
  }
}
