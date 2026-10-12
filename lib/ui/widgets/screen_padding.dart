import 'package:flutter/widgets.dart';

/// Padding for the scrolling content of a full screen: [size] on every side,
/// plus room at the bottom for the system navigation bar.
///
/// The app draws behind the navigation bar, and a list with its own padding
/// no longer leaves space for it automatically, so without this the last
/// item can end up underneath it.
EdgeInsets screenPadding(BuildContext context, {double size = 16}) {
  return EdgeInsets.fromLTRB(
    size,
    size,
    size,
    size + MediaQuery.paddingOf(context).bottom,
  );
}
