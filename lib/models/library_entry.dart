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

enum LibraryStatus { watched, watchlist, library, dropped }

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

  /// Когда добавлен в список (для сортировки «Буду смотреть» новые→старые).
  DateTime? addedAt;

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

  /// Кэш идентификаторов/постера от источников (kinopoisk.dev / KinoBD / TMDB).
  int? kinopoiskId;
  int? tmdbId;
  String? posterUrl;

  /// Жанры и страны (названия, ru) — кэшируются из TMDB details при открытии
  /// карточки / фоновой дозагрузке. Для фильтров и статистики по жанрам.
  List<String> genres;
  List<String> countries;

  /// Пытались ли уже дотянуть подробности (жанры/длительность), чтобы не
  /// дёргать TMDB повторно в фоновой дозагрузке.
  bool detailsTried;

  LibraryMovie({
    required this.uuid,
    required this.title,
    this.ruTitle,
    this.kpRating,
    this.enrichTried = false,
    this.tmdbId,
    this.year,
    this.runtimeMin,
    this.status = LibraryStatus.library,
    this.addedAt,
    List<Viewing>? viewings,
    this.rewatchCount = 0,
    this.score,
    List<MovieEmotion>? emotions,
    this.favorite = false,
    List<String>? lists,
    this.review,
    this.kinopoiskId,
    this.posterUrl,
    List<String>? genres,
    List<String>? countries,
    this.detailsTried = false,
  })  : viewings = viewings ?? [],
        emotions = emotions ?? [],
        lists = lists ?? [],
        genres = genres ?? [],
        countries = countries ?? [];

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

  /// Текущий (последний по дате) просмотр.
  Viewing? get currentViewing {
    if (viewings.isEmpty) return null;
    Viewing? best;
    for (final v in viewings) {
      if (v.date == null) continue;
      if (best == null || v.date!.isAfter(best.date!)) best = v;
    }
    return best ?? viewings.last;
  }

  /// Оценка фильма для показа = оценка текущего просмотра (или общая fallback).
  double? get currentScore {
    final cv = currentViewing;
    return cv != null ? scoreOf(cv) : score;
  }

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
        'dropped' => LibraryStatus.dropped,
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
        addedAt: j['addedAt'] == null ? null : DateTime.tryParse('${j['addedAt']}'),
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
        tmdbId: (j['tmdbId'] as num?)?.toInt(),
        posterUrl: j['posterUrl'] as String?,
        genres: (j['genres'] as List? ?? []).map((e) => '$e').toList(),
        countries: (j['countries'] as List? ?? []).map((e) => '$e').toList(),
        detailsTried: j['detailsTried'] == true,
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
        'addedAt': addedAt?.toIso8601String(),
        'viewings': [for (final v in viewings) v.toJson()],
        'rewatchCount': rewatchCount,
        'score': score,
        'emotions': [for (final e in emotions) e.toJson()],
        'favorite': favorite,
        'lists': lists,
        'review': review,
        'kinopoiskId': kinopoiskId,
        'tmdbId': tmdbId,
        'posterUrl': posterUrl,
        if (genres.isNotEmpty) 'genres': genres,
        if (countries.isNotEmpty) 'countries': countries,
        if (detailsTried) 'detailsTried': true,
      };
}

/// Один просмотр эпизода сериала (со своей датой и оценкой — как фильм).
class Episode {
  int? season;
  int? number;
  DateTime? watchedAt;
  int? runtimeMin;
  double? score;
  String? epId;

  /// Сколько раз серию пересматривали (0 — смотрели один раз). Всего просмотров
  /// серии = rewatchCount + 1. Оставлен для ×N у СТАРЫХ данных без дат.
  int rewatchCount;

  /// ПОВТОРНЫЕ просмотры (сверх первого в [watchedAt]/[score]) — у КАЖДОГО своя
  /// дата и своя оценка, как отдельные просмотры фильма. Первый просмотр — это
  /// сами поля watchedAt+score. Старые данные (rewatchDates) мигрируются сюда.
  List<Viewing> rewatchViews;

