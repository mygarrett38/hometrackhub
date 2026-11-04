import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/data_export_service.dart';
import '../../../state/assist_chat_controller.dart';
import '../../../state/home_item_controller.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/screen_padding.dart';
import '../../widgets/settings_card.dart';

/// Privacy settings: network scanning, notification details, and saving,
/// sharing or deleting the user's data.
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  // Shown in place of a row's usual description once its action is done.
  _SaveResult? _saveResult;
  bool _deleted = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final errorColor = Theme.of(context).colorScheme.error;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: screenPadding(context),
        children: [
          SettingsCard(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.wifi_find),
                title: const Text('Nearby device scanning'),
                subtitle: const Text('Using Wi-Fi and Bluetooth'),
                value: settings.networkDiscoveryEnabled,
                onChanged: (enabled) => controller.update(
                  settings.copyWith(networkDiscoveryEnabled: enabled),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide notification details'),
                subtitle: const Text("Reminders won't name your home items"),
                value: settings.hideDetailsInNotifications,
                onChanged: (hide) => controller.update(
                  settings.copyWith(hideDetailsInNotifications: hide),
                ),
              ),
            ],
          ),
          // Your data.
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save my data'),
                subtitle: Text(
                  switch (_saveResult) {
                    null => 'Save a copy of all of your data as a file',
                    _SaveResult.saved => 'Your data was saved',
                    _SaveResult.failed =>
                      'Could not save your data. Try again.',
                  },
                  style: _saveResult == _SaveResult.failed
                      ? TextStyle(color: errorColor)
                      : null,
                ),
                onTap: _saveData,
              ),
              // A Builder, so the share sheet can point at this row on
              // tablets.
              Builder(
                builder: (rowContext) => ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share my data'),
                  subtitle: const Text(
                    'Sends a copy of everything, including your home items, '
                    'chats and settings, to the app or person you choose',
                  ),
                  onTap: () => _shareData(rowContext),
                ),
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
                      : 'Removes all home items, chats and settings',
                ),
                onTap: _confirmDeleteAll,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// All of the user's data as JSON, for saving or sharing.
  String _exportJson() {
    final export = {
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': context.read<SettingsController>().settings.toJson(),
      'homeItems': [
        for (final item in context.read<HomeItemController>().homeItems)
          item.toJson(),
      ],
      'assistChats': [
        for (final chat in context.read<AssistChatController>().chats)
          chat.toJson(),
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(export);
  }

  /// For example "hometrackhub-data-2026-11-04.json".
  static String _exportFileName() {
    final today = DateTime.now();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return 'hometrackhub-data-${today.year}-${twoDigits(today.month)}-'
        '${twoDigits(today.day)}.json';
  }

  Future<void> _saveData() async {
    final export = context.read<DataExportService>();
    _SaveResult? result;
    try {
      // Cancelling the save dialog leaves the description as it was.
      if (await export.save(_exportFileName(), _exportJson())) {
        result = _SaveResult.saved;
      }
    } catch (error) {
      debugPrint('Could not save data: $error');
      result = _SaveResult.failed;
    }
    if (mounted && result != null) setState(() => _saveResult = result);
  }

  Future<void> _shareData(BuildContext rowContext) async {
    final export = context.read<DataExportService>();
    final box = rowContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await export.share(_exportFileName(), _exportJson(), origin: origin);
    } catch (error) {
      debugPrint('Could not share data: $error');
    }
  }

  Future<void> _confirmDeleteAll() async {
    final homeItems = context.read<HomeItemController>();
    final assistChats = context.read<AssistChatController>();
    final settings = context.read<SettingsController>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: Text(
          'This permanently deletes all of your home items, maintenance '
          'history, reminders, chats and settings from this device'
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
      await assistChats.deleteAll();
      await settings.reset();
      if (mounted) setState(() => _deleted = true);
    }
  }
}

/// How saving the user's data to a file went.
enum _SaveResult { saved, failed }
