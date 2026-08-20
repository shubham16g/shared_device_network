import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/shared_device_record.dart';
import '../models/status.dart';
import '../server/shared_device_network_server.dart';

/// Top-level callback entrypoint for the background isolate.
///
/// MUST be annotated with `@pragma('vm:entry-point')` so it isn't stripped by tree shaking.
@pragma('vm:entry-point')
void sharedDeviceNetworkServerCallback() {
  FlutterForegroundTask.setTaskHandler(SharedDeviceServerTaskHandler());
}

/// A background [TaskHandler] that hosts a [SharedDeviceNetworkServer] in a background isolate,
/// allowing shared connected devices to remain available across the network even when the UI is closed or killed.
class SharedDeviceServerTaskHandler extends TaskHandler {
  SharedDeviceNetworkServer? _server;
  int _receivedCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 1. Read persistent configuration from Task storage
    final port = (await FlutterForegroundTask.getData<int>(key: 'server_port')) ?? 8888;
    final discoveryPort = (await FlutterForegroundTask.getData<int>(key: 'server_discoveryPort')) ?? 8889;
    final devicesJson = await FlutterForegroundTask.getData<String>(key: 'server_devices');

    // 2. Instantiate UDP server inside background isolate
    _server = SharedDeviceNetworkServer(
      port: port,
      discoveryPort: discoveryPort,
      onDataReceived: (deviceId, message) async {
        _receivedCount++;

        // Notify main UI isolate if running
        try {
          FlutterForegroundTask.sendDataToMain({
            'event': 'onDataReceived',
            'deviceId': deviceId,
            'message': message,
            'timestamp': DateTime.now().toIso8601String(),
            'totalCount': _receivedCount,
          });
        } catch (_) {}

        // Update Android notification text
        try {
          await FlutterForegroundTask.updateService(
            notificationTitle: 'Shared Device Server Active',
            notificationText: 'Messages received: $_receivedCount (Last for: $deviceId)',
          );
        } catch (_) {}

        return Status.success(
          message: 'Received by background server for device $deviceId',
          data: {
            'deviceId': deviceId,
            'timestamp': DateTime.now().toIso8601String(),
          },
        );
      },
    );

    // 3. Load pre-configured shared devices
    if (devicesJson != null && devicesJson.isNotEmpty) {
      try {
        final dynamic list = json.decode(devicesJson);
        if (list is List) {
          for (final item in list) {
            if (item is Map) {
              final dev = SharedDeviceRecord.fromMap(Map<String, dynamic>.from(item));
              await _server!.addDevice(
                dev.deviceId,
                dev.deviceName,
                deviceDescription: dev.deviceDescription,
                pairKey: dev.pairKey,
                metadata: dev.metadata,
              );
            }
          }
        }
      } catch (_) {}
    }

    try {
      if (_server!.deviceCount > 0) {
        await _server!.start();
      }
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Health check - ensure server is running if devices exist
    if (_server != null && _server!.deviceCount > 0 && !_server!.isRunning) {
      _server!.start();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    try {
      await _server?.stop();
    } catch (_) {}
    _server = null;
  }

  @override
  void onReceiveData(Object data) async {
    if (_server == null || data is! Map) return;

    final map = Map<String, dynamic>.from(data);
    final action = map['action']?.toString();

    if (action == 'addDevice') {
      final devId = map['deviceId']?.toString() ?? '';
      final devName = map['deviceName']?.toString() ?? '';
      final desc = map['deviceDescription']?.toString();
      final key = map['pairKey']?.toString();
      Map<String, dynamic>? meta;
      if (map['metadata'] is Map) {
        meta = Map<String, dynamic>.from(map['metadata'] as Map);
      }

      if (devId.isNotEmpty) {
        await _server!.addDevice(
          devId,
          devName,
          deviceDescription: desc,
          pairKey: key,
          metadata: meta,
        );
        _persistCurrentDevices();
      }
    } else if (action == 'removeDevice') {
      final devId = map['deviceId']?.toString() ?? '';
      if (devId.isNotEmpty) {
        await _server!.removeDevice(devId);
        _persistCurrentDevices();
      }
    } else if (action == 'stopServer') {
      await _server!.stop();
    }
  }

  void _persistCurrentDevices() {
    if (_server != null) {
      final list = _server!.devices.map((d) => d.toMap()).toList();
      FlutterForegroundTask.saveData(key: 'server_devices', value: json.encode(list));
    }
  }
}

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

    FlutterForegroundTask.initCommunicationPort();

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
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  /// Starts the UDP server in a dedicated background foreground task isolate.
  ///
  /// This server stays active and keeps sharing devices even if the main Flutter UI is closed or killed.
  static Future<bool> startBackgroundServer({
    int port = 8888,
    int discoveryPort = 8889,
    List<SharedDeviceRecord>? initialDevices,
    String notificationTitle = 'Shared Device Server Active',
    String notificationText = 'Sharing connected devices in background...',
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    await init();

    // 1. Request notification and battery optimization permissions
    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    // 2. Persist configuration for the background isolate
    await FlutterForegroundTask.saveData(key: 'server_port', value: port);
    await FlutterForegroundTask.saveData(key: 'server_discoveryPort', value: discoveryPort);
    if (initialDevices != null && initialDevices.isNotEmpty) {
      final jsonList = json.encode(initialDevices.map((d) => d.toMap()).toList());
      await FlutterForegroundTask.saveData(key: 'server_devices', value: jsonList);
    }

    // 3. Start or restart the foreground service with the entrypoint callback
    if (await FlutterForegroundTask.isRunningService) {
      final restartResult = await FlutterForegroundTask.restartService();
      return restartResult is ServiceRequestSuccess;
    }

    final serviceResult = await FlutterForegroundTask.startService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      callback: sharedDeviceNetworkServerCallback,
    );

    return serviceResult is ServiceRequestSuccess;
  }

  /// Starts the foreground service with customizable callback.
  static Future<bool> startService({
    String notificationTitle = 'Shared Device Network Server Active',
    String notificationText = 'Listening for incoming device connections...',
    Function? callback,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true; // No-op on desktop / tests
    }

    await init();

    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
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
      callback: callback ?? sharedDeviceNetworkServerCallback,
    );

    return serviceResult is ServiceRequestSuccess;
  }

  /// Sends command/data to the running background server isolate.
  static void sendDataToBackgroundServer(Map<String, dynamic> data) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterForegroundTask.sendDataToTask(data);
  }

  /// Adds a shared device to the running background server.
  static void addDeviceToBackgroundServer({
    required String deviceId,
    required String deviceName,
    String? deviceDescription,
    String? pairKey,
    Map<String, dynamic>? metadata,
  }) {
    sendDataToBackgroundServer({
      'action': 'addDevice',
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (deviceDescription != null) 'deviceDescription': deviceDescription,
      if (pairKey != null) 'pairKey': pairKey,
      if (metadata != null) 'metadata': metadata,
    });
  }

  /// Removes a shared device from the running background server.
  static void removeDeviceFromBackgroundServer(String deviceId) {
    sendDataToBackgroundServer({
      'action': 'removeDevice',
      'deviceId': deviceId,
    });
  }

  /// Adds a listener to receive messages and events from the background server.
  static void addMessageCallback(void Function(Object data) callback) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterForegroundTask.addTaskDataCallback(callback);
  }

  /// Removes a message listener.
  static void removeMessageCallback(void Function(Object data) callback) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    FlutterForegroundTask.removeTaskDataCallback(callback);
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
