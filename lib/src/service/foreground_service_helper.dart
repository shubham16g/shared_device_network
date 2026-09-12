import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shared_device_record.dart';
import '../models/status.dart';
import '../server/shared_device_network_server.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final port = prefs.getInt('server_port') ?? 8888;
  final discoveryPort = prefs.getInt('server_discoveryPort') ?? 8889;
  final devicesJson = prefs.getString('server_devices');

  int receivedCount = 0;

  // Helper to persist and broadcast logs
  Future<void> logEvent(String message) async {
    try {
      final logsList = prefs.getStringList('server_recent_logs') ?? <String>[];
      final timestamp = DateTime.now().toIso8601String().substring(11, 19);
      final entry = '[$timestamp] $message';
      logsList.insert(0, entry);
      if (logsList.length > 50) {
        logsList.removeRange(50, logsList.length);
      }
      await prefs.setStringList('server_recent_logs', logsList);
      service.invoke('onLog', {'log': entry});
    } catch (_) {}
  }

  // 1. Instantiate the UDP server inside this persistent background isolate
  late final SharedDeviceUdpServer server;
  server = SharedDeviceUdpServer(
    port: port,
    discoveryPort: discoveryPort,
    autoStartOnFirstDevice: false, // Explicitly managed in background isolate
    autoStopOnEmptyDevices: false, // Explicitly managed in background isolate
    enableForegroundService: false, // Already inside the background isolate
    onDataReceived: (deviceId, message) async {
      receivedCount++;

      final logMsg = 'Received for "$deviceId": "$message"';
      await logEvent(logMsg);

      // Notify main UI isolate if active
      try {
        service.invoke('onDataReceived', {
          'deviceId': deviceId,
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
          'totalCount': receivedCount,
        });
      } catch (_) {}

      // Update Android notification text so activity is visible even when app is killed
      try {
        if (service is AndroidServiceInstance) {
          final count = server.deviceCount;
          service.setForegroundNotificationInfo(
            title: 'Shared Device Server Active',
            content: 'Sharing $count device(s) • Last event for: $deviceId',
          );
        }
      } catch (_) {}

      return Status.success(
        message: 'Processed by background service for device $deviceId',
        data: {
          'deviceId': deviceId,
          'timestamp': DateTime.now().toIso8601String(),
          'totalCount': receivedCount,
        },
      );
    },
  );

  // 2. Load pre-configured shared devices
  if (devicesJson != null && devicesJson.isNotEmpty) {
    try {
      final dynamic list = json.decode(devicesJson);
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final dev = SharedDeviceRecord.fromMap(Map<String, dynamic>.from(item));
            await server.addDevice(
              dev.deviceId,
              dev.deviceName,
              deviceDescription: dev.deviceDescription,
              pairKey: dev.pairKey,
              metadata: dev.metadata,
            );
          }
        }
      }
    } catch (e) {
      await logEvent('Error loading stored devices: $e');
    }
  }

  // Only run if at least one device is shared!
  if (server.deviceCount == 0) {
    await logEvent('No devices shared. Background service stopping.');
    service.stopSelf();
    return;
  }

  // 3. Start the UDP server sockets in background isolate
  try {
    await server.start();
    await logEvent('Background UDP server listening on port $port (Discovery: $discoveryPort)');
  } catch (e) {
    await logEvent('Failed to start UDP sockets: $e');
  }

  // Update notification with initial state
  _updateNotificationText(server, service, port: port);

  // 4. Register event handlers from UI isolate
  service.on('stopService').listen((event) async {
    await logEvent('Service stopped on request');
    await server.stop();
    service.stopSelf();
  });

  service.on('addDevice').listen((map) async {
    if (map == null) return;
    final devId = map['deviceId']?.toString() ?? '';
    final devName = map['deviceName']?.toString() ?? '';
    final desc = map['deviceDescription']?.toString();
    final key = map['pairKey']?.toString();
    Map<String, dynamic>? meta;
    if (map['metadata'] is Map) {
      meta = Map<String, dynamic>.from(map['metadata'] as Map);
    }

    if (devId.isNotEmpty) {
      final wasEmpty = server.deviceCount == 0;
      await server.addDevice(
        devId,
        devName,
        deviceDescription: desc,
        pairKey: key,
        metadata: meta,
      );
      if (wasEmpty || !server.isRunning) {
        try {
          await server.start();
          await logEvent('Background UDP server started for $devName');
        } catch (e) {
          await logEvent('Error starting UDP sockets: $e');
        }
      }
      _persistCurrentDevices(server, prefs);
      _updateNotificationText(server, service, port: port);
      await logEvent('Added shared device: $devName ($devId)');
      service.invoke('devicesUpdated', {
        'devices': server.devices.map((d) => d.toMap()).toList(),
      });
    }
  });

  service.on('removeDevice').listen((map) async {
    if (map == null) return;
    final devId = map['deviceId']?.toString() ?? '';
    if (devId.isNotEmpty) {
      await server.removeDevice(devId);
      _persistCurrentDevices(server, prefs);
      if (server.devices.isEmpty) {
        await logEvent('All devices removed. Stopping background service and UDP server.');
        await server.stop();
        service.stopSelf();
      } else {
        _updateNotificationText(server, service, port: port);
        await logEvent('Removed device: $devId. Remaining: ${server.deviceCount}');
      }
      service.invoke('devicesUpdated', {
        'devices': server.devices.map((d) => d.toMap()).toList(),
      });
    }
  });

  service.on('getDevices').listen((_) {
    service.invoke('devicesUpdated', {
      'devices': server.devices.map((d) => d.toMap()).toList(),
      'isRunning': server.isRunning,
    });
  });

  service.on('updateNotification').listen((map) {
    if (map == null) return;
    if (service is AndroidServiceInstance) {
      final title = map['notificationTitle']?.toString();
      final text = map['notificationText']?.toString();
      if (title != null && text != null) {
        service.setForegroundNotificationInfo(title: title, content: text);
      }
    }
  });
}