  Episode({
    this.season,
    this.number,
    this.watchedAt,
    this.runtimeMin,
    this.score,
    this.epId,
    this.rewatchCount = 0,
    List<Viewing>? rewatchViews,
  }) : rewatchViews = rewatchViews ?? [];

  /// Все просмотры серии как список (первый = watchedAt+score, затем повторы) —
  /// для карточки «Оценки по просмотрам» и ленты. Порядок добавления сохранён.
  List<Viewing> get views =>
      [Viewing(date: watchedAt, score: score), ...rewatchViews];

  /// Эффективная оценка конкретного просмотра (своя, иначе — общая первого).
  double? scoreOfView(Viewing v) => v.score ?? score;

  /// Всего просмотров серии (первый + повторы). Учитываем и старый rewatchCount.
  int get watchCount =>
      1 + (rewatchViews.length > rewatchCount ? rewatchViews.length : rewatchCount);

  /// Копия-«событие» одного просмотра (дата + его оценка) — для ленты, где один
  /// просмотр = одна запись. rewatchCount/rewatchViews обнуляем: событие атомарно.
  Episode copyForView(Viewing v) => Episode(
        season: season,
        number: number,
        watchedAt: v.date,
        runtimeMin: runtimeMin,
        score: v.score ?? score,
        epId: epId,
      );

  /// Метка «S1E5» / «Серия 5» / «Эпизод».
  String get label {
    if (season != null && number != null) return 'S$season·E$number';
    if (number != null) return 'Серия $number';
    return 'Эпизод';
  }

  static DateTime? _parse(dynamic v) {
    if (v == null) return null;
    final d = DateTime.tryParse('$v');
    if (d == null || d.millisecondsSinceEpoch <= 0) return null;
    return d;
  }

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        season: (j['season'] as num?)?.toInt(),
        number: (j['number'] as num?)?.toInt(),
        watchedAt: _parse(j['watchedAt']),
        runtimeMin: (j['runtimeMin'] as num?)?.toInt(),
        score: (j['score'] as num?)?.toDouble(),
        epId: j['epId'] as String?,
        rewatchCount: (j['rewatchCount'] as num?)?.toInt() ?? 0,
        rewatchViews: _parseViews(j),
      );

  /// Читает повторы: новый формат rewatchViews (дата+оценка) или старый
  /// rewatchDates (только даты v0.6.4 → оценка null).
  static List<Viewing> _parseViews(Map<String, dynamic> j) {
    final rv = j['rewatchViews'];
    if (rv is List) return [for (final e in rv) Viewing.fromAny(e)];
    final rd = j['rewatchDates'];
    if (rd is List) {
      return [
        for (final e in rd)
          if (_parse(e) != null) Viewing(date: _parse(e))
      ];
    }
    return [];
  }

  Map<String, dynamic> toJson() => {
        'season': season,
        'number': number,
        'watchedAt': watchedAt?.toIso8601String(),
        'runtimeMin': runtimeMin,
        'score': score,
        'epId': epId,
        'rewatchCount': rewatchCount,
        if (rewatchViews.isNotEmpty)
          'rewatchViews': [for (final v in rewatchViews) v.toJson()],
      };
}

/// Сессия просмотра — эпизоды сериала, просмотренные подряд (запоем).
class EpisodeSession {
  final LibrarySeries series;
  final List<Episode> episodes; // отсортированы по времени

  EpisodeSession(this.series, this.episodes);

  DateTime? get start {
    DateTime? best;
    for (final e in episodes) {
      final d = e.watchedAt;
      if (d == null) continue;
      if (best == null || d.isBefore(best)) best = d;
    }
    return best;
  }

