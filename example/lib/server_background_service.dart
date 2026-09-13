import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_device_network/shared_device_network.dart';

/// Default ports for the background service (distinct from foreground server 8888/8889).
const int kDefaultBgServerPort = 9888;
const int kDefaultBgDiscoveryPort = 9889;

const String kNotificationChannelId = 'shared_device_bg_service_channel';
const int kNotificationId = 988;

/// Preference keys for persistence
const String _keyBgPort = 'bg_server_port';
const String _keyBgDiscoveryPort = 'bg_discovery_port';
const String _keyBgDevices = 'bg_server_devices';

// =============================================================================
// Background Service Entry Points (Android / iOS Isolate)
// =============================================================================

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences prefs = await SharedPreferences.getInstance();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  int currentPort = prefs.getInt(_keyBgPort) ?? kDefaultBgServerPort;
  int currentDiscoveryPort =
      prefs.getInt(_keyBgDiscoveryPort) ?? kDefaultBgDiscoveryPort;

  final SharedDeviceNetworkServer server = SharedDeviceNetworkServer();

  void updateNotification({String? customContent}) {
    if (service is AndroidServiceInstance) {
      final content =
          customContent ??
          (server.isRunning
              ? 'Active on :$currentPort (Discovery :$currentDiscoveryPort) • ${server.deviceCount} device(s)'
              : 'Server stopped');
      service.setForegroundNotificationInfo(
        title: 'Shared Device Background Server',
        content: content,
      );
    }
  }

  Future<void> saveDevices() async {
    final list = server.devices.map((d) => d.toJson()).toList();
    await prefs.setStringList(_keyBgDevices, list);
  }

  void broadcastStatus() {
    service.invoke('statusUpdate', {
      'isRunning': server.isRunning,
      'port': currentPort,
      'discoveryPort': currentDiscoveryPort,
      'devices': server.devices.map((d) => d.toMap()).toList(),
    });
  }

  void sendLog(String text) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    service.invoke('log', {'message': text, 'time': time});
  }

  server.onMessageReceived((deviceId, message) async {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    sendLog('📥 [BgService] Received for "$deviceId": $message');

    service.invoke('messageReceived', {
      'deviceId': deviceId,
      'message': message,
      'time': timestamp,
    });

    updateNotification(
      customContent: 'Last message for "$deviceId" at $timestamp',
    );

    return SharedDeviceResponse.success(
      message: 'Processed by Background Service for $deviceId',
      data: {
        'echo': message,
        'serverPort': currentPort,
        'discoveryPort': currentDiscoveryPort,
        'processedInBg': true,
        'time': DateTime.now().toIso8601String(),
      },
    );
  });

  // Restore saved devices
  final savedDevices = prefs.getStringList(_keyBgDevices) ?? [];
  for (final raw in savedDevices) {
    try {
      final record = SharedDeviceRecord.fromJson(raw);
      await server.addDevice(
        record.deviceId,
        record.deviceName,
        deviceDescription: record.deviceDescription,
        pairKey: record.pairKey,
        metadata: record.metadata,
      );
    } catch (_) {}
  }

  Future<void> startServer(int port, int discoveryPort) async {
    try {
      if (server.isRunning) {
        await server.stop();
      }
      currentPort = port;
      currentDiscoveryPort = discoveryPort;
      await prefs.setInt(_keyBgPort, currentPort);
      await prefs.setInt(_keyBgDiscoveryPort, currentDiscoveryPort);

      await server.start(
        port: currentPort,
        discoveryPort: currentDiscoveryPort,
      );
      sendLog(
        '🚀 Background Server running on port $currentPort (discovery: $currentDiscoveryPort)',
      );
      updateNotification();
      broadcastStatus();
    } catch (e) {
      sendLog('❌ Background Server failed to start: $e');
      updateNotification(customContent: 'Failed to start: $e');
      broadcastStatus();
    }
  }

  await startServer(currentPort, currentDiscoveryPort);

  service.on('requestStatus').listen((_) {
    broadcastStatus();
  });

  service.on('startServer').listen((data) async {
    final port = (data?['port'] as int?) ?? currentPort;
    final discoveryPort =
        (data?['discoveryPort'] as int?) ?? currentDiscoveryPort;
    await startServer(port, discoveryPort);
  });

  service.on('stopServer').listen((_) async {
    if (server.isRunning) {
      await server.stop();
      sendLog('⏹️ Background Server stopped');
      updateNotification();
      broadcastStatus();
    }
  });

  service.on('addDevice').listen((data) async {
    if (data == null) return;
    try {
      final id = data['deviceId']?.toString() ?? '';
      final name = data['deviceName']?.toString() ?? '';
      final desc = data['deviceDescription']?.toString();
      final key = data['pairKey']?.toString();
      if (id.isNotEmpty && name.isNotEmpty) {
        if (!server.hasDevice(id)) {
          await server.addDevice(
            id,
            name,
            deviceDescription: desc,
            pairKey: key,
          );
          await saveDevices();
          sendLog('✅ [BgService] Added device: $name ($id)');
          updateNotification();
          broadcastStatus();
        }
      }
    } catch (e) {
      sendLog('❌ Error adding device: $e');
    }
  });

  service.on('removeDevice').listen((data) async {
    if (data == null) return;
    try {
      final id = data['deviceId']?.toString() ?? '';
      if (id.isNotEmpty) {
        await server.removeDevice(id);
        await saveDevices();
        sendLog('🗑️ [BgService] Removed device: $id');
        updateNotification();
        broadcastStatus();
      }
    } catch (e) {
      sendLog('❌ Error removing device: $e');
    }
  });

  service.on('stopService').listen((_) async {
    if (server.isRunning) {
      await server.stop();
    }
    sendLog('🛑 Background service stopped');
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// =============================================================================
// Background Service Controller (Client / UI Interface)
// =============================================================================

class ServerBackgroundServiceController {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _isInitialized = false;

  static bool get isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Initialize the background service configuration.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    if (isMobilePlatform) {
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          autoStartOnBoot: false,
          isForegroundMode: true,
          notificationChannelId: kNotificationChannelId,
          initialNotificationTitle: 'Shared Device Service',
          initialNotificationContent:
              'Shared Device background server is running',
          foregroundServiceNotificationId: kNotificationId,
          foregroundServiceTypes: [
            AndroidForegroundType.connectedDevice,
            AndroidForegroundType.dataSync,
          ],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onStart,
          onBackground: onIosBackground,
        ),
      );
    }
    _isInitialized = true;
  }

  /// Request notification permission (required on Android 13+).
  static Future<bool> requestNotificationPermission() async {
    if (isMobilePlatform) {
      final status = await Permission.notification.request();
      return status.isGranted;
    }
    return true;
  }

  /// Check whether the background server service is actively running.
  static Future<bool> isRunning() async {
    if (isMobilePlatform) {
      return await _service.isRunning();
    }
    return _DesktopFallbackServer.isRunning;
  }

  /// Starts the background server with distinct ports (default: 9888 & 9889).
  static Future<bool> start({
    int port = kDefaultBgServerPort,
    int discoveryPort = kDefaultBgDiscoveryPort,
  }) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBgPort, port);
    await prefs.setInt(_keyBgDiscoveryPort, discoveryPort);

    if (isMobilePlatform) {
      final running = await _service.isRunning();
      if (!running) {
        return await _service.startService();
      } else {
        _service.invoke('startServer', {
          'port': port,
          'discoveryPort': discoveryPort,
        });
        return true;
      }
    } else {
      return await _DesktopFallbackServer.start(
        port: port,
        discoveryPort: discoveryPort,
      );
    }
  }

  /// Stops the background server and shuts down the service.
  static Future<void> stop() async {
    if (isMobilePlatform) {
      _service.invoke('stopService');
    } else {
      await _DesktopFallbackServer.stop();
    }
  }

  /// Requests the current state from the service (responds via [onStatusUpdate]).
  static void requestStatus() {
    if (isMobilePlatform) {
      _service.invoke('requestStatus');
    } else {
      _DesktopFallbackServer.broadcastStatus();
    }
  }

  /// Adds a shared connected device to the background server.
  static void addDevice({
    required String deviceId,
    required String deviceName,
    String? deviceDescription,
    String? pairKey,
  }) {
    if (isMobilePlatform) {
      _service.invoke('addDevice', {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceDescription': deviceDescription,
        'pairKey': pairKey,
      });
    } else {
      _DesktopFallbackServer.addDevice(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceDescription: deviceDescription,
        pairKey: pairKey,
      );
    }
  }

  /// Removes a shared device from the background server by its ID.
  static void removeDevice(String deviceId) {
    if (isMobilePlatform) {
      _service.invoke('removeDevice', {'deviceId': deviceId});
    } else {
      _DesktopFallbackServer.removeDevice(deviceId);
    }
  }

  /// Stream of status updates emitted by the background server.
  static Stream<Map<String, dynamic>?> get onStatusUpdate {
    if (isMobilePlatform) {
      return _service.on('statusUpdate');
    }
    return _DesktopFallbackServer.statusStream;
  }

  /// Stream of log messages from the background server.
  static Stream<Map<String, dynamic>?> get onLog {
    if (isMobilePlatform) {
      return _service.on('log');
    }
    return _DesktopFallbackServer.logStream;
  }

  /// Stream of packet received events from the background server.
  static Stream<Map<String, dynamic>?> get onMessageReceived {
    if (isMobilePlatform) {
      return _service.on('messageReceived');
    }
    return _DesktopFallbackServer.messageStream;
  }
}

