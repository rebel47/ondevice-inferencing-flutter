import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/inference_service.dart';
import '../widgets/chat_bubble.dart';

class ChatScreen extends StatefulWidget {
  final InferenceService inferenceService;

  const ChatScreen({super.key, required this.inferenceService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String _model = 'gemma';

  void _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(text, MessageRole.user));
      _controller.clear();
      _loading = true;
    });

    try {
      // Prepare model (download/copy if needed)
      await widget.inferenceService.prepareModel(_model);

      // Stream reply tokens and append to UI as they arrive
      final tokenStream = widget.inferenceService.generateReplyStream(text, _model);
      _messages.add(ChatMessage('', MessageRole.assistant));
      await for (final token in tokenStream) {
        setState(() {
          final last = _messages.last;
          _messages[_messages.length - 1] = ChatMessage(last.text + token, last.role);
        });
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage('Error: $e', MessageRole.assistant));
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SLM Chat'),
        actions: [
          DropdownButton<String>(
            value: _model,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'gemma', child: Text('Gemma')),
              DropdownMenuItem(value: 'phi', child: Text('Phi')),
              DropdownMenuItem(value: 'smollm', child: Text('SmolLM')),
            ],
            onChanged: (v) => setState(() => _model = v ?? 'gemma'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              shrinkWrap: true,
              reverse: true,
              padding: const EdgeInsets.only(top: 12),
              itemBuilder: (c, i) {
                // show newest at bottom, but reversed list view - show from end
                final message = _messages.reversed.toList()[i];
                return ChatBubble(message: message);
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: 'Type a message...'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _send,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