  DateTime? get end {
    DateTime? best;
    for (final e in episodes) {
      final d = e.watchedAt;
      if (d == null) continue;
      if (best == null || d.isAfter(best)) best = d;
    }
    return best;
  }

  int get count => episodes.length;

  /// Средняя оценка по оценённым эпизодам сессии (или null).
  double? get avgScore {
    final s = episodes.map((e) => e.score).whereType<double>().toList();
    if (s.isEmpty) return null;
    return s.reduce((a, b) => a + b) / s.length;
  }

  /// Диапазон серий: «S1·E1–E5» или «5 серий».
  String get rangeLabel {
    final nums = episodes.map((e) => e.number).whereType<int>().toList()..sort();
    if (nums.length >= 2 && episodes.first.season == episodes.last.season) {
      final s = episodes.first.season;
      final prefix = s != null ? 'S$s·' : '';
      return '$prefix E${nums.first}–E${nums.last}';
    }
    return episodes.length == 1 ? episodes.first.label : '${episodes.length} сер.';
  }
}

/// Сериал в библиотеке.
class LibrarySeries {
  final String tvShowId;
  String title;
  String? ruTitle;
  List<Episode> episodes;
  bool favorite;

  /// Сериал добавлен в «Буду смотреть» (ещё не начат). Показывается во вкладке
  /// «Буду смотреть», пока нет ни одной просмотренной серии.
  bool watchlist;

  /// Сериал брошен (просмотр прекращён) — попадает в список «Брошено» и не
  /// участвует в уведомлениях о новых сериях.
  bool dropped;

  /// Пользователь пометил сериал досмотренным — убирается из «Сейчас смотрю»
  /// даже если общее число серий неизвестно (кривой/отсутствующий TMDB-матч).
  bool finished;

  /// Всего серий по данным TMDB (заполняется при открытии экрана сериала).
  /// Нужно, чтобы «Сейчас смотрю» показывал только незавершённые сериалы.
  int? totalEpisodes;
  double? score;
  String? review;
  int? kinopoiskId;
  int? tmdbId;
  double? kpRating;
  bool enrichTried;
  String? posterUrl;

  LibrarySeries({
    required this.tvShowId,
    required this.title,
    this.ruTitle,
    List<Episode>? episodes,
    this.favorite = false,
    this.watchlist = false,
    this.dropped = false,
    this.finished = false,
    this.totalEpisodes,
    this.score,
    this.review,
    this.kinopoiskId,
    this.tmdbId,
    this.kpRating,
    this.enrichTried = false,
    this.posterUrl,
  }) : episodes = episodes ?? [];

  /// Полностью ли просмотрен сериал (известно общее число серий и все отмечены).
  bool get isCompleted =>
      totalEpisodes != null &&
      totalEpisodes! > 0 &&
      episodes.length >= totalEpisodes!;

  int get episodesSeen => episodes.length;

  /// Средняя оценка по оценённым сериям (или null, если ни одна не оценена).
  double? get episodeScoreAvg {
    final scores = episodes.map((e) => e.score).whereType<double>().toList();
    if (scores.isEmpty) return null;
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    return (avg * 10).round() / 10; // округляем до 0.1
  }

  /// Оценка сериала для показа: если есть оценки серий — их среднее (считается
  /// автоматически, руками не задаётся); иначе — ручная общая оценка.
  double? get displayScore => episodeScoreAvg ?? score;

  DateTime? get lastWatch {
    DateTime? best;
    for (final e in episodes) {
      final d = e.watchedAt;
      if (d == null) continue;
      if (best == null || d.isAfter(best)) best = d;
    }
    return best;
  }

  String get displayTitle =>
      (ruTitle != null && ruTitle!.isNotEmpty) ? ruTitle! : title;

  Episode? watchedEpisode(int? season, int? number) {
    for (final e in episodes) {
      if (e.season == season && e.number == number) return e;
    }
    return null;
  }

