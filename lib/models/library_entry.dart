// Модели библиотеки Kadr. Заполняются из импорта (TV Time) и пополняются
// пользователем. Постеры и `kinopoiskId` дотягиваются лениво из kinopoisk.dev /
// KinoBD-дампа по названию+году и кэшируются здесь же.

/// Эмоция-реакция на фильм (наследие TV Time) + её стартовый вклад в балл.
class MovieEmotion {
  final String id;
  final String label;
  final String emoji;
  final double score;

  const MovieEmotion(
      {required this.id,
      required this.label,
      required this.emoji,
      required this.score});

  factory MovieEmotion.fromJson(Map<String, dynamic> j) => MovieEmotion(
        id: '${j['id']}',
        label: j['label'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '',
        score: (j['score'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'label': label, 'emoji': emoji, 'score': score};
}

/// Один просмотр фильма: дата (может быть неизвестна) и СВОЯ оценка 1.0–10.0.
/// Мнение может меняться при пересмотре — поэтому оценка у каждого просмотра
/// отдельная.
class Viewing {
  DateTime? date;
  double? score;

  Viewing({this.date, this.score});

  bool get hasDate => date != null;

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final d = DateTime.tryParse('$v');
    // Старая заглушка «неизвестная дата» = эпоха (1970) → трактуем как null.
    if (d == null || d.millisecondsSinceEpoch <= 0) return null;
    return d;
  }

  /// Принимает и старый формат (строка-дата), и новый ({date, score}).
  factory Viewing.fromAny(dynamic j) {
    if (j is Map) {
      return Viewing(
        date: _parseDate(j['date']),
        score: (j['score'] as num?)?.toDouble(),
      );
    }
    return Viewing(date: _parseDate(j));
  }

  Map<String, dynamic> toJson() =>
      {'date': date?.toIso8601String(), 'score': score};
}

enum LibraryStatus { watched, watchlist, library }

/// Фильм в библиотеке пользователя.
class LibraryMovie {
  final String uuid;
  String title;

  /// Русское название и рейтинг Кинопоиска — подтягиваются из kinopoisk.dev.
  String? ruTitle;
  double? kpRating;

  /// Пытались ли уже обогатить (чтобы не тратить лимит API повторно).
  bool enrichTried;

  int? year;
  int? runtimeMin;
  LibraryStatus status;

  /// Просмотры (у каждого — своя дата и своя оценка).
  List<Viewing> viewings;
  int rewatchCount;

  /// Общая («headline») оценка 1.0–10.0. Для импортированных — из эмоций.
  /// У отдельных просмотров может быть своя оценка (см. [Viewing.score]).
  double? score;
  List<MovieEmotion> emotions;
  bool favorite;
  List<String> lists;
  String? review;

  /// Кэш от kinopoisk.dev / KinoBD.
  int? kinopoiskId;
  String? posterUrl;

  LibraryMovie({
    required this.uuid,
    required this.title,
    this.ruTitle,
    this.kpRating,
    this.enrichTried = false,
    this.year,
    this.runtimeMin,
    this.status = LibraryStatus.library,
    List<Viewing>? viewings,
    this.rewatchCount = 0,
    this.score,
    List<MovieEmotion>? emotions,
    this.favorite = false,
    List<String>? lists,
    this.review,
    this.kinopoiskId,
    this.posterUrl,
  })  : viewings = viewings ?? [],
        emotions = emotions ?? [],
        lists = lists ?? [];

  /// Последний просмотр с известной датой.
  DateTime? get lastViewing {
    DateTime? best;
    for (final v in viewings) {
      final d = v.date;
      if (d == null) continue;
      if (best == null || d.isAfter(best)) best = d;
    }
    return best;
  }

  /// Просмотры по возрастанию даты (неизвестные — в конец).
  List<Viewing> get sortedViewings {
    final known = viewings.where((v) => v.hasDate).toList()
      ..sort((a, b) => a.date!.compareTo(b.date!));
    final unknown = viewings.where((v) => !v.hasDate).toList();
    return [...known, ...unknown];
  }

  /// Оценка конкретного просмотра или общая (fallback).
  double? scoreOf(Viewing v) => v.score ?? score;

  /// Есть ли различающиеся оценки по просмотрам (для блока сравнения).
  bool get hasScoreComparison {
    final s = viewings.map((v) => v.score).whereType<double>().toSet();
    return s.length >= 2;
  }

  /// Общее число просмотров.
  int get viewCount =>
      viewings.length > rewatchCount ? viewings.length : rewatchCount + 1;

  /// Смотрел ли повторно.
  bool get isRewatched => rewatchCount > 0 || viewings.length > 1;

  /// Название для показа: русское, если уже подтянуто, иначе оригинал.
  String get displayTitle =>
      (ruTitle != null && ruTitle!.isNotEmpty) ? ruTitle! : title;

  static LibraryStatus _status(String? s) => switch (s) {
        'watched' => LibraryStatus.watched,
        'watchlist' => LibraryStatus.watchlist,
        _ => LibraryStatus.library,
      };

  factory LibraryMovie.fromJson(Map<String, dynamic> j) => LibraryMovie(
        uuid: '${j['uuid']}',
        title: j['title'] as String? ?? '',
        ruTitle: j['ruTitle'] as String?,
        kpRating: (j['kpRating'] as num?)?.toDouble(),
        enrichTried: j['enrichTried'] == true,
        year: (j['year'] as num?)?.toInt(),
        runtimeMin: (j['runtimeMin'] as num?)?.toInt(),
        status: _status(j['status'] as String?),
        viewings: (j['viewings'] as List? ?? [])
            .map((e) => Viewing.fromAny(e))
            .toList(),
        rewatchCount: (j['rewatchCount'] as num?)?.toInt() ?? 0,
        score: (j['score'] as num?)?.toDouble(),
        emotions: (j['emotions'] as List? ?? [])
            .map((e) => MovieEmotion.fromJson(e as Map<String, dynamic>))
            .toList(),
        favorite: j['favorite'] == true,
        lists: (j['lists'] as List? ?? []).map((e) => '$e').toList(),
        review: j['review'] as String?,
        kinopoiskId: (j['kinopoiskId'] as num?)?.toInt(),
        posterUrl: j['posterUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'title': title,
        'ruTitle': ruTitle,
        'kpRating': kpRating,
        'enrichTried': enrichTried,
        'year': year,
        'runtimeMin': runtimeMin,
        'status': status.name,
        'viewings': [for (final v in viewings) v.toJson()],
        'rewatchCount': rewatchCount,
        'score': score,
        'emotions': [for (final e in emotions) e.toJson()],
        'favorite': favorite,
        'lists': lists,
        'review': review,
        'kinopoiskId': kinopoiskId,
        'posterUrl': posterUrl,
      };
}

/// Сериал в библиотеке.
class LibrarySeries {
  final String tvShowId;
  String title;
  int episodesSeen;
  List<DateTime> viewings;
  bool favorite;
  double? score;
  String? review;
  int? kinopoiskId;
  String? posterUrl;

  LibrarySeries({
    required this.tvShowId,
    required this.title,
    this.episodesSeen = 0,
    List<DateTime>? viewings,
    this.favorite = false,
    this.score,
    this.review,
    this.kinopoiskId,
    this.posterUrl,
  }) : viewings = viewings ?? [];

  DateTime? get lastWatch => viewings.isEmpty ? null : viewings.last;

  static List<DateTime> _dates(dynamic v) => (v as List? ?? [])
      .map((e) => DateTime.tryParse('$e'))
      .whereType<DateTime>()
      .toList();

  factory LibrarySeries.fromJson(Map<String, dynamic> j) => LibrarySeries(
        tvShowId: '${j['tvShowId']}',
        title: j['title'] as String? ?? '',
        episodesSeen: (j['episodesSeen'] as num?)?.toInt() ?? 0,
        viewings: _dates(j['viewings']),
        favorite: j['favorite'] == true,
        score: (j['score'] as num?)?.toDouble(),
        review: j['review'] as String?,
        kinopoiskId: (j['kinopoiskId'] as num?)?.toInt(),
        posterUrl: j['posterUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'tvShowId': tvShowId,
        'title': title,
        'episodesSeen': episodesSeen,
        'viewings': [for (final d in viewings) d.toIso8601String()],
        'favorite': favorite,
        'score': score,
        'review': review,
        'kinopoiskId': kinopoiskId,
        'posterUrl': posterUrl,
      };
}

/// Пользовательский список фильмов.
class MovieList {
  final String name;
  final List<String> movieUuids;
  final bool public;

  const MovieList(
      {required this.name, required this.movieUuids, this.public = false});

  factory MovieList.fromJson(Map<String, dynamic> j) => MovieList(
        name: j['name'] as String? ?? '',
        movieUuids: (j['movieUuids'] as List? ?? []).map((e) => '$e').toList(),
        public: j['public'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'movieUuids': movieUuids, 'public': public};
}
