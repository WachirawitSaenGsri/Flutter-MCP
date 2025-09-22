import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

// ================= Models =================
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

// ============== Gateway Client ==============
class McpGatewayClient {
  McpGatewayClient(this.url);
  final Uri url;

  WebSocketChannel? _channel;
  final _incoming = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _incoming.stream;
  bool get connected => _channel != null;

  Future<void> connect({Map<String, dynamic>? hello}) async {
    if (_channel != null) return;
    final ch = WebSocketChannel.connect(url);
    _channel = ch;
    ch.sink.add(jsonEncode({'type': 'hello', 'client': 'flutter', 'hello': hello ?? {}}));
    ch.stream.listen((raw) {
      try { _incoming.add(jsonDecode(raw as String) as Map<String, dynamic>); } catch (_) {}
    }, onDone: _handleClose, onError: (_) => _handleClose());
  }

  void _handleClose() { _channel = null; }

  void sendUserMessage({required String conversationId, required String text}) {
    _channel?.sink.add(jsonEncode({'type': 'user_message', 'conversationId': conversationId, 'text': text}));
  }

  void dispose() { _channel?.sink.close(); _incoming.close(); }
}

// ================= State =================
final _uuid = const Uuid();
final gatewayUrlProvider = Provider<Uri>((_) => Uri.parse('ws://localhost:8787/stream'));

final mcpClientProvider = Provider.autoDispose<McpGatewayClient>((ref) {
  final url = ref.watch(gatewayUrlProvider);
  final client = McpGatewayClient(url);
  client.connect();
  ref.onDispose(client.dispose);
  return client;
});

class ChatState {
  final String conversationId;
  final List<ChatMessage> messages;
  final bool isStreaming;
  final String? streamingMessageId;
  final String pendingBuffer; // ป้องกันบับเบิลตัวอักษรเดี่ยวช่วงเริ่มสตรีม

  ChatState({
    required this.conversationId,
    required this.messages,
    required this.isStreaming,
    this.streamingMessageId,
    this.pendingBuffer = '',
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isStreaming,
    String? streamingMessageId,
    String? pendingBuffer,
  }) => ChatState(
        conversationId: conversationId,
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        streamingMessageId: streamingMessageId ?? this.streamingMessageId,
        pendingBuffer: pendingBuffer ?? this.pendingBuffer,
      );
}

final chatProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    final client = ref.watch(mcpClientProvider);
    final s = ChatState(conversationId: _uuid.v4(), messages: [], isStreaming: false);
    client.messages.listen(_onGatewayMessage);
    return s;
  }

  void _onGatewayMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'assistant_delta': {
        final delta = (msg['delta'] ?? '').toString();
        if (delta.isEmpty) return;
        final id = state.streamingMessageId ?? _uuid.v4();
        final buffer = state.pendingBuffer + delta;
        final hasWordBoundary = buffer.contains(' ') || buffer.contains('') || buffer.length >= 6;
        final idx = state.messages.indexWhere((m) => m.id == id);

        if (idx == -1 && !hasWordBoundary) {
          state = state.copyWith(isStreaming: true, streamingMessageId: id, pendingBuffer: buffer);
          return;
        }

        final contentDelta = hasWordBoundary ? buffer : '';
        if (idx == -1) {
          final newMsg = ChatMessage(id: id, role: 'assistant', content: contentDelta, createdAt: DateTime.now());
          state = state.copyWith(
            messages: [...state.messages, newMsg],
            isStreaming: true,
            streamingMessageId: id,
            pendingBuffer: hasWordBoundary ? '' : buffer,
          );
        } else {
          final existing = state.messages[idx];
          final updated = existing.copyWith(content: existing.content + (hasWordBoundary ? contentDelta : ''));
          final copy = [...state.messages]..[idx] = updated;
          state = state.copyWith(
            messages: copy,
            isStreaming: true,
            streamingMessageId: id,
            pendingBuffer: hasWordBoundary ? '' : buffer,
          );
        }
        break;
      }
      case 'assistant_done': {
        state = state.copyWith(isStreaming: false, streamingMessageId: null, pendingBuffer: '');
        break;
      }
      case 'tool_message': {
        final toolMsg = ChatMessage(
          id: _uuid.v4(),
          role: 'tool',
          content: (msg['content'] ?? '').toString(),
          toolName: (msg['name'] as String?),
          createdAt: DateTime.now(),
        );
        state = state.copyWith(messages: [...state.messages, toolMsg]);
        break;
      }
      case 'error': {
        final errMsg = ChatMessage(
          id: _uuid.v4(),
          role: 'tool',
          content: '⚠️ ' + (msg['message']?.toString() ?? 'Unknown error'),
          createdAt: DateTime.now(),
        );
        state = state.copyWith(messages: [...state.messages, errMsg], isStreaming: false, streamingMessageId: null);
        break;
      }
    }
  }

  void send(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final userMsg = ChatMessage(id: _uuid.v4(), role: 'user', content: t, createdAt: DateTime.now());
    state = state.copyWith(messages: [...state.messages, userMsg]);
    final client = ref.read(mcpClientProvider);
    client.sendUserMessage(conversationId: state.conversationId, text: t);
  }
}

void main() { runApp(const ProviderScope(child: App())); }

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter + MCP Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B6EF5)),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final chatCtl = ref.read(chatProvider.notifier);
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(title: const Text('Flutter + MCP Chat')),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: chat.messages.length + (chat.isStreaming ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == chat.messages.length && chat.isStreaming) return _typingBubble(context);
              final m = chat.messages[i];
              return _messageBubble(context, m);
            },
          ),
        ),
        _composer(chatCtl),
      ]),
    );
  }

  Widget _messageBubble(BuildContext context, ChatMessage m) {
    final isUser = m.role == 'user';
    final isTool = m.role == 'tool';
    final bg = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : isTool
            ? Theme.of(context).colorScheme.surfaceVariant
            : Theme.of(context).colorScheme.secondaryContainer;
    final icon = isUser
        ? const Icon(Icons.person, size: 18)
        : isTool
            ? const Icon(Icons.build, size: 18)
            : const Icon(Icons.smart_toy, size: 18);

    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser) Padding(padding: const EdgeInsets.only(top: 6, right: 6), child: icon),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
            child: isTool
                ? SelectableText(m.content)
                : MarkdownBody(data: m.content, selectable: true, shrinkWrap: true),
          ),
        ),
        if (isUser) Padding(padding: const EdgeInsets.only(top: 6, left: 6), child: icon),
      ],
    );
  }

  Widget _typingBubble(BuildContext context) {
    return Row(children: [
      const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.smart_toy, size: 18)),
      Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('กำลังพิมพ์…'),
      )
    ]);
  }

  Widget _composer(ChatController chatCtl) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'พิมพ์ข้อความ…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onSubmitted: (_) => _send(chatCtl),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: () => _send(chatCtl), icon: const Icon(Icons.send)),
        ]),
      ),
    );
  }

  void _send(ChatController chatCtl) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    chatCtl.send(text);
  }
}