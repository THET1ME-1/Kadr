import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../screens/movie_sheet.dart';
import '../screens/series_screen.dart';
import '../services/movie_repository.dart';
import '../services/tmdb_service.dart';
import '../theme/app_theme.dart';

/// Название фильма или сериала внутри текста, по которому можно нажать.
///
/// Тап ищет название в TMDB и открывает карточку фильма либо экран сериала.
/// Пока идёт поиск, рядом крутится маленький индикатор; если не нашли, показываем
/// снекбар и оставляем текст на месте.
class TitleLink extends StatefulWidget {
  final String title;

  /// Год выхода, если известен. У наград не указывается: год вручения и год
  /// фильма расходятся.
  final int? year;

  final double fontSize;
  final FontWeight fontWeight;

  const TitleLink({
    super.key,
    required this.title,
    this.year,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w500,
  });

  @override
  State<TitleLink> createState() => _TitleLinkState();
}

class _TitleLinkState extends State<TitleLink> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final hit = await TmdbService.searchAny(widget.title, year: widget.year);
    if (!mounted) return;
    setState(() => _busy = false);
    final repo = MovieRepository.instance;
    if (hit.movie != null) {
      showMovieSheet(context, repo.ensureFromTmdb(hit.movie!));
    } else if (hit.series != null) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              SeriesScreen(series: repo.ensureSeriesFromTmdb(hit.series!))));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('nothing_found'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _open,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              widget.title,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: widget.fontSize,
                fontWeight: widget.fontWeight,
                height: 1.35,
                color: scheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: scheme.primary.withValues(alpha: 0.4),
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6, color: scheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}
