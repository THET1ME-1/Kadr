import 'package:flutter_test/flutter_test.dart';
import 'package:kadr/l10n/locale_controller.dart';
import 'package:kadr/l10n/strings.dart';
import 'package:kadr/utils/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Числа со словами и даты на языках интерфейса. До этого даты умели только
/// ru/en, а немец видел «3 фев».
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> lang(String code) => LocaleController.instance.setCode(code);

  test('русские формы: один, несколько, много', () async {
    await lang('ru');
    expect(trn('ss_days', 1), '1 день');
    expect(trn('ss_days', 2), '2 дня');
    expect(trn('ss_days', 5), '5 дней');
    expect(trn('ss_days', 11), '11 дней');
    expect(trn('ss_days', 21), '21 день');
    expect(trn('ss_days', 22), '22 дня');
    expect(trn('ss_days', 112), '112 дней');
  });

  test('английский различает только один и много', () async {
    await lang('en');
    expect(trn('ss_days', 1), '1 day');
    expect(trn('ss_days', 2), '2 days');
    expect(trn('ss_days', 0), '0 days');
  });

  test('во французском ноль тоже единственное число', () async {
    await lang('fr');
    expect(trn('ss_days', 0), '0 jour');
    expect(trn('ss_days', 1), '1 jour');
    expect(trn('ss_days', 3), '3 jours');
  });

  test('подстановки кроме числа тоже работают', () async {
    await lang('ru');
    expect(trn('ss_of_episodes', 62, {'a': 60}), '60 из 62 серий');
    expect(trn('ss_of_episodes', 21, {'a': 3}), '3 из 21 серии');
  });

  test('день и месяц на каждом языке свои', () async {
    final d = DateTime(2026, 2, 3, 21, 10);
    await lang('ru');
    expect(dayMonth(d), '3 фев');
    expect(weekdayName(d), 'вторник');
    await lang('en');
    expect(dayMonth(d), 'Feb 3');
    await lang('de');
    expect(dayMonth(d), '3. Feb.');
    expect(longDate(d), '3. Februar 2026');
    expect(weekdayName(d), 'Dienstag');
    await lang('fr');
    expect(dayMonth(d), '3 févr.');
    await lang('es');
    expect(longDate(d), '3 de febrero de 2026');
  });
}
