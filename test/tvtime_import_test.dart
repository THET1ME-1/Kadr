import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/services/tvtime_import_service.dart';
import 'package:kadr/services/tvtime_parser.dart';

// Синтетический (не персональный) экспорт TV Time для проверки парсера и
// конвертации в модель. Реальный экспорт проверяется утилитой tool/tvtime_verify.dart.
Map<String, String> _files() => {
      'tracking-prod-records.csv':
          'entity_type,type,uuid,movie_name,created_at,release_date,runtime,rewatch_count\n'
              'movie,watch,m1,Inception,2024-01-02 10:00:00,2010-07-16 00:00:00,8880,0\n'
              'movie,rewatch,m1,Inception,2024-06-02 10:00:00,2010-07-16 00:00:00,8880,1\n'
              'movie,towatch,m2,Dune,2024-03-01 09:00:00,2021-10-22 00:00:00,9300,0\n',
      'emotions-live-votes.csv':
          'uuid,user_id,movie_name,vote_key,episode_id\n'
              'm1,99,Inception,m1-99-28,0\n', // 28 → «Отлично» = 8.5
      'tracking-prod-records-v2.csv':
          'series_name,s_id,ep_id,created_at,season_number,ep_no,runtime\n'
              'Dark,s1,e1,2024-02-01 20:00:00,1,1,3000\n'
              'Dark,s1,e1,2024-05-01 20:00:00,1,1,3000\n' // пересмотр той же серии
              'Dark,s1,e2,2024-02-01 21:00:00,1,2,3000\n',
      'user_tv_show_data.csv': 'tv_show_id,is_favorited,tv_show_name,user_id\n'
          's1,true,Dark,99\n',
    };

void main() {
  test('parseTvTime — фильмы, сериалы, эмоции, счётчики', () {
    final data = parseTvTime(_files());
    expect(data.movies.length, 2);
    expect(data.counts['movieViewings'], 2); // m1: два просмотра
    expect(data.counts['moviesWatched'], 1);
    expect(data.counts['moviesWatchlist'], 1);
    expect(data.series.length, 1);
    expect(data.counts['episodeViewings'], 3); // e1×2 + e2

    final m1 = data.movies.firstWhere((m) => m.uuid == 'm1');
    expect(m1.status, 'watched');
    expect(m1.year, 2010);
    expect(m1.score, 8.5);
    final m2 = data.movies.firstWhere((m) => m.uuid == 'm2');
    expect(m2.status, 'watchlist');
    expect(data.series.first.favorite, true);
  });

  test('конвертация в модель — статусы, эмоции, группировка пересмотров', () {
    final data = parseTvTime(_files());

    final m1 = TvTimeImportService.toMovie(
        data.movies.firstWhere((m) => m.uuid == 'm1'));
    expect(m1.status, LibraryStatus.watched);
    expect(m1.viewings.length, 2);
    expect(m1.score, 8.5);
    expect(m1.emotions.length, 1);
    expect(m1.emotions.first.emoji, '😍');

    final dark = TvTimeImportService.toSeries(data.series.first);
    expect(dark.favorite, true);
    // e1 смотрели дважды → один Episode с одним повтором; e2 — отдельный Episode.
    expect(dark.episodes.length, 2);
    final e1 = dark.episodes.firstWhere((e) => e.number == 1);
    expect(e1.rewatchViews.length, 1);
    expect(e1.watchCount, 2);
    expect(e1.watchedAt, isNotNull);
  });
}
