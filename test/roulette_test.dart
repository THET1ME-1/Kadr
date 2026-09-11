import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/utils/roulette.dart';

/// Рулетка «что посмотреть»: случайная запись из «Буду смотреть».
void main() {
  test('из пустого списка выбирать нечего', () {
    expect(pickRandom<String>([]), isNull);
  });

  test('единственная запись выпадает даже если её и просили не повторять', () {
    expect(pickRandom(['Дюна'], avoid: 'Дюна'), 'Дюна');
  });

  test('предыдущая запись не выпадает второй раз подряд', () {
    for (var i = 0; i < 60; i++) {
      final next = pickRandom(['Дюна', 'Сияние', 'Бразилия'], avoid: 'Дюна');
      expect(next, isNot('Дюна'));
    }
  });

  test('одно зерно даёт один и тот же выбор', () {
    final a = pickRandom(['а', 'б', 'в', 'г'], rng: Random(7));
    final b = pickRandom(['а', 'б', 'в', 'г'], rng: Random(7));
    expect(a, b);
  });

  test('за много прогонов достаёт каждую запись, а не залипает на первой', () {
    final seen = <String>{};
    final rng = Random(1);
    for (var i = 0; i < 200; i++) {
      seen.add(pickRandom(['а', 'б', 'в'], rng: rng)!);
    }
    expect(seen, {'а', 'б', 'в'});
  });
}
