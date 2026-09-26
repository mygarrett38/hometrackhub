import 'package:flutter/foundation.dart';

import '../models/equipment_category.dart';
import '../models/maintenance_interval.dart';
import '../models/maintenance_task.dart';
import '../utils/id_generator.dart';

/// A maintenance task that is recommended for a type of equipment.
@immutable
class TaskTemplate {
  const TaskTemplate(this.title, this.interval, [this.description = '']);

  final String title;
  final MaintenanceInterval interval;
  final String description;
}

/// A common kind of home equipment together with the maintenance its
/// manufacturers typically recommend.
@immutable
class EquipmentType {
  const EquipmentType({
    required this.id,
    required this.name,
    required this.category,
    required this.tasks,
  });

  /// Stable id stored on [Equipment.catalogTypeId]. Never change an existing
  /// id, because saved equipment refers to it.
  final String id;
  final String name;
  final EquipmentCategory category;
  final List<TaskTemplate> tasks;

  /// Creates the maintenance tasks for a newly added piece of equipment.
  /// Each task starts on the manufacturer's recommended interval.
  List<MaintenanceTask> createTasks({required DateTime startDate}) {
    return [
      for (final template in tasks)
        MaintenanceTask(
          id: generateId(),
          title: template.title,
          description: template.description,
          interval: template.interval,
          recommendedInterval: template.interval,
          startDate: startDate,
        ),
    ];
  }
}

/// Looks up a catalog entry by its id. Returns `null` if it does not exist.
EquipmentType? findEquipmentType(String? id) {
  if (id == null) return null;
  for (final type in equipmentCatalog) {
    if (type.id == id) return type;
  }
  return null;
}

