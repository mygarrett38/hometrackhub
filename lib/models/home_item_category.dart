/// Broad groups used to organize the user's home items.
enum HomeItemCategory {
  appliance('Appliances', 'appliance'),
  vehicle('Vehicles', 'vehicle'),
  electrical('Electrical', 'electrical item'),
  plumbing('Water', 'water system'),
  hvac('Heating & cooling', 'heating & cooling'),
  outdoor('Outdoor', 'outdoor item'),
  safety('Safety', 'safety device'),
  smartDevice('Smart devices', 'smart device'),
  custom('Custom', 'custom item');

  const HomeItemCategory(this.label, this.itemName);

  final String label;

  /// What one home item in this category is called, in lowercase, such as
  /// "appliance" in "Add appliance".
  final String itemName;
}
