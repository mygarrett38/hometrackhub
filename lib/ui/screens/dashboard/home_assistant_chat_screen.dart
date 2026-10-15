import 'package:flutter/material.dart';

import '../../../services/home_assistant_client.dart';

/// Chat interface for questions about home maintenance and repair.
class HomeAssistantChatScreen extends StatefulWidget {
  const HomeAssistantChatScreen({super.key, required this.client});

  final HomeAssistantClient client;

  @override
  State<HomeAssistantChatScreen> createState() =>
      _HomeAssistantChatScreenState();
}

class _HomeAssistantChatScreenState extends State<HomeAssistantChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatEntry>[
    const _ChatEntry(
      role: 'assistant',
      text: 'Hi! Tell me what is happening with a home appliance or system. I can suggest basic next steps and let you know when a licensed professional may be needed.',
    ),
  ];
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestedQuestion]) async {
    final question = (suggestedQuestion ?? _input.text).trim();
    if (question.isEmpty || _sending || !widget.client.isConfigured) return;
    _input.clear();
    setState(() {
      _sending = true;
      _messages.add(_ChatEntry(role: 'user', text: question));
    });
    _scrollToBottom();

    try {
      final reply = await widget.client.ask([
        for (final entry in _messages)
          AssistantMessage(role: entry.role, content: entry.text),
      ]);
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatEntry(
            role: 'assistant',
            text: reply.answer,
            professionalReason: reply.recommendProfessional
                ? reply.professionalReason ?? 'This may need an in-person assessment by a licensed professional.'
                : null,
          ),
        );
      });
    } on AssistantConnectionException catch (error) {
      if (!mounted) return;
      setState(
        () => _messages.add(_ChatEntry(role: 'error', text: error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          const _ChatEntry(
            role: 'error',
            text: 'Something went wrong while contacting the assistant.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Home Assistant'),
        actions: [
          IconButton(
            tooltip: 'About this assistant',
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'HomeTrack Hub AI Home Assistant',
              children: const [
                Text(
                  'This assistant provides general maintenance information, '
                  'not a substitute for an on-site assessment. Follow product '
                  'safety instructions and contact a licensed professional '
                  'when a repair is unsafe or beyond basic maintenance.',
                ),
              ],
            ),
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.client.isConfigured)
            MaterialBanner(
              leading: Icon(Icons.cloud_off_outlined, color: colors.tertiary),
              content: const Text(
                'The secure AI service is not connected yet. Configure a '
                'server endpoint to start chatting.',
              ),
              actions: const [],
            ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                for (final entry in _messages) _MessageBubble(entry: entry),
                if (_sending)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                if (_messages.length == 1 && widget.client.isConfigured) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 8),
                    child: Text('Try asking'),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final question in const [
                        'Why is my heater making a weird noise?',
                        'How often should I clean my dryer vent?',
                        'When should I call a licensed electrician?',
                      ])
                        ActionChip(
                          label: Text(question),
                          onPressed: () => _send(question),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: widget.client.isConfigured && !_sending,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: widget.client.isConfigured
                            ? 'Ask about a home issue…'
                            : 'AI service connection required',
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send question',
                    onPressed: widget.client.isConfigured && !_sending
                        ? _send
                        : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatEntry {
  const _ChatEntry({
    required this.role,
    required this.text,
    this.professionalReason,
  });

  final String role;
  final String text;
  final String? professionalReason;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.entry});

  final _ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUser = entry.role == 'user';
    final isError = entry.role == 'error';
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background = isUser
        ? colors.primary
        : isError
        ? colors.errorContainer
        : colors.surfaceContainerHigh;
    final foreground = isUser
        ? colors.onPrimary
        : isError
        ? colors.onErrorContainer
        : colors.onSurface;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Card(
          color: background,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.text, style: TextStyle(color: foreground)),
                if (entry.professionalReason case final reason?) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.engineering_outlined,
                          color: colors.onErrorContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Licensed professional recommended: $reason',
                            style: TextStyle(color: colors.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
