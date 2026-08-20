import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Helper to configure and control foreground service execution for background UDP listening.
class SharedDeviceForegroundService {
  static bool _isInitialized = false;

  /// Initializes the foreground task communication channel and notification options.
  static Future<void> init({
    String notificationChannelId = 'shared_device_network_service',
    String notificationChannelName = 'Shared Device Network Service',
    String notificationChannelDescription = 'Keeps the Shared Device Network active in background',
    NotificationPriority notificationPriority = NotificationPriority.LOW,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: notificationChannelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: notificationPriority,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  /// Starts the foreground service with customizable notification title and content text.
  static Future<bool> startService({
    String notificationTitle = 'Shared Device Network Server Active',
    String notificationText = 'Listening for incoming device connections...',
    Function? callback,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true; // No-op on desktop / tests
    }

    await init();

    // Check notification permission on Android 13+
    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      final restartResult = await FlutterForegroundTask.restartService();
      return restartResult is ServiceRequestSuccess;
    }

    final serviceResult = await FlutterForegroundTask.startService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      callback: callback,
    );

    return serviceResult is ServiceRequestSuccess;
  }

  /// Stops the foreground service.
  static Future<bool> stopService() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    final serviceResult = await FlutterForegroundTask.stopService();
    return serviceResult is ServiceRequestSuccess;
  }

  /// Updates the foreground notification text while running.
  static Future<bool> updateNotification({
    required String notificationTitle,
    required String notificationText,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    final result = await FlutterForegroundTask.updateService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );

    return result is ServiceRequestSuccess;
  }

  /// Returns whether the foreground service is currently running.
  static Future<bool> isRunning() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    return await FlutterForegroundTask.isRunningService;
  }
}
