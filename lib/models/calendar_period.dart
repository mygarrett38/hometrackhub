/// How much time the calendar shows at once. The one chosen in Appearance
/// settings is what the calendar opens with, and what the Overview's
/// Completed and Spent cards count.
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
}