  bool isEpisodeWatched(int? season, int? number) =>
      watchedEpisode(season, number) != null;

  /// Разбивка на сессии: эпизоды, просмотренные с перерывом ≤ [gap], — вместе.
  List<EpisodeSession> sessions(
      {Duration gap = const Duration(hours: 3)}) {
    // Разворачиваем каждый эпизод в отдельные СОБЫТИЯ просмотра (первый + каждый
    // датированный повтор), чтобы пересмотр в другой день был отдельной записью
    // в ленте — как отдельные просмотры у фильмов. Событие = копия с одной датой.
    final dated = <Episode>[];
    final undated = <Episode>[];
    for (final e in episodes) {
      // Каждый просмотр (первый + повторы) — своё событие с датой и своей оценкой.
      for (final v in e.views) {
        if (v.date == null) {
          undated.add(e.copyForView(v));
        } else {
          dated.add(e.copyForView(v));
        }
      }
    }
    dated.sort((a, b) => a.watchedAt!.compareTo(b.watchedAt!));
    final result = <EpisodeSession>[];
    var cur = <Episode>[];
    DateTime? last;
    for (final e in dated) {
      if (last != null && e.watchedAt!.difference(last) > gap) {
        result.add(EpisodeSession(this, cur));
        cur = [];
      }
      cur.add(e);
      last = e.watchedAt;
    }
    if (cur.isNotEmpty) result.add(EpisodeSession(this, cur));
    if (undated.isNotEmpty) result.add(EpisodeSession(this, undated));
    return result;
  }

  factory LibrarySeries.fromJson(Map<String, dynamic> j) {
    List<Episode> eps;
    if (j['episodes'] != null) {
      eps = (j['episodes'] as List)
          .map((e) => Episode.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      // Старый формат: список дат-просмотров → эпизоды без номеров.
      eps = (j['viewings'] as List? ?? [])
          .map((v) => Episode(watchedAt: Episode._parse(v)))
          .toList();
    }
    return LibrarySeries(
      tvShowId: '${j['tvShowId']}',
      title: j['title'] as String? ?? '',
      ruTitle: j['ruTitle'] as String?,
      episodes: eps,
      favorite: j['favorite'] == true,
      watchlist: j['watchlist'] == true,
      dropped: j['dropped'] == true,
      finished: j['finished'] == true,
      totalEpisodes: (j['totalEpisodes'] as num?)?.toInt(),
      score: (j['score'] as num?)?.toDouble(),
      review: j['review'] as String?,
      kinopoiskId: (j['kinopoiskId'] as num?)?.toInt(),
      tmdbId: (j['tmdbId'] as num?)?.toInt(),
      kpRating: (j['kpRating'] as num?)?.toDouble(),
      enrichTried: j['enrichTried'] == true,
      posterUrl: j['posterUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'tvShowId': tvShowId,
        'title': title,
        'ruTitle': ruTitle,
        'episodes': [for (final e in episodes) e.toJson()],
        'favorite': favorite,
        'watchlist': watchlist,
        'dropped': dropped,
        'finished': finished,
        'totalEpisodes': totalEpisodes,
        'score': score,
        'review': review,
        'kinopoiskId': kinopoiskId,
        'tmdbId': tmdbId,
        'kpRating': kpRating,
        'enrichTried': enrichTried,
        'posterUrl': posterUrl,
      };
}

/// Элемент ленты «Просмотрено»: либо просмотр фильма, либо СЕССИЯ сериала
/// (серии, просмотренные подряд одним блоком).
class WatchedEntry {
  final LibraryMovie? movie;
  final Viewing? viewing;
  final EpisodeSession? session;
  const WatchedEntry.movie(this.movie, this.viewing) : session = null;
  const WatchedEntry.session(this.session)
      : movie = null,
        viewing = null;

  bool get isSeries => session != null;
  DateTime? get date => isSeries ? session!.start : viewing?.date;
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
