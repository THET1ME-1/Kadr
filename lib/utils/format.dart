import '../l10n/locale_controller.dart';

/// Форматирование длительности и дат для табло/аналитики/календаря.
/// Без сторонних зависимостей (intl удалён) — всё локализуется вручную по
/// текущему коду языка [LocaleController].

bool get _en => LocaleController.instance.code == 'en';

String _two(int v) => v.toString().padLeft(2, '0');

/// Часы:минуты:секунды для бегущего таймера. До часа — «MM:SS», от часа —
/// «H:MM:SS».
String clockDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// Человекочитаемая длительность для крупных карточек аналитики:
/// «1 ч 23 мин», «45 мин», «38 сек». На английском — «1h 23m», «45m», «38s».
String humanDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (_en) {
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    if (m > 0) return s > 0 && m < 10 ? '${m}m ${s}s' : '${m}m';
    return '${s}s';
  }
  if (h > 0) return m > 0 ? '$h ч $m мин' : '$h ч';
  if (m > 0) return s > 0 && m < 10 ? '$m мин $s сек' : '$m мин';
  return '$s сек';
}

/// Короткая длительность для подписей в строках: «1:05:00» либо «5:00».
String compactDuration(Duration d) => clockDuration(d);

const List<String> _monthsRu = [
  'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
  'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
];
const List<String> _monthsRuShort = [
  'янв', 'фев', 'мар', 'апр', 'май', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];
const List<String> _monthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _monthsEnShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Полное название месяца (1..12).
String monthName(int month) =>
    (_en ? _monthsEn : _monthsRu)[(month - 1).clamp(0, 11)];

/// Короткое название месяца (1..12).
String monthShort(int month) =>
    (_en ? _monthsEnShort : _monthsRuShort)[(month - 1).clamp(0, 11)];

/// Короткие названия дней недели, начиная с понедельника.
List<String> get weekdayShort =>
    _en ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// «30 июня 2026» / «June 30, 2026».
String longDate(DateTime d) => _en
    ? '${monthName(d.month)} ${d.day}, ${d.year}'
    : '${d.day} ${_monthsRu[d.month - 1].toLowerCase()} ${d.year}';

/// «30.06.2026, 14:05».
String dateTimeShort(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year}, ${_two(d.hour)}:${_two(d.minute)}';
