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

/// Describes when something is due, in weeks or months when it's far off:
/// "Due in 3 months" past six weeks, "Due in 3 weeks" past two weeks, and
/// otherwise as [describeDueDate] does, for example "Due in 5 days" or
/// "Overdue by 2 days".
String describeDueDateRoughly(DateTime dueDate, DateTime today) {
  final days = calendarDaysBetween(today, dueDate);
  if (_inWeeksOrMonths(days) case final time?) return 'Due in $time';
  return describeDueDate(dueDate, today);
}

/// Describes how long ago something was completed, rounded the same way as
/// [describeDueDateRoughly]: "Completed today", "Completed yesterday",
/// "Completed 5 days ago", "Completed 3 weeks ago" or "Completed 2 months
/// ago".
String describeCompletedRoughly(DateTime completedOn, DateTime today) {
  final days = calendarDaysBetween(completedOn, today);
  if (days <= 0) return 'Completed today';
  if (days == 1) return 'Completed yesterday';
  final time = _inWeeksOrMonths(days) ?? '$days days';
  return 'Completed $time ago';
}

/// [days] in months past six weeks, such as "3 months", or in weeks past
/// two weeks, such as "3 weeks". `null` for two weeks or less.
String? _inWeeksOrMonths(int days) {
  if (days > 6 * 7) {
    final months = (days / _averageDaysPerMonth).round();
    return '$months ${months == 1 ? 'month' : 'months'}';
  }
  if (days > 14) return '${(days / 7).round()} weeks';
  return null;
}

/// Describes when a home item's next task is due, for example "Next task
/// due in 3 months" or "Next task overdue by 2 days". See
/// [describeDueDateRoughly].
String describeNextTaskDue(DateTime dueDate, DateTime today) =>
    'Next task ${describeDueDateRoughly(dueDate, today).toLowerCase()}';

/// 365.25 days a year spread over 12 months.
const _averageDaysPerMonth = 365.25 / 12;
