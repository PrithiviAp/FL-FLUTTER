// lib/services/call_recorder_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_client.dart';

class CallRecorderService {
  static final _recorder = AudioRecorder();
  static WebSocketChannel? _ws;
  static StreamSubscription<Uint8List>? _sub;
  static String? _currentPath;

  /// Start recording + live streaming to backend.
  static Future<bool> start({String? number}) async {
    if (!await _recorder.hasPermission()) return false;

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _currentPath = '${dir.path}/call_${ts}_${number ?? 'unknown'}.m4a';

    // Connect live-audio WS (reuse existing /ws/audio endpoint)
    final base = ApiClient.baseUrl;
    final key = ApiClient.deviceKey;
    if (key == null) return false;
    final wsUrl = base.replaceFirst(RegExp(r'^http'), 'ws') +
        '/ws/audio?deviceKey=$key&callRecording=true';
    _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
    await _ws!.ready;

    // Record to file AND stream chunks
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,   // raw PCM for WS
      sampleRate: 16000,
      numChannels: 1,
      androidConfig: AndroidRecordConfig(
        audioSource: AndroidAudioSource.voiceCommunication,
      ),
    ));

    _sub = stream.listen((chunk) {
      try { _ws?.sink.add(chunk); } catch (_) {}
    });

    return true;
  }

  /// Stop recording, return file path of finished recording.
  static Future<String?> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.sink.close();
    _ws = null;
    final path = await _recorder.stop();
    return path ?? _currentPath;
  }
}