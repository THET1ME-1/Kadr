import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/utils/share_card_data.dart';

LibraryMovie _movie({
  LibraryStatus status = LibraryStatus.watched,
  List<Viewing>? viewings,
  double? score,
  List<MovieEmotion> emotions = const [],
  int rewatchCount = 0,
}) =>
    LibraryMovie(
      uuid: 'u1',
      title: 'The Colony',
      status: status,
      viewings: viewings,
      score: score,
      emotions: emotions,
      rewatchCount: rewatchCount,
    );

void main() {
  group('shareMetaLine', () {
    test('собирает год, жанры и хронометраж через точку', () {
      final m = _movie()
        ..year = 2026
        ..runtimeMin = 118
        ..genres.addAll(['ужасы', 'триллер']);

      expect(shareMetaLine(m), '2026 · Ужасы, триллер · 1 ч 58 мин');
    });

    test('пропускает то, чего нет', () {
      final m = _movie()..year = 1999;

      expect(shareMetaLine(m), '1999');
    });

    test('жанров показывает не больше двух', () {
      final m = _movie()..genres.addAll(['драма', 'комедия', 'мелодрама']);

      expect(shareMetaLine(m), 'Драма, комедия');
    });

    test('без данных строки нет вовсе', () {
      expect(shareMetaLine(_movie()), isNull);
    });
  });

  group('shareFooterNote', () {
    test('просмотренный фильм подписан датой', () {
      final note = shareFooterNote(_movie(
        viewings: [Viewing(date: DateTime(2026, 8, 3), score: 7)],
      ));

      expect(note, '3 августа 2026');
    });

    test('пересмотр называет свой номер', () {
      final note = shareFooterNote(_movie(viewings: [
        Viewing(date: DateTime(2024, 1, 5), score: 7),
        Viewing(date: DateTime(2026, 8, 3), score: 8),
      ]));

      expect(note, '2-й просмотр · 3 августа 2026');
    });

    test('фильм из списка подписан списком', () {
      expect(shareFooterNote(_movie(status: LibraryStatus.watchlist)),
          'В списке');
    });

    test('просмотр без даты остаётся без подписи', () {
      expect(shareFooterNote(_movie(score: 6.0)), '');
    });
  });

  group('resolveShareTexture', () {
    test('кадр остаётся кадром, когда бэкдроп есть', () {
      expect(
        resolveShareTexture(ShareTexture.frame,
            hasBackdrop: true, hasPoster: true),
        ShareTexture.frame,
      );
    });

    test('без бэкдропа кадр откатывается на плёнку', () {
      expect(
        resolveShareTexture(ShareTexture.frame,
            hasBackdrop: false, hasPoster: true),
        ShareTexture.film,
      );
    });

    test('без единой картинки остаются буквы', () {
      expect(
        resolveShareTexture(ShareTexture.frame,
            hasBackdrop: false, hasPoster: false),
        ShareTexture.letters,
      );
      expect(
        resolveShareTexture(ShareTexture.film,
            hasBackdrop: false, hasPoster: false),
        ShareTexture.letters,
      );
    });

    test('буквы не требуют картинок и не откатываются', () {
      expect(
        resolveShareTexture(ShareTexture.letters,
            hasBackdrop: false, hasPoster: false),
        ShareTexture.letters,
      );
    });
  });

  group('shareFactsOf', () {
    test('берёт оценку и дату последнего просмотра', () {
      final facts = shareFactsOf(_movie(viewings: [
        Viewing(date: DateTime(2024, 5, 1), score: 5.0),
        Viewing(date: DateTime(2026, 8, 3), score: 6.9),
      ]));

      expect(facts.score, 6.9);
      expect(facts.watchedAt, DateTime(2026, 8, 3));
      expect(facts.viewNumber, 2);
    });

    test('единственный просмотр не считается пересмотром', () {
      final facts = shareFactsOf(_movie(
        viewings: [Viewing(date: DateTime(2026, 8, 3), score: 7.5)],
      ));

      expect(facts.viewNumber, 1);
      expect(facts.isRewatch, isFalse);
    });

    test('оценка просмотра важнее общей', () {
      final facts = shareFactsOf(_movie(
        score: 4.0,
        viewings: [Viewing(date: DateTime(2026, 8, 3), score: 8.2)],
      ));

      expect(facts.score, 8.2);
    });

    test('импортированный фильм без просмотров отдаёт общую оценку', () {
      final facts = shareFactsOf(_movie(score: 6.0));

      expect(facts.score, 6.0);
      expect(facts.watchedAt, isNull);
      expect(facts.viewNumber, 1);
    });

    test('фильм из списка помечен как невиденный, без оценки', () {
      final facts = shareFactsOf(_movie(status: LibraryStatus.watchlist));

      expect(facts.wantToWatch, isTrue);
      expect(facts.score, isNull);
    });

    test('брошенный фильм виден как брошенный', () {
      final facts = shareFactsOf(_movie(status: LibraryStatus.dropped));

      expect(facts.dropped, isTrue);
    });

    test('эмоция берётся первая из отмеченных', () {
      final facts = shareFactsOf(_movie(emotions: const [
        MovieEmotion(id: 'wow', label: 'Взрыв мозга', emoji: '🤯', score: 9),
        MovieEmotion(id: 'fun', label: 'Весело', emoji: '😄', score: 7),
      ]));

      expect(facts.emotion?.label, 'Взрыв мозга');
    });

    test('старый импорт со счётчиком пересмотров считает просмотры', () {
      final facts = shareFactsOf(_movie(rewatchCount: 2));

      expect(facts.viewNumber, 3);
      expect(facts.isRewatch, isTrue);
    });
  });
}
