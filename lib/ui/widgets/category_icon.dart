import 'package:flutter/material.dart';

import '../../models/home_item_category.dart';

/// Material icons used to represent each [HomeItemCategory].
extension HomeItemCategoryIcon on HomeItemCategory {
  IconData get icon => switch (this) {
    HomeItemCategory.appliance => Icons.kitchen,
    HomeItemCategory.hvac => Icons.thermostat,
    HomeItemCategory.plumbing => Icons.water_drop,
    HomeItemCategory.electrical => Icons.electrical_services,
    HomeItemCategory.safety => Icons.local_fire_department,
    HomeItemCategory.outdoor => Icons.yard,
    HomeItemCategory.vehicle => Icons.directions_car,
    HomeItemCategory.smartDevice => Icons.devices_other,
    HomeItemCategory.other => Icons.handyman,
  };
}
