import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'dart:ui';

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

  // 1. Instantiate UDP server inside background isolate
  late final SharedDeviceNetworkServer server;
  server = SharedDeviceNetworkServer(
    port: port,
    discoveryPort: discoveryPort,
    autoStartOnFirstDevice: true,
    autoStopOnEmptyDevices: true,
    enableForegroundService: false, // Handled by this wrapper
    onDataReceived: (deviceId, message) async {
      receivedCount++;

      // Notify main UI isolate if running
      try {
        service.invoke('onDataReceived', {
          'deviceId': deviceId,
          'message': message,
          'timestamp': DateTime.now().toIso8601String(),
          'totalCount': receivedCount,
        });
      } catch (_) {}

      // Update Android notification text
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
        message: 'Received by background server for device $deviceId',
        data: {
          'deviceId': deviceId,
          'timestamp': DateTime.now().toIso8601String(),
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
    } catch (_) {}
  }

  if (server.deviceCount == 0) {
    // No devices registered; stop the service so notification is not shown
    service.stopSelf();
    return;
  } else {
    _updateNotificationText(server, service);
  }

  service.on('stopService').listen((event) async {
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
      await server.addDevice(
        devId,
        devName,
        deviceDescription: desc,
        pairKey: key,
        metadata: meta,
      );
      _persistCurrentDevices(server, prefs);
      _updateNotificationText(server, service);
    }
  });

  service.on('removeDevice').listen((map) async {
    if (map == null) return;
    final devId = map['deviceId']?.toString() ?? '';
    if (devId.isNotEmpty) {
      await server.removeDevice(devId);
      _persistCurrentDevices(server, prefs);

      if (server.deviceCount == 0) {
        service.stopSelf();
      } else {
        _updateNotificationText(server, service);
      }
    }
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

void _updateNotificationText(SharedDeviceNetworkServer server, ServiceInstance service) {
  if (service is AndroidServiceInstance) {
    final count = server.deviceCount;
    if (count == 0) {
      service.stopSelf();
    } else {
      final dev = server.devices.first;
      final title = count == 1 ? '${dev.deviceName} Active' : 'Shared Device Server ($count Active)';
      final text = 'Sharing $count connected peripheral${count == 1 ? "" : "s"} on network';
      service.setForegroundNotificationInfo(
        title: title,
        content: text,
      );
    }
  }
}

void _persistCurrentDevices(SharedDeviceNetworkServer server, SharedPreferences prefs) {
  final list = server.devices.map((d) => d.toMap()).toList();
  prefs.setString('server_devices', json.encode(list));
}

/// Helper to configure and control foreground service execution for background UDP listening.
class SharedDeviceForegroundService {
  static bool _isInitialized = false;
  static final _service = FlutterBackgroundService();
  static final List<void Function(Object data)> _callbacks = [];

  /// Initializes the foreground task communication channel and notification options.
  static Future<void> init({
    String notificationChannelName = 'Shared Device Network Service',
    String notificationChannelDescription = 'Keeps the Shared Device Network active in background',
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    if (_isInitialized) return;

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        initialNotificationTitle: notificationChannelName,
        initialNotificationContent: notificationChannelDescription,
        foregroundServiceNotificationId: 888,
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

    _isInitialized = true;
  }

  /// Adds a shared device to the background isolate server.
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

    final isRunning = await _service.isRunning();
    final newRecord = SharedDeviceRecord(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceDescription: deviceDescription,
      pairKey: pairKey,
      metadata: metadata,
    );

    if (!isRunning) {
      return await startBackgroundServer(
        port: port,
        discoveryPort: discoveryPort,
        initialDevices: [newRecord],
        notificationTitle: '$deviceName Active',
        notificationText: 'Sharing 1 connected peripheral on network',
      );
    } else {
      _service.invoke('addDevice', {
        'deviceId': deviceId,
        'deviceName': deviceName,
        if (deviceDescription != null) 'deviceDescription': deviceDescription,
        if (pairKey != null) 'pairKey': pairKey,
        if (metadata != null) 'metadata': metadata,
      });
      return true;
    }
  }

  /// Removes a shared device from the background server.
  static Future<void> removeDeviceFromBackgroundServer(String deviceId) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

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
    if (initialDevices != null && initialDevices.isNotEmpty) {
      final jsonList = json.encode(initialDevices.map((d) => d.toMap()).toList());
      await prefs.setString('server_devices', jsonList);
    }

    if (await _service.isRunning()) {
      _service.invoke('stopService');
      await Future.delayed(const Duration(milliseconds: 500));
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

  /// Stops the foreground service and removes the notification.
  static Future<bool> stopService() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
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
