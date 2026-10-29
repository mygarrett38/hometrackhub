import 'package:flutter/material.dart';

/// Search for home services near the user, such as plumbers or HVAC
/// technicians. Empty for now.
class NearbyServicesScreen extends StatelessWidget {
  const NearbyServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby services')),
      body: const SizedBox.shrink(),
    );
  }
}
