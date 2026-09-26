import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometrackhub/models/app_settings.dart';
import 'package:hometrackhub/models/equipment.dart';
import 'package:hometrackhub/models/equipment_category.dart';
import 'package:hometrackhub/models/maintenance_interval.dart';
import 'package:hometrackhub/models/maintenance_task.dart';

void main() {
  group('MaintenanceInterval.addTo', () {
    test('adds days and weeks', () {
      final start = DateTime(2026, 3, 30);
      expect(
        const MaintenanceInterval.days(1).addTo(start),
        DateTime(2026, 3, 31),
      );
      expect(
        const MaintenanceInterval.weeks(2).addTo(start),
        DateTime(2026, 4, 13),
      );
    });

    test('adds months, keeping the day of the month', () {
      expect(
        const MaintenanceInterval.months(3).addTo(DateTime(2026, 11, 15)),
        DateTime(2027, 2, 15),
      );
    });

    test('clamps to the last day of shorter months', () {
      expect(
        const MaintenanceInterval.months(1).addTo(DateTime(2026, 1, 31)),
        DateTime(2026, 2, 28),
      );
      expect(
        const MaintenanceInterval.years(1).addTo(DateTime(2028, 2, 29)),
        DateTime(2029, 2, 28),
      );
    });
  });

  test('MaintenanceInterval.label reads naturally', () {
    expect(const MaintenanceInterval.days(1).label, 'Daily');
    expect(const MaintenanceInterval.years(1).label, 'Yearly');
    expect(const MaintenanceInterval.months(6).label, 'Every 6 months');
  });

  group('MaintenanceTask', () {
    final task = MaintenanceTask(
      id: 'task',
      title: 'Replace filter',
      interval: const MaintenanceInterval.months(3),
      recommendedInterval: const MaintenanceInterval.months(3),
      startDate: DateTime(2026, 1, 1),
    );

    test('is first due one interval after tracking started', () {
      expect(task.nextDueDate, DateTime(2026, 4, 1));
    });

    test('is due one interval after it was last completed', () {
      final done = task.copyWith(lastCompleted: DateTime(2026, 2, 10));
      expect(done.nextDueDate, DateTime(2026, 5, 10));
    });

    test('knows whether it follows the manufacturer recommendation', () {
      expect(task.followsRecommendation, isTrue);
      final changed = task.copyWith(
        interval: const MaintenanceInterval.months(1),
      );
      expect(changed.followsRecommendation, isFalse);
    });
  });

  test('Equipment survives a JSON round trip', () {
    final equipment = Equipment(
      id: 'fridge',
      name: 'Kitchen fridge',
      category: EquipmentCategory.appliance,
      catalogTypeId: 'refrigerator',
      manufacturer: 'Acme',
      purchaseDate: DateTime(2020, 5, 1),
      tasks: [
        MaintenanceTask(
          id: 'coils',
          title: 'Clean coils',
          interval: const MaintenanceInterval.months(6),
          recommendedInterval: const MaintenanceInterval.months(6),
          startDate: DateTime(2026, 1, 1),
          lastCompleted: DateTime(2026, 2, 1),
          remindersEnabled: false,
        ),
      ],
    );

    final restored = Equipment.fromJson(equipment.toJson());

    expect(restored.toJson(), equipment.toJson());
  });

  test('AppSettings uses defaults for values missing from saved data', () {
    final settings = AppSettings.fromJson({'themeMode': 'dark'});

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.notificationsEnabled, isTrue);
    expect(settings.reminderHour, 9);
    expect(settings.homeLocation.isEmpty, isTrue);
  });
}
