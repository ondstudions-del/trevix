import 'i18n.dart';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthNames = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const _monthNamesEn = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

bool get _en => Lang.instance.en;

/// Separador decimal del idioma: «1,5» en español y «1.5» en inglés.
String _decimal(String n) => _en ? n : n.replaceAll('.', ',');

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// «ahora», «5 min», «3 h», «2 d», «12 mar», «12 mar 2025» (en inglés «now», «Mar 12»…).
String timeAgo(DateTime? date) {
  if (date == null) return '';
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inSeconds < 60) return _en ? 'now' : 'ahora';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) return '${diff.inHours} h';
  if (diff.inDays < 7) return '${diff.inDays} d';
  final base = _en ? '${shortMonth(date)} ${date.day}' : '${date.day} ${shortMonth(date)}';
  if (date.year == now.year) return base;
  return _en ? '$base, ${date.year}' : '$base ${date.year}';
}

String fullDate(DateTime? date) {
  if (date == null) return '';
  return _en
      ? '${shortMonth(date)} ${date.day}, ${date.year} · ${_hm(date)}'
      : '${date.day} ${shortMonth(date)} ${date.year} · ${_hm(date)}';
}

String shortMonth(DateTime date) => (_en ? _monthsEn : _months)[date.month - 1];

/// «sábado 14 de nov · 20:00 – 23:00» (fecha y horario de un evento); en inglés «Saturday, Nov 14 · 20:00 – 23:00».
String eventWhen(DateTime? starts, DateTime? ends) {
  if (starts == null) return '';
  final sameDay = ends != null && ends.year == starts.year && ends.month == starts.month && ends.day == starts.day;
  String day(DateTime d) => _en ? '${shortMonth(d)} ${d.day}' : '${d.day} ${shortMonth(d)}';
  final end = ends == null ? '' : ' – ${sameDay ? _hm(ends) : '${day(ends)} ${_hm(ends)}'}';
  final weekday = (_en ? _daysEn : _days)[starts.weekday - 1];
  return _en
      ? '$weekday, ${day(starts)} · ${_hm(starts)}$end'
      : '$weekday ${starts.day} de ${shortMonth(starts)} · ${_hm(starts)}$end';
}

String monthYear(DateTime? date) {
  if (date == null) return '';
  return _en ? '${_monthNamesEn[date.month - 1]} ${date.year}' : '${_monthNames[date.month - 1]} de ${date.year}';
}

/// «14 de marzo» o «14 de marzo de 1998» (en inglés «March 14» o «March 14, 1998»).
String birthday(int day, int month, [int? year]) {
  final m = (month - 1).clamp(0, 11);
  if (_en) return '${_monthNamesEn[m]} $day${year != null ? ', $year' : ''}';
  return '$day de ${_monthNames[m]}${year != null ? ' de $year' : ''}';
}

/// 950 · 1,2 mil · 3,4 M (en inglés 950 · 1.2K · 3.4M).
String compact(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000;
    final s = v >= 100 ? '${v.round()}' : _decimal(v.toStringAsFixed(1).replaceAll('.0', ''));
    return _en ? '${s}K' : '$s mil';
  }
  final s = _decimal((n / 1000000).toStringAsFixed(1).replaceAll('.0', ''));
  return _en ? '${s}M' : '$s M';
}

/// 185 → «3:05»
String clock(num seconds) {
  final s = seconds.round().clamp(0, 359999);
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}

/// «1 seguidor», «12 seguidores»: [one] y [many] se escriben en español y se traducen con [tr].
String plural(int n, String one, String many) => '${compact(n)} ${tr(n == 1 ? one : many)}';

String fileSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${_decimal((bytes / 1048576).toStringAsFixed(1))} MB';
}
