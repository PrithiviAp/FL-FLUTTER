import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'tracking_task_handler.dart';
import 'package:flutter/material.dart';

class TrackingManager {
  static bool _configured = false;

  static void initCommunicationPort() {
    FlutterForegroundTask.initCommunicationPort();
  }

  static Future<void> _configureOnce() async {
    if (_configured) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'family_locator_tracking',
        channelName: 'Family Locator Tracking',
        channelDescription: 'Shown continuously while tracking is active.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
     foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(15 * 1000),
      autoRunOnBoot: false, // CHANGE: prevents RestartReceiver crash on Android 12+
      allowWakeLock: true,
      allowWifiLock: true,
    ),
    );
    _configured = true;
  }

  /// Start the foreground service.
  /// Set [withMicrophone] to true ONLY when the user explicitly toggles
  /// the mic on while the app is in the foreground. Starting with
  /// microphone type at app launch causes SecurityException on Android 14+.
  static Future<bool> start({bool withMicrophone = false}) async {
    await _configureOnce();
    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Family Locator — tracking active',
      notificationText: 'Starting up…',
      notificationIcon: const NotificationIcon(
        metaDataName: 'com.familylocator.app.TRACKING_ICON',
        backgroundColor: 0xFF2196F3,
      ),
      callback: startTrackingCallback,
    );
    return result is ServiceRequestSuccess;
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;
}
