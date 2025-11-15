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
    // Request storage permission with detailed dialog
    if (!await _requestStoragePermission()) {
      return;
    }

    try {
      final XTypeGroup ggufGroup = const XTypeGroup(
        label: 'GGUF Model Files',
        extensions: ['gguf'],
      );
      final XFile? xfile = await openFile(
        acceptedTypeGroups: <XTypeGroup>[ggufGroup],
      );
      
      if (xfile == null) return;
      
      final path = xfile.path;
      final selectedFile = File(path);
      
      // Check if file exists and is readable
      if (!await selectedFile.exists()) {
        _showErrorDialog('File not found', 'The selected file could not be accessed.');
        return;
      }

      // Get file size and warn if large
      final size = await selectedFile.length();
      const warnSize = 500 * 1024 * 1024; // 500MB
      
      if (size >= warnSize) {
        final confirmed = await _showLargeFileDialog(size);
        if (!confirmed) return;
      }

      // Show loading dialog while copying
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
                  Text('Copying model file...'),
                ],
              ),
            ),
          ),
        ),
      );

      try {
        // Copy to app's documents directory
        final doc = await getApplicationDocumentsDirectory();
        final modelsDir = Directory(p.join(doc.path, 'models'));
        if (!await modelsDir.exists()) await modelsDir.create(recursive: true);
        
        final fileName = p.basename(path);
        final dest = File(p.join(modelsDir.path, fileName));
        
        if (!await dest.exists()) {
          await selectedFile.copy(dest.path);
        }

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
                  child: Text('Model "$fileName" loaded successfully'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pop(); // Close loading dialog
        _showErrorDialog('Copy failed', 'Failed to copy model file: $e');
      }
    } catch (e) {
      _showErrorDialog('Error', 'Failed to select file: $e');
    }
  }

  Future<bool> _requestStoragePermission() async {
    // For Android 13+ (API 33+), we don't need storage permission for file picker
    // For older versions, we need storage permission
    final status = await Permission.storage.status;
    
    if (status.isGranted) return true;
    
    if (status.isPermanentlyDenied) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
          title: const Text('Storage Permission Required'),
          content: const Text(
            'This app needs storage permission to access model files from your device. '
            'The permission has been permanently denied. Please enable it in app settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ) ?? false;
      
      if (openSettings) {
        await openAppSettings();
      }
      return false;
    }
    
    if (status.isDenied) {
      // Show explanation before requesting
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.folder_open, size: 48, color: Colors.blue),
          title: const Text('Storage Access Needed'),
          content: const Text(
            'To select GGUF model files from your device, this app needs permission to access your storage.\n\n'
            'Your privacy is protected - we only read the specific model files you choose.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      ) ?? false;
      
      if (!shouldRequest) return false;
      
      final result = await Permission.storage.request();
      
      if (result.isGranted) {
        return true;
      } else if (result.isPermanentlyDenied) {
        _showErrorDialog(
          'Permission Denied',
          'Storage permission is required to select model files. Please enable it in app settings.',
        );
      }
      return result.isGranted;
    }
    
    return false;
  }

  Future<bool> _showLargeFileDialog(int size) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
        title: const Text('Large Model File'),
        content: Text(
          'The selected model is ${(size / (1024 * 1024)).toStringAsFixed(1)} MB.\n\n'
          'This may take time to copy and can use significant memory. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.error_outline, size: 48, color: Colors.red),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
                value: '__pick__',
                child: Row(
                  children: [
                    Icon(Icons.upload_file, size: 18),
                    SizedBox(width: 8),
                    Text('Import from device', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            onSelected: (v) async {
              if (v == '__pick__') {
                await _pickModelFromDevice();
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
                title: const Text('About Models & Permissions'),
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
                        'Storage Permission',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'On Android versions below 13, storage permission is required to '
                        'import model files from your device. The app only accesses files you explicitly select.',
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
