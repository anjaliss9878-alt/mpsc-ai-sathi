/// Tiny date formatting helpers — kept dependency-free (no `intl` package)
/// since the app only needs a couple of fixed English date formats.
const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _monthsFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// e.g. "20 Jul 2026".
String formatShortDate(DateTime date) {
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

/// e.g. "Monday, 20 July 2026".
String formatLongDate(DateTime date) {
  final weekday = _weekdays[date.weekday - 1];
  return '$weekday, ${date.day} ${_monthsFull[date.month - 1]} ${date.year}';
}

/// e.g. "20 Jul 2026, 7:05 PM".
String formatFriendlyDateTime(DateTime date) {
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final ampm = date.hour >= 12 ? 'PM' : 'AM';
  final minute = date.minute.toString().padLeft(2, '0');
  return '${formatShortDate(date)}, $hour12:$minute $ampm';
}
