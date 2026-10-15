// Модели библиотеки Kadr. Заполняются из импорта (TV Time) и пополняются
// пользователем. Постеры и `kinopoiskId` дотягиваются лениво из kinopoisk.dev /
// KinoBD-дампа по названию+году и кэшируются здесь же.

import '../l10n/locale_controller.dart';
import '../services/poster_store.dart';
import 'review.dart';

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

/// Запись «дневника просмотра»: настроение, с кем, где, фото, заметка. Личная и
/// приватная — фото хранится ЛОКАЛЬНО (PosterStore), на сервер/друзьям не уходит.
/// Привязана к конкретному просмотру ([Viewing]) или серии ([Episode]).
class DiaryEntry {
  List<String> moods; // эмодзи настроения (мультивыбор)
  String? withWhom; // «с кем» — свободный текст
  List<String> friendIds; // id друзей (для связи и авто-co-watch)
  String? place; // home | cinema | trip
  String? photoFile; // локальный файл фото (билет/зал)
  String? note; // короткая заметка на этот просмотр

  DiaryEntry({
    List<String>? moods,
    this.withWhom,
    List<String>? friendIds,
    this.place,
    this.photoFile,
    this.note,
  })  : moods = moods ?? [],
        friendIds = friendIds ?? [];

  bool get isEmpty =>
      moods.isEmpty &&
      (withWhom == null || withWhom!.isEmpty) &&
      friendIds.isEmpty &&
      place == null &&
      photoFile == null &&
      (note == null || note!.isEmpty);
  bool get isNotEmpty => !isEmpty;

  factory DiaryEntry.fromJson(Map<String, dynamic> j) => DiaryEntry(
        moods: (j['moods'] as List? ?? []).map((e) => '$e').toList(),
        withWhom: j['withWhom'] as String?,
        friendIds: (j['friendIds'] as List? ?? []).map((e) => '$e').toList(),
        place: j['place'] as String?,
        photoFile: j['photoFile'] as String?,
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (moods.isNotEmpty) 'moods': moods,
        if (withWhom != null && withWhom!.isNotEmpty) 'withWhom': withWhom,
        if (friendIds.isNotEmpty) 'friendIds': friendIds,
        if (place != null) 'place': place,
        if (photoFile != null) 'photoFile': photoFile,
        if (note != null && note!.isNotEmpty) 'note': note,
      };
}

int _viewingSeq = 0;

/// Id нового просмотра: время плюс счётчик на случай двух в одну микросекунду.
String newViewingId() =>
    'v${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${(_viewingSeq++).toRadixString(36)}';

/// Проставляет id просмотрам, у которых его нет (записи старых версий).
///
/// Id выводится из даты, чтобы два устройства с одной базой получили
/// одинаковые: `d<мс>` у датированных, `u<номер>` у остальных. Повтор той же
/// даты получает хвост `-1`, `-2`. [reserved] — id, занятые рядом (первый
/// просмотр серии).
void stampViewingIds(List<Viewing> list, {Set<String> reserved = const {}}) {
  final used = <String>{
    ...reserved,
    for (final v in list)
      if (v.id.isNotEmpty) v.id,
  };
  var undated = 0;
  for (final v in list) {
    if (v.id.isNotEmpty) continue;
    final d = v.date;
    var id = d != null ? 'd${d.millisecondsSinceEpoch}' : 'u${undated++}';
    if (d != null) {
      for (var n = 1; used.contains(id); n++) {
        id = 'd${d.millisecondsSinceEpoch}-$n';
      }
    } else {
      while (used.contains(id)) {
        id = 'u${undated++}';
      }
    }
    v.id = id;
    used.add(id);
  }
}

/// Просмотры по порядку: без даты первыми (их считаем самыми ранними), дальше
/// по дате. Равные остаются в порядке записи.
List<Viewing> orderViewings(List<Viewing> list) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final da = a.$2.date, db = b.$2.date;
    if (da == null || db == null) {
      if (da == null && db == null) return a.$1.compareTo(b.$1);
      return da == null ? -1 : 1;
    }
    final byDate = da.compareTo(db);
    return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Оценка последнего оценённого просмотра из [ordered]; null, если оценок нет.
double? lastRatedScore(List<Viewing> ordered) {
  for (var i = ordered.length - 1; i >= 0; i--) {
    final s = ordered[i].score;
    if (s != null) return s;
  }
  return null;
}

/// Пометка «брошен» у просмотра фильма: где остановились и что не так.
/// Причины — короткие фразы, как «Слабое» в рецензии: подсказки и свои.
class DropMark {
  /// Минута, на которой бросили; null — не указали.
  int? atMin;
  List<String> reasons;

  DropMark({this.atMin, List<String>? reasons}) : reasons = reasons ?? [];

  factory DropMark.fromJson(Map j) => DropMark(
        atMin: (j['min'] as num?)?.toInt(),
        reasons: [
          for (final e in (j['why'] as List? ?? const []))
            if ('$e'.trim().isNotEmpty) '$e'.trim(),
        ],
      );

  Map<String, dynamic> toJson() => {
        if (atMin != null) 'min': atMin,
        if (reasons.isNotEmpty) 'why': reasons,
      };

  DropMark copy() => DropMark(atMin: atMin, reasons: [...reasons]);
}

/// Пауза у просмотра фильма: начал, остановился на минуте и досмотрит
/// потом («Досмотрю потом»). У серий не бывает.
class PauseMark {
  /// Минута, на которой остановились; null — не указали.
  int? atMin;

