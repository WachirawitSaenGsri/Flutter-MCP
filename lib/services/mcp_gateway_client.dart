import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

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

    ch.sink.add(jsonEncode({
      'type': 'hello',
      'client': 'flutter',
      'hello': hello ?? {},
    }));

    ch.stream.listen((raw) {
      try {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        _incoming.add(msg);
      } catch (_) {}
    }, onDone: _handleClose, onError: (_) => _handleClose());
  }

  void _handleClose() {
    _channel = null;
  }

  void sendUserMessage({
    required String conversationId,
    required String text,
  }) {
    _channel?.sink.add(jsonEncode({
      'type': 'user_message',
      'conversationId': conversationId,
      'text': text,
    }));
  }

  void dispose() {
    _channel?.sink.close();
    _incoming.close();
  }
}