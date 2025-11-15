import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'inference_service.dart';

/// A service that loads a GGUF model (from app assets or from a remote URL)
/// and streams generation tokens using llama_cpp_dart plugin.
class LlamaService implements InferenceService {
  LlamaParent? _llamaParent;
  bool _loaded = false;
  String? _currentModelPath;

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
  Future<bool> loadModel(String modelPath, {int nThreads = 4, bool useGpu = true, int nGpuLayers = 0}) async {
    if (_loaded && _currentModelPath == modelPath) return true;

    // Dispose previous instance if exists
    if (_llamaParent != null) {
      await _llamaParent!.dispose();
      _llamaParent = null;
    }

    try {
      final loadCommand = LlamaLoad(
        path: modelPath,
        modelParams: ModelParams(),
        contextParams: ContextParams(),
        samplingParams: SamplerParams(),
        format: ChatMLFormat(),
      );

      _llamaParent = LlamaParent(loadCommand);
      await _llamaParent!.init();
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

    if (_llamaParent == null) {
      throw Exception('Model not loaded');
    }

    final completer = Completer<String>();
    final buffer = StringBuffer();

    final subscription = _llamaParent!.stream.listen(
      (response) {
        buffer.write(response);
      },
      onDone: () {
        completer.complete(buffer.toString());
      },
      onError: (error) {
        completer.completeError(error);
      },
    );

    _llamaParent!.sendPrompt(input);

    final result = await completer.future;
    await subscription.cancel();
    return result;
  }

  @override
  Stream<String> generateReplyStream(String input, String model) async* {
    final modelPath = await ensureModelAvailable(model);
    await loadModel(modelPath);

    if (_llamaParent == null) {
      throw Exception('Model not loaded');
    }

    _llamaParent!.sendPrompt(input);
    
    await for (final token in _llamaParent!.stream) {
      yield token;
    }
  }

  /// Clean up resources
  Future<void> dispose() async {
    if (_llamaParent != null) {
      await _llamaParent!.dispose();
      _llamaParent = null;
    }
    _loaded = false;
    _currentModelPath = null;
  }
}
