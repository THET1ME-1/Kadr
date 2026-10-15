import '../l10n/strings.dart';

/// Готовые причины бросить фильм, от частых к редким. Часть общая со
/// «Слабым» в рецензии (те же ключи `tag_*`), остальные свои: «Не мой жанр»,
/// «Тяжело смотреть» и подобные. «Слабого финала» нет: финал брошенного фильма
/// не видели.
const List<String> kDropReasonTags = [
  'tag_boring',
  'tag_slow',
  'tag_not_my_genre',
  'tag_hard_to_watch',
  'tag_dumb_plot',
  'tag_predictable',
  'tag_confusing',
  'tag_plotholes',
  'tag_flat_characters',
  'tag_overacting',
  'tag_cliches',
  'tag_not_funny',
  'tag_cgi',
  'tag_bad_dub',
];

/// Подсказки к «Что не так» без уже выбранных: сначала причины из прошлых
/// попыток ([used], свежие первыми), потом готовые. Причина хранится текстом,
/// как «Слабое» в рецензии, поэтому сравнение идёт по тексту.
List<String> dropReasonSuggestions(
    List<String> chosen, List<String> used) {
  final taken = {for (final c in chosen) c.toLowerCase()};
  final out = <String>[];
  for (final r in [...used, for (final k in kDropReasonTags) tr(k)]) {
    if (taken.add(r.toLowerCase())) out.add(r);
  }
  return out;
}
