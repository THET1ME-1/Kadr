import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/library_entry.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster.dart';
import 'series_screen.dart';

/// Ближайшая невышедшая серия одного сериала.
class _Upcoming {
  final LibrarySeries series;
  final DateTime date;
  final int? season;
  final int? number;
  final String? name;
  _Upcoming(this.series, this.date, this.season, this.number, this.name);
}

/// Раздел «Расписание»: ближайшие ещё НЕ вышедшие серии сериалов из «Сейчас
/// смотрю» (даты из TMDB `next_episode_to_air`), по возрастанию даты.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool _loading = true;
  List<_Upcoming> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = MovieRepository.instance;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final out = <_Upcoming>[];
    for (final s in repo.nowWatching) {
      final id = s.tmdbId;
      if (id == null) continue;
      final extra = await TmdbService.tvExtra(id);
      final raw = extra?.nextEpDate;
      if (raw == null || raw.isEmpty) continue;
      final d = DateTime.tryParse(raw);
      if (d == null || d.isBefore(midnight)) continue;
      out.add(_Upcoming(
          s, d, extra!.nextEpSeason, extra.nextEpNumber, extra.nextEpName));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    if (mounted) {
      setState(() {
        _items = out;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('drawer_schedule'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? EmptyState(
                  icon: Icons.event_available_rounded,
                  title: tr('schedule_empty_title'),
                  subtitle: tr('schedule_empty_sub'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (c, i) => _row(scheme, _items[i]),
                ),
    );
  }

  Widget _row(ColorScheme scheme, _Upcoming u) {
    final s = u.series;
    final ep = (u.season != null && u.number != null)
        ? 'S${u.season} · E${u.number}'
        : null;
    final sub = [
      ?ep,
      if (u.name != null && u.name!.isNotEmpty) u.name!,
    ].join(' · ');
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => SeriesScreen(series: s))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Poster(title: s.displayTitle, url: s.displayPoster, width: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: scheme.onSurface)),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: AppTheme.bodyFont,
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${u.date.day} ${monthShort(u.date.month)}',
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: scheme.primary)),
                  Text(_dayLabel(u.date),
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final md = DateTime(now.year, now.month, now.day);
    final diff = DateTime(d.year, d.month, d.day).difference(md).inDays;
    if (diff <= 0) return tr('schedule_today');
    if (diff == 1) return tr('schedule_tomorrow');
    if (diff < 7) return trf('schedule_in_days', {'n': diff});
    return '${d.year}';
  }
}
