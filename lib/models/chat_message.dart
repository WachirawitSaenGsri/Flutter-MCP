class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'tool'
  final String content;
  final DateTime createdAt;
  final String? toolName;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.toolName,
  });

  ChatMessage copyWith({String? content}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
        toolName: toolName,
      );
}