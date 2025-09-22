import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.role, required this.text, this.toolName});
  final String role; // 'user' | 'assistant' | 'tool'
  final String text;
  final String? toolName;

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final isTool = role == 'tool';
    final bg = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : isTool
            ? Theme.of(context).colorScheme.surfaceVariant
            : Theme.of(context).colorScheme.secondaryContainer;
    final icon = isUser
        ? const CircleAvatar(child: Icon(Icons.person))
        : isTool
            ? const CircleAvatar(child: Icon(Icons.build))
            : const CircleAvatar(child: Icon(Icons.smart_toy));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isUser) icon,
        if (!isUser) const SizedBox(width: 8),
        Flexible(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isTool && toolName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('🔧 ' + toolName!, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                MarkdownBody(
                  data: text,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    codeblockPadding: const EdgeInsets.all(10),
                    codeblockDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isUser) const SizedBox(width: 8),
        if (isUser) icon,
      ],
    );
  }
}