/// Returns [date] with the time of day removed.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// The number of whole calendar days from [from] to [to]. Negative when [to]
/// is before [from].
///
/// Uses UTC dates so daylight saving time changes do not produce off-by-one
/// results.
int calendarDaysBetween(DateTime from, DateTime to) {
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

/// Describes when something is due relative to [today], for example
/// "Due today", "Due in 5 days", or "Overdue by 2 days".
String describeDueDate(DateTime dueDate, DateTime today) {
  final days = calendarDaysBetween(today, dueDate);
  if (days < 0) {
    final overdueDays = -days;
    return 'Overdue by $overdueDays ${overdueDays == 1 ? 'day' : 'days'}';
  }
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in $days days';
}