void _updateNotificationText(
  SharedDeviceUdpServer server,
  ServiceInstance service, {
  int port = 8888,
}) {
  if (service is AndroidServiceInstance) {
    final count = server.deviceCount;
    if (count == 0) {
      return;
    }
    final dev = server.devices.first;
    final title = count == 1 ? '${dev.deviceName} Active' : 'Shared Device Server ($count Active)';
    final text = 'Sharing $count connected peripheral${count == 1 ? "" : "s"} on network';
    service.setForegroundNotificationInfo(
      title: title,
      content: text,
    );
  }
}

void _persistCurrentDevices(SharedDeviceUdpServer server, SharedPreferences prefs) {
  final list = server.devices.map((d) => d.toMap()).toList();
  prefs.setString('server_devices', json.encode(list));
}

/// Helper to configure, start, and control foreground service execution for background UDP listening.
///
/// Ensures the UDP server keeps running and responding even when the app is swiped away / killed.
class SharedDeviceForegroundService {
  static bool _isInitialized = false;
  static final _service = FlutterBackgroundService();
  static final List<void Function(Object data)> _callbacks = [];
  static final List<void Function(String log)> _logCallbacks = [];
  static final List<void Function(List<SharedDeviceRecord> devices)> _deviceCallbacks = [];

  /// Requests necessary Android runtime permissions (Notification + Battery Optimization Exemption).
  ///
  /// Required on Android 13+ (API 33+) to show notifications and prevent OS from killing background services.
  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    // 1. Request notification permission (Android 13+)
    final notifStatus = await Permission.notification.request();

    // 2. Request battery optimization ignore permission
    try {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}

