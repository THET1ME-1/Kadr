/// Ролики и циклы с YouTube в библиотеке (макет «Циклы с YouTube», Э1).
///
/// Цикл — плейлист канала, Kadr хранит его как сериал из одного сезона:
/// выпуск становится серией. Одиночный ролик живёт фильмом.
library;

/// Номер выпуска из названия ролика: «№4», «#4», «Часть 4», «Part 4».
/// null — номера нет.
int? ytIssueNumber(String title) {
  final m = _issueRe.firstMatch(title);
  return m == null ? null : int.tryParse(m.group(1)!);
}

// Границы слова через \p{L}: \b в Dart знает только латиницу.
final _issueRe = RegExp(
  r'(?:№|#|(?<!\p{L})(?:часть|выпуск|серия|эпизод|глава|part|episode|ep\.?|chapter)(?!\p{L}))\s*(\d{1,4})(?!\d)',
  caseSensitive: false,
  unicode: true,
);

/// Название цикла из названия выпуска: всё до номера («Абсолют Флэш №1» →
/// «Абсолют Флэш»). null — номера нет или до него пусто.
String? ytCycleName(String title) {
  final m = _issueRe.firstMatch(title);
  if (m == null) return null;
  final name = title
      .substring(0, m.start)
      .replaceAll(RegExp(r'[\s:|,.\-–—(\[]+$', unicode: true), '')
      .trim();
  return name.length < 2 ? null : name;
}

/// Подзаголовок выпуска: слова в скобках после номера («Абсолют Бэтмен №24
/// (Бэтгёрл)» → «Бэтгёрл»). Метку издателя вроде «(DC)» не берёт.
String? ytSubtitle(String title) {
  final m = _issueRe.firstMatch(title);
  if (m == null) return null;
  final rest = title.substring(m.end);
  final p = RegExp(r'\(([^)]*)\)').firstMatch(rest);
  if (p == null) return null;
  final text = p.group(1)!.trim();
  if (text.isEmpty || RegExp(r'^[A-Z]{1,6}$').hasMatch(text)) return null;
  return text;
}

/// Слова названия для сравнения: строчные, без знаков.
Set<String> ytWords(String s) => {
      for (final w in s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
        if (w.isNotEmpty) w,
    };

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v');

/// Ролик цикла: id, название, длина в секундах и день выхода.
class YtEntry {
  final String id;
  String title;
  int? durSec;
  DateTime? published;

  YtEntry({required this.id, required this.title, this.durSec, this.published});

  factory YtEntry.fromJson(Map j) => YtEntry(
        id: '${j['id']}',
        title: '${j['t'] ?? ''}',
        durSec: (j['d'] as num?)?.toInt(),
        published: _date(j['p']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        't': title,
        if (durSec != null) 'd': durSec,
        if (published != null) 'p': published!.toIso8601String(),
      };

  /// Длина в минутах для времени у экрана.
  int? get runtimeMin => durSec == null ? null : (durSec! / 60).ceil();

  String get url => ytWatchUrl(id);

  /// Кадр 16:9 без полос: для плиток выпусков.
  String get still => 'https://i.ytimg.com/vi/$id/mqdefault.jpg';

  /// Крупный кадр: шапка и обложка цикла.
  String get cover => ytCover(id);
}

String ytWatchUrl(String videoId) => 'https://www.youtube.com/watch?v=$videoId';

String ytCover(String videoId) =>
    'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';

/// Цикл с YouTube: плейлист канала как сериал из одного сезона. Номер серии —
/// место ролика в [videos]: новые ролики только дописываются в конец, поэтому
/// номера отмеченных выпусков не сдвигаются.
class YtCycle {
  final String playlistId;
  String channelId;
  String channelName;
  String? avatar;
  List<YtEntry> videos;

  /// Присылать ли пуш о новых выпусках.
  bool notify;

  /// Когда последний раз смотрели ленту плейлиста.
  DateTime? checkedAt;

  YtCycle({
    required this.playlistId,
    required this.channelId,
    required this.channelName,
    this.avatar,
    List<YtEntry>? videos,
    this.notify = true,
    this.checkedAt,
  }) : videos = videos ?? [];

  factory YtCycle.fromJson(Map j) => YtCycle(
        playlistId: '${j['list']}',
        channelId: '${j['ch'] ?? ''}',
        channelName: '${j['chName'] ?? ''}',
        avatar: j['ava'] as String?,
        videos: [
          for (final v in (j['videos'] as List? ?? const []))
            if (v is Map) YtEntry.fromJson(v),
        ],
        notify: j['notify'] != false,
        checkedAt: _date(j['checked']),
      );

  Map<String, dynamic> toJson() => {
        'list': playlistId,
        'ch': channelId,
        'chName': channelName,
        if (avatar != null) 'ava': avatar,
        'videos': [for (final v in videos) v.toJson()],
        if (!notify) 'notify': false,
        if (checkedAt != null) 'checked': checkedAt!.toIso8601String(),
      };

  String get url => 'https://www.youtube.com/playlist?list=$playlistId';

  /// Выпуск по номеру серии (с единицы); null — такого нет.
  YtEntry? entryAt(int number) =>
      number >= 1 && number <= videos.length ? videos[number - 1] : null;

  /// Подпись выпуска: «№4» из названия, иначе его место в цикле.
  String labelOf(int number) {
    final issue = entryAt(number) == null
        ? null
        : ytIssueNumber(entryAt(number)!.title);
    return '№${issue ?? number}';
  }
}

/// Одиночный ролик YouTube в библиотеке: живёт фильмом.
class YtRef {
  final String videoId;
  String channelId;
  String channelName;
  String? avatar;
  DateTime? published;

  YtRef({
    required this.videoId,
    required this.channelId,
    required this.channelName,
    this.avatar,
    this.published,
  });

  factory YtRef.fromJson(Map j) => YtRef(
        videoId: '${j['id']}',
        channelId: '${j['ch'] ?? ''}',
        channelName: '${j['chName'] ?? ''}',
        avatar: j['ava'] as String?,
        published: _date(j['p']),
      );

  Map<String, dynamic> toJson() => {
        'id': videoId,
        'ch': channelId,
        'chName': channelName,
        if (avatar != null) 'ava': avatar,
        if (published != null) 'p': published!.toIso8601String(),
      };

  String get url => ytWatchUrl(videoId);
}
