import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/app_settings.dart';
import '../../state/settings_controller.dart';

/// Form for entering or clearing the home's address.
class HomeLocationScreen extends StatefulWidget {
  const HomeLocationScreen({super.key});

  @override
  State<HomeLocationScreen> createState() => _HomeLocationScreenState();
}

class _HomeLocationScreenState extends State<HomeLocationScreen> {
  late final TextEditingController _streetAddress;
  late final TextEditingController _city;
  late final TextEditingController _region;
  late final TextEditingController _postalCode;
  late final TextEditingController _country;

  @override
  void initState() {
    super.initState();
    final location = context.read<SettingsController>().settings.homeLocation;
    _streetAddress = TextEditingController(text: location.streetAddress);
    _city = TextEditingController(text: location.city);
    _region = TextEditingController(text: location.region);
    _postalCode = TextEditingController(text: location.postalCode);
    _country = TextEditingController(text: location.country);
  }

  @override
  void dispose() {
    for (final controller in [
      _streetAddress,
      _city,
      _region,
      _postalCode,
      _country,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(HomeLocation location) async {
    final controller = context.read<SettingsController>();
    final navigator = Navigator.of(context);
    await controller.update(
      controller.settings.copyWith(homeLocation: location),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home location'),
        actions: [
          TextButton(
            onPressed: () => _save(
              HomeLocation(
                streetAddress: _streetAddress.text.trim(),
                city: _city.text.trim(),
                region: _region.text.trim(),
                postalCode: _postalCode.text.trim(),
                country: _country.text.trim(),
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Your address is optional and is stored only on this device.',
          ),
          gap,
          _field(_streetAddress, 'Street address'),
          gap,
          _field(_city, 'City'),
          gap,
          _field(_region, 'State / province / region'),
          gap,
          _field(_postalCode, 'ZIP / postal code'),
          gap,
          _field(_country, 'Country'),
          gap,
          OutlinedButton.icon(
            icon: const Icon(Icons.clear),
            label: const Text('Clear home location'),
            onPressed: () => _save(const HomeLocation()),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
