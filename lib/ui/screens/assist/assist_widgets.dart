import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The text field and send button at the bottom of the Assist screens.
class AssistComposer extends StatelessWidget {
  const AssistComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    this.enabled = true,
  });

  /// Longest question the user can type, well under the server's limit.
  static const maxQuestionLength = 2000;

  final TextEditingController controller;
  final bool sending;
  final ValueChanged<String> onSend;

  /// Whether the user can type and send. False when the assistant isn't
  /// available, in which case the field is shown greyed out.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Keeps clear of the system navigation bar.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(maxQuestionLength),
                ],
                decoration: const InputDecoration(
                  hintText: 'Ask a maintenance question',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Rebuilds as the user types, so the button is only enabled when
            // there's a question to send.
            ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, _) => IconButton.filled(
                tooltip: 'Send',
                icon: const Icon(Icons.send),
                onPressed: !enabled || sending || value.text.trim().isEmpty
                    ? null
                    : () => onSend(value.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
