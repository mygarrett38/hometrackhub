import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/assist_chat.dart';
import '../../../state/assist_chat_controller.dart';
import '../../../utils/date_utils.dart';
import '../../widgets/screen_padding.dart';
import 'assist_chat_screen.dart';

/// The user's saved Assist chats in two collapsible cards: one for pinned
/// chats and one for the rest, each most recently active first. Tapping a
/// chat opens it on its own screen.
///
/// Pressing and holding a chat selects it, and tapping others then adds
/// them to the selection. The selected chats can be pinned or deleted
/// together, and a single selected chat can be renamed, which edits the
/// name in its card. Selecting is animated unless the device asks for
/// reduced motion.
class AssistHistoryScreen extends StatefulWidget {
  const AssistHistoryScreen({super.key});

  static String _expiryNote(Duration keepFor) =>
      'Chats are saved only on this device and are deleted after '
      '${keepFor.inDays} days without new messages, unless they are pinned.';

  @override
  State<AssistHistoryScreen> createState() => _AssistHistoryScreenState();
}

class _AssistHistoryScreenState extends State<AssistHistoryScreen> {
  /// The ids of the selected chats. While any are selected, tapping a chat
  /// selects or deselects it instead of opening it.
  final _selected = <String>{};

  /// The chat whose name is being edited in its card, if any.
  String? _renamingId;

  final _name = TextEditingController();

  bool get _selecting => _selected.isNotEmpty;