// =============================================================================
// Desktop / Fallback Server for Non-Mobile Environments (Windows/macOS/Linux)
// =============================================================================

class _DesktopFallbackServer {
  static SharedDeviceNetworkServer? _server;
  static int _port = kDefaultBgServerPort;
  static int _discoveryPort = kDefaultBgDiscoveryPort;

  static final StreamController<Map<String, dynamic>?> _statusCtrl =
      StreamController<Map<String, dynamic>?>.broadcast();
  static final StreamController<Map<String, dynamic>?> _logCtrl =
      StreamController<Map<String, dynamic>?>.broadcast();
  static final StreamController<Map<String, dynamic>?> _msgCtrl =
      StreamController<Map<String, dynamic>?>.broadcast();

  static Stream<Map<String, dynamic>?> get statusStream => _statusCtrl.stream;
  static Stream<Map<String, dynamic>?> get logStream => _logCtrl.stream;
  static Stream<Map<String, dynamic>?> get messageStream => _msgCtrl.stream;

  static bool get isRunning => _server?.isRunning ?? false;

  static void broadcastStatus() {
    _statusCtrl.add({
      'isRunning': isRunning,
      'port': _port,
      'discoveryPort': _discoveryPort,
      'devices': _server?.devices.map((d) => d.toMap()).toList() ?? [],
    });
  }

