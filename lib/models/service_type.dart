import 'package:flutter/material.dart';

/// The kinds of home maintenance businesses the Nearby services screen can
/// filter by.
enum ServiceType {
  plumbing('Plumbing', 'plumber', Icons.plumbing),
  hvac('Heating & cooling', 'HVAC repair', Icons.hvac),
  electrical('Electrical', 'electrician', Icons.electrical_services),
  appliance('Appliance repair', 'appliance repair', Icons.kitchen),
  roofing('Roofing', 'roofing contractor', Icons.roofing),
  landscaping('Lawn & landscaping', 'landscaping', Icons.grass),
  pestControl('Pest control', 'pest control', Icons.pest_control),
  handyman('Handyman', 'handyman', Icons.handyman),
  auto('Auto repair', 'auto repair', Icons.car_repair);

  const ServiceType(this.label, this.searchPhrase, this.icon);

  final String label;

  /// What to search for to find businesses that offer this service, such as
  /// "plumber". Most trades have no category of their own in map search, so
  /// businesses are found by these words instead.
  final String searchPhrase;

  final IconData icon;
}