  PauseMark({this.atMin});

  factory PauseMark.fromJson(Map j) =>
      PauseMark(atMin: (j['min'] as num?)?.toInt());

  Map<String, dynamic> toJson() => {if (atMin != null) 'min': atMin};

  PauseMark copy() => PauseMark(atMin: atMin);
}

/// Прошлый заход просмотра: в какой день смотрел и где остановился. В ленте
/// это строка «начал» или «продолжил» в свой день.
class Sitting {
  DateTime? date;

  /// Минута, на которой остановился; null — не указали.
  int? toMin;

  Sitting({this.date, this.toMin});

  factory Sitting.fromJson(Map j) => Sitting(
        date: Viewing._parseDate(j['date']),
        toMin: (j['min'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'date': date?.toIso8601String(),
        if (toMin != null) 'min': toMin,
      };

  Sitting copy() => Sitting(date: date, toMin: toMin);
}

/// Один просмотр фильма или серии: дата (может быть неизвестна), СВОЯ оценка
/// 1.0–10.0 и дневник. Мнение может меняться при пересмотре — поэтому оценка у
/// каждого просмотра отдельная.
class Viewing {
  /// Постоянный номер записи: по нему просмотр находят рецензия,
  /// синхронизация и окно просмотра. Пустой только до [stampViewingIds].
  String id;
  DateTime? date;
  double? score;

  /// Дневник этого просмотра (настроение/с кем/где/фото/заметка) — опционально.
  DiaryEntry? diary;

  /// Когда просмотр правили в последний раз (оценка, дата или дневник). По
  /// нему синхронизация выбирает из двух версий одной записи более свежую.
  /// Пусто у записей, которые после отметки не трогали.
  DateTime? editedAt;

  /// Фильм бросили на этом просмотре; null — досмотрели. У серий не бывает.
  DropMark? drop;

  /// Просмотр на паузе: досмотрят потом. Дата у такого просмотра — день
  /// последнего захода. У серий не бывает.
  PauseMark? pause;

  /// Прошлые заходы по порядку: первый — день, когда начал. Пусто у
  /// просмотра в один вечер.
  List<Sitting> parts;

  Viewing(
      {String? id,
      this.date,
      this.score,
      this.diary,
      this.editedAt,
      this.drop,
      this.pause,
      List<Sitting>? parts})
      : id = id ?? newViewingId(),
        parts = parts ?? [];

  bool get hasDate => date != null;

  /// Начат и стоит на паузе.
  bool get isPaused => pause != null;

  /// Досмотрен: не брошен и не на паузе.
  bool get isFull => drop == null && pause == null;

  /// День, когда начал, если смотрел в несколько заходов.
  DateTime? get startedAt => parts.isEmpty ? null : parts.first.date;

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final d = DateTime.tryParse('$v');
    // Старая заглушка «неизвестная дата» = эпоха (1970) → трактуем как null.
    if (d == null || d.millisecondsSinceEpoch <= 0) return null;
    return d;
  }

  /// Принимает и старый формат (строка-дата), и новый ({date, score}). Запись
  /// без id получает пустой: его проставит владелец через [stampViewingIds].
  factory Viewing.fromAny(dynamic j) {
    if (j is Map) {
      return Viewing(
        id: j['id'] as String? ?? '',
        date: _parseDate(j['date']),
        score: (j['score'] as num?)?.toDouble(),
        diary: j['diary'] is Map
            ? DiaryEntry.fromJson((j['diary'] as Map).cast<String, dynamic>())
            : null,
        editedAt: _parseDate(j['edited']),
        drop: j['drop'] is Map ? DropMark.fromJson(j['drop'] as Map) : null,
        pause:
            j['pause'] is Map ? PauseMark.fromJson(j['pause'] as Map) : null,
        parts: [
          for (final p in (j['parts'] as List? ?? const []))
            if (p is Map) Sitting.fromJson(p),
        ],
      );
    }
    return Viewing(id: '', date: _parseDate(j));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date?.toIso8601String(),
        'score': score,
        if (diary != null && diary!.isNotEmpty) 'diary': diary!.toJson(),
        if (editedAt != null) 'edited': editedAt!.toIso8601String(),
        if (drop != null) 'drop': drop!.toJson(),
        if (pause != null) 'pause': pause!.toJson(),
        if (parts.isNotEmpty) 'parts': [for (final p in parts) p.toJson()],
      };
}

enum LibraryStatus { watched, watchlist, library, dropped }

/// Фильм в библиотеке пользователя.
class LibraryMovie with HasReview {
  final String uuid;
  String title;

  /// Локализованное название (в языке [titleLang]). Имя историческое: приложение
  /// было русским-первым. Меняется через сеттер, который проставляет [titleLang].
  String? _ruTitle;
  String? get ruTitle => _ruTitle;
  set ruTitle(String? v) {
    _ruTitle = v;
    if (v != null && v.isNotEmpty) titleLang = LocaleController.instance.code;
  }

  /// Код языка, на котором сейчас лежит [ruTitle]. У легаси-записей — null,
  /// трактуется как 'ru'. По нему решаем, нужна ли пере-локализация при смене
  /// языка интерфейса.
  String? titleLang;
  double? kpRating;

  /// Пытались ли уже обогатить (чтобы не тратить лимит API повторно).
  bool enrichTried;

  int? year;
  int? runtimeMin;
  LibraryStatus status;

  /// Когда добавлен в список (для сортировки «Буду смотреть» новые→старые).
  DateTime? addedAt;

