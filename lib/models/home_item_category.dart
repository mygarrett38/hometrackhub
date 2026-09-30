/// Broad groups used to organize the user's home items.
enum HomeItemCategory {
  appliance('Appliances'),
  hvac('Heating & cooling'),
  plumbing('Plumbing & water'),
  electrical('Electrical & power'),
  safety('Safety'),
  outdoor('Outdoor & yard'),
  vehicle('Vehicles'),
  smartDevice('Smart devices'),
  other('Other');

  const HomeItemCategory(this.label);

  final String label;
}
