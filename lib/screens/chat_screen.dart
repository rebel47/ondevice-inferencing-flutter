import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/inference_service.dart';
// Note: LlamaService is injected by main.dart; no direct import required here.
import 'package:file_selector/file_selector.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const _prefsLastModelKey = 'last_model';

  @override
  void initState() {
    super.initState();
    _scanLocalModels();
    _loadLastSelectedModel();
  }

  Future<void> _loadLastSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsLastModelKey);
    if (last != null && last.isNotEmpty) {
      setState(() => _model = last);
    }
  }

  Future<void> _scanLocalModels() async {
    // Ask service for local models first (plugin may manage models outside app dir)
    final fromService = await widget.inferenceService.listLocalModels();

    final doc = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(doc.path, 'models'));
    if (!await modelsDir.exists()) await modelsDir.create(recursive: true);

    final files = modelsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gguf')).toList();
    setState(() {
      _availableModels = [for (final f in files) p.basenameWithoutExtension(f.path)];
      // Add service-discovered models
      for (final m in fromService) {
        if (!_availableModels.contains(m)) _availableModels.add(m);
      }
      // keep the currently selected model if present
      if (!_availableModels.contains(_model)) {
        _model = _availableModels.isNotEmpty ? _availableModels.first : _model;
      }
    });
  }

  Future<void> _pickModelFromDevice() async {
    // Check storage permission for older Android versions
    if (!await _ensureStoragePermission()) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Permission required'),
          content: const Text('The app needs storage permission to pick models from your device. Please grant permission in the app settings.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    final XTypeGroup ggufGroup = const XTypeGroup(
      label: 'GGUF',
      extensions: ['gguf'],
    );
  final XFile? xfile = await openFile(acceptedTypeGroups: <XTypeGroup>[ggufGroup]);
  if (xfile == null) return;
  final path = xfile.path;
    // Warn if model is large
  final selectedFile = File(path);
  final size = await selectedFile.length();
    const warnSize = 500 * 1024 * 1024; // 500MB
    if (size >= warnSize) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Large model file'),
              content: Text('The selected model is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB. This may take a long time to download or copy and can cause high memory usage. Continue?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    setState(() => _model = path);
  // persist last model selection
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsLastModelKey, _model);
    // Optionally copy into documents models dir for later use
    final doc = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(doc.path, 'models'));
    if (!await modelsDir.exists()) await modelsDir.create(recursive: true);
    final dest = File(p.join(modelsDir.path, p.basename(path)));
    if (!await dest.exists()) {
      await selectedFile.copy(dest.path);
      await _scanLocalModels();
    }
  }

  Future<bool> _ensureStoragePermission() async {
    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.storage.request();
    return result.isGranted;
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
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('File & Permissions'),
                content: const Text('To pick a model from your device the app needs storage access (Android pre-13). Models can be large (100s of MB). Choose a GGUF file and be patient while it copies/downloads. If permission is denied, grant it in app settings.'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
              ),
            ),
          ),
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
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_prefsLastModelKey, _model);
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