  /// Просмотры (у каждого — своя дата и своя оценка). Единственный источник
  /// правды: число повторов и оценка фильма считаются отсюда.
  List<Viewing> viewings;

  /// Оценка фильма без просмотров (оценили, не отметив просмотр). Как только
  /// появляется просмотр, она переезжает в него и здесь обнуляется.
  double? score;
  List<MovieEmotion> emotions;
  bool favorite;
  List<String> lists;

  /// Текст первой написанной рецензии (Markdown), разбор критика лежит в
  /// [reviewMeta]. Рецензии на другие просмотры — в [moreReviews].
  @override
  String? review;
  @override
  ReviewMeta? reviewMeta;

  /// Рецензии на другие просмотры. Первая остаётся в [review], чтобы её
  /// видели старые версии и бэкапы.
  List<ExtraReview> moreReviews;

  /// Кэш идентификаторов/постера от источников (kinopoisk.dev / KinoBD / TMDB).
  int? kinopoiskId;
  int? tmdbId;
  int? tvdbId;

  /// IMDb id (tt…) — универсальный мост между источниками: по нему запись
  /// находится в любой базе, поэтому смена источника не теряет данные.
  String? imdbId;
  String? posterUrl;

  /// Имя файла локального пользовательского постера (замена своим изображением).
  /// При показе приоритетнее сетевого `posterUrl`; на сервер/друзьям не уходит.
  String? posterFile;

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
    String? ruTitle,
    String? titleLang,
    this.kpRating,
    this.enrichTried = false,
    this.tmdbId,
    this.year,
    this.runtimeMin,
    this.status = LibraryStatus.library,
    this.addedAt,
    List<Viewing>? viewings,
    int rewatchCount = 0,
    this.score,
    List<MovieEmotion>? emotions,
    this.favorite = false,
    List<String>? lists,
    this.review,
    this.reviewMeta,
    List<ExtraReview>? moreReviews,
    this.kinopoiskId,
    this.tvdbId,
    this.imdbId,
    this.posterUrl,
    this.posterFile,
    List<String>? genres,
    List<String>? countries,
    this.detailsTried = false,
  })  : _ruTitle = ruTitle,
        titleLang = titleLang ??
            ((ruTitle != null && ruTitle.isNotEmpty)
                ? LocaleController.instance.code
                : null),
        viewings = viewings ?? [],
        emotions = emotions ?? [],
        lists = lists ?? [],
        moreReviews = moreReviews ?? [],
        genres = genres ?? [],
        countries = countries ?? [] {
    // Старый счётчик повторов мог обогнать список (импорт TV Time): достраиваем
    // просмотры без даты, чтобы число и список совпадали.
    if (rewatchCount > 0 && status == LibraryStatus.watched) {
      for (var i = this.viewings.length; i <= rewatchCount; i++) {
        this.viewings.add(Viewing(id: ''));
      }
    }
    stampViewingIds(this.viewings);
    adoptHeadlineScore();
  }

  /// Общая оценка (импорт, оценка до отметки просмотра) переезжает в последний
  /// просмотр, если своей у него нет, и обнуляется: дальше оценка фильма
  /// считается только из просмотров.
  ///
  /// Показанная оценка при этом не меняется. Старые версии брали оценку у
  /// последнего по дате просмотра, а из нескольких с одной датой — у первого
  /// (так отмечали «видел раньше»: дубли до секунды), общая была запасной.
  /// Поэтому общая достаётся последнему просмотру, только когда своей оценки
  /// нет ни у него, ни у его дублей; иначе она просто отбрасывается.
  void adoptHeadlineScore() {
    final head = score;
    if (head == null) return;
    final ordered = orderedViewings;
    if (ordered.isEmpty) return;
    final cv = ordered.last;
    final from = cv.date == null
        ? ordered.length - 1
        : ordered.indexWhere((v) => v.date == cv.date);
    if (ordered.skip(from).every((v) => v.score == null)) cv.score = head;
    score = null;
  }

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

  /// Просмотры по порядку: без даты первыми, дальше по дате.
  List<Viewing> get orderedViewings => orderViewings(viewings);

  /// Номер просмотра по порядку, с единицы; 0, если просмотр не отсюда.
  int ordinalOf(Viewing v) => orderedViewings.indexOf(v) + 1;

  Viewing? viewingById(String? id) {
    if (id == null) return null;
    for (final v in viewings) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// Оценка конкретного просмотра.
  double? scoreOf(Viewing v) => v.score;

  /// Текущий (последний по порядку) просмотр.
  Viewing? get currentViewing {
    final ordered = orderedViewings;
    return ordered.isEmpty ? null : ordered.last;
  }

  /// Оценка фильма: последний оценённый просмотр. Без просмотров — общая.
  /// С одним просмотром список не сортируем: геттер зовёт каждое сравнение в
  /// сортировке ленты.
  double? get currentScore => switch (viewings.length) {
        0 => score,
        1 => viewings.first.score ?? score,
        _ => lastRatedScore(orderedViewings) ?? score,
      };

  /// Оценка ближайшего оценённого просмотра перед [v]: «в прошлый раз».
  double? previousScore(Viewing v) {
    final ordered = orderedViewings;
    final at = ordered.indexOf(v);
    return at <= 0 ? null : lastRatedScore(ordered.sublist(0, at));
  }

  /// Досмотренных просмотров: брошенные и начатые попытки в счёт не идут.
  int get _fullCount {
    var n = 0;
    for (final v in viewings) {
      if (v.isFull) n++;
    }
    return n;
  }

  /// Повторов сверх первого досмотренного просмотра.
  int get rewatchCount => _fullCount > 1 ? _fullCount - 1 : 0;

  /// Общее число досмотренных просмотров.
  int get viewCount => _fullCount == 0 ? 1 : _fullCount;

  /// Смотрел ли повторно.
  bool get isRewatched => _fullCount > 1;

  /// Досмотрен хоть раз.
  bool get hasFullViewing => _fullCount > 0;

  /// Фильм брошен: каждый его просмотр брошен. Начатый, но не досмотренный
  /// фильм брошенным не считается. Старые версии бросали фильм статусом без
  /// просмотров, такая отметка тоже считается.
  bool get isDropped =>
      status == LibraryStatus.dropped ||
      (viewings.isNotEmpty && !hasFullViewing && pausedViewing == null);

  /// Просмотр на паузе («Досмотрю потом»); null, если такого нет.
  Viewing? get pausedViewing {
    final ordered = orderedViewings;
    for (var i = ordered.length - 1; i >= 0; i--) {
      if (ordered[i].isPaused) return ordered[i];
    }
    return null;
  }

  /// День последнего досмотренного просмотра: начатые и брошенные попытки
  /// не в счёт.
  DateTime? get lastFullViewing {
    DateTime? best;
    for (final v in viewings) {
      final d = v.date;
      if (d == null || !v.isFull) continue;
      if (best == null || d.isAfter(best)) best = d;
    }
    return best;
  }

  /// В «Просмотренных»: хоть раз досмотрен. Старые записи «просмотрено» без
  /// единого просмотра тоже здесь.
  bool get isWatched =>
      status == LibraryStatus.watched && (viewings.isEmpty || hasFullViewing);

  /// Последний по порядку брошенный просмотр; null, если не бросали.
  Viewing? get lastDropped {
    final ordered = orderedViewings;
    for (var i = ordered.length - 1; i >= 0; i--) {
      if (ordered[i].drop != null) return ordered[i];
    }
    return null;
  }

  /// Номер досмотренного просмотра по порядку, с единицы. Брошенные и
  /// начатые номера не получают (0) и следующие не сдвигают.
  int fullOrdinalOf(Viewing v) {
    var n = 0;
    for (final x in orderedViewings) {
      if (x.isFull) n++;
      if (x.id == v.id) return x.isFull ? n : 0;
    }
    return 0;
  }

  /// Минуты у экрана: досмотренный просмотр идёт целиком [runtime], брошенный
  /// и начатый до своей минуты (не дальше конца фильма), без минуты не идут.
  /// Без длительности такая попытка считается своей минутой, но не больше
  /// 10 часов.
  int screenMinutes(int? runtime) {
    var sum = 0;
    for (final v in viewings) {
      if (v.isFull) {
        sum += runtime ?? 0;
        continue;
      }
      final at = v.pause?.atMin ?? v.drop?.atMin;
      if (at != null) sum += at.clamp(0, runtime ?? 600);
    }
    return sum;
  }

  /// Все рецензии фильма: первая и на другие просмотры.
  List<HasReview> get allReviews => [
        if (hasReview) this,
        for (final r in moreReviews)
          if (r.hasReview) r,
      ];

  /// Название для показа: локализованное, если оно в языке интерфейса, иначе
  /// оригинал. Так при смене языка не показывается устаревший кэш (напр. русский
  /// при английском интерфейсе), пока пере-локализация не подтянет перевод.
  String get displayTitle {
    final rt = _ruTitle;
    if (rt != null &&
        rt.isNotEmpty &&
        (titleLang ?? 'ru') == LocaleController.instance.code) {
      return rt;
    }
    return title;
  }

  /// Постер для показа: локальный пользовательский (если задан), иначе сетевой.
  String? get displayPoster =>
      PosterStore.instance.pathOf(posterFile) ?? posterUrl;

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
        titleLang: j['titleLang'] as String? ??
            ((j['ruTitle'] as String?)?.isNotEmpty == true ? 'ru' : null),
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
        reviewMeta: _meta(j['reviewMeta']),
        moreReviews: [
          for (final r in (j['moreReviews'] as List? ?? []))
            if (r is Map) ExtraReview.fromJson(Map<String, dynamic>.from(r)),
        ],
        kinopoiskId: (j['kinopoiskId'] as num?)?.toInt(),
        tmdbId: (j['tmdbId'] as num?)?.toInt(),
        tvdbId: (j['tvdbId'] as num?)?.toInt(),
        imdbId: j['imdbId'] as String?,
        posterUrl: j['posterUrl'] as String?,
        posterFile: j['posterFile'] as String?,
        genres: (j['genres'] as List? ?? []).map((e) => '$e').toList(),
        countries: (j['countries'] as List? ?? []).map((e) => '$e').toList(),
        detailsTried: j['detailsTried'] == true,
      );

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'title': title,
        'ruTitle': ruTitle,
        'titleLang': titleLang,
        'kpRating': kpRating,
        'enrichTried': enrichTried,
        'year': year,
        'runtimeMin': runtimeMin,
        'status': status.name,
        'addedAt': addedAt?.toIso8601String(),
        'viewings': [for (final v in viewings) v.toJson()],
        // Число пишется для старых версий, новая считает его из списка.
        'rewatchCount': rewatchCount,
        'score': score,
        'emotions': [for (final e in emotions) e.toJson()],
        'favorite': favorite,
        'lists': lists,
        'review': review,
        if (reviewMeta != null) 'reviewMeta': reviewMeta!.toJson(),
        if (moreReviews.isNotEmpty)
          'moreReviews': [for (final r in moreReviews) r.toJson()],
        'kinopoiskId': kinopoiskId,
        'tmdbId': tmdbId,
        if (tvdbId != null) 'tvdbId': tvdbId,
        if (imdbId != null) 'imdbId': imdbId,
        'posterUrl': posterUrl,
        if (posterFile != null) 'posterFile': posterFile,
        if (genres.isNotEmpty) 'genres': genres,
        if (countries.isNotEmpty) 'countries': countries,
        if (detailsTried) 'detailsTried': true,
      };
}

