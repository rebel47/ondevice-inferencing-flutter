import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'inference_service.dart';

/// A service that loads a GGUF model (from app assets or from a remote URL)
/// and streams generation tokens using llama_flutter_android plugin.
class LlamaService implements InferenceService {
  LlamaController? _llamaController;
  bool _loaded = false;
  String? _currentModelPath;
  StreamSubscription? _currentGeneration;

  /// Make sure [modelId] is available locally. If not, attempt to copy the
  /// model from assets (asset path is 'assets/models/<modelId>.gguf') or
  /// download from the provided [downloadUrl]. Returns the absolute file path
  /// to the GGUF file.
  Future<String> ensureModelAvailable(String modelIdOrPath, {String? downloadUrl}) async {
    final docDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(docDir.path, 'models'));
    if (!await modelsDir.exists()) await modelsDir.create(recursive: true);

    // If the provided string looks like a path to an existing local file, use it.
    if (modelIdOrPath.contains(Platform.pathSeparator) && await File(modelIdOrPath).exists()) {
      return modelIdOrPath;
    }

    final modelId = modelIdOrPath;
    final dest = p.join(modelsDir.path, '$modelId.gguf');
    final destFile = File(dest);
    if (await destFile.exists()) return dest;

    // Try assets first
  final assetPath = 'assets/models/$modelId.gguf';
    try {
      final bytes = await rootBundle.load(assetPath);
      await destFile.writeAsBytes(bytes.buffer.asUint8List());
      return dest;
    } catch (e) {
      // Not found in assets -> try a download URL
    }

    if (downloadUrl == null) {
      throw Exception('Model $modelId not found in assets and no download URL provided.');
    }

    final request = await http.Client().send(http.Request('GET', Uri.parse(downloadUrl)));
  final sink = destFile.openWrite();
    await for (final chunk in request.stream) {
  // Optionally track progress; omitted to keep implementation simple.
      sink.add(chunk);
      // Optionally, we could report progress using a stream or callback.
    }
    await sink.flush();
    await sink.close();

    if (!await destFile.exists()) throw Exception('Failed to download model.');
    return dest;
  }

  @override
  Future<void> prepareModel(String model, {String? downloadUrl}) async {
    // Map friendly model names to GGUF IDs
    final modelMap = <String, String>{
      'phi': 'phi-3-mini',
      'gemma': 'gemma',
      'smollm': 'smollm',
    };

    final id = modelMap[model] ?? model;
    await ensureModelAvailable(id, downloadUrl: downloadUrl);
  }

  @override
  Future<List<String>> listLocalModels() async {
    final doc = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(doc.path, 'models'));
    if (!await modelsDir.exists()) return [];
    final files = modelsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gguf'))
        .map((f) => p.basenameWithoutExtension(f.path))
        .toList();
    return files;
  }

  /// Load model and prepare for generation. If already loaded, this is a no-op.
  Future<bool> loadModel(String modelPath, {int threads = 4, int contextSize = 2048}) async {
    if (_loaded && _currentModelPath == modelPath) return true;

    // Cancel any ongoing generation
    await stopGeneration();

    // Dispose previous instance if exists
    if (_llamaController != null) {
      await _llamaController!.dispose();
      _llamaController = null;
    }

    try {
      _llamaController = LlamaController();
      
      await _llamaController!.loadModel(
        modelPath: modelPath,
        threads: threads,
        contextSize: contextSize,
      );
      
      _loaded = true;
      _currentModelPath = modelPath;
      return true;
    } catch (e) {
      print('Error loading model: $e');
      _loaded = false;
      return false;
    }
  }

  @override
  Future<String> generateReply(String input, String model) async {
    // Convenience - run a blocking generation. Ensure model loaded first.
    final modelPath = await ensureModelAvailable(model);
    await loadModel(modelPath);

    if (_llamaController == null) {
      throw Exception('Model not loaded');
    }

    final completer = Completer<String>();
    final buffer = StringBuffer();

    _currentGeneration = _llamaController!.generate(
      prompt: input,
      maxTokens: 512,
      temperature: 0.7,
    ).listen(
      (token) {
        buffer.write(token);
      },
      onDone: () {
        _currentGeneration = null;
        completer.complete(buffer.toString());
      },
      onError: (error) {
        _currentGeneration = null;
        completer.completeError(error);
      },
    );

    return await completer.future;
  }

  @override
  Stream<String> generateReplyStream(String input, String model) async* {
    final modelPath = await ensureModelAvailable(model);
    await loadModel(modelPath);

    if (_llamaController == null) {
      throw Exception('Model not loaded');
    }

    // Cancel any previous generation
    await stopGeneration();

    // Create a stream controller to handle the generation
    final controller = StreamController<String>();
    
    _currentGeneration = _llamaController!.generate(
      prompt: input,
      maxTokens: 512,
      temperature: 0.7,
    ).listen(
      (token) => controller.add(token),
      onDone: () {
        _currentGeneration = null;
        controller.close();
      },
      onError: (error) {
        _currentGeneration = null;
        controller.addError(error);
      },
    );

    yield* controller.stream;
  }

  /// Stop any ongoing generation
  Future<void> stopGeneration() async {
    if (_currentGeneration != null) {
      await _currentGeneration!.cancel();
      _currentGeneration = null;
    }
    if (_llamaController != null) {
      await _llamaController!.stop();
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    await stopGeneration();
    
    if (_llamaController != null) {
      await _llamaController!.dispose();
      _llamaController = null;
    }
    _loaded = false;
    _currentModelPath = null;
  }
}
