import 'package:flutter/foundation.dart';

/// The unit of time a [MaintenanceInterval] is measured in.
enum IntervalUnit {
  days('day', 'days'),
  weeks('week', 'weeks'),
  months('month', 'months'),
  years('year', 'years');

  const IntervalUnit(this.singular, this.plural);

  final String singular;
  final String plural;
}

/// How often a maintenance task should be repeated, for example
/// "every 3 months" or "every day".
@immutable
class MaintenanceInterval {
  const MaintenanceInterval(this.amount, this.unit)
    : assert(amount > 0, 'An interval must be at least 1 unit long.');

  const MaintenanceInterval.days(int amount) : this(amount, IntervalUnit.days);
  const MaintenanceInterval.weeks(int amount)
    : this(amount, IntervalUnit.weeks);
  const MaintenanceInterval.months(int amount)
    : this(amount, IntervalUnit.months);
  const MaintenanceInterval.years(int amount)
    : this(amount, IntervalUnit.years);

  final int amount;
  final IntervalUnit unit;

  /// Returns the date that is one interval after [date].
  ///
  /// Months and years follow the calendar, so adding one month to
  /// January 31 gives the last day of February rather than skipping into
  /// March.
  DateTime addTo(DateTime date) {
    switch (unit) {
      case IntervalUnit.days:
        return DateTime(date.year, date.month, date.day + amount);
      case IntervalUnit.weeks:
        return DateTime(date.year, date.month, date.day + amount * 7);
      case IntervalUnit.months:
        return _addMonths(date, amount);
      case IntervalUnit.years:
        return _addMonths(date, amount * 12);
    }
  }

  /// A human readable description such as "Daily" or "Every 6 months".
  String get label {
    if (amount == 1) {
      return switch (unit) {
        IntervalUnit.days => 'Daily',
        IntervalUnit.weeks => 'Weekly',
        IntervalUnit.months => 'Monthly',
        IntervalUnit.years => 'Yearly',
      };
    }
    return 'Every $amount ${unit.plural}';
  }

  Map<String, dynamic> toJson() => {'amount': amount, 'unit': unit.name};

  factory MaintenanceInterval.fromJson(Map<String, dynamic> json) {
    return MaintenanceInterval(
      json['amount'] as int,
      IntervalUnit.values.byName(json['unit'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MaintenanceInterval &&
      other.amount == amount &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => label;
}

DateTime _addMonths(DateTime date, int months) {
  final targetMonthIndex = date.month - 1 + months;
  final year = date.year + targetMonthIndex ~/ 12;
  final month = targetMonthIndex % 12 + 1;
  // Day 0 of the following month is the last day of the target month.
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final day = date.day > lastDayOfMonth ? lastDayOfMonth : date.day;
  return DateTime(year, month, day);
}
