import 'package:flutter/foundation.dart';

import 'equipment_category.dart';
import 'maintenance_task.dart';

/// Anything in or around the home that needs maintenance: an appliance,
/// a vehicle, a smart device, or something the user describes themselves.
@immutable
class Equipment {
  const Equipment({
    required this.id,
    required this.name,
    required this.category,
    this.catalogTypeId,
    this.manufacturer = '',
    this.modelNumber = '',
    this.serialNumber = '',
    this.location = '',
    this.notes = '',
    this.purchaseDate,
    this.networkId,
    this.tasks = const [],
  });

  final String id;
  final String name;
  final EquipmentCategory category;

  /// The id of the catalog entry this was created from, or `null` if the
  /// user entered a custom piece of equipment.
  final String? catalogTypeId;

  final String manufacturer;
  final String modelNumber;
  final String serialNumber;

  /// Where the equipment is, such as "Kitchen" or "Garage".
  final String location;
  final String notes;
  final DateTime? purchaseDate;

  /// A stable identifier for devices found by the network scan, so the scan
  /// can tell which devices have already been added.
  final String? networkId;

  final List<MaintenanceTask> tasks;

  bool get isCustom => catalogTypeId == null;

  Equipment copyWith({
    String? name,
    EquipmentCategory? category,
    String? manufacturer,
    String? modelNumber,
    String? serialNumber,
    String? location,
    String? notes,
    DateTime? purchaseDate,
    List<MaintenanceTask>? tasks,
  }) {
    return Equipment(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      catalogTypeId: catalogTypeId,
      manufacturer: manufacturer ?? this.manufacturer,
      modelNumber: modelNumber ?? this.modelNumber,
      serialNumber: serialNumber ?? this.serialNumber,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      networkId: networkId,
      tasks: tasks ?? this.tasks,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'catalogTypeId': catalogTypeId,
    'manufacturer': manufacturer,
    'modelNumber': modelNumber,
    'serialNumber': serialNumber,
    'location': location,
    'notes': notes,
    'purchaseDate': purchaseDate?.toIso8601String(),
    'networkId': networkId,
    'tasks': [for (final task in tasks) task.toJson()],
  };

  factory Equipment.fromJson(Map<String, dynamic> json) {
    final purchaseDate = json['purchaseDate'] as String?;
    return Equipment(
      id: json['id'] as String,
      name: json['name'] as String,
      category: EquipmentCategory.values.byName(json['category'] as String),
      catalogTypeId: json['catalogTypeId'] as String?,
      manufacturer: json['manufacturer'] as String? ?? '',
      modelNumber: json['modelNumber'] as String? ?? '',
      serialNumber: json['serialNumber'] as String? ?? '',
      location: json['location'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      purchaseDate: purchaseDate == null ? null : DateTime.parse(purchaseDate),
      networkId: json['networkId'] as String?,
      tasks: [
        for (final task in json['tasks'] as List<dynamic>? ?? [])
          MaintenanceTask.fromJson(task as Map<String, dynamic>),
      ],
    );
  }
}
