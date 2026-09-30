import 'package:flutter/material.dart';

import '../../models/home_item_category.dart';

/// Material icons used to represent each [HomeItemCategory].
extension HomeItemCategoryIcon on HomeItemCategory {
  IconData get icon => switch (this) {
    HomeItemCategory.appliance => Icons.local_laundry_service,
    HomeItemCategory.vehicle => Icons.directions_car,
    HomeItemCategory.electrical => Icons.power,
    HomeItemCategory.plumbing => Icons.water_drop,
    HomeItemCategory.hvac => Icons.thermostat,
    HomeItemCategory.outdoor => Icons.sunny,
    HomeItemCategory.safety => Icons.local_fire_department,
    HomeItemCategory.smartDevice => Icons.devices_other,
    HomeItemCategory.custom => Icons.handyman,
  };
}
