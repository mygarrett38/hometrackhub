/// The orders the Nearby services screen can list businesses in.
enum ServiceSort {
  rating('Top rated'),
  distance('Closest'),
  reviews('Most reviewed');

  const ServiceSort(this.label);

  final String label;
}
