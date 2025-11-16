import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/inference_service.dart';
// Note: LlamaService is injected by main.dart; no direct import required here.
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../widgets/chat_bubble.dart';
import '../models/chat_session.dart';

class ChatScreen extends StatefulWidget {
  final InferenceService inferenceService;

  const ChatScreen({super.key, required this.inferenceService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final Map<String, ChatSession> _sessions = {};
  String? _activeSessionId;
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  bool _cancelRequested = false;
  String _model = 'gemma';
  List<String> _availableModels = [];
  static const _prefsLastModelKey = 'last_model';
  static const _prefsSessionsKey = 'chat_sessions_v1';

  @override
  void initState() {
    super.initState();
    _scanLocalModels();
    _loadLastSelectedModel();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsSessionsKey);
    if (jsonStr == null) {
      // create a default session
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final defaultSession = ChatSession(
        id: id,
        name: 'Default',
        systemPrompt: 'You are a helpful, concise assistant. Be factual and admit when you do not know the answer.',
      );
      _sessions[id] = defaultSession;
      _activeSessionId = id;
      _messages.clear();
      setState(() {});
      await _saveSessions();
      return;
    }

    try {
      final decoded = jsonDecode(jsonStr) as List<dynamic>;
      for (final item in decoded) {
        final s = ChatSession.fromJson(Map<String, dynamic>.from(item));
        _sessions[s.id] = s;
      }
      // Pick first as active if none
      _activeSessionId ??= _sessions.keys.isNotEmpty ? _sessions.keys.first : null;
      _messages.clear();
      if (_activeSessionId != null) {
        _messages.addAll(_sessions[_activeSessionId]!.messages);
      }
      setState(() {});
    } catch (e) {
      debugPrint('Error loading sessions: $e');
    }
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _sessions.values.map((s) => s.toJson()).toList();
    await prefs.setString(_prefsSessionsKey, jsonEncode(list));
  }

  Future<void> _createNewSession() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final session = ChatSession(
      id: id,
      name: 'Session ${_sessions.length + 1}',
      systemPrompt: 'You are a helpful, concise assistant. Be factual and admit when you do not know the answer.',
    );
    _sessions[id] = session;
    _activeSessionId = id;
    _messages.clear();
    await _saveSessions();
    setState(() {});
  }

  Future<void> _switchSession(String id) async {
    if (!_sessions.containsKey(id)) return;
    _activeSessionId = id;
    _messages.clear();
    _messages.addAll(_sessions[id]!.messages);
    await _saveSessions();
    setState(() {});
  }