  static void _log(String message) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    _logCtrl.add({'message': message, 'time': time});
  }

  static Future<bool> start({required int port, required int discoveryPort}) async {
    _port = port;
    _discoveryPort = discoveryPort;

    if (_server != null && _server!.isRunning) {
      await _server!.stop();
    }

    _server = SharedDeviceNetworkServer();
    _server!.onMessageReceived((deviceId, message) async {
      final time = DateTime.now().toIso8601String().substring(11, 19);
      _log('📥 [BgFallback] Received for "$deviceId": $message');
      _msgCtrl.add({'deviceId': deviceId, 'message': message, 'time': time});

      return SharedDeviceResponse.success(
        message: 'Processed by Background Server for $deviceId',
        data: {
          'echo': message,
          'serverPort': _port,
          'discoveryPort': _discoveryPort,
          'time': DateTime.now().toIso8601String(),
        },
      );
    });

    try {
      await _server!.start(port: _port, discoveryPort: _discoveryPort);
      _log('🚀 Background Server running on port $_port (discovery: $_discoveryPort)');
      broadcastStatus();
      return true;
    } catch (e) {
      _log('❌ Failed to start background server: $e');
      broadcastStatus();
      return false;
    }
  }

  static Future<void> stop() async {
    if (_server != null) {
      await _server!.stop();
      _log('⏹️ Background Server stopped');
      broadcastStatus();
    }
  }

  static Future<void> addDevice({
    required String deviceId,
    required String deviceName,
    String? deviceDescription,
    String? pairKey,
  }) async {
    if (_server != null && !_server!.hasDevice(deviceId)) {
      await _server!.addDevice(
        deviceId,
        deviceName,
        deviceDescription: deviceDescription,
        pairKey: pairKey,
      );
      _log('✅ [BgFallback] Added device: $deviceName ($deviceId)');
      broadcastStatus();
    }
  }

  static Future<void> removeDevice(String deviceId) async {
    if (_server != null) {
      await _server!.removeDevice(deviceId);
      _log('🗑️ [BgFallback] Removed device: $deviceId');
      broadcastStatus();
    }
  }
}
