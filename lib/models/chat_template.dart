// chat_template.dart
// Production-ready Flutter on-device chat template manager
// Features:
// - Universal chat templates for LLaMA, Mistral, Qwen, Phi, Gemma, Alpaca
// - Auto-detection from filename or GGUF metadata
// - Memory manager with summarization
// - Prompt builder with token trimming
// - Coherence checks
// - Model quality detection

import 'dart:convert';

/// ---------------------------
/// Chat Model Type & Templates
/// ---------------------------

enum ChatModelType { llama, mistral, qwen, phi, gemma, alpacaFallback }

class ChatTemplate {
  final ChatModelType type;
  ChatTemplate(this.type);

  String buildPrompt({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
  }) {
    switch (type) {
      case ChatModelType.llama:
        return _llama(systemPrompt, history, userMessage);
      case ChatModelType.mistral:
        return _chatML(systemPrompt, history, userMessage);
      case ChatModelType.qwen:
        return _chatML(systemPrompt, history, userMessage);
      case ChatModelType.phi:
        return _phi(systemPrompt, history, userMessage);
      case ChatModelType.gemma:
        return _gemma(systemPrompt, history, userMessage);
      default:
        return _alpaca(systemPrompt, history, userMessage);
    }
  }

  String _llama(String systemPrompt, List<Map<String, String>> history, String userMsg) {
    final buffer = StringBuffer();
    buffer.writeln("<|begin_of_text|>");
    buffer.writeln("<|start_header_id|>system<|end_header_id|>");
    buffer.writeln(systemPrompt);

    for (var turn in history) {
      buffer.writeln("<|start_header_id|>user<|end_header_id|>");
      buffer.writeln(turn["user"] ?? '');
      buffer.writeln("<|start_header_id|>assistant<|end_header_id|>");
      buffer.writeln(turn["assistant"] ?? '');
    }

    buffer.writeln("<|start_header_id|>user<|end_header_id|>");
    buffer.writeln(userMsg);
    buffer.writeln("<|start_header_id|>assistant<|end_header_id|>");

    return buffer.toString();
  }

  String _chatML(String systemPrompt, List<Map<String, String>> history, String userMsg) {
    final buffer = StringBuffer();
    buffer.writeln("<|im_start|>system");
    buffer.writeln(systemPrompt);
    buffer.writeln("<|im_end|>");

    for (var turn in history) {
      buffer.writeln("<|im_start|>user");
      buffer.writeln(turn["user"] ?? '');
      buffer.writeln("<|im_end|>");
      buffer.writeln("<|im_start|>assistant");
      buffer.writeln(turn["assistant"] ?? '');
      buffer.writeln("<|im_end|>");
    }

    buffer.writeln("<|im_start|>user");
    buffer.writeln(userMsg);
    buffer.writeln("<|im_end|>");
    buffer.writeln("<|im_start|>assistant");

    return buffer.toString();
  }

  String _phi(String systemPrompt, List<Map<String, String>> history, String userMsg) {
    final buffer = StringBuffer();
    buffer.writeln("System: $systemPrompt\n");

    for (var turn in history) {
      buffer.writeln("User: ${turn["user"]}");
      buffer.writeln("Assistant: ${turn["assistant"]}\n");
    }

    buffer.writeln("User: $userMsg");
    buffer.writeln("Assistant:");
    return buffer.toString();
  }

  String _gemma(String systemPrompt, List<Map<String, String>> history, String userMsg) {
    final buffer = StringBuffer();
    buffer.writeln("<start_of_turn>system");
    buffer.writeln(systemPrompt);
    buffer.writeln("<end_of_turn>");

    for (var turn in history) {
      buffer.writeln("<start_of_turn>user");
      buffer.writeln(turn["user"] ?? '');
      buffer.writeln("<end_of_turn>");

      buffer.writeln("<start_of_turn>model");
      buffer.writeln(turn["assistant"] ?? '');
      buffer.writeln("<end_of_turn>");
    }

    buffer.writeln("<start_of_turn>user");
    buffer.writeln(userMsg);
    buffer.writeln("<end_of_turn>");
    buffer.writeln("<start_of_turn>model");
    return buffer.toString();
  }

