import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/services/facts_service.dart';

/// Разбор фактов ПоискКино: html чистится, киноляпы и спойлеры распознаются.
void main() {
  test('html-разметка вычищается, сущности разворачиваются', () {
    final facts = FactsService.parseFacts([
      {
        'value':
            'Роль <b>принца</b>&nbsp;досталась актёру после&nbsp;проб.<br/>Съёмки шли 40 дней.',
        'type': 'FACT',
        'spoiler': false,
      },
    ]);
    expect(facts, hasLength(1));
    expect(facts.first.text,
        'Роль принца досталась актёру после проб.\nСъёмки шли 40 дней.');
    expect(facts.first.blooper, isFalse);
    expect(facts.first.spoiler, isFalse);
  });

  test('киноляпы и спойлеры помечаются', () {
    final facts = FactsService.parseFacts([
      {'value': 'В кадре видна тень микрофона.', 'type': 'BLOOPER'},
      {'value': 'Герой умирает в финале.', 'type': 'FACT', 'spoiler': true},
    ]);
    expect(facts[0].blooper, isTrue);
    expect(facts[1].spoiler, isTrue);
    expect(facts[1].blooper, isFalse);
  });

  test('пустые и битые записи пропускаются', () {
    expect(FactsService.parseFacts(null), isEmpty);
    expect(FactsService.parseFacts([]), isEmpty);
    expect(
        FactsService.parseFacts([
          {'value': '   '},
          {'value': '<i></i>'},
          {'type': 'FACT'},
        ]),
        isEmpty);
  });

  test('факт переживает запись в кэш и чтение обратно', () {
    final original = FactsService.parseFacts([
      {'value': 'Ляп: часы показывают разное время.', 'type': 'BLOOPER', 'spoiler': true},
    ]).first;
    final restored = KpFact.fromCache(original.toJson());
    expect(restored.text, original.text);
    expect(restored.blooper, isTrue);
    expect(restored.spoiler, isTrue);
  });

  test('имена сравниваются без регистра, «ё», дефисов и апострофов', () {
    expect(FactsService.nameKey("Джош О'Коннор"), 'джошоконнор');
    expect(FactsService.nameKey('Джош О’Коннор'), FactsService.nameKey("Джош О'Коннор"));
    expect(FactsService.nameKey('Пётр Фёдоров'), FactsService.nameKey('петр федоров'));
  });

  test('диакритика приводится к базовым буквам', () {
    expect(FactsService.nameKey('Jean-Pierre Léaud'), 'jeanpierreleaud');
    expect(FactsService.nameKey('Léaud'), FactsService.nameKey('Leaud'));
    expect(FactsService.nameKey('Renée Zellweger'),
        FactsService.nameKey('Renee Zellweger'));
    expect(FactsService.nameKey('Peter Højlund'),
        FactsService.nameKey('Peter Hojlund'));
  });
}