  /// How long selection animations take: none when the device asks for
  /// reduced motion.
  Duration get _animation => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 200);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AssistChatController>();
    final chats = controller.chats;
    final now = DateTime.now();
    // Chats can expire or be deleted while they're selected.
    _selected.removeWhere((id) => controller.chatById(id) == null);
    final pinned = [
      for (final chat in chats)
        if (chat.pinned) chat,
    ];
    final recent = [
      for (final chat in chats)
        if (!chat.pinned) chat,
    ];

    Widget row(AssistChat chat) => chat.id == _renamingId
        ? _renamingTile(chat, controller)
        : _chatTile(chat, controller.titleOf(chat), now);

    // Back stops selecting or renaming before it leaves the screen.
    return PopScope(
      canPop: !_selecting && _renamingId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          _selected.clear();
          _renamingId = null;
        });
      },
      child: Scaffold(
        // Fades between the normal top bar and the one for selecting.
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: AnimatedSwitcher(
            duration: _animation,
            child: _selecting
                ? AppBar(
                    key: const ValueKey('selecting'),
                    leading: IconButton(
                      tooltip: 'Cancel selection',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_selected.clear),
                    ),
                    // The count slides as it changes.
                    title: AnimatedSwitcher(
                      duration: _animation,
                      transitionBuilder: (child, animation) => SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.5),
                          end: Offset.zero,
                        ).animate(animation),
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Text(
                        '${_selected.length} selected',
                        key: ValueKey(_selected.length),
                      ),
                    ),
                  )
                : AppBar(
                    key: const ValueKey('history'),
                    title: const Text('Chat history'),
                  ),
          ),
        ),
        // Slides up from the bottom while chats are selected.
        bottomNavigationBar: AnimatedSwitcher(
          duration: _animation,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: child,
          ),
          child: _selecting
              ? _SelectionBar(
                  allSelected: _selected.length == chats.length,
                  allPinned: _selected.every(
                    (id) => controller.chatById(id)!.pinned,
                  ),
                  canRename: _selected.length == 1,
                  onSelectAll: () => _selectAll(chats),
                  onPin: _pinSelected,
                  onRename: _renameSelected,
                  onDelete: _deleteSelected,
                )
              : const SizedBox(width: double.infinity),
        ),
        body: chats.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'You have no saved chats yet.\n\n'
                    '${AssistHistoryScreen._expiryNote(controller.keepFor)}',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: screenPadding(context),
                children: [
                  if (pinned.isNotEmpty)
                    _ChatGroupCard(
                      key: const ValueKey('pinned'),
                      title: 'Pinned',
                      children: [for (final chat in pinned) row(chat)],
                    ),
                  if (recent.isNotEmpty)
                    _ChatGroupCard(
                      key: const ValueKey('recent'),
                      title: 'Recent',
                      children: [for (final chat in recent) row(chat)],
                    ),
                ],
              ),
      ),
    );
  }

  Widget _chatTile(AssistChat chat, String title, DateTime now) {
    final selected = _selected.contains(chat.id);
    final colors = Theme.of(context).colorScheme;

    final icon = !_selecting
        ? Icons.chat_bubble_outline
        : selected
        ? Icons.check_circle
        : Icons.radio_button_unchecked;

    // A selected chat fades to the highlight color. Fading to a see-through
    // copy of that color, rather than to plain transparent, keeps it from
    // turning grey on the way.
    final highlight = colors.secondaryContainer;
    return TweenAnimationBuilder<Color?>(
      key: ValueKey(chat.id),
      tween: ColorTween(
        end: selected ? highlight : highlight.withValues(alpha: 0),
      ),
      duration: _animation,
      builder: (context, color, child) => ListTile(
        tileColor: color,
        // The icon pops between the chat's icon and the selection circle.
        leading: AnimatedSwitcher(
          duration: _animation,
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Icon(
            icon,
            key: ValueKey(icon),
            color: _selecting
                ? (selected ? colors.primary : colors.onSurfaceVariant)
                : null,
            semanticLabel: _selecting
                ? (selected ? 'Selected' : 'Not selected')
                : null,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          chat.pinned
              ? _describeLastChat(chat, now)
              : _describe(
                  context.read<AssistChatController>().expiresAt(chat),
                  now,
                ),
        ),
        trailing: _selecting ? null : const Icon(Icons.chevron_right),
        onTap: _selecting
            ? () => _toggle(chat.id)
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AssistChatScreen(chatId: chat.id),
                ),
              ),
        onLongPress: () => _toggle(chat.id),
      ),
    );
  }

  /// A chat's row while it's being renamed: the name as a text field, with
  /// buttons to save or cancel.
  Widget _renamingTile(AssistChat chat, AssistChatController controller) {
    return ListTile(
      key: ValueKey(chat.id),
      // Less space on the right than other rows, so the buttons sit close to
      // the edge where the arrow usually is.
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      leading: const Icon(Icons.chat_bubble_outline),
      title: _ChatNameField(
        controller: _name,
        defaultName: controller.titleOf(chat.copyWith(clearName: true)),
        onSubmitted: () => _saveName(chat),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Compact so the two buttons sit close together.
          IconButton(
            tooltip: 'Cancel renaming',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _renamingId = null),
          ),
          IconButton(
            tooltip: 'Save name',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.check),
            onPressed: () => _saveName(chat),
          ),
        ],
      ),
    );
  }

  void _toggle(String chatId) {
    setState(() {
      _renamingId = null;
      if (!_selected.remove(chatId)) _selected.add(chatId);
    });
  }

  /// Selects every chat, or stops selecting if they're all selected already.
  void _selectAll(List<AssistChat> chats) {
    setState(() {
      if (_selected.length == chats.length) {
        _selected.clear();
      } else {
        _selected.addAll([for (final chat in chats) chat.id]);
      }
    });
  }

  /// Pins the selected chats, or unpins them if they're all pinned already.
  Future<void> _pinSelected() async {
    final chats = context.read<AssistChatController>();
    final ids = {..._selected};
    // The bar can still be tapped while it slides away.
    if (ids.isEmpty) return;
    final allPinned = ids.every((id) => chats.chatById(id)!.pinned);
    setState(_selected.clear);
    await chats.setPinned(ids, !allPinned);
  }

  void _renameSelected() {
    if (_selected.length != 1) return;
    final chats = context.read<AssistChatController>();
    final chat = chats.chatById(_selected.single)!;
    _ChatNameField.startEditing(_name, chats.titleOf(chat));
    setState(() {
      _selected.clear();
      _renamingId = chat.id;
    });
  }

  Future<void> _deleteSelected() async {
    final chats = context.read<AssistChatController>();
    final ids = {..._selected};
    if (ids.isEmpty) return;
    final titles = [
      for (final chat in chats.chats)
        if (ids.contains(chat.id)) chats.titleOf(chat),
    ];
    if (!await _confirmDeleteChats(context, titles) || !mounted) return;
    setState(_selected.clear);
    await chats.deleteChats(ids);
  }

  Future<void> _saveName(AssistChat chat) async {
    setState(() => _renamingId = null);
    await context.read<AssistChatController>().rename(chat.id, _name.text);
  }

  /// When there was last a message in the chat, for a pinned chat that
  /// isn't going to be deleted: "Last chatted today", "Last chatted 3 days
  /// ago", or the date once it's more than a week ago, such as "Last
  /// chatted on October 12th".
  static String _describeLastChat(AssistChat chat, DateTime now) {
    final last = chat.lastActiveAt;
    final daysAgo = calendarDaysBetween(last, now);
    return switch (daysAgo) {
      <= 0 => 'Last chatted today',
      1 => 'Last chatted yesterday',
      <= 7 => 'Last chatted $daysAgo days ago',
      _ when last.year == now.year =>
        'Last chatted on ${monthDayOrdinal(last)}',
      _ => 'Last chatted on ${monthDayOrdinal(last)}, ${last.year}',
    };
  }

  /// When the chat will be deleted, for example "Deleting in 11 days".
  static String _describe(DateTime expiresAt, DateTime now) {
    final daysLeft = calendarDaysBetween(now, expiresAt);
    return switch (daysLeft) {
      <= 0 => 'Deleting today',
      1 => 'Deleting tomorrow',
      _ => 'Deleting in $daysLeft days',
    };
  }
}

