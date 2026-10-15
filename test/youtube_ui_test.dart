import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/models/library_entry.dart';
import 'package:kadr/screens/series_screen.dart';
import 'package:kadr/screens/youtube_add.dart';
import 'package:kadr/services/movie_repository.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'youtube_fixtures.dart';

/// Циклы с YouTube на экранах (макет «Циклы с YouTube», Э1): экран цикла как
/// у сериала, ссылка в «Обзоре» и окно «Что уже посмотрел?», ролик без
/// цикла — фильмом.

LibrarySeries _flash({int watched = 3}) => LibrarySeries(
      tvShowId: 'yt:PLFlash0000001',
      title: 'Абсолют Флэш',
      watchlist: true,
      enrichTried: true,
      posterUrl: 'https://i.ytimg.com/vi/F7LGGTZaXLs/maxresdefault.jpg',
      totalEpisodes: 5,
      youtube: YtCycle(
        playlistId: 'PLFlash0000001',
        channelId: 'UCdev',
        channelName: 'Dev the Geek',
        checkedAt: DateTime.now(),
        videos: [
          for (final (i, id) in [
            'F7LGGTZaXLs',
            'ObfHEiiEPMo',
            '7AqMmcc62hE',
            'GGWKmsPU5Jw',
            'TP2jtN2KlSU',
          ].indexed)
            YtEntry(
              id: id,
              title: 'Абсолют Флэш №${i + 1} (DC)',
              durSec: 1500 + i * 60,
              published: DateTime(2025, 4 + i, 14),
            ),
        ],
      ),
      episodes: [
        for (var n = 1; n <= watched; n++) Episode(season: 1, number: n),
      ],
    );

Future<void> _prepare(WidgetTester tester,
    {String lang = 'ru', double width = 700, double height = 2400}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => LocaleController.instance.setCode(lang));
  // У цикла с YouTube картинки есть всегда: кэшу картинок нужна папка.
  // Библиотека в неё не пишется: её файл в тесте не нужен.
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final tmp = Directory.systemTemp.createTempSync('kadr_yt_');
  addTearDown(() => tmp.deleteSync(recursive: true));
  messenger.setMockMethodCallHandler(paths, (call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      throw PlatformException(code: 'no-dir');
    }
    return tmp.path;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
}

Future<List<Uri>> _openCycle(WidgetTester tester, LibrarySeries s,
    {String lang = 'ru', double width = 700}) async {
  await _prepare(tester, lang: lang, width: width);
  final repo = MovieRepository.instance;
  await tester.runAsync(() => repo.restoreFromSnapshot(const [], [s.toJson()]));
  final requests = <Uri>[];
  await http.runWithClient(
    () async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: SeriesScreen(series: repo.seriesById(s.tvShowId)!),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
    () => ytSite(requests: requests),
  );
  return requests;
}

Future<void> _openLink(WidgetTester tester, String link,
    {String lang = 'ru', double width = 420}) async {
  await _prepare(tester, lang: lang, width: width, height: 1400);
  // Библиотека общая на весь файл: цикл и ролик из прошлых тестов убираем.
  final repo = MovieRepository.instance;
  await tester.runAsync(() async {
    await repo.deleteSeries('yt:PLFlash0000001');
    await repo.deleteMovie('yt:plainvideo1');
  });
  await http.runWithClient(
    () async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(AppTheme.defaultSeed),
        home: Scaffold(body: YouTubeLinkResult(text: link)),
      ));
      // Ответы сайта приходят цепочкой: даём ей пройти.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
    ytSite,
  );
}

/// Закрывает открытые экраны и даёт доиграть их таймерам (отложенная запись
/// библиотеки, появление строк), чтобы тест не кончался с живыми таймерами.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  group('экран цикла', () {
    testWidgets('как сериал: выпуски с номерами, канал и кнопка в YouTube',
        (tester) async {
      final requests = await _openCycle(tester, _flash());
      expect(find.text('Абсолют Флэш'), findsOneWidget);
      expect(find.text('Dev the Geek'), findsOneWidget);
      expect(find.text('Просмотрено 3 из 5'), findsOneWidget);
      expect(find.text('Смотреть №4 в YouTube'), findsOneWidget);
      expect(find.text('№1'), findsOneWidget);
      expect(find.text('№5'), findsOneWidget);
      expect(find.text('S1 · E1'), findsNothing);
      expect(find.text('Отметить ещё 2'), findsOneWidget);
      // TMDB о цикле не спрашивают.
      expect(requests.where((u) => u.host.contains('themoviedb')), isEmpty);
    });

    testWidgets('всё просмотрено: кнопки «Смотреть» нет', (tester) async {
      await _openCycle(tester, _flash(watched: 5));
      expect(find.textContaining('Смотреть №'), findsNothing);
    });

    for (final lang in LocaleController.languages.map((l) => l.code)) {
      testWidgets('320 dp без переполнений, $lang', (tester) async {
        await _openCycle(tester, _flash(), lang: lang, width: 320);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ссылка в «Обзоре»', () {
    testWidgets('цикл: карточка, окно «Что уже посмотрел?», добавление',
        (tester) async {
      await _openLink(tester, 'https://youtu.be/F7LGGTZaXLs?si=Uzb');
      expect(find.text('Абсолют Флэш'), findsOneWidget);
      expect(find.text('Dev the Geek'), findsOneWidget);
      expect(find.text('Ссылка на №1 из этого плейлиста'), findsOneWidget);
      expect(find.textContaining('5 выпусков'), findsWidgets);
      await tester.tap(find.text('Добавить цикл'));
      await tester.pumpAndSettle();
      expect(find.text('Что уже посмотрел?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '№3'));
      await tester.pumpAndSettle();
      expect(find.text('Выпуски до №3 встанут просмотренными без даты'),
          findsOneWidget);
      await http.runWithClient(() async {
        await tester.tap(find.text(tr('yt_add')));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }, ytSite);
      final s = MovieRepository.instance.seriesById('yt:PLFlash0000001')!;
      expect(s.youtube!.videos.length, 5);
      expect(s.episodes.map((e) => e.number), [1, 2, 3]);
      // После добавления открывается экран цикла.
      expect(find.text('Смотреть №4 в YouTube'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('ролик без номера: «Добавить видео» кладёт его фильмом',
        (tester) async {
      await _openLink(tester, 'https://youtu.be/plainvideo1');
      expect(find.text('Обзор без номера'), findsOneWidget);
      expect(find.text('Добавить цикл'), findsNothing);
      await http.runWithClient(() async {
        await tester.tap(find.text('Добавить видео'));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }, ytSite);
      final m = MovieRepository.instance.byUuid('yt:plainvideo1')!;
      expect(m.isYouTube, isTrue);
      expect(m.status, LibraryStatus.watchlist);
      expect(find.text('Смотреть в YouTube'), findsOneWidget);
      await _close(tester);
    });

    for (final lang in LocaleController.languages.map((l) => l.code)) {
      testWidgets('карточка цикла на 320 dp без переполнений, $lang',
          (tester) async {
        await _openLink(tester, 'https://youtu.be/F7LGGTZaXLs',
            lang: lang, width: 320);
        expect(tester.takeException(), isNull);
        expect(find.text(tr('yt_add_cycle')), findsOneWidget);
      });
    }
  });
}
