import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/inference_service.dart';
// Note: LlamaService is injected by main.dart; no direct import required here.
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
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
      print('Error scanning documents directory: $e');
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
      print('Error scanning external directory: $e');
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
      print('Error scanning Download directory: $e');
    }

    // 4. Ask service for any models it knows about
    try {
      final fromService = await widget.inferenceService.listLocalModels();
      foundModels.addAll(fromService);
    } catch (e) {
      print('Error getting models from service: $e');
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
      print('Opening file picker...');
      
      // CRITICAL: withData: false means we only get the path, NOT the bytes.
      // This is why it won't crash with large files.
      // Using FileType.any because .gguf is not a recognized MIME type on Android
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Allow any file type
        withData: false, // KEY: Do not load file into memory!
      );

      if (result == null || result.files.single.path == null) {
        print('File selection canceled');
        return; // User cancelled
      }

      // Get file info
      final String sourcePath = result.files.single.path!;
      final String fileName = result.files.single.name;
      final int fileSize = result.files.single.size;

      // Validate it's a .gguf file
      if (!fileName.toLowerCase().endsWith('.gguf')) {
        print('Invalid file type: $fileName');
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

      print('File selected: $fileName ($fileSize bytes)');
      print('Path: $sourcePath');

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

        print('File copied successfully to: $destPath');

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
        print('Error copying file: $e');
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
      print('Error selecting file: $e');
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Chat', style: TextStyle(fontSize: 18)),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Switched to model: $v'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
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
                          color: Colors.blue.withOpacity(0.1),
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
                  color: Colors.black.withOpacity(0.05),
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
