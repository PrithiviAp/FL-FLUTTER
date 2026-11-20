import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'tracking_task_handler.dart';

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
        autoRunOnBoot: true,
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
      // If it's already running without mic and the caller now wants mic,
      // restart is needed — the caller should stop() first in that case.
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      serviceTypes: withMicrophone
          ? [ForegroundServiceTypes.location,
             ForegroundServiceTypes.dataSync,
             ForegroundServiceTypes.microphone,
             ForegroundServiceTypes.phoneCall]
          : [ForegroundServiceTypes.location,
             ForegroundServiceTypes.dataSync],
      notificationTitle: 'Family Locator — tracking active',
      notificationText: 'Starting up…',
      callback: startTrackingCallback,
    );
    return result is ServiceRequestSuccess;
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  static Future<bool> isRunning() => FlutterForegroundTask.isRunningService;
}
