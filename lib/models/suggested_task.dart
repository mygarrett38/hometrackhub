import 'package:flutter/foundation.dart';

import '../utils/id_generator.dart';
import 'maintenance_interval.dart';
import 'maintenance_task.dart';

/// A maintenance task the assistant suggested repeating on a schedule, such
/// as replacing a furnace filter every 3 months, which the user can add to
/// a home item.
@immutable
class SuggestedTask {
  const SuggestedTask({
    required this.title,
    required this.interval,
    this.description = '',
  });

  final String title;

  /// Short instructions for doing the task.
  final String description;

  /// How often the assistant suggested repeating it.
  final MaintenanceInterval interval;

  /// A new task with this one's title, instructions and repeat, starting
  /// on [today].
  MaintenanceTask toTask(DateTime today) => MaintenanceTask(
    id: generateId(),
    title: title,
    description: description,
    interval: interval,
    startDate: today,
  );

  /// Laid out as the assistant's server sends it.
  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'every': interval.amount,
    'unit': interval.unit.name,
  };

  /// The suggested task in [json], laid out as [toJson] and the assistant's
  /// server lay it out, or `null` if it isn't one, such as from a newer
  /// server.
  static SuggestedTask? tryParse(Object? json) {
    if (json
        case {
          'title': final String title,
          'every': final int every,
          'unit': final String unitName,
        }
        when title.trim().isNotEmpty && every >= 1) {
      final unit = IntervalUnit.values.asNameMap()[unitName];
      if (unit == null) return null;
      return SuggestedTask(
        title: title.trim(),
        description: switch (json['description']) {
          final String description => description.trim(),
          _ => '',
        },
        interval: MaintenanceInterval(every, unit),
      );
    }
    return null;
  }

  /// The suggested tasks in [json], a list of them, leaving out any that
  /// can't be read.
  static List<SuggestedTask> listFrom(Object? json) => [
    if (json is List)
      for (final task in json) ?tryParse(task),
  ];
}
