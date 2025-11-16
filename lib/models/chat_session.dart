import 'dart:convert';

import 'chat_message.dart';

class ChatSession {
  final String id;
  String name;
  String systemPrompt;
  List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.name,
    this.systemPrompt = '',
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'systemPrompt': systemPrompt,
        'messages': messages
            .map((m) => {
                  'text': m.text,
                  'role': m.role.toString(),
                  'timestamp': m.timestamp.toIso8601String(),
                })
            .toList(),
      };

  static ChatSession fromJson(Map<String, dynamic> j) {
    final msgs = <ChatMessage>[];
    if (j['messages'] is List) {
      for (final m in j['messages']) {
        try {
          final role = (m['role'] as String).contains('assistant')
              ? MessageRole.assistant
              : MessageRole.user;
          msgs.add(ChatMessage(m['text'] ?? '', role));
        } catch (_) {}
      }
    }

    return ChatSession(
      id: j['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: j['name'] ?? 'Session',
      systemPrompt: j['systemPrompt'] ?? '',
      messages: msgs,
    );
  }

  String encode() => jsonEncode(toJson());
}