/// Built-in list of common equipment and its recommended maintenance.
///
/// Intervals reflect the general guidance found in manufacturer owner's
/// manuals for each kind of equipment. A specific model may differ, so users
/// can change any interval and reset it to this default later.
const List<EquipmentType> equipmentCatalog = [
  // Appliances
  EquipmentType(
    id: 'refrigerator',
    name: 'Refrigerator',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate(
        'Replace water filter',
        MaintenanceInterval.months(6),
        'Only needed if the fridge has a water or ice dispenser.',
      ),
      TaskTemplate(
        'Clean condenser coils',
        MaintenanceInterval.months(6),
        'Vacuum the coils behind or under the fridge.',
      ),
      TaskTemplate(
        'Clean door gaskets',
        MaintenanceInterval.months(3),
        'Wipe seals with warm soapy water and check they close tightly.',
      ),
    ],
  ),
  EquipmentType(
    id: 'dishwasher',
    name: 'Dishwasher',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate('Clean filter', MaintenanceInterval.months(1)),
      TaskTemplate('Run cleaning cycle', MaintenanceInterval.months(1)),
      TaskTemplate(
        'Inspect spray arms and door seal',
        MaintenanceInterval.months(6),
      ),
    ],
  ),
  EquipmentType(
    id: 'washing_machine',
    name: 'Washing machine',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate('Run tub clean cycle', MaintenanceInterval.months(1)),
      TaskTemplate(
        'Clean detergent dispenser and door seal',
        MaintenanceInterval.months(1),
      ),
      TaskTemplate(
        'Inspect water supply hoses',
        MaintenanceInterval.years(1),
        'Replace hoses that are cracked, bulging, or over 5 years old.',
      ),
    ],
  ),
  EquipmentType(
    id: 'clothes_dryer',
    name: 'Clothes dryer',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate(
        'Deep clean lint screen',
        MaintenanceInterval.months(3),
        'Wash the screen with soapy water to remove fabric softener film.',
      ),
      TaskTemplate(
        'Clean exhaust vent duct',
        MaintenanceInterval.years(1),
        'A clogged vent is a fire hazard.',
      ),
    ],
  ),
  EquipmentType(
    id: 'oven_range',
    name: 'Oven / range',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate('Clean oven interior', MaintenanceInterval.months(3)),
      TaskTemplate(
        'Clean burners and drip pans',
        MaintenanceInterval.months(1),
      ),
    ],
  ),
  EquipmentType(
    id: 'range_hood',
    name: 'Range hood',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate('Clean grease filters', MaintenanceInterval.months(1)),
    ],
  ),
  EquipmentType(
    id: 'microwave',
    name: 'Microwave',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate('Clean interior', MaintenanceInterval.weeks(1)),
      TaskTemplate(
        'Replace charcoal filter',
        MaintenanceInterval.months(6),
        'Over-the-range models only.',
      ),
    ],
  ),
  EquipmentType(
    id: 'garbage_disposal',
    name: 'Garbage disposal',
    category: EquipmentCategory.appliance,
    tasks: [TaskTemplate('Clean and deodorize', MaintenanceInterval.months(1))],
  ),
  EquipmentType(
    id: 'dehumidifier',
    name: 'Dehumidifier',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate(
        'Empty water bucket',
        MaintenanceInterval.days(1),
        'Not needed if the unit drains to a hose.',
      ),
      TaskTemplate('Clean air filter', MaintenanceInterval.weeks(2)),
    ],
  ),
  EquipmentType(
    id: 'humidifier',
    name: 'Humidifier',
    category: EquipmentCategory.appliance,
    tasks: [
      TaskTemplate('Clean and disinfect tank', MaintenanceInterval.weeks(1)),
      TaskTemplate('Replace wick filter', MaintenanceInterval.months(2)),
    ],
  ),

  // Heating and cooling
  EquipmentType(
    id: 'central_hvac',
    name: 'Furnace / central air',
    category: EquipmentCategory.hvac,
    tasks: [
      TaskTemplate(
        'Replace air filter',
        MaintenanceInterval.months(3),
        'Check monthly if you have pets or allergies.',
      ),
      TaskTemplate('Professional tune-up', MaintenanceInterval.years(1)),
      TaskTemplate(
        'Clear debris around outdoor unit',
        MaintenanceInterval.months(6),
        'Keep at least 2 feet of clearance around the condenser.',
      ),
    ],
  ),
  EquipmentType(
    id: 'heat_pump',
    name: 'Heat pump',
    category: EquipmentCategory.hvac,
    tasks: [
      TaskTemplate(
        'Clean or replace air filter',
        MaintenanceInterval.months(1),
      ),
      TaskTemplate('Professional service', MaintenanceInterval.years(1)),
    ],
  ),
  EquipmentType(
    id: 'window_ac',
    name: 'Window / portable air conditioner',
    category: EquipmentCategory.hvac,
    tasks: [
      TaskTemplate('Clean air filter', MaintenanceInterval.weeks(2)),
      TaskTemplate('Clean coils and drain pan', MaintenanceInterval.years(1)),
    ],
  ),
  EquipmentType(
    id: 'fireplace',
    name: 'Fireplace / chimney',
    category: EquipmentCategory.hvac,
    tasks: [
      TaskTemplate(
        'Chimney inspection and sweep',
        MaintenanceInterval.years(1),
      ),
    ],
  ),
  EquipmentType(
    id: 'ceiling_fan',
    name: 'Ceiling fan',
    category: EquipmentCategory.hvac,
    tasks: [TaskTemplate('Dust blades', MaintenanceInterval.months(1))],
  ),

  // Plumbing and water
  EquipmentType(
    id: 'water_heater',
    name: 'Water heater',
    category: EquipmentCategory.plumbing,
    tasks: [
      TaskTemplate(
        'Flush tank to remove sediment',
        MaintenanceInterval.years(1),
      ),
      TaskTemplate('Test pressure relief valve', MaintenanceInterval.years(1)),
      TaskTemplate('Inspect anode rod', MaintenanceInterval.years(3)),
    ],
  ),
  EquipmentType(
    id: 'tankless_water_heater',
    name: 'Tankless water heater',
    category: EquipmentCategory.plumbing,
    tasks: [
      TaskTemplate(
        'Descale / flush heat exchanger',
        MaintenanceInterval.years(1),
      ),
      TaskTemplate('Clean inlet water filter', MaintenanceInterval.months(6)),
    ],
  ),
  EquipmentType(
    id: 'water_softener',
    name: 'Water softener',
    category: EquipmentCategory.plumbing,
    tasks: [
      TaskTemplate('Check and refill salt', MaintenanceInterval.months(1)),
      TaskTemplate('Clean brine tank', MaintenanceInterval.years(1)),
    ],
  ),
  EquipmentType(
    id: 'water_filter',
    name: 'Water filtration system',
    category: EquipmentCategory.plumbing,
    tasks: [
      TaskTemplate('Replace filter cartridges', MaintenanceInterval.months(6)),
      TaskTemplate(
        'Replace reverse osmosis membrane',
        MaintenanceInterval.years(2),
        'Reverse osmosis systems only.',
      ),
    ],
  ),
  EquipmentType(
    id: 'sump_pump',
    name: 'Sump pump',
    category: EquipmentCategory.plumbing,
    tasks: [
      TaskTemplate(
        'Test pump',
        MaintenanceInterval.months(3),
        'Pour water into the pit and make sure the pump turns on.',
      ),
      TaskTemplate('Clean pit and inlet screen', MaintenanceInterval.years(1)),
    ],
  ),
  EquipmentType(
    id: 'septic_system',
    name: 'Septic system',
    category: EquipmentCategory.plumbing,
    tasks: [
      TaskTemplate('Professional inspection', MaintenanceInterval.years(3)),
      TaskTemplate('Pump tank', MaintenanceInterval.years(3)),
    ],
  ),

  // Electrical and power
  EquipmentType(
    id: 'generator',
    name: 'Backup generator',
    category: EquipmentCategory.electrical,
    tasks: [
      TaskTemplate('Run under load (exercise)', MaintenanceInterval.months(1)),
      TaskTemplate('Change oil and filter', MaintenanceInterval.years(1)),
    ],
  ),
  EquipmentType(
    id: 'gfci_outlets',
    name: 'GFCI outlets',
    category: EquipmentCategory.electrical,
    tasks: [
      TaskTemplate(
        'Press test and reset buttons',
        MaintenanceInterval.months(1),
      ),
    ],
  ),
  EquipmentType(
    id: 'solar_panels',
    name: 'Solar panels',
    category: EquipmentCategory.electrical,
    tasks: [
      TaskTemplate('Clean panels', MaintenanceInterval.months(6)),
      TaskTemplate('Inspect wiring and mounts', MaintenanceInterval.years(1)),
    ],
  ),

  // Safety
  EquipmentType(
    id: 'smoke_detector',
    name: 'Smoke detector',
    category: EquipmentCategory.safety,
    tasks: [
      TaskTemplate('Press test button', MaintenanceInterval.months(1)),
      TaskTemplate('Replace batteries', MaintenanceInterval.years(1)),
      TaskTemplate('Replace detector', MaintenanceInterval.years(10)),
    ],
  ),
  EquipmentType(
    id: 'co_detector',
    name: 'Carbon monoxide detector',
    category: EquipmentCategory.safety,
    tasks: [
      TaskTemplate('Press test button', MaintenanceInterval.months(1)),
      TaskTemplate('Replace batteries', MaintenanceInterval.years(1)),
      TaskTemplate('Replace detector', MaintenanceInterval.years(7)),
    ],
  ),
  EquipmentType(
    id: 'fire_extinguisher',
    name: 'Fire extinguisher',
    category: EquipmentCategory.safety,
    tasks: [
      TaskTemplate(
        'Check pressure gauge',
        MaintenanceInterval.months(1),
        'The needle should be in the green zone.',
      ),
      TaskTemplate('Professional inspection', MaintenanceInterval.years(1)),
    ],
  ),

  // Outdoor and yard
  EquipmentType(
    id: 'lawn_mower',
    name: 'Lawn mower',
    category: EquipmentCategory.outdoor,
    tasks: [
      TaskTemplate('Change oil', MaintenanceInterval.years(1)),
      TaskTemplate('Sharpen blade', MaintenanceInterval.years(1)),
      TaskTemplate(
        'Replace air filter and spark plug',
        MaintenanceInterval.years(1),
      ),
    ],
  ),
  EquipmentType(
    id: 'snow_blower',
    name: 'Snow blower',
    category: EquipmentCategory.outdoor,
    tasks: [
      TaskTemplate('Change oil', MaintenanceInterval.years(1)),
      TaskTemplate(
        'Inspect shear pins and belts',
        MaintenanceInterval.years(1),
      ),
    ],
  ),
  EquipmentType(
    id: 'gutters',
    name: 'Gutters',
    category: EquipmentCategory.outdoor,
    tasks: [
      TaskTemplate(
        'Clean gutters and downspouts',
        MaintenanceInterval.months(6),
      ),
    ],
  ),
  EquipmentType(
    id: 'pool',
    name: 'Swimming pool',
    category: EquipmentCategory.outdoor,
    tasks: [
      TaskTemplate('Test water chemistry', MaintenanceInterval.weeks(1)),
      TaskTemplate(
        'Clean skimmer and pump baskets',
        MaintenanceInterval.weeks(1),
      ),
      TaskTemplate('Clean filter', MaintenanceInterval.months(1)),
    ],
  ),
  EquipmentType(
    id: 'hot_tub',
    name: 'Hot tub',
    category: EquipmentCategory.outdoor,
    tasks: [
      TaskTemplate('Test water chemistry', MaintenanceInterval.weeks(1)),
      TaskTemplate('Rinse filter', MaintenanceInterval.weeks(2)),
      TaskTemplate('Drain and refill', MaintenanceInterval.months(3)),
    ],
  ),
  EquipmentType(
    id: 'sprinkler_system',
    name: 'Sprinkler system',
    category: EquipmentCategory.outdoor,
    tasks: [
      TaskTemplate(
        'Inspect heads and adjust spray',
        MaintenanceInterval.months(1),
      ),
      TaskTemplate('Winterize / blow out lines', MaintenanceInterval.years(1)),
    ],
  ),

  // Vehicles
  EquipmentType(
    id: 'car',
    name: 'Car / SUV / truck',
    category: EquipmentCategory.vehicle,
    tasks: [
      TaskTemplate(
        'Oil and filter change',
        MaintenanceInterval.months(6),
        'Or at the mileage in your owner\'s manual, whichever comes first.',
      ),
      TaskTemplate('Rotate tires', MaintenanceInterval.months(6)),
      TaskTemplate('Check tire pressure', MaintenanceInterval.months(1)),
      TaskTemplate('Replace cabin air filter', MaintenanceInterval.years(1)),
      TaskTemplate('Replace wiper blades', MaintenanceInterval.years(1)),
      TaskTemplate('Replace brake fluid', MaintenanceInterval.years(2)),
    ],
  ),
  EquipmentType(
    id: 'electric_vehicle',
    name: 'Electric vehicle',
    category: EquipmentCategory.vehicle,
    tasks: [
      TaskTemplate('Rotate tires', MaintenanceInterval.months(6)),
      TaskTemplate('Check tire pressure', MaintenanceInterval.months(1)),
      TaskTemplate('Replace cabin air filter', MaintenanceInterval.years(2)),
      TaskTemplate('Test brake fluid', MaintenanceInterval.years(2)),
    ],
  ),
  EquipmentType(
    id: 'motorcycle',
    name: 'Motorcycle',
    category: EquipmentCategory.vehicle,
    tasks: [
      TaskTemplate('Clean and lubricate chain', MaintenanceInterval.weeks(2)),
      TaskTemplate('Oil and filter change', MaintenanceInterval.years(1)),
      TaskTemplate('Replace brake fluid', MaintenanceInterval.years(2)),
    ],
  ),
  EquipmentType(
    id: 'boat',
    name: 'Boat',
    category: EquipmentCategory.vehicle,
    tasks: [
      TaskTemplate('Flush engine after use', MaintenanceInterval.weeks(1)),
      TaskTemplate('Change engine oil', MaintenanceInterval.years(1)),
      TaskTemplate('Winterize', MaintenanceInterval.years(1)),
    ],
  ),

  // Smart devices. The network scan suggests these types for the devices
  // it finds, so keep these ids in sync with device_discovery_service.dart.
  EquipmentType(
    id: 'smart_tv',
    name: 'Smart TV / streaming device',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate('Install software updates', MaintenanceInterval.months(1)),
      TaskTemplate('Dust screen and vents', MaintenanceInterval.months(1)),
    ],
  ),
  EquipmentType(
    id: 'smart_speaker',
    name: 'Smart speaker',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate('Install software updates', MaintenanceInterval.months(1)),
    ],
  ),
  EquipmentType(
    id: 'smart_thermostat',
    name: 'Smart thermostat',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate(
        'Review heating and cooling schedule',
        MaintenanceInterval.months(6),
      ),
      TaskTemplate(
        'Replace batteries',
        MaintenanceInterval.years(1),
        'Battery powered models.',
      ),
    ],
  ),
  EquipmentType(
    id: 'smart_lighting',
    name: 'Smart lighting / bridge',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate('Install firmware updates', MaintenanceInterval.months(3)),
    ],
  ),
  EquipmentType(
    id: 'smart_hub',
    name: 'Smart home hub',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate('Install firmware updates', MaintenanceInterval.months(1)),
      TaskTemplate('Back up configuration', MaintenanceInterval.months(3)),
    ],
  ),
  EquipmentType(
    id: 'security_camera',
    name: 'Security camera / doorbell',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate('Clean lens', MaintenanceInterval.months(3)),
      TaskTemplate('Install firmware updates', MaintenanceInterval.months(1)),
      TaskTemplate(
        'Recharge battery',
        MaintenanceInterval.months(3),
        'Battery powered models.',
      ),
    ],
  ),
  EquipmentType(
    id: 'smart_lock',
    name: 'Smart lock',
    category: EquipmentCategory.smartDevice,
    tasks: [TaskTemplate('Replace batteries', MaintenanceInterval.months(6))],
  ),
  EquipmentType(
    id: 'robot_vacuum',
    name: 'Robot vacuum',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate('Clean brushes', MaintenanceInterval.weeks(1)),
      TaskTemplate('Replace filter', MaintenanceInterval.months(2)),
      TaskTemplate('Replace side brush', MaintenanceInterval.months(3)),
    ],
  ),
  EquipmentType(
    id: 'printer',
    name: 'Printer',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate(
        'Print a test page',
        MaintenanceInterval.weeks(2),
        'Keeps inkjet nozzles from drying out.',
      ),
      TaskTemplate('Install firmware updates', MaintenanceInterval.months(3)),
    ],
  ),
  EquipmentType(
    id: 'router',
    name: 'Wi-Fi router',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate('Install firmware updates', MaintenanceInterval.months(1)),
      TaskTemplate('Restart router', MaintenanceInterval.months(1)),
    ],
  ),
  EquipmentType(
    id: 'smart_device',
    name: 'Other smart device',
    category: EquipmentCategory.smartDevice,
    tasks: [
      TaskTemplate('Install firmware updates', MaintenanceInterval.months(3)),
    ],
  ),
];
