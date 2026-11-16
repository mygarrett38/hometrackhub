import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/app_data_file.dart';
import '../../../models/app_settings.dart';
import '../../../services/data_export_service.dart';
import '../../../state/assist_chat_controller.dart';
import '../../../state/home_item_controller.dart';
import '../../../state/settings_controller.dart';
import '../../widgets/screen_padding.dart';
import '../../widgets/settings_card.dart';

/// Privacy settings: network scanning, notification details, hiding serial
/// numbers, and saving, loading, sharing or deleting the user's data.
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
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
              SwitchListTile(
                secondary: const Icon(Icons.pin_outlined),
                title: const Text('Hide serial numbers'),
                subtitle: const Text(
                  'Serial numbers will only be visible '
                  'with this setting off',
                ),
                value: settings.hideSerialNumbers,
                onChanged: (hide) => controller.update(
                  settings.copyWith(hideSerialNumbers: hide),
                ),
              ),
            ],
          ),
          // Your data, as a row of buttons.
          SettingsCard(
            children: [
              Row(
                children: [
                  _DataButton(
                    icon: Icons.save_alt,
                    label: 'Save',
                    tooltip: 'Save my data',
                    onPressed: (_) => _saveData(),
                  ),
                  // Loading brings data back up out of a file: the same
                  // arrow and base as saving, pointing the other way.
                  _DataButton(
                    icon: Icons.upload,
                    label: 'Load',
                    tooltip: 'Load my data',
                    onPressed: (_) => _loadData(),
                  ),
                  _DataButton(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    tooltip: 'Share my data',
                    onPressed: _shareData,
                  ),
                  _DataButton(
                    icon: Icons.delete_forever_outlined,
                    label: 'Delete',
                    tooltip: 'Delete all my data',
                    color: errorColor,
                    onPressed: (_) => _confirmDeleteAll(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// All of the user's data as a file, for saving or sharing.
  String _exportJson() {
    return AppDataFile(
      settings: context.read<SettingsController>().settings,
      homeItems: context.read<HomeItemController>().homeItems,
      assistChats: context.read<AssistChatController>().chats,
    ).encode(DateTime.now());
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
    final bool saved;
    try {
      saved = await export.save(_exportFileName(), _exportJson());
    } catch (error) {
      debugPrint('Could not save data: $error');
      if (mounted) {
        await _showMessage(
          "Couldn't save your data",
          'Something went wrong while saving. Please try again.',
        );
      }
      return;
    }
    // Cancelling the save dialog shows nothing.
    if (saved && mounted) {
      await _showMessage('Data saved', 'A copy of all of your data was saved.');
    }
  }

  /// Replaces all of the user's data with a file they saved, once they
  /// confirm. Files this version of the app can't read are turned away.
  Future<void> _loadData() async {
    final export = context.read<DataExportService>();
    final homeItems = context.read<HomeItemController>();
    final assistChats = context.read<AssistChatController>();
    final settings = context.read<SettingsController>();

    final OpenedFile? opened;
    try {
      opened = await export.open();
    } catch (error) {
      debugPrint('Could not open data file: $error');
      if (mounted) {
        await _showMessage(
          "Couldn't open the file",
          'Something went wrong while opening the file. Please try again.',
        );
      }
      return;
    }
    // Cancelling the file picker shows nothing.
    if (opened == null || !mounted) return;

    final AppDataFile file;
    try {
      file = AppDataFile.decode(opened.contents);
    } on IncompatibleDataFileException catch (error) {
      await _showMessage("Can't load this file", switch (error.problem) {
        DataFileProblem.notAppData =>
          'The file you selected is incompatible with HomeTrackHub. '
              'Please select a file you saved using this app.',
        DataFileProblem.otherVersion =>
          'The file you selected was saved by an incompatible version of '
              "HomeTrackHub and cannot be loaded.",
        DataFileProblem.damaged =>
          'The file you selected is corrupted and cannot be loaded.',
      });
      return;
    }

    if (!await _confirmLoad(opened.name, file) || !mounted) return;

    // Which calendar tasks are added to is kept: calendars belong to this
    // device, so one picked on another device wouldn't be found here.
    final current = settings.settings;
    await settings.update(
      AppSettings.fromJson({
        ...file.settings.toJson(),
        'calendarSyncEnabled': current.calendarSyncEnabled,
        'syncCalendarId': current.syncCalendarId,
        'syncCalendarName': current.syncCalendarName,
      }),
    );
    await assistChats.replaceAll(file.assistChats);
    await homeItems.replaceAll(file.homeItems);
    if (mounted) {
      await _showMessage(
        'Data loaded',
        'Your data was successfully imported.',
      );
    }
  }

  /// Shows how saving, loading, sharing or deleting the user's data went,
  /// in a popup.
  Future<void> _showMessage(String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Warns that loading [file], named [fileName], replaces everything, and
  /// returns whether the user wants to go ahead.
  Future<bool> _confirmLoad(String fileName, AppDataFile file) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm import'),
        content: const Text('All data you have currently loaded will be lost!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Opens the share sheet, pointing from [buttonContext]'s button on
  /// tablets.
  Future<void> _shareData(BuildContext buttonContext) async {
    final export = context.read<DataExportService>();
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await export.share(_exportFileName(), _exportJson(), origin: origin);
    } catch (error) {
      debugPrint('Could not share data: $error');
      if (mounted) {
        await _showMessage(
          "Couldn't share your data",
          'Something went wrong while sharing. Please try again.',
        );
      }
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
      if (mounted) {
        await _showMessage('Data deleted', 'All of your data was deleted.');
      }
    }
  }
}

/// One of the buttons for the user's data: an [icon] with a one-word
/// [label] below it, sharing a row equally with the others. [tooltip] says
/// in full what it does, and is what screen readers hear.
class _DataButton extends StatelessWidget {
  const _DataButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;

  /// Called with the button's own context, so the share sheet can point
  /// from it.
  final ValueChanged<BuildContext> onPressed;

  /// The icon and label's color, such as red for deleting. Defaults to the
  /// usual text color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: tooltip,
          excludeSemantics: true,
          child: InkWell(
            onTap: () => onPressed(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
