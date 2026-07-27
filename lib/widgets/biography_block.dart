import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../utils/bio_parser.dart';
import 'title_link.dart';

/// Биография персоны с разбором русского шаблона TMDB.
///
/// Награды и заметные проекты раскладываются по строкам, названия фильмов
/// становятся ссылками на карточку. Если шаблон не узнан (английский текст,
/// произвольная биография), показываем обычный абзац с разворотом.
class BiographyBlock extends StatefulWidget {
  final String biography;
  const BiographyBlock({super.key, required this.biography});

  @override
  State<BiographyBlock> createState() => _BiographyBlockState();
}

class _BiographyBlockState extends State<BiographyBlock> {
  bool _expanded = false;
  late ParsedBio _bio = parseBio(widget.biography);

  @override
  void didUpdateWidget(BiographyBlock old) {
    super.didUpdateWidget(old);
    if (old.biography != widget.biography) {
      _bio = parseBio(widget.biography);
      _expanded = false;
    }
  }

  void _copy(String text) {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('copied'))));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _intro(scheme),
              if (_bio.awards.isNotEmpty) ...[
                _sectionHead(scheme, Icons.emoji_events_rounded,
                    tr('bio_awards'), scheme.primary),
                for (var i = 0; i < _bio.awards.length; i++) ...[
                  _awardRow(scheme, _bio.awards[i]),
                  if (i < _bio.awards.length - 1) _line(scheme),
                ],
              ],
              if (_bio.works.isNotEmpty) ...[
                _sectionHead(scheme, Icons.local_movies_rounded,
                    tr('bio_works'), scheme.tertiary),
                for (var i = 0; i < _bio.works.length; i++) ...[
                  _workRow(scheme, _bio.works[i]),
                  if (i < _bio.works.length - 1) _line(scheme),
                ],
              ],
              if (_bio.trivia != null) _trivia(scheme, _bio.trivia!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro(ColorScheme scheme) {
    final text = _bio.intro;
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: AppTheme.emphasized,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onLongPress: () => _copy(text),
            child: Text(
              text,
              maxLines: _expanded ? null : 4,
              overflow:
                  _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  height: 1.55,
                  color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(_expanded ? tr('read_less') : tr('read_more')),
          ),
        ),
      ],
    );
  }

  Widget _sectionHead(
          ColorScheme scheme, IconData icon, String title, Color accent) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
        child: Row(
          children: [
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: 9),
            Text(title,
                style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: scheme.onSurface)),
          ],
        ),
      );

  /// Год крупной цифрой слева, премия и фильм-ссылка справа.
  Widget _awardRow(ColorScheme scheme, BioAward a) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _year(scheme, a.year, scheme.primary),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onLongPress: () => _copy(a.title),
                    child: Text(a.title,
                        style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 14.5,
                            height: 1.3,
                            color: scheme.onSurface)),
                  ),
                  if (a.film != null) ...[
                    const SizedBox(height: 3),
                    TitleLink(title: a.film!),
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _workRow(ColorScheme scheme, BioWork w) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _year(scheme, w.year, scheme.tertiary),
            Expanded(
              child: TitleLink(
                  title: w.title,
                  year: w.year,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  Widget _year(ColorScheme scheme, int? year, Color accent) => SizedBox(
        width: 76,
        child: Text(year?.toString() ?? '',
            style: TextStyle(
                fontFamily: AppTheme.displayFont,
                fontWeight: FontWeight.w800,
                fontSize: 25,
                height: 1.05,
                color: accent.withValues(alpha: 0.45))),
      );

  Widget _line(ColorScheme scheme) =>
      Divider(height: 1, thickness: 1, color: scheme.outlineVariant);

  Widget _trivia(ColorScheme scheme, String text) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      size: 16, color: scheme.secondary),
                  const SizedBox(width: 8),
                  Text(tr('bio_trivia'),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFont,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: scheme.onSurface)),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onLongPress: () => _copy(text),
                child: Text(text,
                    style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 14,
                        height: 1.55,
                        color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      );
}
