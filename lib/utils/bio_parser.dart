/// Разбор русских биографий TMDB.
///
/// Русское сообщество TMDB пишет их по единому шаблону:
///
/// ```
/// 💥Имя. Родился в 1946-ом году…
///
/// 🏆Главные награды🏆: Оскар (1994) [Список Шиндлера], BAFTA (1994) […]
///
/// 🎬Главные проекты🎬: «Челюсти» (1975), «Фабельманы» (2022)
///
/// ⭐Интересный факт⭐: …
/// ```
///
/// Сплошным абзацем это читается плохо, а названия фильмов внутри просятся в
/// ссылки. Разбираем шаблон на части; если он не узнан (английский текст,
/// произвольная биография), возвращаем текст как есть.
library;

/// Награда: премия, год вручения и фильм, за который её дали.
class BioAward {
  final String title;
  final int? year;

  /// Фильм из квадратных скобок. У наград вроде звезды на Аллее славы его нет.
  final String? film;

  const BioAward({required this.title, this.year, this.film});
}

/// Заметный проект: название и год выхода.
class BioWork {
  final String title;
  final int? year;

  const BioWork({required this.title, this.year});
}

/// Разобранная биография.
class ParsedBio {
  final String intro;
  final List<BioAward> awards;
  final List<BioWork> works;
  final String? trivia;

  const ParsedBio({
    required this.intro,
    this.awards = const [],
    this.works = const [],
    this.trivia,
  });

  /// Узнали ли шаблон. Если нет, показываем [intro] обычным абзацем.
  bool get isStructured => awards.isNotEmpty || works.isNotEmpty;
}

/// Заголовки секций. Эмодзи вокруг них необязательны: у части персон их нет.
final RegExp _awardsHead = RegExp(r'Главные\s+награды', caseSensitive: false);
final RegExp _worksHead =
    RegExp(r'Главные\s+(?:проекты|роли|фильмы)', caseSensitive: false);

/// `\S*` вместо `\w*`: в Dart `\w` — только латиница, кириллицу он не ловит.
final RegExp _triviaHead =
    RegExp(r'Интересн\S*\s+факт', caseSensitive: false);

/// «Оскар (1994) [Список Шиндлера]» и «Звезда на Аллее славы (2012)».
/// Название премии тянем не жадно от начала записи, поэтому запятые внутри
/// квадратных скобок список не рвут.
final RegExp _awardRe = RegExp(r'([^,\[\]()]+?)\s*\((\d{4})\)(?:\s*\[([^\]]+)\])?');

/// «Челюсти» (1975)
final RegExp _workRe = RegExp(r'«([^»]+)»\s*(?:\((\d{4})\))?');

/// Ведущие эмодзи и служебные символы в начале абзаца.
final RegExp _leadingJunk = RegExp(r'^[\s\p{S}\p{P}]+', unicode: true);

ParsedBio parseBio(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const ParsedBio(intro: '');

  final awardsAt = _headStart(text, _awardsHead);
  final worksAt = _headStart(text, _worksHead);
  final triviaAt = _headStart(text, _triviaHead);

  final starts = [awardsAt, worksAt, triviaAt].whereType<int>().toList()..sort();
  if (starts.isEmpty) return ParsedBio(intro: text);

  String section(int? start) {
    if (start == null) return '';
    final next = starts.firstWhere((s) => s > start, orElse: () => text.length);
    final body = text.substring(start, next);
    // Содержимое идёт после двоеточия заголовка.
    final colon = body.indexOf(':');
    return (colon == -1 ? body : body.substring(colon + 1)).trim();
  }

  final trivia = section(triviaAt);
  return ParsedBio(
    intro: _clean(text.substring(0, starts.first)),
    awards: _awards(section(awardsAt)),
    works: _works(section(worksAt)),
    trivia: trivia.isEmpty ? null : _trimTail(trivia),
  );
}

/// Начало абзаца с заголовком: от заголовка отступаем назад к переносу строки,
/// чтобы эмодзи перед ним не уехали во вступление.
int? _headStart(String text, RegExp head) {
  final m = head.firstMatch(text);
  if (m == null) return null;
  final lineStart = text.lastIndexOf('\n', m.start);
  return lineStart == -1 ? m.start : lineStart + 1;
}

List<BioAward> _awards(String body) {
  if (body.isEmpty) return const [];
  final out = <BioAward>[];
  for (final m in _awardRe.allMatches(body)) {
    final title = _clean(m.group(1) ?? '');
    if (title.isEmpty) continue;
    out.add(BioAward(
      title: title,
      year: int.tryParse(m.group(2) ?? ''),
      film: m.group(3)?.trim(),
    ));
  }
  return out;
}

List<BioWork> _works(String body) {
  if (body.isEmpty) return const [];
  final out = <BioWork>[];
  for (final m in _workRe.allMatches(body)) {
    final title = m.group(1)?.trim() ?? '';
    if (title.isEmpty) continue;
    out.add(BioWork(title: title, year: int.tryParse(m.group(2) ?? '')));
  }
  return out;
}

/// Снимает ведущие эмодзи и знаки, хвостовые пробелы и запятые.
String _clean(String s) => _trimTail(s.replaceFirst(_leadingJunk, ''));

String _trimTail(String s) =>
    s.trim().replaceFirst(RegExp(r'[\s,;]+$'), '');
