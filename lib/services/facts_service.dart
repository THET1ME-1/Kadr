import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_keys.dart';
import 'movie_source.dart';
import 'store.dart';

/// Факт о фильме или человеке — «Знаете ли вы» с Кинопоиска.
class KpFact {
  final String text;

  /// Киноляп (`type == 'BLOOPER'`), а не просто факт — показываем отдельно.
  final bool blooper;

  /// Раскрывает сюжет: прячем под тап, пока пользователь сам не откроет.
  final bool spoiler;

  const KpFact({required this.text, this.blooper = false, this.spoiler = false});

  Map<String, dynamic> toJson() => {
        'v': text,
        if (blooper) 'b': true,
        if (spoiler) 's': true,
      };

  factory KpFact.fromCache(Map<String, dynamic> j) => KpFact(
        text: j['v'] as String? ?? '',
        blooper: j['b'] == true,
        spoiler: j['s'] == true,
      );
}

/// Интересные факты из ПоискКино (kinopoisk.dev): у фильмов — факты и киноляпы,
/// у персон — факты.
///
/// TMDB такого не отдаёт вообще, поэтому блок работает только с ключом
/// ПоискКино. Тариф там жёсткий (демо — 200 запросов в сутки), поэтому запрос
/// идёт лениво при открытии карточки, ответ ложится в кэш на полгода, а промах
/// («такого фильма у КП нет») запоминается на две недели — иначе каждое
/// открытие карточки жгло бы лимит впустую.
class FactsService {
  FactsService._();

  static const Duration _ttl = Duration(days: 180);
  static const Duration _missTtl = Duration(days: 14);

  /// Есть ли ключ ПоискКино. Без него блок фактов не показываем совсем.
  static bool get available => ApiKeys.kinopoiskKey.trim().isNotEmpty;

  static Map<String, String> get _headers => {
        'X-API-KEY': ApiKeys.kinopoiskKey,
        'accept': 'application/json',
      };

  /// Факты фильма. Идентификаторы пробуем по убыванию надёжности:
  /// известный `kinopoiskId` → `imdbId` → поиск по названию и году.
  static Future<List<KpFact>> forMovie({
    int? kinopoiskId,
    String? imdbId,
    required String title,
    int? year,
  }) async {
    if (!available) return const [];
    final imdb = imdbId?.trim() ?? '';
    try {
      var kpId = kinopoiskId;
      if (kpId == null && imdb.isNotEmpty) {
        final mapped = await _cachedId('mi', _key(imdb));
        if (mapped == -1) return const [];
        kpId = mapped;
      }
      if (kpId != null) {
        final cached = await _cachedFacts('m', kpId);
        if (cached != null) return cached;
      }
      if (kpId == null && imdb.isNotEmpty) {
        // Один запрос отдаёт и id, и факты — imdbId тут самый дешёвый путь.
        final doc = await _docFrom('/v1.4/movie', {
          'externalId.imdb': imdb,
          'limit': '1',
          'selectFields': ['id', 'facts'],
        });
        final id = (doc?['id'] as num?)?.toInt();
        await _cacheId('mi', _key(imdb), id ?? -1);
        if (id != null) {
          final facts = _parseFacts(doc!['facts']);
          await _cacheFacts('m', id, facts);
          return facts;
        }
      }
      kpId ??= await _searchMovieId(title, year);
      if (kpId == null) return const [];
      final cached = await _cachedFacts('m', kpId);
      if (cached != null) return cached;
      final doc = await _docFrom('/v1.4/movie', {
        'id': '$kpId',
        'limit': '1',
        'selectFields': ['id', 'facts'],
      });
      final facts = _parseFacts(doc?['facts']);
      await _cacheFacts('m', kpId, facts);
      return facts;
    } on SourceLimitException {
      return const []; // лимит на сегодня выбран — молча ничего не показываем
    } catch (e) {
      debugPrint('facts movie error: $e');
      return const [];
    }
  }

  /// Факты о человеке. Персону ищем по имени: русское отдаёт TMDB на русской
  /// локали, латинские варианты берём из `also_known_as`.
  static Future<List<KpFact>> forPerson({
    required String name,
    List<String> aliases = const [],
  }) async {
    if (!available || name.trim().isEmpty) return const [];
    try {
      final nameKey = _nameKey(name);
      var personId = await _cachedId('pn', nameKey);
      if (personId == -1) return const [];
      if (personId != null) {
        final cached = await _cachedFacts('p', personId);
        if (cached != null) return cached;
      } else {
        personId = await _findPerson(name, aliases);
        await _cacheId('pn', nameKey, personId ?? -1);
        if (personId == null) return const [];
      }
      final doc = await _docFrom('/v1.4/person', {
        'id': '$personId',
        'limit': '1',
        'selectFields': ['id', 'facts'],
      });
      final facts = _parseFacts(doc?['facts']);
      await _cacheFacts('p', personId, facts);
      return facts;
    } on SourceLimitException {
      return const [];
    } catch (e) {
      debugPrint('facts person error: $e');
      return const [];
    }
  }

