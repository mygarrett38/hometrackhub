import 'package:flutter/material.dart';

import '../../models/equipment_category.dart';

/// Material icons used to represent each [EquipmentCategory].
extension EquipmentCategoryIcon on EquipmentCategory {
  IconData get icon => switch (this) {
    EquipmentCategory.appliance => Icons.kitchen,
    EquipmentCategory.hvac => Icons.thermostat,
    EquipmentCategory.plumbing => Icons.water_drop,
    EquipmentCategory.electrical => Icons.electrical_services,
    EquipmentCategory.safety => Icons.local_fire_department,
    EquipmentCategory.outdoor => Icons.yard,
    EquipmentCategory.vehicle => Icons.directions_car,
    EquipmentCategory.smartDevice => Icons.devices_other,
    EquipmentCategory.other => Icons.handyman,
  };
}
