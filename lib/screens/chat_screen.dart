import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/inference_service.dart';
import '../services/llama_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
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
  List<String> _availableModels = [];

  @override
  void initState() {
    super.initState();
    _scanLocalModels();
  }

  Future<void> _scanLocalModels() async {
    final doc = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(doc.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    final files = modelsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gguf'))
        .toList();
    setState(() {
      _availableModels = [for (final f in files) p.basenameWithoutExtension(f.path)];
      // keep the currently selected model if present
      if (!_availableModels.contains(_model)) {
        _model = _availableModels.isNotEmpty ? _availableModels.first : _model;
      }
    });
  }

  Future<void> _pickModelFromDevice() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['gguf']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path!;
    setState(() => _model = path);
    // Optionally copy into documents models dir for later use
    final doc = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(doc.path, 'models'));
    if (!await modelsDir.exists()) await modelsDir.create(recursive: true);
    final dest = File(p.join(modelsDir.path, p.basename(path)));
    if (!await dest.exists()) {
      await File(path).copy(dest.path);
      await _scanLocalModels();
    }
  }

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
          PopupMenuButton<String>(
            itemBuilder: (ctx) => [
              ..._availableModels.map((m) => PopupMenuItem(value: m, child: Text(m))),
              const PopupMenuItem(value: '__pick__', child: Text('Choose model from device')),
            ],
            onSelected: (v) async {
              if (v == '__pick__') {
                await _pickModelFromDevice();
              } else {
                setState(() => _model = v);
              }
            },
            child: Row(children: [Text(_model), const Icon(Icons.arrow_drop_down)]),
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
