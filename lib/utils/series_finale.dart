import '../l10n/strings.dart';
import '../models/library_entry.dart';
import 'format.dart';

/// Где человек сейчас в сериале.
enum SeriesRun {
  /// Смотрит или бросил: вышли серии, которых нет в отметках.
  watching,

  /// Сериал ещё выходит, а все вышедшие серии отмечены.
  caughtUp,

  /// Сериал закрыт и досмотрен до последней серии.
  finished,
}

/// Перерыв между просмотрами длиннее этого делит сериал на заходы, и в срок
/// просмотра он не входит: первый сезон два года назад и остальные за пару
/// месяцев не превращаются в «смотрел три года».
const int kRunGapDays = 60;

/// Отмеченные серии сериала без спецвыпусков и без серий без номера.
Iterable<Episode> _numbered(LibrarySeries s) => s.episodes.where(
  (e) => (e.season ?? 0) >= 1 && (e.number ?? 0) >= 1,
);

int _seen(LibrarySeries s) =>
    {for (final e in _numbered(s)) (e.season, e.number)}.length;

/// Статус сериала по сведениям TMDB и отметкам. Без TMDB решает ручная
/// отметка «Досмотрел» из «Сейчас смотрю».
SeriesRun seriesRun(LibrarySeries s) {
  if (s.dropped) return SeriesRun.watching;
  final air = s.air;
  final aired = air?.aired;
  if (air?.status != null && aired != null && aired > 0 && _seen(s) >= aired) {
    return air!.ended ? SeriesRun.finished : SeriesRun.caughtUp;
  }
  return s.finished ? SeriesRun.finished : SeriesRun.watching;
}

/// Момент, когда сериал был досмотрен или догнан: самый поздний ПЕРВЫЙ
/// просмотр серии. Пересмотры не в счёт, иначе плашка уезжала бы на них.
DateTime? completedAt(LibrarySeries s) {
  DateTime? best;
  for (final e in _numbered(s)) {
    final d = e.watchedAt;
    if (d != null && (best == null || d.isAfter(best))) best = d;
  }
  return best;
}

/// Сколько календарных дней человек реально смотрел: заходы, разделённые
/// перерывом больше [kRunGapDays], складываются. null, если дат нет или весь
/// сериал отмечен одной пачкой (импорт, «отметить сезон»): тогда срок врёт.
int? activeDays(Iterable<DateTime> views) {
  final ds = views.toList()..sort();
  if (ds.isEmpty) return null;
  if (ds.length > 3 && ds.last.difference(ds.first).inMinutes < 2) return null;
  int day(DateTime d) => DateTime.utc(d.year, d.month, d.day)
      .millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  var total = 0;
  var from = day(ds.first), prev = from;
  for (final d in ds.skip(1)) {
    final cur = day(d);
    if (cur - prev > kRunGapDays) {
      total += prev - from + 1;
      from = cur;
    }
    prev = cur;
  }
  return total + prev - from + 1;
}

/// «за один день», «за 6 дней», «за 3 месяца», «за 2 года».
String? spanLabel(int? days) {
  if (days == null) return null;
  if (days <= 1) return tr('fin_span_day');
  if (days < 45) return trn('fin_span_days', days);
  if (days < 365) return trn('fin_span_months', (days / 30.4).round());
  return trn('fin_span_years', (days / 365).round());
}

/// Отметка сессии в ленте: финал сериала или «Догнал».
class SessionMilestone {
  /// Финал сериала; иначе «Догнал».
  final bool finale;

  /// «Догнал» относится к нынешнему состоянию (ждём новые серии), а не к
  /// прошлому заходу из истории.
  final bool current;

  /// Первый просмотр серии, которой сериал был досмотрен или догнан.
  final DateTime at;

  const SessionMilestone({
    required this.finale,
    required this.current,
    required this.at,
  });
}

/// Отметка для сессии ленты, если в ней посмотрена серия, которой сериал
/// досмотрен или догнан.
SessionMilestone? milestoneOf(EpisodeSession session) {
  final s = session.series;
  if (s.dropped) return null;
  bool has(DateTime at) => session.episodes.any(
    (e) => e.rewatchOrdinal <= 1 && e.watchedAt == at,
  );
  final run = seriesRun(s);
  final at = completedAt(s);
  if (at != null && run != SeriesRun.watching && has(at)) {
    return SessionMilestone(
      finale: run == SeriesRun.finished,
      current: true,
      at: at,
    );
  }
  for (final d in s.caughtUpAt) {
    if (has(d)) return SessionMilestone(finale: false, current: false, at: d);
  }
  return null;
}

String _seasonOrd(int n) => trf('season_ord', {'n': n});

/// Что ждём у догнанного сериала: «ждём 4-й сезон», «4-й сезон 12 мар»,
/// «новая серия 15 окт».
String catchUpLine(LibrarySeries s) {
  final air = s.air;
  final last = air?.lastSeason ?? 0;
  final next = air?.nextSeason;
  final date = air?.nextDate == null ? null : DateTime.tryParse(air!.nextDate!);
  if (date != null && next != null && next > last) {
    return trf('catch_next_season', {
      'season': _seasonOrd(next),
      'date': dayMonth(date),
    });
  }
  if (date != null) return trf('catch_next_ep', {'date': dayMonth(date)});
  return trf('catch_wait', {'season': _seasonOrd(last + 1)});
}

/// Подпись в шапке сессии вместо «S4 · 2 сер.».
String milestoneLine(SessionMilestone m, EpisodeSession session) {
  final s = session.series;
  if (m.finale) {
    final eps = trn('ss_episodes', _seen(s));
    final span = spanLabel(
      activeDays([for (final e in _numbered(s)) ?e.watchedAt]),
    );
    return span == null
        ? trf('fin_line', {'eps': eps})
        : trf('fin_line_span', {'eps': eps, 'span': span});
  }
  if (m.current) return catchUpLine(s);
  final ep = session.episodes.firstWhere(
    (e) => e.watchedAt == m.at,
    orElse: () => session.episodes.last,
  );
  return trf('catch_past', {'season': _seasonOrd(ep.season ?? 1)});
}

/// Таблетка в шапке экрана сериала: «Досмотрел 7 октября 2026» или то же,
/// что в плашке «Догнал». null, пока сериал смотрят.
String? statusPill(LibrarySeries s) {
  switch (seriesRun(s)) {
    case SeriesRun.watching:
      return null;
    case SeriesRun.caughtUp:
      return catchUpLine(s);
    case SeriesRun.finished:
      final at = completedAt(s);
      return at == null
          ? tr('fin_pill_nodate')
          : trf('fin_pill', {'date': longDate(at)});
  }
}
