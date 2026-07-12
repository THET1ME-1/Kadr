import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/library_entry.dart';
import 'movie_repository.dart';
import 'tvtime_parser.dart';

/// Итог импорта TV Time. Числа `movies/series/episodes/...` — это ОБЪЁМ данных
/// в экспорте (для «вау»-сводки), а `addedMovies/addedSeries` — сколько реально
/// добавлено в библиотеку (остальное слилось с уже существующим).
class TvTimeImportResult {
  final bool ok;
  final String? error;
  final int movies;
  final int moviesWatched;
  final int moviesWatchlist;
  final int moviesRated;
  final int series;
  final int episodes; // просмотров серий
  final int lists;
  final int reviews;
  final int addedMovies;
  final int updatedMovies;
  final int addedSeries;
  final int updatedSeries;

  const TvTimeImportResult({
    this.ok = false,
    this.error,
    this.movies = 0,
    this.moviesWatched = 0,
    this.moviesWatchlist = 0,
    this.moviesRated = 0,
    this.series = 0,
    this.episodes = 0,
    this.lists = 0,
    this.reviews = 0,
    this.addedMovies = 0,
    this.updatedMovies = 0,
    this.addedSeries = 0,
    this.updatedSeries = 0,
  });

  bool get isEmpty => movies == 0 && series == 0;
}

/// Этапы импорта — для анимации статуса на экране.
enum TvTimeStage { unzip, parse, movies, series, lists, done }

/// Импорт GDPR-экспорта TV Time (.zip) во встроенную библиотеку.
/// Постеры/kinopoisk-id/локализованные названия дотягиваются лениво по
/// названию+году (тот же фон, что и для остальных записей).
class TvTimeImportService {
  /// Открыть выбор .zip и вернуть его байты (null — отмена/ошибка чтения).
  static Future<List<int>?> pickZipBytes() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.single;
    if (f.bytes != null) return f.bytes;
    if (f.path != null) return File(f.path!).readAsBytes();
    return null;
  }

  /// Выбрать .zip и импортировать. [onStage] — коллбэк для анимации прогресса.
  static Future<TvTimeImportResult> pickAndImport(
      {void Function(TvTimeStage)? onStage}) async {
    final bytes = await pickZipBytes();
    if (bytes == null) {
      return const TvTimeImportResult(); // отмена — ok=false, без ошибки
    }
    return importFromZipBytes(bytes, onStage: onStage);
  }

  static Future<TvTimeImportResult> importFromZipBytes(List<int> bytes,
      {void Function(TvTimeStage)? onStage}) async {
    try {
      onStage?.call(TvTimeStage.unzip);
      final Map<String, String> files = {};
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = entry.name.split('/').last;
        if (!name.toLowerCase().endsWith('.csv')) continue;
        final content = entry.content;
        if (content is List<int>) {
          files[name] = utf8.decode(content, allowMalformed: true);
        }
      }
      if (files.isEmpty) {
        return const TvTimeImportResult(error: 'not_tvtime');
      }

      onStage?.call(TvTimeStage.parse);
      // Парсинг CSV — в фоновом изоляте, чтобы волнистая анимация не дёргалась.
      final data = await compute(parseTvTime, files);
      if (data.movies.isEmpty && data.series.isEmpty) {
        return const TvTimeImportResult(error: 'empty');
      }

      final repo = MovieRepository.instance;

      onStage?.call(TvTimeStage.movies);
      final movies = data.movies.map(_toMovie).toList();
      final (am, um) = await repo.importMovies(movies);

      onStage?.call(TvTimeStage.series);
      final series = data.series.map(_toSeries).toList();
      final (asr, usr) = await repo.importSeries(series);

      onStage?.call(TvTimeStage.lists);
      final lists = data.lists
          .map((l) =>
              MovieList(name: l.name, movieUuids: l.movieUuids, public: l.public))
          .toList();
      await repo.importLists(lists);

      onStage?.call(TvTimeStage.done);
      final c = data.counts;
      return TvTimeImportResult(
        ok: true,
        movies: c['movies'] ?? 0,
        moviesWatched: c['moviesWatched'] ?? 0,
        moviesWatchlist: c['moviesWatchlist'] ?? 0,
        moviesRated: c['moviesRated'] ?? 0,
        series: c['series'] ?? 0,
        episodes: c['episodeViewings'] ?? 0,
        lists: c['lists'] ?? 0,
        reviews: c['reviews'] ?? 0,
        addedMovies: am,
        updatedMovies: um,
        addedSeries: asr,
        updatedSeries: usr,
      );
    } catch (e) {
      return TvTimeImportResult(error: '$e');
    }
  }

  static DateTime? _date(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static LibraryStatus _status(String s) => switch (s) {
        'watched' => LibraryStatus.watched,
        'watchlist' => LibraryStatus.watchlist,
        _ => LibraryStatus.library,
      };

  static LibraryMovie _toMovie(TvMovie m) => LibraryMovie(
        uuid: m.uuid,
        title: m.title,
        year: m.year,
        runtimeMin: m.runtimeMin,
        status: _status(m.status),
        addedAt: _date(m.addedAt),
        viewings: [for (final d in m.viewings) Viewing(date: _date(d))],
        rewatchCount: m.rewatchCount,
        score: m.score,
        emotions: [
          for (final e in m.emotions)
            MovieEmotion(id: e.id, label: e.label, emoji: e.emoji, score: e.score)
        ],
        favorite: m.favorite,
        lists: [...m.lists],
        review: m.review,
      );

  /// DTO-сериал (плоские записи просмотров) → [LibrarySeries]: эпизоды
  /// группируются по (сезон, номер) — первый просмотр в watchedAt, повторы в
  /// rewatchViews.
  static LibrarySeries _toSeries(TvSeries s) {
    final byKey = <String, List<TvEpisode>>{};
    for (final e in s.episodes) {
      (byKey['${e.season}|${e.number}'] ??= []).add(e);
    }
    final episodes = <Episode>[];
    for (final group in byKey.values) {
      group.sort((a, b) => a.watchedAt.compareTo(b.watchedAt));
      final first = group.first;
      episodes.add(Episode(
        season: first.season,
        number: first.number,
        watchedAt: _date(first.watchedAt),
        runtimeMin: first.runtimeMin,
        epId: first.epId,
        rewatchViews: [
          for (var i = 1; i < group.length; i++)
            Viewing(date: _date(group[i].watchedAt))
        ],
      ));
    }
    episodes.sort((a, b) {
      final an = (a.season ?? 0) * 10000 + (a.number ?? 0);
      final bn = (b.season ?? 0) * 10000 + (b.number ?? 0);
      return an.compareTo(bn);
    });
    final id = s.tvShowId.isNotEmpty
        ? 'tvt-${s.tvShowId}'
        : 'tvt-${s.title.toLowerCase().trim()}';
    return LibrarySeries(
      tvShowId: id,
      title: s.title,
      episodes: episodes,
      favorite: s.favorite,
      review: s.review,
    );
  }

  // Тест-хуки конвертации DTO → модель (см. test/tvtime_import_test.dart).
  @visibleForTesting
  static LibraryMovie toMovie(TvMovie m) => _toMovie(m);
  @visibleForTesting
  static LibrarySeries toSeries(TvSeries s) => _toSeries(s);
}
