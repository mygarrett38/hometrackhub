import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// The text field and send button at the bottom of the Assist screens, with
/// a line above them to set them apart from the chat.
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

  /// The height of the text field with one line in it, which the send
  /// button matches.
  static const _lineHeight = 48.0;

  final TextEditingController controller;
  final bool sending;
  final ValueChanged<String> onSend;

  /// Whether the user can type and send. False when the assistant isn't
  /// available, in which case the field is shown greyed out.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        // Keeps clear of the system navigation bar.
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              // The button stays at the bottom as the question gets longer.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: _lineHeight),
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
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Rebuilds as the user types, so the button is only enabled
                // when there's a question to send.
                ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (context, value, _) => IconButton.filled(
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(_lineHeight),
                      // Cream once there's a question to send. Set here
                      // because the app's navy icon color would otherwise
                      // win over the button's own.
                      foregroundColor: BrandColors.cream,
                    ),
                    icon: const Icon(Icons.send),
                    onPressed: !enabled || sending || value.text.trim().isEmpty
                        ? null
                        : () => onSend(value.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
