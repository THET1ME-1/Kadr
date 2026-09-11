import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/services/tmdb_service.dart';

/// Разбор ответа TMDB `/person/{id}` для шапки экрана актёра.
void main() {
  test('карточка персоны читается целиком', () {
    final p = TmdbPerson.fromJson({
      'id': 1234,
      'name': 'Джош О\'Коннор',
      'biography': '  Английский актёр.  ',
      'profile_path': '/abc.jpg',
      'birthday': '1990-05-20',
      'place_of_birth': 'Саутгемптон, Англия',
      'known_for_department': 'Acting',
    });
    expect(p.id, 1234);
    expect(p.biography, 'Английский актёр.');
    expect(p.photoUrl, endsWith('/abc.jpg'));
    expect(p.largePhotoUrl, contains('h632'));
    expect(p.birthday, DateTime(1990, 5, 20));
    expect(p.deathday, isNull);
    expect(p.department, 'Acting');
  });

  test('пустая биография превращается в null — блок не рисуем', () {
    final p = TmdbPerson.fromJson({'id': 1, 'name': 'Без описания', 'biography': '   '});
    expect(p.biography, isNull);
    expect(p.photoUrl, isNull);
    expect(p.largePhotoUrl, isNull);
  });

  test('возраст умершего считается на день смерти', () {
    final p = TmdbPerson.fromJson({
      'id': 2,
      'name': 'Умерший',
      'birthday': '1930-01-10',
      'deathday': '2000-01-09', // за день до дня рождения — 69, не 70
    });
    expect(p.age, 69);
  });

  test('возраст живого растёт от даты рождения', () {
    final p = TmdbPerson.fromJson({'id': 3, 'name': 'Живой', 'birthday': '1990-05-20'});
    expect(p.age, greaterThanOrEqualTo(35));
  });

  test('без даты рождения возраста нет', () {
    expect(TmdbPerson.fromJson({'id': 4, 'name': 'Никто'}).age, isNull);
  });

  test('фильмография: каст и команда сливаются, свежие сверху', () {
    final list = TmdbService.parsePersonMovies({
      'cast': [
        {'id': 10, 'title': 'Старый', 'release_date': '1999-03-01'},
        {'id': 20, 'title': 'Свежий', 'release_date': '2024-07-15'},
      ],
      'crew': [
        // Тот же фильм: снялся и спродюсировал — строка должна быть одна.
        {'id': 20, 'title': 'Свежий', 'release_date': '2024-07-15', 'job': 'Producer'},
        {'id': 30, 'title': 'Средний', 'release_date': '2010-01-01'},
      ],
    });
    expect(list.map((m) => m.id).toList(), [20, 30, 10]);
    expect(list.first.title, 'Свежий');
  });

  test('сериалография читается из tv_credits с полями сериала', () {
    final list = TmdbService.parsePersonSeries({
      'cast': [
        {'id': 5, 'name': 'Сериал', 'first_air_date': '2015-09-10'},
        {'id': 6, 'name': 'Новый сериал', 'first_air_date': '2023-01-05'},
      ],
      'crew': [
        {'id': 5, 'name': 'Сериал', 'first_air_date': '2015-09-10', 'job': 'Director'},
      ],
    });
    expect(list.map((s) => s.id).toList(), [6, 5]);
    expect(list.last.title, 'Сериал');
    expect(list.last.year, 2015);
  });

  test('пустой ответ фильмографии даёт пустой список, а не падение', () {
    expect(TmdbService.parsePersonMovies(const {}), isEmpty);
    expect(TmdbService.parsePersonSeries(const {}), isEmpty);
  });

  test('поиск людей: имя, фото и «известен по» из фильмов и сериалов', () {
    final hits = TmdbService.parsePeople({
      'results': [
        {
          'id': 11,
          'name': 'Киллиан Мёрфи',
          'profile_path': '/km.jpg',
          'known_for': [
            {'media_type': 'movie', 'title': 'Оппенгеймер'},
            {'media_type': 'tv', 'name': 'Острые козырьки'},
          ],
        },
        {'id': 12, 'name': 'Однофамилец'},
      ],
    });
    expect(hits.length, 2);
    expect(hits.first.name, 'Киллиан Мёрфи');
    expect(hits.first.photoUrl, endsWith('/km.jpg'));
    expect(hits.first.knownFor, ['Оппенгеймер', 'Острые козырьки']);
    expect(hits.last.photoUrl, isNull);
    expect(hits.last.knownFor, isEmpty);
  });

  test('поиск людей: запись без имени или id выбрасывается', () {
    final hits = TmdbService.parsePeople({
      'results': [
        {'id': 1, 'name': '   '},
        {'name': 'Без id'},
        {'id': 2, 'name': 'Годный'},
      ],
    });
    expect(hits.map((h) => h.name).toList(), ['Годный']);
  });
}
