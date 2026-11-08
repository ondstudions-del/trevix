const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// «ahora», «5 min», «3 h», «2 d», «12 mar», «12 mar 2025».
String timeAgo(DateTime? date) {
  if (date == null) return '';
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inSeconds < 60) return 'ahora';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) return '${diff.inHours} h';
  if (diff.inDays < 7) return '${diff.inDays} d';
  final base = '${date.day} ${_months[date.month - 1]}';
  return date.year == now.year ? base : '$base ${date.year}';
}

String fullDate(DateTime? date) {
  if (date == null) return '';
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '${date.day} ${_months[date.month - 1]} ${date.year} · $h:$m';
}

String shortMonth(DateTime date) => _months[date.month - 1];

/// «sábado 14 de nov · 20:00 – 23:00» (fecha y horario de un evento).
String eventWhen(DateTime? starts, DateTime? ends) {
  if (starts == null) return '';
  const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final sameDay = ends != null && ends.year == starts.year && ends.month == starts.month && ends.day == starts.day;
  final end = ends == null ? '' : ' – ${sameDay ? hm(ends) : '${ends.day} ${shortMonth(ends)} ${hm(ends)}'}';
  return '${days[starts.weekday - 1]} ${starts.day} de ${shortMonth(starts)} · ${hm(starts)}$end';
}

const _monthNames = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

String monthYear(DateTime? date) {
  if (date == null) return '';
  return '${_monthNames[date.month - 1]} de ${date.year}';
}

/// «14 de marzo» o «14 de marzo de 1998».
String birthday(int day, int month, [int? year]) =>
    '$day de ${_monthNames[(month - 1).clamp(0, 11)]}${year != null ? ' de $year' : ''}';

/// 950 · 1,2 mil · 3,4 M
String compact(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final v = n / 1000;
    return '${v >= 100 ? v.round() : v.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} mil';
  }
  final v = n / 1000000;
  return '${v.toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')} M';
}

/// 185 → «3:05»
String clock(num seconds) {
  final s = seconds.round().clamp(0, 359999);
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}

String plural(int n, String one, String many) => '${compact(n)} ${n == 1 ? one : many}';

String fileSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',')} MB';
}
