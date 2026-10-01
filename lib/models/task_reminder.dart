import 'package:flutter/foundation.dart';

/// When to send the notification for one maintenance task.
@immutable
class TaskReminder {
  const TaskReminder({
    this.enabled = true,
    this.daysBefore = 0,
    this.hour = 9,
    this.minute = 0,
  }) : assert(daysBefore >= 0, 'daysBefore cannot be negative.');

  /// A reminder that is turned off.
  const TaskReminder.off() : this(enabled: false);

  /// Whether the user wants to be notified about this task.
  final bool enabled;

  /// How many days before the due date the reminder is sent.
  /// 0 means on the due date itself.
  final int daysBefore;

  /// The time of day (24 hour clock) the reminder is sent.
  final int hour;
  final int minute;

  /// The moment the reminder should appear for a task due on [dueDate].
  DateTime timeFor(DateTime dueDate) {
    final day = DateTime(dueDate.year, dueDate.month, dueDate.day - daysBefore);
    return DateTime(day.year, day.month, day.day, hour, minute);
  }

  TaskReminder copyWith({
    bool? enabled,
    int? daysBefore,
    int? hour,
    int? minute,
  }) {
    return TaskReminder(
      enabled: enabled ?? this.enabled,
      daysBefore: daysBefore ?? this.daysBefore,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'daysBefore': daysBefore,
    'hour': hour,
    'minute': minute,
  };

  factory TaskReminder.fromJson(Map<String, dynamic> json) {
    const defaults = TaskReminder();
    return TaskReminder(
      enabled: json['enabled'] as bool? ?? defaults.enabled,
      daysBefore: json['daysBefore'] as int? ?? defaults.daysBefore,
      hour: json['hour'] as int? ?? defaults.hour,
      minute: json['minute'] as int? ?? defaults.minute,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskReminder &&
      other.enabled == enabled &&
      other.daysBefore == daysBefore &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(enabled, daysBefore, hour, minute);
}