  String _alpaca(String systemPrompt, List<Map<String, String>> history, String userMsg) {
    final buffer = StringBuffer();
    buffer.writeln("### Instruction:");
    buffer.writeln(systemPrompt);

    for (var turn in history) {
      buffer.writeln("\n# User:");
      buffer.writeln(turn["user"] ?? '');
      buffer.writeln("\n# Assistant:");
      buffer.writeln(turn["assistant"] ?? '');
    }

    buffer.writeln("\n### Instruction:");
    buffer.writeln(userMsg);
    buffer.writeln("\n### Response:");
    return buffer.toString();
  }
}

/// ---------------------------
/// Model detection helpers
/// ---------------------------

class ModelDetector {
  static ChatModelType detectFromFilename(String filename) {
    final f = filename.toLowerCase();
    if (f.contains('llama')) return ChatModelType.llama;
    if (f.contains('mistral') || f.contains('mixtral')) return ChatModelType.mistral;
    if (f.contains('qwen')) return ChatModelType.qwen;
    if (f.contains('phi')) return ChatModelType.phi;
    if (f.contains('gemma') || f.contains('gamma')) return ChatModelType.gemma;
    return ChatModelType.alpacaFallback;
  }

  /// If you can extract GGUF metadata into a Map<String, dynamic>, prefer this method.
  static ChatModelType detectFromMetadataMap(Map<String, dynamic> meta) {
    final arch = (meta['gguf_model_arch'] ?? meta['general.architecture'] ?? '').toString().toLowerCase();
    if (arch.contains('llama')) return ChatModelType.llama;
    if (arch.contains('mistral') || arch.contains('mixtral')) return ChatModelType.mistral;
    if (arch.contains('qwen')) return ChatModelType.qwen;
    if (arch.contains('phi')) return ChatModelType.phi;
    if (arch.contains('gemma') || arch.contains('gamma')) return ChatModelType.gemma;
    return ChatModelType.alpacaFallback;
  }
  
  /// Detect model quality from filename (quantization level)
  static ModelQuality detectQuality(String filename) {
    final f = filename.toLowerCase();
    
    // Check for extremely low quality indicators
    if (f.contains('q2_k') || f.contains('2bit') || f.contains('1b') || f.contains('0.5b')) {
      return ModelQuality.poor;
    }
    
    // Check for fair quality
    if (f.contains('q3_k') || f.contains('q4_0') || f.contains('q4_1')) {
      return ModelQuality.fair;
    }
    
    // Check for good quality
    if (f.contains('q4_k_m') || f.contains('q5_') || f.contains('q6_') || f.contains('q8_') || f.contains('f16') || f.contains('f32')) {
      return ModelQuality.good;
    }
    
    // Default to fair if can't determine
    return ModelQuality.fair;
  }
}

enum ModelQuality { good, fair, poor }

/// ---------------------------
/// Memory manager
/// ---------------------------

class MemoryManager {
  // In-memory short-term history (circular/append)
  final List<Map<String, String>> _history = [];
  // Persistent key-value 'facts' about the user
  final Map<String, String> facts = {};

  // thresholds
  final int maxShortTermTurns;
  final int maxSummaryChars;

  String _summary = '';

  MemoryManager({this.maxShortTermTurns = 6, this.maxSummaryChars = 800});

  List<Map<String, String>> get history => List.unmodifiable(_history);
  String get summary => _summary;

  void pushTurn(String user, String assistant) {
    _history.add({'user': user, 'assistant': assistant});
    // trim
    while (_history.length > maxShortTermTurns) {
      _compressOldest();
    }
  }

  void _compressOldest() {
    // Basic summarization heuristic: move oldest two turns into summary
    if (_history.length < 2) return;
    final first = _history.removeAt(0);
    final second = _history.removeAt(0);
    final excerpt = 'Previously, the user said: "${first['user']}" and "${second['user']}"; assistant replied briefly.';
    _prependToSummary(excerpt);
  }

  void _prependToSummary(String excerpt) {
    final candidate = '$excerpt\n\n$_summary';
    if (candidate.length > maxSummaryChars) {
      // naive trimming: cut summary to maxSummaryChars
      _summary = '${candidate.substring(0, maxSummaryChars - 3)}...';
    } else {
      _summary = candidate;
    }
  }

  void setFact(String key, String value) {
    facts[key] = value;
  }

  String factsAsString() {
    if (facts.isEmpty) return '';
    final buffer = StringBuffer('User facts:\n');
    facts.forEach((k, v) => buffer.writeln('$k: $v'));
    return buffer.toString();
  }

