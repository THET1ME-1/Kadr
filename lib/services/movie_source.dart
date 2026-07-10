import 'package:flutter/foundation.dart';

import 'store.dart';

/// Источник данных о фильмах (поиск + обогащение).
enum MovieSource { tmdb, kinopoisk, tvdb }

extension MovieSourceX on MovieSource {
  String get id => name;
  String get label => switch (this) {
        MovieSource.tmdb => 'TMDB',
        MovieSource.kinopoisk => 'ПоискКино',
        MovieSource.tvdb => 'TheTVDB',
      };
  String get note => switch (this) {
        MovieSource.tmdb => 'Без лимита · русский + постеры',
        MovieSource.kinopoisk => '200 запросов/сутки · русский',
        MovieSource.tvdb => 'Фильмы + сериалы · англ/лок',
      };
}

/// Унифицированный результат поиска фильма из любого источника. Кроме постера и
/// названия несёт ВСЕ известные ID (перекрёстные) — по ним запись сопоставляется
/// в любой базе, поэтому смена источника не создаёт дублей и не теряет данные.
class SourceMatch {
  final String? ruName;
  final String? posterUrl;
  final double? rating;
  final int? kinopoiskId;
  final int? tmdbId;
  final int? tvdbId;
  final String? imdbId;
  const SourceMatch(
      {this.ruName,
      this.posterUrl,
      this.rating,
      this.kinopoiskId,
      this.tmdbId,
      this.tvdbId,
      this.imdbId});
}

/// Исчерпан лимит/блокировка источника — останавливаем фоновую дозагрузку.
class SourceLimitException implements Exception {
  final int statusCode;
  SourceLimitException(this.statusCode);
  @override
  String toString() => 'Source limit/blocked ($statusCode)';
}

/// Выбор источника фильмов (persist в [Store]). По умолчанию — TMDB.
class SourceController extends ChangeNotifier {
  SourceController._();
  static final SourceController instance = SourceController._();

  MovieSource _source = MovieSource.tmdb;
  MovieSource get source => _source;

  Future<void> load() async {
    final stored = await Store.instance.getString('searchSource');
    _source = MovieSource.values.firstWhere(
      (s) => s.id == stored,
      orElse: () => MovieSource.tmdb,
    );
    notifyListeners();
  }

  Future<void> setSource(MovieSource s) async {
    if (s == _source) return;
    _source = s;
    notifyListeners();
    await Store.instance.setString('searchSource', s.id);
  }
}
