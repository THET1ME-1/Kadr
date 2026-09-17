import '../models/library_entry.dart';

/// Сколько серий сезона отмечено.
///
/// [total] — число серий сезона по TMDB. Считаются разные номера от 1 до
/// [total]: пересмотр той же серии и серии вне структуры (спецвыпуски, лишние
/// номера из неточного импорта) счёт не накручивают.
typedef SeasonProgress = ({int seen, int total});

SeasonProgress seasonProgress(LibrarySeries s, int season, int total) {
  final numbers = <int>{
    for (final e in s.episodes)
      if (e.season == season &&
          e.number != null &&
          e.number! >= 1 &&
          e.number! <= total)
        e.number!,
  };
  return (seen: numbers.length, total: total);
}

extension SeasonProgressX on SeasonProgress {
  /// Доля отмеченного, 0…1. У сезона без серий 0.
  double get fraction => total <= 0 ? 0 : (seen / total).clamp(0.0, 1.0);

  /// Досмотрен ли сезон целиком.
  bool get done => total > 0 && seen >= total;
}
