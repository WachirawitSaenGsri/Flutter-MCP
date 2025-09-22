import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env"); // ต้อง stop -> run ใหม่เพื่อโหลดค่า .env
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat App (Groq REST)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;

  late final GroqClient _groq;

  @override
  void initState() {
    super.initState();
    _initGroq();
  }

  void _initGroq() {
    final apiKey = (dotenv.env['GROQ_API_KEY'] ?? '').trim();
    final apiBase = (dotenv.env['GROQ_API_BASE'] ?? 'https://api.groq.com/openai/v1').trim();
    final model  = (dotenv.env['GROQ_MODEL'] ?? 'llama-3.3-70b-versatile').trim();

    if (apiKey.isEmpty) {
      _showError('Missing GROQ_API_KEY (.env)');
      return;
    }
    _groq = GroqClient(apiKey: apiKey, apiBase: apiBase, model: model);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isTyping = true;
    });

    try {
      final reply = await _groq.chatCompletion(
        userMessage: text,
        systemPrompt: 'You are a helpful assistant. Be concise and friendly.',
      );

      setState(() {
        _messages.add(ChatMessage(text: reply, isUser: false));
        _isTyping = false;
      });
    } catch (e) {
      _showError('Error: $e');
      setState(() => _isTyping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Chat App (Groq)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (_, index) => _messages[_messages.length - 1 - index],
            ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
                  SizedBox(width: 8),
                  Text('AI is typing...'),
                ],
              ),
            ),
          const Divider(height: 1.0),
          Container(
            decoration: BoxDecoration(color: Theme.of(context).cardColor),
            child: _buildTextComposer(),
          ),
        ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return IconTheme(
      data: IconThemeData(color: Theme.of(context).colorScheme.primary),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Row(
          children: [
            Flexible(
              child: TextField(
                controller: _textController,
                textInputAction: TextInputAction.send,
                onSubmitted: _handleSubmitted,
                decoration: const InputDecoration.collapsed(hintText: 'Send a message'),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () => _handleSubmitted(_textController.text),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  const ChatMessage({super.key, required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser
            ? Theme.of(context).colorScheme.primary.withOpacity(.12)
            : Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              child: const Text('AI'),
              backgroundColor: Theme.of(context).colorScheme.secondary,
            ),
          const SizedBox(width: 8),
          Flexible(child: bubble),
          const SizedBox(width: 8),
          if (isUser)
            CircleAvatar(
              child: const Text('You'),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
    );
  }
}

/// -------- Groq REST client (OpenAI-compatible /chat/completions) --------
class GroqClient {
  final String apiKey;
  final String apiBase; // e.g. https://api.groq.com/openai/v1
  final String model;
  final http.Client _http = http.Client();

  GroqClient({
    required this.apiKey,
    required this.apiBase,
    required this.model,
  });

  Future<String> chatCompletion({
    required String userMessage,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 1500,
  }) async {
    final uri = Uri.parse('$apiBase/chat/completions');

    final messages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }
    messages.add({'role': 'user', 'content': userMessage});

    final payload = {
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      // 'stream': true, // ถ้าจะทำสตรีม ต้องอ่าน SSE/streaming response เพิ่ม
    };

    final res = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (res.statusCode != 200) {
      throw Exception('Groq error ${res.statusCode}: ${res.body}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>?;

    if (choices == null || choices.isEmpty) {
      return '(no response)';
    }

    // OpenAI-compatible: choices[0].message.content
    final msg = choices.first['message'] as Map<String, dynamic>?;
    final content = msg?['content'] as String? ?? '';
    return content.isEmpty ? '(no response)' : content;
  }
}
