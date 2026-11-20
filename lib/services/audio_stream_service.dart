import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';

class AudioStreamService {
  static WebSocketChannel? _ws;
  static StreamSubscription? _audioSub;
  static bool _streaming = false;

  /// Start streaming mic to the backend. Returns true on success.
  static Future<bool> start() async {
    if (_streaming) return true;

    final base = ApiClient.baseUrl;
    final key = ApiClient.deviceKey;
    if (key == null) return false;

    // Connect to the audio WS endpoint
    final wsUrl = base.replaceFirst(RegExp(r'^http'), 'ws')
        + '/ws/audio?deviceKey=$key';

    try {
      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));

      // Wait for connection to open
      await _ws!.ready;

      // Initialize recorder for raw PCM streaming
      final recorder = Recorder.instance;
      await recorder.init(
        format: PCMFormat.s16le,
        sampleRate: 16000,
        channels: RecorderChannels.mono,
      );

      recorder.start();

      // Listen to PCM chunks and forward to WS
      _audioSub = recorder.uint8ListStream.listen(
        (AudioDataContainer data) {
          // CRITICAL: copy the buffer — the native layer reuses memory [citation:14]
          final Uint8List frame = Uint8List.fromList(data.rawData);
          try {
            _ws?.sink.add(frame);
          } catch (_) {}
        },
        onError: (_) => stop(),
      );

      // Start streaming PCM
      recorder.startStreamingData(format: StreamingFormat.pcm);

      _streaming = true;
      return true;
    } catch (e) {
      await stop();
      return false;
    }
  }

  static Future<void> stop() async {
    _streaming = false;
    await _audioSub?.cancel();
    _audioSub = null;

    try {
      Recorder.instance.stopStreamingData();
      Recorder.instance.stop();
    } catch (_) {}

    await _ws?.sink.close();
    _ws = null;
  }

  static bool get isStreaming => _streaming;
}