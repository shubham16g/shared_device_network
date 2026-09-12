import 'dart:async';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Top-level or static entry point for the foreground task isolate.
///
/// NOTE: Must be decorated with `@pragma('vm:entry-point')` so Flutter's AOT
/// compiler does not strip it out during tree shaking.
@pragma('vm:entry-point')
void continuousForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(ContinuousTaskHandler());
}

/// A clean, standalone task handler that executes continuously in a dedicated
/// background isolate.
///
/// You can place your custom long-running logic in [onStart] or [onRepeatEvent].
class ContinuousTaskHandler extends TaskHandler {
  int _tickCount = 0;

  /// Called when the foreground service starts.
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _tickCount = 0;
    // Notify UI isolate that the service started
    FlutterForegroundTask.sendDataToMain({
      'status': 'started',
      'timestamp': timestamp.toIso8601String(),
      'starter': starter.name,
      'tick': _tickCount,
    });

    // =========================================================================
    // TODO: [USER INITIALIZATION LOGIC]
    // Place any one-time background initialization (e.g. opening sockets,
    // initializing DBs or listeners) here.
    // =========================================================================
  }

  /// Called repeatedly based on [ForegroundTaskOptions.eventAction].
  /// By default, this is triggered every 5 seconds.
  @override
  void onRepeatEvent(DateTime timestamp) {
    _tickCount++;

    // 1. Update the foreground notification with current test status
    FlutterForegroundTask.updateService(
      notificationTitle: 'Continuous Service Active',
      notificationText: 'Service running continuously (Tick: $_tickCount)',
    );

    // 2. Send heartbeat / telemetry data back to the UI isolate
    FlutterForegroundTask.sendDataToMain({
      'status': 'running',
      'tick': _tickCount,
      'timestamp': timestamp.toIso8601String(),
    });

    // =========================================================================
    // TODO: [USER RECURRING LOGIC]
    // Place your custom indefinite background logic here.
    // This runs continuously on every tick without being suspended by OS sleep.
    // =========================================================================
  }

  /// Called when the service is stopped or destroyed.
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Notify UI isolate of destruction
    FlutterForegroundTask.sendDataToMain({
      'status': 'stopped',
      'timestamp': timestamp.toIso8601String(),
      'isTimeout': isTimeout,
      'lastTick': _tickCount,
    });

    // =========================================================================
    // TODO: [USER CLEANUP LOGIC]
    // Dispose timers, cancel subscriptions, or close network sockets here.
    // =========================================================================
  }

  /// Called when data is sent from the UI isolate via [FlutterForegroundTask.sendDataToTask].
  @override
  void onReceiveData(Object data) {
    // =========================================================================
    // TODO: [USER DATA HANDLER]
    // Handle commands or data passed from the UI isolate to this service.
    // =========================================================================
  }

  /// Called when user taps the foreground service notification.
  @override
  void onNotificationPressed() {
    // Launch/bring the application back to the foreground
    FlutterForegroundTask.launchApp();
  }

  /// Called when a notification button is tapped.
  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_button') {
      FlutterForegroundTask.stopService();
    }
  }

  /// Called when the notification is dismissed.
  @override
  void onNotificationDismissed() {}
}

/// Helper manager class to configure, request permissions, and control the
/// indefinite [ContinuousForegroundService].
class ContinuousForegroundService {
  static bool _isInitialized = false;

  /// Initializes communication ports between the UI isolate and the background service isolate.
  /// Call this early in `main()` before `runApp()`.
  static void initCommunicationPort() {
    FlutterForegroundTask.initCommunicationPort();
  }

  /// Initializes notification options and foreground task configurations.
  ///
  /// Requests notification permission (Android 13+) and prepares the service
  /// with wake lock and wifi lock for non-stop execution.
  static Future<void> init({
    int repeatIntervalMs = 5000,
    String notificationChannelId = 'continuous_foreground_service',
    String notificationChannelName = 'Continuous Background Service',
    String notificationChannelDescription = 'Keeps background tasks running continuously',
  }) async {
    if (_isInitialized) return;

    // Check & request notification permission
    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Configure the foreground task
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: notificationChannelDescription,
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(repeatIntervalMs),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  /// Starts the continuous foreground service.
  ///
  /// Runs indefinitely with a persistent notification until [stopService] is called.
  static Future<bool> startService({
    String notificationTitle = 'Continuous Service Active',
    String notificationText = 'Service is running continuously...',
    int serviceId = 256,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    if (!_isInitialized) {
      await init();
    }

    if (await isRunning()) {
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: serviceId,
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      notificationButtons: const [
        NotificationButton(id: 'stop_button', text: 'Stop'),
      ],
      callback: continuousForegroundTaskCallback,
    );

    return result is ServiceRequestSuccess;
  }

  /// Stops the continuous foreground service.
  static Future<bool> stopService() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    final result = await FlutterForegroundTask.stopService();
    return result is ServiceRequestSuccess;
  }

  /// Checks if the foreground service is currently running.
  static Future<bool> isRunning() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    return await FlutterForegroundTask.isRunningService;
  }

  /// Checks if battery optimizations are ignored for this app.
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (Platform.isAndroid) {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    }
    return true;
  }

  /// Prompts the user to ignore battery optimization for non-stop execution.
  static Future<bool> requestIgnoreBatteryOptimization() async {
    if (Platform.isAndroid) {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    return true;
  }

  /// Adds a listener to receive data/heartbeat packets from the background task.
  static void addDataCallback(void Function(Object data) callback) {
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  /// Removes a previously registered data listener.
  static void removeDataCallback(void Function(Object data) callback) {
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }

  /// Sends a data object/command to the running task handler in the background isolate.
  static void sendData(Object data) {
    FlutterForegroundTask.sendDataToTask(data);
  }
}