    return notifStatus.isGranted;
  }

  /// Initializes the foreground service configuration and event listeners.
  static Future<void> init({
    String notificationChannelName = 'Shared Device Network Service',
    String notificationChannelDescription = 'Keeps the Shared Device Network active in background',
    int notificationId = 888,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    if (_isInitialized) return;

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        autoStartOnBoot: false,
        isForegroundMode: true,
        initialNotificationTitle: notificationChannelName,
        initialNotificationContent: notificationChannelDescription,
        foregroundServiceNotificationId: notificationId,
        foregroundServiceTypes: [
          AndroidForegroundType.connectedDevice,
          AndroidForegroundType.dataSync,
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );

    _service.on('onDataReceived').listen((event) {
      if (event != null) {
        final payload = {'event': 'onDataReceived', ...event};
        for (final callback in _callbacks) {
          callback(payload);
        }
      }
    });

    _service.on('onLog').listen((event) {
      if (event != null && event['log'] != null) {
        final log = event['log'].toString();
        for (final callback in _logCallbacks) {
          callback(log);
        }
      }
    });

    _service.on('devicesUpdated').listen((event) {
      if (event != null && event['devices'] is List) {
        final rawList = event['devices'] as List;
        final devices = rawList
            .whereType<Map>()
            .map((m) => SharedDeviceRecord.fromMap(Map<String, dynamic>.from(m)))
            .toList();
        for (final callback in _deviceCallbacks) {
          callback(devices);
        }
      }
    });

    _isInitialized = true;
  }

  /// Adds a shared device to the background isolate server and persists it.
  static Future<bool> addDeviceToBackgroundServer({
    required String deviceId,
    required String deviceName,
    String? deviceDescription,
    String? pairKey,
    Map<String, dynamic>? metadata,
    int port = 8888,
    int discoveryPort = 8889,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    await init();

    final newRecord = SharedDeviceRecord(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceDescription: deviceDescription,
      pairKey: pairKey,
      metadata: metadata,
      addedAt: DateTime.now(),
    );

    // 1. Immediately persist to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('server_port', port);
    await prefs.setInt('server_discoveryPort', discoveryPort);

    final currentDevices = await getStoredDevices();
    final existingIndex = currentDevices.indexWhere((d) => d.deviceId == deviceId);
    if (existingIndex >= 0) {
      currentDevices[existingIndex] = newRecord;
    } else {
      currentDevices.add(newRecord);
    }
    await prefs.setString(
      'server_devices',
      json.encode(currentDevices.map((d) => d.toMap()).toList()),
    );

    // 2. Ensure background service is running
    final isRunningNow = await _service.isRunning();
    if (!isRunningNow) {
      await _service.startService();
      // Allow background isolate brief time to start
      await Future.delayed(const Duration(milliseconds: 300));
    } else {
      // 3. Dispatch to running background isolate
      _service.invoke('addDevice', {
        'deviceId': deviceId,
        'deviceName': deviceName,
        if (deviceDescription != null) 'deviceDescription': deviceDescription,
        if (pairKey != null) 'pairKey': pairKey,
        if (metadata != null) 'metadata': metadata,
      });
    }

    return true;
  }

  /// Removes a shared device from the background server.
  static Future<void> removeDeviceFromBackgroundServer(String deviceId) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // Remove from storage
    final prefs = await SharedPreferences.getInstance();
    final currentDevices = await getStoredDevices();
    currentDevices.removeWhere((d) => d.deviceId == deviceId);
    await prefs.setString(
      'server_devices',
      json.encode(currentDevices.map((d) => d.toMap()).toList()),
    );

    if (currentDevices.isEmpty) {
      await stopService();
      return;
    }

    final isRunning = await _service.isRunning();
    if (!isRunning) return;

    _service.invoke('removeDevice', {
      'deviceId': deviceId,
    });
  }

  /// Starts the UDP server in a dedicated background isolate.
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('server_port', port);
    await prefs.setInt('server_discoveryPort', discoveryPort);
    if (initialDevices != null) {
      final jsonList = json.encode(initialDevices.map((d) => d.toMap()).toList());
      await prefs.setString('server_devices', jsonList);
    }

    if (await _service.isRunning()) {
      return true;
    }

    return await _service.startService();
  }

  /// Starts the foreground service.
  static Future<bool> startService({
    String notificationTitle = 'Shared Device Network Server Active',
    String notificationText = 'Listening for incoming device connections...',
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    await init();

    if (await _service.isRunning()) {
      return true;
    }

    return await _service.startService();
  }

  /// Retrieves the list of currently saved devices from persistent storage.
  static Future<List<SharedDeviceRecord>> getStoredDevices() async {
    if (!Platform.isAndroid && !Platform.isIOS) return [];

    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('server_devices');

    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final dynamic list = json.decode(jsonStr);
      if (list is List) {
        return list
            .whereType<Map>()
            .map((item) => SharedDeviceRecord.fromMap(Map<String, dynamic>.from(item)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Clears stored shared devices from persistent storage.
  static Future<void> clearStoredDevices() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_devices');
  }

  /// Retrieves recent background logs saved in SharedPreferences.
  static Future<List<String>> getStoredLogs() async {
    if (!Platform.isAndroid && !Platform.isIOS) return [];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('server_recent_logs') ?? [];
  }

  /// Clears recent background logs from SharedPreferences.
  static Future<void> clearStoredLogs() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('server_recent_logs');
  }

  /// Sends command/data to the running background server isolate.
  static void sendDataToBackgroundServer(Map<String, dynamic> data) {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final action = data['action']?.toString();
    if (action != null) {
      _service.invoke(action, data);
    }
  }

  /// Adds a listener to receive messages and events from the background server.
  static void addMessageCallback(void Function(Object data) callback) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _callbacks.add(callback);
  }

  /// Removes a message listener.
  static void removeMessageCallback(void Function(Object data) callback) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _callbacks.remove(callback);
  }

  /// Adds a listener to receive background server log lines.
  static void addLogCallback(void Function(String log) callback) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _logCallbacks.add(callback);
  }

  /// Removes a log listener.
  static void removeLogCallback(void Function(String log) callback) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _logCallbacks.remove(callback);
  }

  /// Adds a listener to receive device list changes from background server.
  static void addDeviceCallback(void Function(List<SharedDeviceRecord> devices) callback) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _deviceCallbacks.add(callback);
  }

  /// Removes a device list listener.
  static void removeDeviceCallback(void Function(List<SharedDeviceRecord> devices) callback) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _deviceCallbacks.remove(callback);
  }

  /// Stops the foreground service and removes the ongoing notification.
  static Future<bool> stopService({bool clearDevices = false}) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    if (clearDevices) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('server_devices');
    }

    _service.invoke('stopService');
    return true;
  }

  /// Updates the foreground notification text while running.
  static Future<bool> updateNotification({
    required String notificationTitle,
    required String notificationText,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    _service.invoke('updateNotification', {
      'notificationTitle': notificationTitle,
      'notificationText': notificationText,
    });

    return true;
  }

  /// Returns whether the foreground service is currently running.
  static Future<bool> isRunning() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }
    return await _service.isRunning();
  }
}
