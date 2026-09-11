/// Фильтр библиотеки по одному актёру.
library;

/// Совпадение ищется по `tmdbId` из фильмографии человека, а не по кэшу каста:
/// каст у записей не хранится, а дозагружать его для всей библиотеки — это
/// тысяча запросов и неделя ожидания. Зато фильтр сразу работает и по
/// сериалам. Цена: запись без `tmdbId` через него не проходит.
class ActorFilter {
  final int personId;
  final String name;

  /// `tmdbId` фильмов и сериалов, где человек участвовал (TMDB credits).
  final Set<int> movieIds;
  final Set<int> seriesIds;

  const ActorFilter({
    required this.personId,
    required this.name,
    this.movieIds = const {},
    this.seriesIds = const {},
  });

  /// У человека нет ни одной роли в базе — фильтровать нечем.
  bool get isEmpty => movieIds.isEmpty && seriesIds.isEmpty;

  bool matchesMovie(int? tmdbId) => tmdbId != null && movieIds.contains(tmdbId);

  bool matchesSeries(int? tmdbId) =>
      tmdbId != null && seriesIds.contains(tmdbId);
}