  Future<void> _editSystemPromptDialog() async {
    final session = _activeSessionId == null ? null : _sessions[_activeSessionId!];
    if (session == null) return;
    final ctrl = TextEditingController(text: session.systemPrompt);
    final updated = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit System Prompt'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'System prompt for this session'),
        ),
        actions: [
          // Sessions menu
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Sessions',
            onPressed: () async {
              await showModalBottomSheet<void>(
                context: context,
                builder: (c) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: const Text('New Session'),
                        leading: const Icon(Icons.add),
                        onTap: () async {
                          Navigator.pop(c);
                          await _createNewSession();
                        },
                      ),
                      const Divider(),
                      if (_sessions.isEmpty)
                        const ListTile(title: Text('No sessions'))
                      else
                        ..._sessions.values.map((s) => ListTile(
                              title: Text(s.name),
                              subtitle: s.systemPrompt.isNotEmpty ? Text(s.systemPrompt, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                              leading: _activeSessionId == s.id ? const Icon(Icons.check) : null,
                              onTap: () async {
                                Navigator.pop(c);
                                await _switchSession(s.id);
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  Navigator.pop(c);
                                  if (v == 'edit') {
                                    _activeSessionId = s.id;
                                    await _editSystemPromptDialog();
                                  } else if (v == 'delete') {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Delete Session'),
                                        content: Text('Delete session "${s.name}"?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) await _deleteSession(s.id);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'edit', child: Text('Edit system prompt')),
                                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              ),
                            ))
                    ],
                  ),
                ),
              );
            },
          ),
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (updated != null) {
      session.systemPrompt = updated;
      await _saveSessions();
      setState(() {});
    }
  }

  Future<void> _deleteSession(String id) async {
    if (!_sessions.containsKey(id)) return;
    _sessions.remove(id);
    if (_activeSessionId == id) {
      _activeSessionId = _sessions.keys.isNotEmpty ? _sessions.keys.first : null;
      _messages.clear();
      if (_activeSessionId != null) _messages.addAll(_sessions[_activeSessionId]!.messages);
    }
    await _saveSessions();
    setState(() {});
  }

  Future<void> _showSessionsMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.chat, size: 24),
                    const SizedBox(width: 12),
                    const Text(
                      'Chat Sessions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      tooltip: 'New Session',
                      onPressed: () async {
                        Navigator.pop(c);
                        await _createNewSession();
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Sessions List
              Expanded(
                child: _sessions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No sessions yet',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                Navigator.pop(c);
                                await _createNewSession();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Create First Session'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions.values.toList()[index];
                          final isActive = _activeSessionId == session.id;
                          final messageCount = session.messages.length;
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            elevation: isActive ? 4 : 1,
                            color: isActive
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: isActive
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey[400],
                                child: Icon(
                                  isActive ? Icons.chat : Icons.chat_bubble_outline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                session.name,
                                style: TextStyle(
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (session.systemPrompt.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        session.systemPrompt,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '$messageCount message${messageCount == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () async {
                                Navigator.pop(c);
                                await _switchSession(session.id);
                              },
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    Navigator.pop(c);
                                    _activeSessionId = session.id;
                                    await _editSystemPromptDialog();
                                  } else if (v == 'rename') {
                                    final newName = await showDialog<String>(
                                      context: context,
                                      builder: (_) {
                                        final controller = TextEditingController(text: session.name);
                                        return AlertDialog(
                                          title: const Text('Rename Session'),
                                          content: TextField(
                                            controller: controller,
                                            decoration: const InputDecoration(
                                              labelText: 'Session name',
                                            ),
                                            autofocus: true,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(context, controller.text.trim()),
                                              child: const Text('Save'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    if (newName != null && newName.isNotEmpty) {
                                      session.name = newName;
                                      await _saveSessions();
                                      setState(() {});
                                    }
                                  } else if (v == 'delete') {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Delete Session'),
                                        content: Text('Delete session "${session.name}"? This cannot be undone.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(context, true),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red,
                                            ),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await _deleteSession(session.id);
                                      if (_sessions.isEmpty) {
                                        Navigator.pop(c);
                                      }
                                    }
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, size: 18),
                                        SizedBox(width: 12),
                                        Text('Rename'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.psychology, size: 18),
                                        SizedBox(width: 12),
                                        Text('Edit system prompt'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 18, color: Colors.red),
                                        SizedBox(width: 12),
                                        Text('Delete', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadLastSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsLastModelKey);
    if (last != null && last.isNotEmpty) {
      setState(() => _model = last);
    }
  }

  Future<void> _scanLocalModels() async {
    final Set<String> foundModels = {};
    
    // 1. Scan app's internal documents directory
    try {
      final doc = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(doc.path, 'models'));
      if (await modelsDir.exists()) {
        final files = modelsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gguf')).toList();
        for (final f in files) {
          foundModels.add(p.basenameWithoutExtension(f.path));
        }
      }
    } catch (e) {
      debugPrint('Error scanning documents directory: $e');
    }

    // 2. Scan app's external storage directory (Android/data/...)
    try {
      final externalDir = await getApplicationDocumentsDirectory();
      // On Android, getExternalStorageDirectory() gives us Android/data/package/files
      final externalModelsDir = Directory(p.join(externalDir.path, 'models'));
      if (await externalModelsDir.exists()) {
        final files = externalModelsDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gguf')).toList();
        for (final f in files) {
          foundModels.add(p.basenameWithoutExtension(f.path));
        }
      }
    } catch (e) {
      debugPrint('Error scanning external directory: $e');
    }

    // 3. Scan common Download locations
    try {
      // Try /storage/emulated/0/Download
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final files = downloadDir.listSync().whereType<File>().where((f) => f.path.endsWith('.gguf')).toList();
        for (final f in files) {
          foundModels.add(p.basenameWithoutExtension(f.path));
        }
      }
    } catch (e) {
      debugPrint('Error scanning Download directory: $e');
    }

    // 4. Ask service for any models it knows about
    try {
      final fromService = await widget.inferenceService.listLocalModels();
      foundModels.addAll(fromService);
    } catch (e) {
      debugPrint('Error getting models from service: $e');
    }

    setState(() {
      _availableModels = foundModels.toList()..sort();
      // Keep the currently selected model if present
      if (!_availableModels.contains(_model) && _availableModels.isNotEmpty) {
        _model = _availableModels.first;
      }
    });
  }

  /// Memory-safe file import using file_picker.
  /// This only gets the file PATH, not the file contents, so it works with files of ANY size.
  Future<void> _importModelFromDevice() async {
    try {
      debugPrint('Opening file picker...');
      
      // CRITICAL: withData: false means we only get the path, NOT the bytes.
      // This is why it won't crash with large files.
      // Using FileType.any because .gguf is not a recognized MIME type on Android
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Allow any file type
        withData: false, // KEY: Do not load file into memory!
      );

      if (result == null || result.files.single.path == null) {
        debugPrint('File selection canceled');
        return; // User cancelled
      }

      // Get file info
      final String sourcePath = result.files.single.path!;
      final String fileName = result.files.single.name;
      final int fileSize = result.files.single.size;

      // Validate it's a .gguf file
      if (!fileName.toLowerCase().endsWith('.gguf')) {
        debugPrint('Invalid file type: $fileName');
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.error_outline, size: 48, color: Colors.orange),
            title: const Text('Invalid File Type'),
            content: Text(
              'Please select a .gguf model file.\n\n'
              'Selected: $fileName',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // SUCCESS: Valid .gguf file selected, and we only have the path (not file bytes in memory)

      debugPrint('File selected: $fileName ($fileSize bytes)');
      debugPrint('Path: $sourcePath');

      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Copying $fileName...'),
                  const SizedBox(height: 8),
                  Text(
                    'Size: ${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      try {
        // Get destination directory
        final doc = await getApplicationDocumentsDirectory();
        final modelsDir = Directory(p.join(doc.path, 'models'));
        if (!await modelsDir.exists()) {
          await modelsDir.create(recursive: true);
        }

        final destPath = p.join(modelsDir.path, fileName);
        final destFile = File(destPath);

        // Check if file already exists
        if (await destFile.exists()) {
          if (!mounted) return;
          Navigator.of(context).pop(); // Close loading dialog

          final overwrite = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              icon: const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
              title: const Text('File Already Exists'),
              content: Text('A model named "$fileName" already exists. Overwrite?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Overwrite'),
                ),
              ],
            ),
          );

          if (overwrite != true) return;

          // Show loading dialog again
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Copying file...'),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // MEMORY-SAFE COPY: Stream the file in chunks
        // This works for ANY file size without loading it all into memory
        final sourceFile = File(sourcePath);
        final inputStream = sourceFile.openRead();
        final outputSink = destFile.openWrite();

        try {
          await for (final chunk in inputStream) {
            outputSink.add(chunk);
          }
          await outputSink.flush();
        } finally {
          await outputSink.close();
        }

        debugPrint('File copied successfully to: $destPath');

        // Update model selection
        setState(() => _model = p.basenameWithoutExtension(fileName));

        // Save preference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsLastModelKey, _model);

        // Refresh model list
        await _scanLocalModels();

        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Model "$fileName" imported successfully!'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        debugPrint('Error copying file: $e');
        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog

        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.error_outline, size: 48, color: Colors.red),
            title: const Text('Import Failed'),
            content: Text('Failed to copy model file: $e'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error selecting file: $e');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.error_outline, size: 48, color: Colors.red),
          title: const Text('Selection Failed'),
          content: Text('Failed to open file picker: $e'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(text, MessageRole.user));
      _controller.clear();
      _loading = true;
    });

    // Persist user message in active session
    if (_activeSessionId != null && _sessions.containsKey(_activeSessionId)) {
      final sess = _sessions[_activeSessionId!]!;
      sess.messages.add(ChatMessage(text, MessageRole.user));
      await _saveSessions();
    }

    try {
      // Prepare model (download/copy if needed)
      await widget.inferenceService.prepareModel(_model);

      // Prepare prompt with system prompt (if any)
      String promptToSend = text;
      if (_activeSessionId != null && _sessions.containsKey(_activeSessionId)) {
        final sess = _sessions[_activeSessionId!]!;
        if (sess.systemPrompt.trim().isNotEmpty) {
          promptToSend = '${sess.systemPrompt}\n\n$text';
        }
      }

      // Stream reply tokens and append to UI as they arrive
      final tokenStream = widget.inferenceService.generateReplyStream(promptToSend, _model);
      _messages.add(ChatMessage('', MessageRole.assistant));

      // If we have an active session, create placeholder assistant message so we can stream into it
      ChatSession? sess;
      if (_activeSessionId != null && _sessions.containsKey(_activeSessionId)) {
        sess = _sessions[_activeSessionId!]!;
        sess.messages.add(ChatMessage('', MessageRole.assistant));
        await _saveSessions();
      }

      await for (final token in tokenStream) {
        // If dispose() requested cancellation, stop consuming tokens.
        if (_cancelRequested) break;

        if (mounted) {
          setState(() {
            final last = _messages.last;
            _messages[_messages.length - 1] = ChatMessage(last.text + token, last.role);
          });
        } else {
          // If not mounted, just update the in-memory list for persistence.
          if (_messages.isNotEmpty) {
            final last = _messages.last;
            _messages[_messages.length - 1] = ChatMessage(last.text + token, last.role);
          }
        }

        if (sess != null) {
          final lastSess = sess.messages.last;
          sess.messages[sess.messages.length - 1] = ChatMessage(lastSess.text + token, lastSess.role);
        }
      }

      if (sess != null) {
        await _saveSessions();
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage('Error: $e', MessageRole.assistant));
          _loading = false;
        });
      } else {
        _messages.add(ChatMessage('Error: $e', MessageRole.assistant));
      }
    }
  }

  @override
  void dispose() {
    _cancelRequested = true;
    // Try to stop any ongoing generation on the service if it supports it.
    try {
      (widget.inferenceService as dynamic).stopGeneration();
    } catch (_) {}
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _activeSessionId != null && _sessions.containsKey(_activeSessionId)
                  ? _sessions[_activeSessionId]!.name
                  : 'AI Chat',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              'Model: $_model',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        elevation: 0,
        actions: [
          // Model Selector
          PopupMenuButton<String>(
            tooltip: 'Select Model',
            icon: const Icon(Icons.model_training),
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                enabled: false,
                child: Row(
                  children: [
                    Icon(Icons.folder, size: 18),
                    SizedBox(width: 8),
                    Text('Available Models', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              if (_availableModels.isEmpty)
                const PopupMenuItem(
                  enabled: false,
                  child: Text('No models found', style: TextStyle(fontStyle: FontStyle.italic)),
                )
              else
                ..._availableModels.map((m) => PopupMenuItem(
                  value: m,
                  child: Row(
                    children: [
                      Icon(
                        _model == m ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                        color: _model == m ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m)),
                    ],
                  ),
                )),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: '__import__',
                child: Row(
                  children: [
                    Icon(Icons.upload_file, size: 18),
                    SizedBox(width: 8),
                    Text('Import from device', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '__refresh__',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 8),
                    Text('Refresh model list', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            onSelected: (v) async {
              if (v == '__import__') {
                await _importModelFromDevice();
              } else if (v == '__refresh__') {
                await _scanLocalModels();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Found ${_availableModels.length} model(s)'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else {
                setState(() => _model = v);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_prefsLastModelKey, _model);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Switched to model: $v'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          // Sessions Button
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Chat Sessions',
            onPressed: () => _showSessionsMenu(),
          ),
          // Info Button
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Information',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                icon: const Icon(Icons.psychology, size: 48),
                title: const Text('About Models'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Model Files',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This app uses GGUF format models for on-device AI inference. '
                        'Models can be 100MB to several GB in size.',
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'How to Add Models',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Option 1: Import from Device\n'
                        '• Tap "Import from device" in the model menu\n'
                        '• Select any .gguf file (works with files of ANY size!)\n'
                        '• File will be copied to app storage\n\n'
                        'Option 2: Manual Placement\n'
                        '• Download folder\n'
                        '• Android/data/com.example.ondevice_slm_app/files/models/\n\n'
                        'Then tap "Refresh model list" to scan.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.security, size: 20, color: Colors.blue),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'All processing happens on your device. No data is sent to servers.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Got it'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Start a conversation',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Type a message below to begin',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _messages.length,
                    shrinkWrap: true,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemBuilder: (c, i) {
                      final message = _messages.reversed.toList()[i];
                      return ChatBubble(message: message);
                    },
                  ),
          ),
          
          // Loading Indicator
          if (_loading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generating response...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          
          const Divider(height: 1),
          
          // Input Area
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            suffixIcon: _controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      _controller.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: _loading || _controller.text.trim().isEmpty
                            ? Colors.grey[300]
                            : Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _loading || _controller.text.trim().isEmpty
                            ? null
                            : _send,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
