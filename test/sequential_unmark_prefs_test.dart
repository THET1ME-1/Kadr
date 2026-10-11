import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/screens/settings/library_pages.dart';
import 'package:kadr/services/app_prefs.dart';
import 'package:kadr/services/store.dart';
import 'package:kadr/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройка «Снимать серии по порядку» в «Отметках просмотра».
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.remove('sequentialUnmark');
    await Store.instance.remove('sequentialEpisodes');
  });

  tearDown(() async {
    await Store.instance.remove('sequentialUnmark');
    await Store.instance.remove('sequentialEpisodes');
    AppPrefs.instance.sequentialUnmark = true;
  });

  // Раньше одна настройка «по порядку» обещала и отметку, и снятие. Кто её
  // выключил, не ждёт, что серии начнут сниматься пачкой.
  test('пока настройку не трогали, снятие идёт так же, как отметка', () async {
    await AppPrefs.instance.load();
    expect(AppPrefs.instance.sequentialUnmark, isTrue);
    await Store.instance.setBool('sequentialEpisodes', false);
    await AppPrefs.instance.load();
    expect(AppPrefs.instance.sequentialUnmark, isFalse);
  });

  test('свой выбор важнее настройки отметки', () async {
    await Store.instance.setBool('sequentialEpisodes', true);
    await AppPrefs.instance.setSequentialUnmark(false);
    await AppPrefs.instance.load();
    expect(AppPrefs.instance.sequentialUnmark, isFalse);
  });

  testWidgets('переключатель стоит под отметкой по порядку и запоминается', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LocaleController.instance.setCode('ru'));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(AppTheme.defaultSeed),
      home: const TrackingPage(),
    ));
    await tester.pumpAndSettle();
    final mark = tester.getTopLeft(find.text(tr('seq_mode'))).dy;
    final unmark = tester.getTopLeft(find.text(tr('unmark_seq'))).dy;
    expect(unmark, greaterThan(mark));
    expect(AppPrefs.instance.sequentialUnmark, isTrue);
    await tester.tap(find.text(tr('unmark_seq')));
    await tester.pumpAndSettle();
    expect(AppPrefs.instance.sequentialUnmark, isFalse);
    expect(
      await tester.runAsync(
          () => Store.instance.getBool('sequentialUnmark', def: true)),
      isFalse,
    );
  });
}
