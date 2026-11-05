/// How much the user knows about home repairs, chosen in Assistant settings,
/// so the assistant can pitch its answers at the right level.
enum TechnicalLevel {
  beginner('Beginner'),
  someExperience('Some experience'),
  handy('Handy');

  const TechnicalLevel(this.label);

  final String label;
}