  void clear() {
    _history.clear();
    _summary = '';
    facts.clear();
  }
}

/// ---------------------------
/// Prompt builder & token trimming (approximate)
/// ---------------------------

class PromptBuilder {
  final ChatTemplate template;
  final MemoryManager memory;
  final int maxTokensApprox; // approximate token budget for final prompt

  PromptBuilder({required this.template, required this.memory, this.maxTokensApprox = 2048});

  /// Note: token approximation uses UTF-8 length / 4 heuristic. It's not exact but works for trimming.
  int _approxTokens(String text) => (utf8.encode(text).length / 4).ceil();

  String build({required String systemPrompt, required String userMessage}) {
    // Compose blocks
    final sb = StringBuffer();

    // System block
    sb.writeln(systemPrompt);

    // Facts
    final facts = memory.factsAsString();
    if (facts.isNotEmpty) {
      sb.writeln('\n$facts\n');
    }

    // Summary
    if (memory.summary.isNotEmpty) {
      sb.writeln('\nConversation summary:\n${memory.summary}\n');
    }

    // History (as template-specific insert)
    final history = memory.history;

    // Build the full template with history inside template
    final fullPrompt = template.buildPrompt(
      systemPrompt: sb.toString().trim(),
      history: history,
      userMessage: userMessage,
    );

    // Trim if exceeds token budget
    var approx = _approxTokens(fullPrompt);
    if (approx <= maxTokensApprox) return fullPrompt;

    // If too long, progressively remove oldest history turns until fits
    var tempHistory = List<Map<String, String>>.from(history);
    while (approx > maxTokensApprox && tempHistory.isNotEmpty) {
      tempHistory.removeAt(0);
      final p = template.buildPrompt(systemPrompt: sb.toString().trim(), history: tempHistory, userMessage: userMessage);
      approx = _approxTokens(p);
      if (approx <= maxTokensApprox) return p;
    }

    // If still too long, trim summary
    var trimmedSummary = memory.summary;
    while (approx > maxTokensApprox && trimmedSummary.length > 50) {
      trimmedSummary = trimmedSummary.substring(0, (trimmedSummary.length * 0.9).toInt());
      final sblock = sb.toString().replaceAll(memory.summary, trimmedSummary);
      final p = template.buildPrompt(systemPrompt: sblock.trim(), history: tempHistory, userMessage: userMessage);
      approx = _approxTokens(p);
      if (approx <= maxTokensApprox) return p;
    }

    // As last resort, return a heavily trimmed prompt with just the system + user message
    final fallback = template.buildPrompt(systemPrompt: systemPrompt, history: [], userMessage: userMessage);
    return fallback;
  }
}

/// ---------------------------
/// Coherence checks
/// ---------------------------

class CoherenceChecker {
  final int minChars; // min acceptable answer length
  final int maxRepeats; // max repeated words threshold

  const CoherenceChecker({this.minChars = 8, this.maxRepeats = 6});

  bool looksCoherent(String text) {
    if (text.trim().isEmpty) return false;
    if (text.trim().length < minChars) return false;

    // simple repetition heuristic
    final tokens = text.split(RegExp(r"\s+"));
    final counts = <String, int>{};
    for (final t in tokens) {
      final key = t.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      if (counts[key]! >= maxRepeats) return false;
    }

    // detect lots of punctuation / undecipherable chars
    final punctRatio = RegExp(r"[^A-Za-z0-9\s]").allMatches(text).length / (text.length + 1);
    if (punctRatio > 0.4) return false;

    // detect fallback tokens like '<|start' — model leaked template
    if (text.contains('<|start') || text.contains('<|im_start') || text.contains('<|end')) return false;

    return true;
  }
}

/// ---------------------------
/// Legacy API (backward compatibility)
/// ---------------------------

/// Auto-detect model type from GGUF metadata or filename
ChatModelType detectModelType(String archOrFilename) {
  return ModelDetector.detectFromFilename(archOrFilename);
}

/// Ready-to-use helper: Auto-detect model and build prompt
String buildPromptForModel({
  required String modelNameOrArch,
  required String systemPrompt,
  required List<Map<String, String>> history,
  required String userMessage,
}) {
  final modelType = detectModelType(modelNameOrArch);
  final template = ChatTemplate(modelType);

  return template.buildPrompt(
    systemPrompt: systemPrompt,
    history: history,
    userMessage: userMessage,
  );
}
