import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';

class WsClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnect;
  bool _stopped = false;

  final void Function(Map<String, dynamic> msg) onMessage;

  WsClient({required this.onMessage});

  void connect() {
    _stopped = false;
    _open();
  }

  void _open() {
    final base = ApiClient.baseUrl;
    final key = ApiClient.deviceKey;
    if (key == null) return;

    final wsUrl = base.replaceFirst(RegExp(r'^http'), 'ws') + '/ws?deviceKey=$key';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _sub = _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            onMessage(msg);
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_stopped) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 5), _open);
  }

  void dispose() {
    _stopped = true;
    _reconnect?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }
}