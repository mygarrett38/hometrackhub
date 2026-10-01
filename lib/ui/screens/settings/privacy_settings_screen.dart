import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../state/home_item_controller.dart';
import '../../../state/settings_controller.dart';

/// Privacy settings: network scanning, notification details, and exporting
/// or deleting the user's data.
class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final errorColor = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Everything you enter is stored only on this device and is '
              'never uploaded.',
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_find),
            title: const Text('Find smart devices on my network'),
            subtitle: const Text(
              'Allows scanning your local Wi-Fi network for smart devices',
            ),
            value: settings.networkDiscoveryEnabled,
            onChanged: (enabled) => controller.update(
              settings.copyWith(networkDiscoveryEnabled: enabled),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hide details in notifications'),
            subtitle: const Text(
              'Reminders will not name your home items, for example on a '
              'locked screen',
            ),
            value: settings.hideDetailsInNotifications,
            onChanged: (hide) => controller.update(
              settings.copyWith(hideDetailsInNotifications: hide),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Export my data'),
            subtitle: const Text('Copy all of your data to the clipboard'),
            onTap: () => _exportData(context),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: errorColor),
            title: Text(
              'Delete all my data',
              style: TextStyle(color: errorColor),
            ),
            subtitle: const Text('Removes all home items and settings'),
            onTap: () => _confirmDeleteAll(context),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final export = {
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': context.read<SettingsController>().settings.toJson(),
      'homeItems': [
        for (final item in context.read<HomeItemController>().homeItems)
          item.toJson(),
      ],
    };
    final json = const JsonEncoder.withIndent('  ').convert(export);
    await Clipboard.setData(ClipboardData(text: json));
    messenger.showSnackBar(
      const SnackBar(content: Text('Your data was copied to the clipboard.')),
    );
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final homeItems = context.read<HomeItemController>();
    final settings = context.read<SettingsController>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'This permanently deletes all of your home items, maintenance '
          'history, reminders and settings from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await homeItems.deleteAll();
      await settings.reset();
      messenger.showSnackBar(
        const SnackBar(content: Text('All data was deleted.')),
      );
    }
  }
}
