import '../l10n/locale_controller.dart';

/// Форматирование длительности и дат для табло/аналитики/календаря.
/// Без сторонних зависимостей (intl удалён) — всё локализуется вручную по
/// текущему коду языка [LocaleController].

String get _lang => LocaleController.instance.code;
bool get _en => _lang == 'en';

String _two(int v) => v.toString().padLeft(2, '0');

/// Делает первую букву заглавной («фантастика» → «Фантастика»).
String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

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

const Map<String, List<String>> _months = {
  'ru': ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'],
  'en': ['January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'],
  'de': ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'],
  'fr': ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
      'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'],
  'es': ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'],
  'it': ['Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
      'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'],
  'pt': ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'],
};

const Map<String, List<String>> _monthsShort = {
  'ru': ['янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'],
  'en': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  'de': ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni',
      'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.'],
  'fr': ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'],
  'es': ['ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sept', 'oct', 'nov', 'dic'],
  'it': ['gen', 'feb', 'mar', 'apr', 'mag', 'giu',
      'lug', 'ago', 'set', 'ott', 'nov', 'dic'],
  'pt': ['jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez'],
};

const Map<String, List<String>> _weekdaysShort = {
  'ru': ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
  'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  'de': ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
  'fr': ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'],
  'es': ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'],
  'it': ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'],
  'pt': ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'],
};

const Map<String, List<String>> _weekdays = {
  'ru': ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота',
      'воскресенье'],
  'en': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday'],
  'de': ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag',
      'Sonntag'],
  'fr': ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi',
      'dimanche'],
  'es': ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado',
      'domingo'],
  'it': ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato',
      'domenica'],
  'pt': ['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira',
      'sexta-feira', 'sábado', 'domingo'],
};

/// Родительный падеж месяцев для русских дат («15 января»).
const List<String> _monthsRuGen = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

List<String> _pick(Map<String, List<String>> table) =>
    table[_lang] ?? table['ru']!;

/// Полное название месяца (1..12), с заглавной: заголовки месяцев.
String monthName(int month) => _pick(_months)[(month - 1).clamp(0, 11)];

/// Короткое название месяца (1..12).
String monthShort(int month) => _pick(_monthsShort)[(month - 1).clamp(0, 11)];

/// Короткие названия дней недели, начиная с понедельника.
List<String> get weekdayShort => _pick(_weekdaysShort);

/// День недели полностью: «вторник», «Dienstag».
String weekdayName(DateTime d) => _pick(_weekdays)[d.weekday - 1];

/// День и короткий месяц без года: «3 фев», «Feb 3», «3. Feb.».
String dayMonth(DateTime d) {
  final m = monthShort(d.month);
  return switch (_lang) {
    'en' => '$m ${d.day}',
    'de' => '${d.day}. $m',
    _ => '${d.day} $m',
  };
}

/// «30 июня 2026» / «June 30, 2026» / «30. Juni 2026».
String longDate(DateTime d) {
  final m = monthName(d.month);
  return switch (_lang) {
    'en' => '$m ${d.day}, ${d.year}',
    'de' => '${d.day}. $m ${d.year}',
    'es' || 'pt' => '${d.day} de ${m.toLowerCase()} de ${d.year}',
    'fr' || 'it' => '${d.day} ${m.toLowerCase()} ${d.year}',
    _ => '${d.day} ${_monthsRuGen[d.month - 1]} ${d.year}',
  };
}

/// «30.06.2026, 14:05».
String dateTimeShort(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year}, ${_two(d.hour)}:${_two(d.minute)}';

/// «18.10.2023» — числовой формат ДД.ММ.ГГГГ.
String numericDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

/// «20:45» — только время.
String hhmm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// «18.10.2023 11:31» — с точным временем, если оно задано (не полночь),
/// иначе только дата.
String dateExactWithTime(DateTime d) {
  final hasTime = d.hour != 0 || d.minute != 0;
  return hasTime
      ? '${numericDate(d)} ${_two(d.hour)}:${_two(d.minute)}'
      : numericDate(d);
}