/// Рецензия на ещё один просмотр фильма. Устроена как первая: текст и разбор,
/// просмотр записан в [ReviewMeta.viewId].
class ExtraReview with HasReview {
  final String id;
  @override
  String? review;
  @override
  ReviewMeta? reviewMeta;

  ExtraReview({required this.id, this.review, this.reviewMeta});

  factory ExtraReview.fromJson(Map<String, dynamic> j) => ExtraReview(
        id: '${j['id']}',
        review: j['review'] as String?,
        reviewMeta: _meta(j['reviewMeta']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'review': review,
        if (reviewMeta != null) 'reviewMeta': reviewMeta!.toJson(),
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

  /// Id первого просмотра (его дата, оценка и дневник лежат в полях серии).
  /// Нужен, чтобы окно просмотра, лента и синхронизация находили его так же,
  /// как повторы. Id уникален внутри серии.
  String vid;

  /// ПОВТОРНЫЕ просмотры (сверх первого в [watchedAt]/[score]) — у КАЖДОГО своя
  /// дата и своя оценка, как отдельные просмотры фильма. Первый просмотр — это
  /// сами поля watchedAt+score. Старые данные (rewatchDates) мигрируются сюда.
  List<Viewing> rewatchViews;

  /// НЕ сохраняется. Порядковый номер просмотра для копии-события в ленте
  /// (1 — первый, 2 — второй…); нужен, чтобы показать «2-й просмотр» как у фильмов.
  int rewatchOrdinal = 0;

  /// НЕ сохраняется. Id просмотра, который стоит за копией-событием в ленте.
  String? eventViewId;

  /// Дневник первого просмотра серии (настроение/с кем/где/фото/заметка).
  DiaryEntry? diary;

  /// Когда правили первый просмотр, см. [Viewing.editedAt].
  DateTime? editedAt;

  /// [rewatchCount] — счётчик старых версий: если он обогнал [rewatchViews],
  /// недостающие повторы достраиваются без даты, чтобы ×N совпадал со списком.
  Episode({
    this.season,
    this.number,
    this.watchedAt,
    this.runtimeMin,
    this.score,
    this.epId,
    String? vid,
    int rewatchCount = 0,
    List<Viewing>? rewatchViews,
    this.diary,
    this.editedAt,
  })  : vid = vid ?? 'f',
        rewatchViews = rewatchViews ?? [] {
    for (var i = this.rewatchViews.length; i < rewatchCount; i++) {
      this.rewatchViews.add(Viewing(id: ''));
    }
    stampViewingIds(this.rewatchViews, reserved: {this.vid});
  }

  /// Сколько раз серию пересматривали (0 — смотрели один раз).
  int get rewatchCount => rewatchViews.length;

  /// Все просмотры серии в порядке записи: первый = watchedAt+score, затем
  /// повторы. Первый отдаётся копией: менять его через репозиторий по [vid].
  List<Viewing> get views => [
        Viewing(
          id: vid,
          date: watchedAt,
          score: score,
          diary: diary,
          editedAt: editedAt,
        ),
        ...rewatchViews,
      ];

  /// Просмотры по порядку: без даты первыми, дальше по дате.
  List<Viewing> get orderedViews => orderViewings(views);

  /// Оценка конкретного просмотра.
  double? scoreOfView(Viewing v) => v.score;

  /// Оценка серии: последний оценённый просмотр. У серии без повторов это
  /// её собственная оценка: список собирать незачем, а зовут геттер часто
  /// (средняя сериала, сортировка ленты).
  double? get currentScore =>
      rewatchViews.isEmpty ? score : lastRatedScore(orderedViews);

  /// Всего просмотров серии (первый + повторы).
  int get watchCount => 1 + rewatchViews.length;

  /// Копия-«событие» одного просмотра (дата, его оценка и дневник) — для
  /// ленты, где один просмотр = одна запись. Id первого просмотра у копии
  /// тот же, что у серии: по нему видно, первый это просмотр или повтор.
  Episode copyForView(Viewing v) => Episode(
        season: season,
        number: number,
        watchedAt: v.date,
        runtimeMin: runtimeMin,
        score: v.score,
        epId: epId,
        vid: vid,
        diary: v.diary,
      )..eventViewId = v.id;

  /// У копии-события: это первый просмотр серии, а не повтор. Сама серия,
  /// не копия, тоже отвечает «да»: её поля и есть первый просмотр.
  bool get eventIsFirst => eventViewId == null || eventViewId == vid;

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

  /// Легаси-рассинхрон: счётчик `rewatchCount` мог обогнать `rewatchViews`
  /// (пересмотр сезона без даты; потеря повторов при старом слиянии). Конструктор
  /// достраивает недостающие повторы как «без даты» — чтобы ×N и список
  /// просмотров совпадали, а сами повторы можно было редактировать и удалять.
  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        season: (j['season'] as num?)?.toInt(),
        number: (j['number'] as num?)?.toInt(),
        watchedAt: _parse(j['watchedAt']),
        runtimeMin: (j['runtimeMin'] as num?)?.toInt(),
        score: (j['score'] as num?)?.toDouble(),
        epId: j['epId'] as String?,
        vid: j['vid'] as String?,
        rewatchCount: (j['rewatchCount'] as num?)?.toInt() ?? 0,
        rewatchViews: _parseViews(j),
        diary: j['diary'] is Map
            ? DiaryEntry.fromJson((j['diary'] as Map).cast<String, dynamic>())
            : null,
        editedAt: _parse(j['vEdited']),
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
          if (_parse(e) != null) Viewing(id: '', date: _parse(e))
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
        if (vid != 'f') 'vid': vid,
        // Число пишется для старых версий, новая считает его из списка.
        'rewatchCount': rewatchCount,
        if (rewatchViews.isNotEmpty)
          'rewatchViews': [for (final v in rewatchViews) v.toJson()],
        if (diary != null && diary!.isNotEmpty) 'diary': diary!.toJson(),
        if (editedAt != null) 'vEdited': editedAt!.toIso8601String(),
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
class LibrarySeries with HasReview {
  final String tvShowId;
  String title;

  /// Локализованное название (в языке [titleLang]) — см. [LibraryMovie.ruTitle].
  String? _ruTitle;
  String? get ruTitle => _ruTitle;
  set ruTitle(String? v) {
    _ruTitle = v;
    if (v != null && v.isNotEmpty) titleLang = LocaleController.instance.code;
  }

  /// Язык, на котором сейчас лежит [ruTitle] (null → легаси, трактуем как 'ru').
  String? titleLang;
  List<Episode> episodes;
  bool favorite;

  /// Сериал добавлен в «Буду смотреть». Отметку ставит пользователь, и она
  /// держится, даже когда часть серий уже просмотрена.
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

  /// Год выхода (первый эфир) — из TMDB. Для статистики оценок по годам выхода.
  int? year;

  /// Выходит ли сериал и сколько серий уже вышло (TMDB). По ним решается,
  /// досмотрен сериал или догнан, см. `utils/series_finale.dart`.
  SeriesAir? air;

  /// Даты, когда человек догонял вышедшие серии. Пишутся в момент, когда
  /// вышла новая серия, чтобы плашка «Догнал» осталась в истории ленты.
  List<DateTime> caughtUpAt;

  /// Рецензии на сезон или диапазон сезонов. Рецензия на весь сериал
  /// остаётся в [review] и [reviewMeta]: так её видят старые версии.
  List<SeasonReview> seasonReviews;

  /// Откуда берётся оценка сериала: средняя по сериям, свод рецензий на
  /// сезоны или рецензия на весь сериал. Ставит человек кнопкой
  /// «Выставить сериалу», [scoreSourceAt] нужна слиянию при синке.
  SeriesScoreSource scoreSource;
  DateTime? scoreSourceAt;
  double? score;

  /// Текст рецензии (Markdown). Разбор критика лежит в [reviewMeta].
  @override
  String? review;
  @override
  ReviewMeta? reviewMeta;
  int? kinopoiskId;
  int? tmdbId;
  int? tvdbId;
  String? imdbId;
  double? kpRating;
  bool enrichTried;
  String? posterUrl;

  /// Имя файла локального пользовательского постера (см. [LibraryMovie.posterFile]).
  String? posterFile;

  /// Когда сериал попал в библиотеку — по ней «Буду смотреть» сортирует
  /// сериалы вместе с фильмами. У импорта TV Time даты нет: такие записи
  /// сортировка уводит вниз.
  DateTime? addedAt;

  LibrarySeries({
    required this.tvShowId,
    required this.title,
    String? ruTitle,
    String? titleLang,
    List<Episode>? episodes,
    this.addedAt,
    this.favorite = false,
    this.watchlist = false,
    this.dropped = false,
    this.finished = false,
    this.totalEpisodes,
    this.year,
    this.air,
    List<DateTime>? caughtUpAt,
    List<SeasonReview>? seasonReviews,
    this.scoreSource = SeriesScoreSource.episodes,
    this.scoreSourceAt,
    this.score,
    this.review,
    this.reviewMeta,
    this.kinopoiskId,
    this.tmdbId,
    this.tvdbId,
    this.imdbId,
    this.kpRating,
    this.enrichTried = false,
    this.posterUrl,
    this.posterFile,
  })  : _ruTitle = ruTitle,
        titleLang = titleLang ??
            ((ruTitle != null && ruTitle.isNotEmpty)
                ? LocaleController.instance.code
                : null),
        episodes = episodes ?? [],
        caughtUpAt = caughtUpAt ?? [],
        seasonReviews = seasonReviews ?? [];

  /// Полностью ли просмотрен сериал (известно общее число серий и все отмечены).
  bool get isCompleted =>
      totalEpisodes != null &&
      totalEpisodes! > 0 &&
      episodes.length >= totalEpisodes!;

  int get episodesSeen => episodes.length;

  /// Средняя оценка по оценённым сериям (или null, если ни одна не оценена).
  /// У пересмотренной серии берётся её последняя оценка.
  double? get episodeScoreAvg {
    final scores =
        episodes.map((e) => e.currentScore).whereType<double>().toList();
    if (scores.isEmpty) return null;
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    return (avg * 10).round() / 10; // округляем до 0.1
  }

  /// Оценка сериала для показа: если есть оценки серий — их среднее (считается
  /// автоматически, руками не задаётся); иначе — ручная общая оценка.
  double? get displayScore => switch (scoreSource) {
        SeriesScoreSource.reviews => seasonReviewsAverage ?? _ownScore,
        SeriesScoreSource.review => reviewMeta?.average ?? _ownScore,
        SeriesScoreSource.episodes => _ownScore,
      };

  /// Оценка без рецензий: средняя по сериям, иначе ручная.
  double? get _ownScore => episodeScoreAvg ?? score;

  /// Рецензия, которая идёт в свод за [season]: опубликованная, с оценками и
  /// на самый поздний просмотр этого сезона.
  SeasonReview? summaryReviewOf(int season) {
    SeasonReview? best;
    for (final p in seasonReviews) {
      if (!p.covers(season) || !p.countsInSummary) continue;
      if (best == null || p.pass > best.pass) best = p;
    }
    return best;
  }

  /// Свод рецензий на сезоны: по каждому сезону берётся средняя его последней
  /// рецензии, поэтому рецензия на три сезона весит втрое больше рецензии на
  /// один. Черновики и рецензии без оценок не в счёт.
  double? get seasonReviewsAverage {
    final seasons = <int>{
      for (final p in seasonReviews)
        if (p.countsInSummary)
          for (var n = p.from; n <= p.to; n++) n,
    };
    if (seasons.isEmpty) return null;
    var sum = 0.0;
    for (final n in seasons) {
      sum += summaryReviewOf(n)!.reviewMeta!.average!;
    }
    return (sum / seasons.length * 10).round() / 10;
  }

  DateTime? get lastWatch {
    DateTime? best;
    for (final e in episodes) {
      final d = e.watchedAt;
      if (d == null) continue;
      if (best == null || d.isAfter(best)) best = d;
    }
    return best;
  }

  String get displayTitle {
    final rt = _ruTitle;
    if (rt != null &&
        rt.isNotEmpty &&
        (titleLang ?? 'ru') == LocaleController.instance.code) {
      return rt;
    }
    return title;
  }

  /// Постер для показа: локальный пользовательский (если задан), иначе сетевой.
  String? get displayPoster =>
      PosterStore.instance.pathOf(posterFile) ?? posterUrl;

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
      // Каждый просмотр (первый + повторы) — своё событие с датой, оценкой и
      // порядковым номером по дате (для метки «2-й просмотр» в ленте).
      final vs = e.orderedViews;
      for (var i = 0; i < vs.length; i++) {
        final copy = e.copyForView(vs[i])..rewatchOrdinal = i + 1;
        if (vs[i].date == null) {
          undated.add(copy);
        } else {
          dated.add(copy);
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
      titleLang: j['titleLang'] as String? ??
          ((j['ruTitle'] as String?)?.isNotEmpty == true ? 'ru' : null),
      episodes: eps,
      addedAt:
          j['addedAt'] == null ? null : DateTime.tryParse('${j['addedAt']}'),
      favorite: j['favorite'] == true,
      watchlist: j['watchlist'] == true,
      dropped: j['dropped'] == true,
      finished: j['finished'] == true,
      totalEpisodes: (j['totalEpisodes'] as num?)?.toInt(),
      year: (j['year'] as num?)?.toInt(),
      air: j['air'] is Map<String, dynamic>
          ? SeriesAir.fromJson(j['air'] as Map<String, dynamic>)
          : null,
      caughtUpAt: [
        for (final d in (j['caughtUpAt'] as List? ?? []))
          ?DateTime.tryParse('$d'),
      ],
      seasonReviews: [
        for (final p in (j['seasonReviews'] as List? ?? []))
          if (p is Map<String, dynamic>) SeasonReview.fromJson(p),
      ],
      scoreSource: SeriesScoreSource.values.firstWhere(
        (v) => v.name == j['scoreSource'],
        orElse: () => SeriesScoreSource.episodes,
      ),
      scoreSourceAt: j['scoreSourceAt'] == null
          ? null
          : DateTime.tryParse('${j['scoreSourceAt']}'),
      score: (j['score'] as num?)?.toDouble(),
      review: j['review'] as String?,
      reviewMeta: _meta(j['reviewMeta']),
      kinopoiskId: (j['kinopoiskId'] as num?)?.toInt(),
      tmdbId: (j['tmdbId'] as num?)?.toInt(),
      tvdbId: (j['tvdbId'] as num?)?.toInt(),
      imdbId: j['imdbId'] as String?,
      kpRating: (j['kpRating'] as num?)?.toDouble(),
      enrichTried: j['enrichTried'] == true,
      posterUrl: j['posterUrl'] as String?,
      posterFile: j['posterFile'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'tvShowId': tvShowId,
        'title': title,
        'ruTitle': ruTitle,
        'titleLang': titleLang,
        'episodes': [for (final e in episodes) e.toJson()],
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
        'favorite': favorite,
        'watchlist': watchlist,
        'dropped': dropped,
        'finished': finished,
        'totalEpisodes': totalEpisodes,
        'year': year,
        if (air != null) 'air': air!.toJson(),
        if (caughtUpAt.isNotEmpty)
          'caughtUpAt': [for (final d in caughtUpAt) d.toIso8601String()],
        if (seasonReviews.isNotEmpty)
          'seasonReviews': [for (final p in seasonReviews) p.toJson()],
        if (scoreSource != SeriesScoreSource.episodes)
          'scoreSource': scoreSource.name,
        if (scoreSourceAt != null)
          'scoreSourceAt': scoreSourceAt!.toIso8601String(),
        'score': score,
        'review': review,
        if (reviewMeta != null) 'reviewMeta': reviewMeta!.toJson(),
        'kinopoiskId': kinopoiskId,
        'tmdbId': tmdbId,
        if (tvdbId != null) 'tvdbId': tvdbId,
        if (imdbId != null) 'imdbId': imdbId,
        'kpRating': kpRating,
        'enrichTried': enrichTried,
        'posterUrl': posterUrl,
        if (posterFile != null) 'posterFile': posterFile,
      };
}

/// Откуда берётся оценка сериала.
enum SeriesScoreSource { episodes, reviews, review }

/// Рецензия на один сезон или диапазон сезонов подряд. Текст и разбор
/// устроены как у рецензии на весь сериал.
class SeasonReview with HasReview {
  final String id;
  int from;
  int to;

  /// Какой по счёту просмотр этих сезонов описывает рецензия: 1 — первый,
  /// 2 — пересмотр и так далее. На один просмотр сезона одна рецензия.
  int pass;
  @override
  String? review;
  @override
  ReviewMeta? reviewMeta;

  SeasonReview({
    required this.id,
    required this.from,
    required this.to,
    this.pass = 1,
    this.review,
    this.reviewMeta,
  });

  bool covers(int season) => season >= from && season <= to;

  /// Идёт ли рецензия в свод: не черновик и с оценками по пунктам.
  bool get countsInSummary =>
      reviewMeta?.average != null && !(reviewMeta?.draft ?? false);

  factory SeasonReview.fromJson(Map<String, dynamic> j) {
    final pass = (j['pass'] as num?)?.toInt() ?? 1;
    return SeasonReview(
      id: '${j['id']}',
      from: (j['from'] as num?)?.toInt() ?? 1,
      to: (j['to'] as num?)?.toInt() ?? (j['from'] as num?)?.toInt() ?? 1,
      pass: pass < 1 ? 1 : pass,
      review: j['review'] as String?,
      reviewMeta: _meta(j['reviewMeta']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        if (pass > 1) 'pass': pass,
        'review': review,
        if (reviewMeta != null) 'reviewMeta': reviewMeta!.toJson(),
      };
}

/// Сведения TMDB о выходе сериала: закрыт ли он, сколько серий вышло и когда
/// ждать следующую.
class SeriesAir {
  /// Статус TMDB: `Ended`, `Canceled`, `Returning Series`, `In Production`…
  final String? status;

  /// Вышедших серий без спецвыпусков.
  final int? aired;

  /// Сезон последней вышедшей серии.
  final int? lastSeason;

  /// Ближайшая невышедшая серия, дата ISO `YYYY-MM-DD`.
  final int? nextSeason;
  final int? nextNumber;
  final String? nextDate;

  /// Когда сведения пришли из TMDB: по нему обход решает, пора ли обновить.
  final DateTime? checkedAt;

  const SeriesAir({
    this.status,
    this.aired,
    this.lastSeason,
    this.nextSeason,
    this.nextNumber,
    this.nextDate,
    this.checkedAt,
  });

  /// Новых серий у сериала уже не будет.
  bool get ended => status == 'Ended' || status == 'Canceled';

  factory SeriesAir.fromJson(Map<String, dynamic> j) => SeriesAir(
        status: j['status'] as String?,
        aired: (j['aired'] as num?)?.toInt(),
        lastSeason: (j['lastSeason'] as num?)?.toInt(),
        nextSeason: (j['nextSeason'] as num?)?.toInt(),
        nextNumber: (j['nextNumber'] as num?)?.toInt(),
        nextDate: j['nextDate'] as String?,
        checkedAt: j['checkedAt'] == null
            ? null
            : DateTime.tryParse('${j['checkedAt']}'),
      );

  Map<String, dynamic> toJson() => {
        if (status != null) 'status': status,
        if (aired != null) 'aired': aired,
        if (lastSeason != null) 'lastSeason': lastSeason,
        if (nextSeason != null) 'nextSeason': nextSeason,
        if (nextNumber != null) 'nextNumber': nextNumber,
        if (nextDate != null) 'nextDate': nextDate,
        if (checkedAt != null) 'checkedAt': checkedAt!.toIso8601String(),
      };
}

/// Элемент ленты «Просмотрено»: либо просмотр фильма, либо СЕССИЯ сериала
/// (серии, просмотренные подряд одним блоком).
class WatchedEntry {
  final LibraryMovie? movie;
  final Viewing? viewing;
  final EpisodeSession? session;

  /// Номер прошлого захода просмотра: запись — строка «начал» или
  /// «продолжил» в день этого захода. null у самого просмотра.
  final int? part;

  const WatchedEntry.movie(this.movie, this.viewing, {this.part})
      : session = null;
  const WatchedEntry.session(this.session)
      : movie = null,
        viewing = null,
        part = null;

  bool get isSeries => session != null;
  DateTime? get date => isSeries
      ? session!.start
      : (part != null ? viewing!.parts[part!].date : viewing?.date);
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

/// Разбор рецензии из JSON; мусор вместо объекта даёт null.
ReviewMeta? _meta(dynamic v) =>
    v is Map ? ReviewMeta.fromJson(Map<String, dynamic>.from(v)) : null;
