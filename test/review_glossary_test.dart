import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/data/critic_glossary.dart';
import 'package:kadr/l10n/locale_controller.dart';

/// Словарь критика: каждый термин на всех языках интерфейса, id уникальны.
void main() {
  final langs = {for (final l in LocaleController.languages) l.code};

  test('у каждого термина название и определение на всех языках', () {
    for (final t in kCriticTerms) {
      expect(t.name.keys.toSet(), langs, reason: 'название ${t.id}');
      expect(t.def.keys.toSet(), langs, reason: 'определение ${t.id}');
      for (final v in [...t.name.values, ...t.def.values]) {
        expect(v.trim(), isNotEmpty, reason: t.id);
      }
    }
  });

  test('id уникальны и находятся поиском', () {
    final ids = kCriticTerms.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(criticTerm('noir')?.group, TermGroup.genre);
    expect(criticTerm('нет-такого'), isNull);
  });

  test('в каждой группе есть термины', () {
    for (final g in TermGroup.values) {
      expect(kCriticTerms.where((t) => t.group == g), isNotEmpty);
    }
  });
}
