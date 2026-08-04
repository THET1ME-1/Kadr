import '../l10n/strings.dart';
import '../models/library_entry.dart';
import 'format.dart';

/// Чем занят фон карточки «Поделиться».
enum ShareTexture {
  /// Кадр из фильма (бэкдроп TMDB) в дуотоне.
  frame,

  /// Кромки киноплёнки, задник из размытого постера.
  film,

  /// Название фильма во всю карточку — работает даже без картинок.
  letters,
}

/// Приводит желаемую фактуру к тому, что можно нарисовать этим фильмом.
///
/// Порядок отката: кадр → плёнка → буквы. Пустой заливки не остаётся никогда,
/// поэтому у записи без единой картинки карточка всё равно выглядит собранной.
ShareTexture resolveShareTexture(
  ShareTexture wanted, {
  required bool hasBackdrop,
  required bool hasPoster,
}) {
  if (wanted == ShareTexture.frame && hasBackdrop) return ShareTexture.frame;
  if (wanted != ShareTexture.letters && hasPoster) return ShareTexture.film;
  return ShareTexture.letters;
}

/// Строка под названием: «2026 · Ужасы, триллер · 1 ч 58 мин».
///
/// Жанров показываем не больше двух — иначе строка ломается на две и рушит
/// вёрстку карточки. Пустые части выпадают целиком, разделителей-сирот нет.
String? shareMetaLine(LibraryMovie m) {
  final parts = <String>[
    if (m.year != null) '${m.year}',
    if (m.genres.isNotEmpty)
      capitalize(m.genres.take(2).join(', ').toLowerCase()),
    if (m.runtimeMin != null && m.runtimeMin! > 0)
      humanDuration(Duration(minutes: m.runtimeMin!)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Правый угол подвала: дата просмотра, номер пересмотра или «В списке».
String shareFooterNote(LibraryMovie m) {
  final facts = shareFactsOf(m);
  if (facts.wantToWatch) return tr('share_in_list');
  final date = facts.watchedAt;
  if (date == null) return '';
  final when = longDate(date);
  if (!facts.isRewatch) return when;
  return '${trf('share_view_nth', {'n': '${facts.viewNumber}'})} · $when';
}

/// То, что карточка знает о просмотре: оценка, дата, какой он по счёту.
class ShareFacts {
  const ShareFacts({
    this.score,
    this.watchedAt,
    this.viewNumber = 1,
    this.wantToWatch = false,
    this.dropped = false,
    this.emotion,
  });

  /// Оценка показываемого просмотра (или общая, если просмотров нет).
  final double? score;

  /// Дата последнего просмотра, если она известна.
  final DateTime? watchedAt;

  /// Какой это по счёту просмотр: 1 — первый, 2 — второй и так далее.
  final int viewNumber;

  /// Фильм ещё не смотрели, он лежит в «Буду смотреть».
  final bool wantToWatch;

  /// Фильм брошен.
  final bool dropped;

  /// Отмеченная эмоция, если есть.
  final MovieEmotion? emotion;

  bool get isRewatch => viewNumber > 1;
}

/// Собирает факты о фильме для карточки.
///
/// Оценка берётся у последнего просмотра и откатывается на общую — так же, как
/// `scoreOf()` в карточке фильма, чтобы цифры сходились. Число просмотров
/// учитывает и старый импорт TV Time, где вместо записей стоял счётчик.
ShareFacts shareFactsOf(LibraryMovie m) {
  if (m.status == LibraryStatus.watchlist) {
    return const ShareFacts(wantToWatch: true);
  }

  final emotion = m.emotions.isEmpty ? null : m.emotions.first;
  final current = m.currentViewing;

  return ShareFacts(
    score: current != null ? m.scoreOf(current) : m.score,
    watchedAt: m.lastViewing,
    viewNumber: m.viewCount,
    dropped: m.status == LibraryStatus.dropped,
    emotion: emotion,
  );
}
