import '../models/library_entry.dart';

/// Просмотр сезона целиком. Отдельно он не хранится: N-й просмотр сезона —
/// это N-й по порядку просмотр каждой его серии.
class SeasonPassState {
  /// Сколько раз сезон досмотрен: у каждой серии не меньше стольких
  /// просмотров.
  final int completed;

  /// Сколько серий уже есть в идущем просмотре (номер [current]).
  final int done;

  /// Серий в сезоне, по которым считаем.
  final int total;

  /// Когда шёл идущий просмотр, а если он не начат — последний законченный.
  final DateTime? from;
  final DateTime? to;

  const SeasonPassState({
    required this.completed,
    required this.done,
    required this.total,
    this.from,
    this.to,
  });

  /// Номер идущего или следующего просмотра.
  int get current => completed + 1;

  /// Просмотр начат, но не закончен.
  bool get inProgress => done > 0 && done < total;

  /// Сколько серий осталось до конца идущего просмотра.
  int get left => total - done;

  /// Что делает широкая кнопка сезона: она называет следующий шаг.
  SeasonAction get action {
    if (completed >= 1 && !inProgress) return SeasonAction.rewatch;
    return done > 0 || completed >= 1
        ? SeasonAction.markRest
        : SeasonAction.markAll;
  }

  /// Нужна ли полоса пересмотра под кнопками: идёт пересмотр или сезон
  /// досмотрен не один раз. Ход первого просмотра виден на таблетке сезона.
  bool get showsStrip => completed >= 1 && (inProgress || completed >= 2);
}

/// Следующий шаг с сезоном.
enum SeasonAction {
  /// Сезон не начат: «Отметить весь сезон».
  markAll,

  /// Просмотр начат и не закончен: «Отметить ещё N».
  markRest,

  /// Все серии просмотрены поровну: «Пересмотреть сезон».
  rewatch,
}

DateTime? _earlier(DateTime? a, DateTime? b) =>
    a == null || (b != null && b.isBefore(a)) ? b : a;

DateTime? _later(DateTime? a, DateTime? b) =>
    a == null || (b != null && b.isAfter(a)) ? b : a;

/// Состояние просмотра сезона [season] по сериям с номерами [numbers]
/// (обычно вышедшие серии из TMDB). Серия, которую пересматривали чаще
/// остальных, счёт не сдвигает: сезон досмотрен столько раз, сколько раз
/// посмотрена самая редкая его серия.
SeasonPassState seasonPass(LibrarySeries s, int season, Iterable<int> numbers) {
  final eps = [for (final n in numbers) s.watchedEpisode(season, n)];
  if (eps.isEmpty) {
    return const SeasonPassState(completed: 0, done: 0, total: 0);
  }
  var completed = eps.first?.watchCount ?? 0;
  for (final e in eps) {
    final c = e?.watchCount ?? 0;
    if (c < completed) completed = c;
  }
  final current = completed + 1;
  final done = eps.where((e) => (e?.watchCount ?? 0) >= current).length;
  // Даты берём у идущего просмотра, а пока он не начат — у законченного.
  final pass = done > 0 ? current : completed;
  DateTime? from, to;
  if (pass > 0) {
    for (final e in eps) {
      if (e == null || e.watchCount < pass) continue;
      final d = e.orderedViews[pass - 1].date;
      from = _earlier(from, d);
      to = _later(to, d);
    }
  }
  return SeasonPassState(
    completed: completed,
    done: done,
    total: eps.length,
    from: from,
    to: to,
  );
}

/// Просмотр охвата рецензии: номер, даты и досмотрен ли он.
class ScopePass {
  final int pass;
  final DateTime? from;
  final DateTime? to;

  /// У каждой отмеченной серии охвата есть такой просмотр.
  final bool complete;
  const ScopePass(this.pass, {this.from, this.to, this.complete = false});
}

/// Просмотры сезонов [from]..[to] (оба null — весь сериал) для выбора в
/// рецензии. Их столько, сколько раз посмотрена самая пересмотренная серия
/// охвата; без отметок остаётся один первый просмотр без дат.
List<ScopePass> scopePasses(LibrarySeries s, int? from, int? to) {
  final eps = [
    for (final e in s.episodes)
      if (from == null ||
          to == null ||
          ((e.season ?? 0) >= from && (e.season ?? 0) <= to))
        e,
  ];
  var count = 1;
  for (final e in eps) {
    if (e.watchCount > count) count = e.watchCount;
  }
  return [
    for (var pass = 1; pass <= count; pass++)
      () {
        DateTime? a, b;
        var all = eps.isNotEmpty;
        for (final e in eps) {
          if (e.watchCount < pass) {
            all = false;
            continue;
          }
          final d = e.orderedViews[pass - 1].date;
          a = _earlier(a, d);
          b = _later(b, d);
        }
        return ScopePass(pass, from: a, to: b, complete: all);
      }(),
  ];
}

/// Сколько раз целиком посмотрен сезон [season] по отмеченным сериям: для
/// таблицы рецензий, где структура TMDB не нужна.
int seasonViewsMax(LibrarySeries s, int season) {
  var count = 0;
  for (final e in s.episodes) {
    if (e.season == season && e.watchCount > count) count = e.watchCount;
  }
  return count;
}
