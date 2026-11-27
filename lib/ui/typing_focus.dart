import 'package:flutter/widgets.dart';

/// Stops the keyboard coming back when the user returns to a screen they'd
/// been typing on.
///
/// Flutter gives focus back to whatever had it on a screen when the user
/// returns to it, so a text field that was being typed in would be focused
/// again and bring the keyboard back up. When a screen, dialog or sheet
/// opens over a text field that's being typed in, this makes the field give
/// up focus first, so there's nothing to give focus back to.
class TypingFocusObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The new route only takes focus once it's built, after this, so a
    // field that has focus here is on the screen being covered.
    stopTyping();
  }
}

/// Makes the text field being typed in give up focus, which hides the
/// keyboard, and makes its screen forget it was focused, so it isn't
/// focused again when the user comes back. Anything else that has focus,
/// such as a button, is left alone.
void stopTyping() {
  final focused = FocusManager.instance.primaryFocus;
  final isTextField =
      focused?.context?.findAncestorStateOfType<EditableTextState>() != null;
  // Unfocusing to the enclosing scope also clears the scope's record of
  // what it last focused.
  if (isTextField) focused!.unfocus();
}