  /// Ищет персону по имени. Берём только точное совпадение имени (русского или
  /// латинского) — однофамильцев в базе КП много, а чужие факты хуже пустоты.
  static Future<int?> _findPerson(String name, List<String> aliases) async {
    final wanted = {_nameKey(name), for (final a in aliases) _nameKey(a)}
      ..remove('');
    final data = await _getJson(
        Uri.parse('${ApiConfig.kinopoiskBase}/v1.4/person/search').replace(
            queryParameters: {'query': name, 'limit': '10', 'page': '1'}));
    final docs = (data?['docs'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final d in docs) {
      final names = {
        _nameKey(d['name'] as String? ?? ''),
        _nameKey(d['enName'] as String? ?? ''),
      };
      if (names.intersection(wanted).isNotEmpty) {
        return (d['id'] as num?)?.toInt();
      }
    }
    return null;
  }

  /// Последний путь к фильму, когда нет ни kp-, ни imdb-id: поиск по названию.
  static Future<int?> _searchMovieId(String title, int? year) async {
    final data = await _getJson(
        Uri.parse('${ApiConfig.kinopoiskBase}/v1.4/movie/search').replace(
            queryParameters: {'query': title, 'limit': '5', 'page': '1'}));
    final docs = (data?['docs'] as List? ?? []).cast<Map<String, dynamic>>();
    for (final d in docs) {
      final y = (d['year'] as num?)?.toInt();
      if (year == null || y == null || (y - year).abs() <= 1) {
        return (d['id'] as num?)?.toInt();
      }
    }
    return null;
  }

  // ------------------------------ запросы ------------------------------

  /// Первый документ списочного эндпоинта (`docs[0]`) или null.
  static Future<Map<String, dynamic>?> _docFrom(
      String path, Map<String, dynamic> query) async {
    final data = await _getJson(
        Uri.parse('${ApiConfig.kinopoiskBase}$path')
            .replace(queryParameters: query));
    final docs = (data?['docs'] as List? ?? []).cast<Map<String, dynamic>>();
    return docs.isEmpty ? null : docs.first;
  }

  static Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode == 403 || resp.statusCode == 429) {
      throw SourceLimitException(resp.statusCode);
    }
    if (resp.statusCode != 200) {
      debugPrint('facts ${resp.statusCode}: ${uri.path}');
      return null;
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  // ------------------------------ разбор -------------------------------

  @visibleForTesting
  static List<KpFact> parseFacts(Object? raw) => _parseFacts(raw);

  static List<KpFact> _parseFacts(Object? raw) {
    final out = <KpFact>[];
    for (final f in (raw as List? ?? []).whereType<Map>()) {
      final text = _plain(f['value'] as String? ?? '');
      if (text.isEmpty) continue;
      out.add(KpFact(
        text: text,
        blooper: (f['type'] as String?)?.toUpperCase() == 'BLOOPER',
        spoiler: f['spoiler'] == true,
      ));
    }
    return out;
  }

  /// Кинопоиск отдаёт факты с html-разметкой (`<b>`, `&nbsp;`, ссылки).
  static String _plain(String html) {
    var s = html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&quot;': '"',
      '&laquo;': '«',
      '&raquo;': '»',
      '&mdash;': '—',
      '&ndash;': '–',
      '&lt;': '<',
      '&gt;': '>',
      '&#39;': "'",
      '&apos;': "'",
      '&hellip;': '…',
    };
    entities.forEach((k, v) => s = s.replaceAll(k, v));
    return s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  /// Ключ сравнения имён: регистр, «ё», дефисы, апострофы и диакритика не
  /// должны мешать. Без снятия диакритики «Léaud» у КП не совпал бы с «Leaud».
  @visibleForTesting
  static String nameKey(String s) => _nameKey(s);

  static const Map<String, String> _diacritics = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ō': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
    'ç': 'c', 'ć': 'c', 'č': 'c', 'ñ': 'n', 'ń': 'n', 'ß': 'ss',
    'ś': 's', 'š': 's', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'ý': 'y', 'ÿ': 'y',
    'ł': 'l', 'đ': 'd', 'ř': 'r', 'ť': 't', 'ď': 'd', 'ğ': 'g', 'ı': 'i',
    'ё': 'е', 'й': 'и',
  };

  static String _nameKey(String s) {
    var out = s.toLowerCase();
    _diacritics.forEach((from, to) => out = out.replaceAll(from, to));
    return out.replaceAll(RegExp(r'[^0-9a-zа-я]+'), '');
  }

  static String _key(String s) => s.replaceAll(RegExp(r'[^0-9a-zA-Z]+'), '');

  // -------------------------------- кэш --------------------------------

  static Future<List<KpFact>?> _cachedFacts(String kind, int id) async {
    final raw = await Store.instance.getString('kpf.$kind.$id');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (_stale(j['t'], _ttl)) return null;
      return [
        for (final f in (j['f'] as List? ?? []))
          KpFact.fromCache((f as Map).cast<String, dynamic>())
      ];
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cacheFacts(
          String kind, int id, List<KpFact> facts) async =>
      Store.instance.setString(
          'kpf.$kind.$id',
          jsonEncode({
            't': DateTime.now().millisecondsSinceEpoch,
            'f': [for (final f in facts) f.toJson()],
          }));

  /// Запомненный id: число, -1 если сущность не нашлась, null если не спрашивали.
  static Future<int?> _cachedId(String kind, String key) async {
    final raw = await Store.instance.getString('kpf.$kind.$key');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final id = (j['id'] as num?)?.toInt();
      if (_stale(j['t'], id == -1 ? _missTtl : _ttl)) return null;
      return id;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cacheId(String kind, String key, int id) async =>
      Store.instance.setString('kpf.$kind.$key',
          jsonEncode({'t': DateTime.now().millisecondsSinceEpoch, 'id': id}));

  static bool _stale(Object? millis, Duration ttl) {
    final t = (millis as num?)?.toInt();
    if (t == null) return true;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(t));
    return age > ttl;
  }
}
