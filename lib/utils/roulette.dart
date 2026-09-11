/// Случайный выбор записи — «рулетка» на вкладке «Буду смотреть».
library;

import 'dart:math';

final _shared = Random();

/// Одна случайная запись из [items].
///
/// [avoid] — предыдущий выбор: при повторном нажатии «Другой» он не выпадает
/// снова, иначе кнопка выглядит сломанной. Когда выбирать больше не из чего
/// (список из одной записи), возвращается она же. Пустой список даёт null.
/// [rng] нужен тестам, чтобы выбор был воспроизводимым.
T? pickRandom<T>(List<T> items, {T? avoid, Random? rng}) {
  if (items.isEmpty) return null;
  final pool = avoid == null ? items : items.where((e) => e != avoid).toList();
  final from = pool.isEmpty ? items : pool;
  return from[(rng ?? _shared).nextInt(from.length)];
}
