import 'dart:async';

abstract class InferenceService {
  /// Generate a reply for [input] using the [model] name.
  Future<String> generateReply(String input, String model);

  /// Generate a reply streaming tokens as they become available. Each token
  /// should be emitted by the returned Stream so UI can append it.
  /// 
  /// [systemPrompt] - Optional system prompt to guide model behavior
  /// [conversationHistory] - List of previous turns: [{"user": "...", "assistant": "..."}]
  /// [userMessage] - Current user message
  /// [model] - Model identifier
  Stream<String> generateReplyStream(
    String userMessage,
    String model, {
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
  });

  /// Optional: prepare or download model resources on device. Default noop.
  Future<void> prepareModel(String model, {String? downloadUrl});

  /// List models available in the app's models directory. Default empty list.
  Future<List<String>> listLocalModels();
  
  /// Stop current generation (if supported)
  Future<void> stopGeneration();
  
  /// Clean up resources
  void dispose();
}

/// A very small stub used for local development/tests. Replace with real
/// on-device model adapter (platform channels / FFI / native gRPC).
class MockInferenceService implements InferenceService {
  @override
  Future<String> generateReply(String input, String model) async {
    // Simulate some computation latency
    await Future.delayed(const Duration(milliseconds: 700));
    // Return a deterministic answer depending on model for easier tests.
    switch (model) {
      case 'gemma':
        return 'Gemma reply to "$input"';
      case 'phi':
        return 'Phi replies: "$input"';
      case 'smollm':
        return 'SmolLM echo: "$input"';
      default:
        return 'Unknown model replies to "$input"';
    }
  }

  @override
  Stream<String> generateReplyStream(
    String userMessage,
    String model, {
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
  }) async* {
    // Keep tests deterministic: yield tokens synchronously.
    final reply = await generateReply(userMessage, model);
    for (final chunk in reply.split(' ')) {
      yield '$chunk ';
    }
  }

  @override
  Future<void> prepareModel(String model, {String? downloadUrl}) async {
    // No-op for mock
    return;
  }

  @override
  Future<List<String>> listLocalModels() async => [];
  
  @override
  Future<void> stopGeneration() async {
    // No-op for mock
  }
  
  @override
  void dispose() {
    // No-op for mock
  }
}
