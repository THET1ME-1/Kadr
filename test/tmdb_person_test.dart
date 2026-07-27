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
}
