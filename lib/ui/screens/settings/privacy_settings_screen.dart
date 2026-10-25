import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/home_assistant_client.dart';
import '../../../state/home_item_controller.dart';
import '../../../state/settings_controller.dart';

/// Privacy settings: network scanning, notification details, and exporting
/// or deleting the user's data. Also explains what leaves the device.
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  // Confirmations shown in place of a row's usual description once its
  // action is done.
  bool _exported = false;
  bool _deleted = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final assistAvailable = context.read<HomeAssistantClient>().isConfigured;
    final errorColor = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              [
                if (settings.calendarSyncEnabled)
                  'Everything you enter is stored only on this device. Your '
                      'tasks are also added to the calendar you chose, which '
                      "may sync them to that calendar's account."
                else if (assistAvailable)
                  'Everything you enter is stored only on this device.'
                else
                  'Everything you enter is stored only on this device and is '
                      'never uploaded.',
                if (assistAvailable)
                  "Questions you ask on the Assist tab are sent to Anthropic's "
                      'Claude AI to answer them. Your home items are not '
                      'sent with them.',
              ].join(' '),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_find),
            title: const Text('Find smart devices nearby'),
            subtitle: const Text(
              'Enables scanning for smart devices using Wi-Fi or Bluetooth',
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
            subtitle: Text(
              _exported
                  ? 'Your data was copied to the clipboard'
                  : 'Copy all of your data to the clipboard',
            ),
            onTap: _exportData,
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: errorColor),
            title: Text(
              'Delete all my data',
              style: TextStyle(color: errorColor),
            ),
            subtitle: Text(
              _deleted
                  ? 'All data was deleted'
                  : 'Removes all home items and settings',
            ),
            onTap: _confirmDeleteAll,
          ),
        ],
      ),
    );
  }

  Future<void> _exportData() async {
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
    if (mounted) setState(() => _exported = true);
  }

  Future<void> _confirmDeleteAll() async {
    final homeItems = context.read<HomeItemController>();
    final settings = context.read<SettingsController>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: Text(
          'This permanently deletes all of your home items, maintenance '
          'history, reminders and settings from this device'
          '${settings.settings.calendarSyncEnabled ? ', and removes your tasks from your calendar' : ''}.',
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
      if (mounted) setState(() => _deleted = true);
    }
  }
}
