import 'dart:math';

final _random = Random.secure();

/// Creates a random 32 character hexadecimal id for stored records.
String generateId() {
  return List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
