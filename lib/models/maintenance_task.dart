import 'package:flutter/foundation.dart';

import 'maintenance_interval.dart';

/// A recurring maintenance job for one piece of equipment, such as
/// "Replace air filter every 3 months".
@immutable
class MaintenanceTask {
  const MaintenanceTask({
    required this.id,
    required this.title,
    required this.interval,
    required this.startDate,
    this.description = '',
    this.recommendedInterval,
    this.lastCompleted,
    this.remindersEnabled = true,
  });

  final String id;
  final String title;
  final String description;

  /// How often the user wants to do this task.
  final MaintenanceInterval interval;

  /// The manufacturer's recommended interval. This is `null` for tasks the
  /// user created themselves.
  final MaintenanceInterval? recommendedInterval;

  /// When tracking started. Used to calculate the first due date if the task
  /// has never been completed.
  final DateTime startDate;

  /// The last time the user marked this task as done.
  final DateTime? lastCompleted;

  /// Whether the user wants to be notified when this task is due.
  final bool remindersEnabled;

  /// The date this task is next due.
  DateTime get nextDueDate => interval.addTo(lastCompleted ?? startDate);

  /// Whether the user created this task instead of it coming from the
  /// manufacturer recommendations.
  bool get isCustom => recommendedInterval == null;

  /// Whether the user is using the manufacturer's recommended interval.
  bool get followsRecommendation => recommendedInterval == interval;

  MaintenanceTask copyWith({
    String? title,
    String? description,
    MaintenanceInterval? interval,
    DateTime? startDate,
    DateTime? lastCompleted,
    bool? remindersEnabled,
  }) {
    return MaintenanceTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      interval: interval ?? this.interval,
      recommendedInterval: recommendedInterval,
      startDate: startDate ?? this.startDate,
      lastCompleted: lastCompleted ?? this.lastCompleted,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'interval': interval.toJson(),
    'recommendedInterval': recommendedInterval?.toJson(),
    'startDate': startDate.toIso8601String(),
    'lastCompleted': lastCompleted?.toIso8601String(),
    'remindersEnabled': remindersEnabled,
  };

  factory MaintenanceTask.fromJson(Map<String, dynamic> json) {
    final recommended = json['recommendedInterval'] as Map<String, dynamic>?;
    final lastCompleted = json['lastCompleted'] as String?;
    return MaintenanceTask(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      interval: MaintenanceInterval.fromJson(
        json['interval'] as Map<String, dynamic>,
      ),
      recommendedInterval: recommended == null
          ? null
          : MaintenanceInterval.fromJson(recommended),
      startDate: DateTime.parse(json['startDate'] as String),
      lastCompleted: lastCompleted == null
          ? null
          : DateTime.parse(lastCompleted),
      remindersEnabled: json['remindersEnabled'] as bool? ?? true,
    );
  }
}
