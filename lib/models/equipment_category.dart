/// Broad groups used to organize the user's equipment.
enum EquipmentCategory {
  appliance('Appliances'),
  hvac('Heating & cooling'),
  plumbing('Plumbing & water'),
  electrical('Electrical & power'),
  safety('Safety'),
  outdoor('Outdoor & yard'),
  vehicle('Vehicles'),
  smartDevice('Smart devices'),
  other('Other');

  const EquipmentCategory(this.label);

  final String label;
}
