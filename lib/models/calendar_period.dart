import 'dart:math' show min;

/// How much time the calendar shows at once. The one chosen in Appearance
/// settings is what the calendar opens with, and how far ahead and back the
/// Overview's Upcoming and Recently Completed cards look (see [shift]). The
/// Spent card counts this month or year (see [budgetPeriod]).
enum CalendarPeriod {
  week('Week'),
  month('Month'),
  year('Year');

  const CalendarPeriod(this.label);

  final String label;

  /// The first day of the week, month or year that [day] is in, and the
  /// first day after it. Weeks start on Sunday, as on the calendar.
  (DateTime start, DateTime end) rangeOf(DateTime day) {
    switch (this) {
      case week:
        final start = DateTime(day.year, day.month, day.day - day.weekday % 7);
        return (start, DateTime(start.year, start.month, start.day + 7));
      case month:
        return (
          DateTime(day.year, day.month),
          DateTime(day.year, day.month + 1),
        );
      case year:
        return (DateTime(day.year), DateTime(day.year + 1));
    }
  }

  /// The same day [count] weeks, months or years after [day], or before it
  /// when [count] is negative. A day the month is too short for, such as
  /// the 31st, becomes the month's last day.
  DateTime shift(DateTime day, int count) {
    switch (this) {
      case week:
        return DateTime(day.year, day.month, day.day + 7 * count);
      case month:
        return _clampedDate(day.year, day.month + count, day.day);
      case year:
        return _clampedDate(day.year + count, day.month, day.day);
    }
  }

  /// The period spending is counted by: a month or a year, like a budget.
  /// A week counts its month.
  CalendarPeriod get budgetPeriod => this == week ? month : this;

  /// [day] of [month] in [year], or the month's last day if it's shorter.
  /// [month] may run past December or before January.
  static DateTime _clampedDate(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, min(day, lastDay));
  }
}
