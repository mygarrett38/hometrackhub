import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/app_settings.dart';
import '../../../models/service_sort.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/screen_padding.dart';
import '../../widgets/settings_card.dart';
import '../../widgets/settings_dropdown_row.dart';

/// Lets the user choose where the Nearby services screen searches around,
/// their location or a ZIP code, and the order businesses are listed in
/// when it opens.
class NearbyServicesSettingsScreen extends StatelessWidget {
  const NearbyServicesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final useZipCode =
        settings.nearbyLocationSource == NearbyLocationSource.zipCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Nearby services')),
      body: ListView(
        padding: screenPadding(context),
        children: [
          SettingsCard(
            children: [
              SettingsDropdownRow<NearbyLocationSource>(
                icon: Icons.location_on_outlined,
                title: 'Search near',
                description: useZipCode
                    ? 'Businesses are found around the middle of this ZIP '
                          'code.'
                    : "Your approximate location is sent to Google to find "
                          "businesses near you. It isn't saved.",
                value: settings.nearbyLocationSource,
                choices: {
                  for (final source in NearbyLocationSource.values)
                    source: source.label,
                },
                onChanged: (source) => controller.update(
                  settings.copyWith(nearbyLocationSource: source),
                ),
              ),
              if (useZipCode) const _ZipCodeField(),
            ],
          ),
          SettingsCard(
            children: [
              SettingsDropdownRow<ServiceSort>(
                icon: Icons.sort,
                title: 'Default sort',
                description:
                    'How businesses are listed when you open Nearby '
                    'services. You can still change it there.',
                value: settings.nearbySort,
                choices: {
                  for (final sort in ServiceSort.values) sort: sort.label,
                },
                onChanged: (sort) =>
                    controller.update(settings.copyWith(nearbySort: sort)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The ZIP code to search around. Saved as soon as it's five digits, and
/// cleared when the field is emptied. Says what's wrong once the user
/// leaves the field with a partial ZIP code.
class _ZipCodeField extends StatefulWidget {
  const _ZipCodeField();

  @override
  State<_ZipCodeField> createState() => _ZipCodeFieldState();
}

class _ZipCodeFieldState extends State<_ZipCodeField> {
  late final _text = TextEditingController(
    text: context.read<SettingsController>().settings.nearbyZipCode ?? '',
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Shows or hides the error as the user enters and leaves the field.
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text.text;
    final incomplete =
        text.isNotEmpty &&
        !AppSettings.isValidZipCode(text) &&
        !_focus.hasFocus;

    return Padding(
      // Lined up with the titles of the rows, after their icons.
      padding: const EdgeInsets.fromLTRB(56, 4, 16, 16),
      child: TextField(
        controller: _text,
        focusNode: _focus,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        decoration: InputDecoration(
          labelText: 'ZIP code',
          hintText: 'For example, 62701',
          errorText: incomplete ? 'Enter all 5 digits of the ZIP code.' : null,
          border: const OutlineInputBorder(),
        ),
        onChanged: _save,
      ),
    );
  }

  void _save(String text) {
    setState(() {});
    final controller = context.read<SettingsController>();
    final settings = controller.settings;
    if (AppSettings.isValidZipCode(text)) {
      controller.update(settings.copyWith(nearbyZipCode: text));
    } else if (text.isEmpty && settings.nearbyZipCode != null) {
      controller.update(settings.copyWith(clearNearbyZipCode: true));
    }
  }
}
