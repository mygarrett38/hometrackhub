/// Broad groups used to organize the user's home items.
enum HomeItemCategory {
  appliance('Appliances'),
  vehicle('Vehicles'),
  electrical('Electrical'),
  plumbing('Water'),
  hvac('Heating & cooling'),
  outdoor('Outdoor'),
  safety('Safety'),
  smartDevice('Smart devices'),
  custom('Custom');

  const HomeItemCategory(this.label);

  final String label;
}
