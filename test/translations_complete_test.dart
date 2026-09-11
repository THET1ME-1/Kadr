import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/l10n/translations.dart';

/// Пять дополнительных языков обязаны покрывать весь базовый словарь.
///
/// Без этого новая строка тихо уезжает в английский фолбэк: интерфейс
/// остаётся рабочим, но немец видит половину экрана по-английски. Так уже
/// накопилось 83 непереведённых ключа.
void main() {
  const langs = ['de', 'fr', 'es', 'it', 'pt'];

  test('каждый язык переводит все базовые ключи', () {
    for (final lang in langs) {
      final map = kTranslations[lang];
      expect(map, isNotNull, reason: 'нет карты языка $lang');
      final missing = kBaseStrings.keys.where((k) => !map!.containsKey(k));
      expect(missing, isEmpty, reason: 'в $lang нет перевода для: $missing');
    }
  });

  test('переводов-пустышек нет', () {
    for (final lang in langs) {
      final empty = kTranslations[lang]!.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key);
      expect(empty, isEmpty, reason: 'пустые значения в $lang: $empty');
    }
  });

  test('лишних ключей в переводах нет', () {
    for (final lang in langs) {
      final extra = kTranslations[lang]!.keys.where(
        (k) => !kBaseStrings.containsKey(k),
      );
      expect(extra, isEmpty, reason: 'в $lang ключи мимо словаря: $extra');
    }
  });

  test('плейсхолдеры {..} совпадают с английским', () {
    final re = RegExp(r'\{(\w+)\}');
    Set<String> holders(String s) => re.allMatches(s).map((m) => m[1]!).toSet();
    for (final lang in langs) {
      kTranslations[lang]!.forEach((key, value) {
        final base = kBaseStrings[key]?['en'];
        if (base == null) return;
        expect(
          holders(value),
          holders(base),
          reason: '$lang/$key: плейсхолдеры разошлись',
        );
      });
    }
  });
}
