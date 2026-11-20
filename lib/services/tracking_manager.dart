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

  static Future<bool> start() async {
    await _configureOnce();
    if (await FlutterForegroundTask.isRunningService) return true;

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
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