import 'package:flutter/material.dart';

/// Assist tab. Empty for now.
class AssistScreen extends StatelessWidget {
  const AssistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assist')),
      body: const SizedBox.shrink(),
    );
  }
}