/// A group of chats in a card that can be collapsed to just its heading,
/// like the rooms on the My Home tab. The heading also shows how many chats
/// are in the group.
class _ChatGroupCard extends StatefulWidget {
  const _ChatGroupCard({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  State<_ChatGroupCard> createState() => _ChatGroupCardState();
}

class _ChatGroupCardState extends State<_ChatGroupCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.children.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        // The card already draws the outline, so the tile shouldn't add its
        // own borders when expanded.
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(widget.title, style: theme.textTheme.titleMedium),
        // Replacing the trailing arrow means turning it ourselves.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              // Read aloud with the word, since a bare number is unclear.
              semanticsLabel: '$count ${count == 1 ? 'chat' : 'chats'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more),
            ),
          ],
        ),
        children: [const Divider(height: 1), ...widget.children],
      ),
    );
  }
}

/// The row of buttons at the bottom of the history while chats are
/// selected, each with its label under its icon.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.allSelected,
    required this.allPinned,
    required this.canRename,
    required this.onSelectAll,
    required this.onPin,
    required this.onRename,
    required this.onDelete,
  });

  /// Whether every chat is selected, in which case the first button
  /// deselects them instead.
  final bool allSelected;

  /// Whether every selected chat is pinned, in which case the pin button
  /// unpins them instead.
  final bool allPinned;

  /// Whether just one chat is selected, which is the only time it can be
  /// renamed. Otherwise the rename button is greyed out, so the buttons
  /// don't move around as chats are selected.
  final bool canRename;

  final VoidCallback onSelectAll;
  final VoidCallback onPin;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _BarButton(
            icon: allSelected ? Icons.deselect : Icons.select_all,
            label: allSelected ? 'Deselect all' : 'Select all',
            onPressed: onSelectAll,
          ),
          _BarButton(
            icon: allPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: allPinned ? 'Unpin' : 'Pin',
            onPressed: onPin,
          ),
          _BarButton(
            icon: Icons.edit_outlined,
            label: 'Rename',
            onPressed: canRename ? onRename : null,
          ),
          _BarButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            onPressed: onDelete,
            color: Theme.of(context).colorScheme.error,
          ),
        ],
      ),
    );
  }
}

/// One of the evenly spaced buttons in [_SelectionBar]: a large icon with
/// its label underneath. Greyed out when [onPressed] is `null`.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: onPressed == null ? null : color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The text field for renaming a chat in its row. [defaultName] is shown as
/// the hint, since saving it empty goes back to that name.
class _ChatNameField extends StatelessWidget {
  const _ChatNameField({
    required this.controller,
    required this.defaultName,
    required this.onSubmitted,
  });

  static const maxLength = 60;

  final TextEditingController controller;
  final String defaultName;
  final VoidCallback onSubmitted;

  /// Puts [name] in [controller], selected so typing replaces it.
  static void startEditing(TextEditingController controller, String name) {
    controller.value = TextEditingValue(
      text: name,
      selection: TextSelection(baseOffset: 0, extentOffset: name.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
      decoration: InputDecoration(
        hintText: defaultName,
        isDense: true,
        border: const UnderlineInputBorder(),
      ),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

/// Asks the user to confirm deleting the chats with these [titles]. Returns
/// whether they did.
Future<bool> _confirmDeleteChats(
  BuildContext context,
  List<String> titles,
) async {
  final one = titles.length == 1;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(one ? 'Delete this chat?' : 'Delete ${titles.length} chats?'),
      content: Text(
        one
            ? '"${titles.single}" will be permanently deleted.'
            : 'They will be permanently deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
