import 'package:flutter/material.dart';

/// Settings for the Assist tab's AI assistant. Empty for now.
class AssistantSettingsScreen extends StatelessWidget {
  const AssistantSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: const SizedBox.shrink(),
    );
  }
}
