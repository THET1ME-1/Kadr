import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/utils/bio_parser.dart';

/// Разбор русских биографий TMDB. Тексты взяты дословно со страниц персон.
void main() {
  const spielberg =
      '💥Стивен Аллан Спилберг. Родился в 1946-ом году в Цинциннати, Огайо, США. '
      'Отец работал инженером, а мать была пианисткой.\n\n'
      '🏆Главные награды🏆: Оскар (1994) [Список Шиндлера], Оскар (1999) '
      '[Спасти рядового Райана], Золотой глобус (1994) [Список Шиндлера], '
      'BAFTA (1994) [Список Шиндлера], Гильдия режиссёров США (1999) '
      '[Спасти рядового Райана]\n\n'
      '🎬Главные проекты🎬: «Челюсти» (1975), «Инопланетянин» (1982), '
      '«Парк юрского периода» (1993), «Фабельманы» (2022).\n\n'
      '⭐Интересный факт⭐: В 1984-ом году Стивен стал одним из сооснователей '
      'студии DreamWorks';

  const johansson =
      '💥Скарлетт Ингрид Йоханссон. Родилась в 1984-ом году в Нью-Йорке, США.\n\n'
      '🏆Главные награды🏆: BAFTA (2004) [Трудности перевода], Тони (2010) '
      '[Вид с моста], Звезда на Аллее славы в Голливуде (2012)\n\n'
      '🎬Главные проекты🎬: «Трудности перевода» (2003), «Чёрная вдова» (2021)\n\n'
      '⭐Интересный факт⭐: Скарлетт подала в суд на Disney в 2021-ом году.';

  test('вступление очищено от эмодзи и обрезано по первой секции', () {
    final bio = parseBio(spielberg);
    expect(bio.isStructured, isTrue);
    expect(bio.intro, startsWith('Стивен Аллан Спилберг. Родился в 1946-ом'));
    expect(bio.intro, endsWith('пианисткой.'));
    expect(bio.intro, isNot(contains('Главные награды')));
  });

  test('награды разбираются на премию, год и фильм', () {
    final awards = parseBio(spielberg).awards;
    expect(awards, hasLength(5));
    expect(awards.first.title, 'Оскар');
    expect(awards.first.year, 1994);
    expect(awards.first.film, 'Список Шиндлера');
    expect(awards[4].title, 'Гильдия режиссёров США');
    expect(awards[4].film, 'Спасти рядового Райана');
  });

  test('награда без фильма не теряется', () {
    final awards = parseBio(johansson).awards;
    expect(awards, hasLength(3));
    final star = awards.last;
    expect(star.title, 'Звезда на Аллее славы в Голливуде');
    expect(star.year, 2012);
    expect(star.film, isNull);
  });

  test('проекты разбираются на название и год', () {
    final works = parseBio(spielberg).works;
    expect(works.map((w) => w.title), [
      'Челюсти',
      'Инопланетянин',
      'Парк юрского периода',
      'Фабельманы',
    ]);
    expect(works.first.year, 1975);
    expect(works.last.year, 2022);
  });

  test('интересный факт отделяется от остального текста', () {
    expect(parseBio(spielberg).trivia,
        'В 1984-ом году Стивен стал одним из сооснователей студии DreamWorks');
  });

  test('биография без секций остаётся сплошным текстом', () {
    const plain =
        'English actor. Known for his role as Prince Charles in The Crown.';
    final bio = parseBio(plain);
    expect(bio.isStructured, isFalse);
    expect(bio.intro, plain);
    expect(bio.awards, isEmpty);
    expect(bio.works, isEmpty);
    expect(bio.trivia, isNull);
  });

  test('пустая биография не роняет разбор', () {
    final bio = parseBio('   ');
    expect(bio.isStructured, isFalse);
    expect(bio.intro, isEmpty);
  });

  test('запятые внутри названий не рвут список наград', () {
    const tricky = '💥Кто-то.\n\n'
        '🏆Главные награды🏆: Каннский кинофестиваль (2019) [Однажды в Голливуде], '
        'Приз жюри (2021) [Купе номер 6, Финляндия]';
    final awards = parseBio(tricky).awards;
    expect(awards, hasLength(2));
    expect(awards.last.film, 'Купе номер 6, Финляндия');
  });
}
