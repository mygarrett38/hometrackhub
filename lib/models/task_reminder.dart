import 'package:flutter/foundation.dart';

/// Whether to send notifications for one maintenance task, and how far ahead
/// of its due date they start. When they're sent, how often and at what time
/// is set in the notification settings (see [AppSettings.upcomingHour] and
/// [AppSettings.overdueEnabled]).
@immutable
class TaskReminder {
  const TaskReminder({this.enabled = true, this.daysBefore = 0})
    : assert(daysBefore >= 0, 'daysBefore cannot be negative.');

  /// A reminder that is turned off.
  const TaskReminder.off() : this(enabled: false);

  /// Whether the user wants to be notified about this task.
  final bool enabled;

  /// How many days before the due date the first upcoming notification is
  /// sent. 0 means on the due date itself.
  final int daysBefore;

  TaskReminder copyWith({bool? enabled, int? daysBefore}) {
    return TaskReminder(
      enabled: enabled ?? this.enabled,
      daysBefore: daysBefore ?? this.daysBefore,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'daysBefore': daysBefore,
  };

  /// Reads a reminder saved by [toJson]. Reminders saved when each task had
  /// its own time also stored an hour and minute, which are ignored now.
  factory TaskReminder.fromJson(Map<String, dynamic> json) {
    const defaults = TaskReminder();
    return TaskReminder(
      enabled: json['enabled'] as bool? ?? defaults.enabled,
      daysBefore: json['daysBefore'] as int? ?? defaults.daysBefore,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskReminder &&
      other.enabled == enabled &&
      other.daysBefore == daysBefore;

  @override
  int get hashCode => Object.hash(enabled, daysBefore);
}
