import 'dart:async';
import 'dart:io';

import '../models/network_packet.dart';
import '../models/shared_device.dart';
import '../models/shared_device_record.dart';
import '../models/status.dart';
import '../utils/network_utils.dart';
import '../service/foreground_service_helper.dart';

/// Callback invoked when a message is received for a shared connected device.
typedef OnDataReceivedCallback = Future<Status> Function(
  String deviceId,
  dynamic message,
);

/// A UDP server running on a host device that shares local connected peripherals
/// (e.g. Bluetooth printers, USB scanners, cash drawers) across the local network.
///
/// - Calling [addDevice] registers a shared connected device, automatically starts the UDP server,
///   and starts the Android/iOS foreground service (displaying the notification).
/// - Calling [removeDevice] removes the device, and when all devices are removed, automatically
///   stops the UDP server and terminates the foreground service (removing the notification).
class SharedDeviceNetworkServer {
  // ==========================================
  // STATIC API
  // ==========================================

  static int _staticPort = 8888;
  static int _staticDiscoveryPort = 8889;
  static String _staticNotificationTitle = 'Shared Device Server Active';
  static String _staticNotificationText = 'Sharing connected devices on network...';
  static bool _staticEnableForegroundService = true;

  static FutureOr<dynamic> Function(String deviceId, dynamic message)? _globalDataCallback;
  static final Map<String, SharedDeviceRecord> _staticDevices = {};
  static final _staticMessageController = StreamController<NetworkPacket>.broadcast();
  static final _staticDevicesController = StreamController<List<SharedDeviceRecord>>.broadcast();
  static final _staticLogController = StreamController<String>.broadcast();
  static final List<void Function(String log)> _staticLogCallbacks = [];
  static SharedDeviceUdpServer? _staticLocalServer;

  /// Initializes the server settings and Android foreground service configuration.
  ///
  /// Note: This method does NOT start the UDP server or display the notification.
  /// The server sockets and foreground notification will only start when the first device
  /// is added via [addDevice].
  static Future<void> init({
    int port = 8888,
    int discoveryPort = 8889,
    String notificationChannelName = 'Shared Device Network Service',
    String notificationChannelDescription = 'Keeps the Shared Device Network active in background',
    int notificationId = 888,
    String notificationTitle = 'Shared Device Server Active',
    String notificationText = 'Sharing connected devices on network...',
    bool enableForegroundService = true,
  }) async {
    _staticPort = port;
    _staticDiscoveryPort = discoveryPort;
    _staticNotificationTitle = notificationTitle;
    _staticNotificationText = notificationText;
    _staticEnableForegroundService = enableForegroundService;

    _staticDevices.clear();
    _staticDevicesController.add(devices);

    if (enableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      await SharedDeviceForegroundService.init(
        notificationChannelName: notificationChannelName,
        notificationChannelDescription: notificationChannelDescription,
        notificationId: notificationId,
      );

      // Never auto-add devices or auto-start server/notification on startup
      await SharedDeviceForegroundService.clearStoredDevices();
      await SharedDeviceForegroundService.stopService();

      SharedDeviceForegroundService.addMessageCallback(_handleStaticBackgroundMessage);
      SharedDeviceForegroundService.addLogCallback(_handleStaticBackgroundLog);
      SharedDeviceForegroundService.addDeviceCallback(_handleStaticDevicesUpdated);
    }
  }

  /// Registers the handler for data/commands received for any shared peripheral device.
  ///
  /// The [callback] can return a [Status], a custom data payload (e.g. [Map] or [String]),
  /// or void. If void or null is returned, a successful [Status] is automatically sent back to the client.
  static void onDataReceived(FutureOr<dynamic> Function(String deviceId, dynamic message) callback) {
    _globalDataCallback = callback;
  }

  /// Adds a shared connected peripheral device.
  ///
  /// Automatically starts the UDP server and displays the foreground notification
  /// when the first device is added.
  static Future<bool> addDevice(
    String deviceId,
    String deviceName, {
    String? deviceDescription,
    String? pairKey,
    Map<String, dynamic>? metadata,
  }) async {
    if (deviceId.trim().isEmpty) return false;

    final record = SharedDeviceRecord(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceDescription: deviceDescription,
      pairKey: pairKey,
      metadata: metadata,
      addedAt: DateTime.now(),
    );
    _staticDevices[deviceId] = record;
    _staticDevicesController.add(devices);

    if (_staticEnableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      return await SharedDeviceForegroundService.addDeviceToBackgroundServer(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceDescription: deviceDescription,
        pairKey: pairKey,
        metadata: metadata,
        port: _staticPort,
        discoveryPort: _staticDiscoveryPort,
      );
    }

    _ensureLocalServer();
    if (!_staticLocalServer!.hasDevice(deviceId)) {
      await _staticLocalServer!.addDevice(
        deviceId,
        deviceName,
        deviceDescription: deviceDescription,
        pairKey: pairKey,
        metadata: metadata,
      );
    }
    return true;
  }

  /// Removes a shared connected device.
  ///
  /// When all devices are removed, automatically stops the UDP server and
  /// terminates the foreground notification.
  static Future<bool> removeDevice(String deviceId) async {
    final removed = _staticDevices.remove(deviceId);
    _staticDevicesController.add(devices);

    if (_staticEnableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      await SharedDeviceForegroundService.removeDeviceFromBackgroundServer(deviceId);
      return removed != null;
    }

    if (_staticLocalServer != null) {
      await _staticLocalServer!.removeDevice(deviceId);
      if (_staticDevices.isEmpty) {
        await _staticLocalServer!.stop();
      }
    }
    return removed != null;
  }

  /// List of currently registered shared connected devices.
  static List<SharedDeviceRecord> get devices => _staticDevices.values.toList();

  /// Total count of shared connected devices hosted on this server.
  static int get deviceCount => _staticDevices.length;

  /// Checks if a device ID is currently registered.
  static bool hasDevice(String deviceId) => _staticDevices.containsKey(deviceId);

  /// Retrieves a registered shared device record.
  static SharedDeviceRecord? getDevice(String deviceId) => _staticDevices[deviceId];

  /// Whether the server is currently running with at least one active shared device.
  static bool get isRunning {
    if (_staticDevices.isEmpty) return false;
    if (_staticLocalServer != null && _staticLocalServer!.isRunning) return true;
    return _staticDevices.isNotEmpty;
  }

  /// Asynchronously checks whether the foreground service / server is active.
  static Future<bool> isServiceRunning() async {
    if (_staticDevices.isEmpty) return false;
    if (Platform.isAndroid || Platform.isIOS) {
      return await SharedDeviceForegroundService.isRunning();
    }
    return _staticLocalServer?.isRunning ?? false;
  }

  /// Requests necessary Android runtime permissions (Notification + Battery Optimization Exemption).
  static Future<bool> requestPermissions() async {
    return await SharedDeviceForegroundService.requestPermissions();
  }

  /// Manually stops the server and terminates the foreground service notification.
  static Future<void> stop() async {
    if (_staticEnableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      await SharedDeviceForegroundService.stopService();
    }
    if (_staticLocalServer != null) {
      await _staticLocalServer!.stop();
    }
  }

  /// Stream of incoming valid packets.
  static Stream<NetworkPacket> get messageStream => _staticMessageController.stream;

  /// Stream of shared device list updates.
  static Stream<List<SharedDeviceRecord>> get devicesStream => _staticDevicesController.stream;

  /// Stream of server log messages.
  static Stream<String> get logStream => _staticLogController.stream;

  /// Retrieves stored background logs.
  static Future<List<String>> getLogs() async {
    return await SharedDeviceForegroundService.getStoredLogs();
  }

  /// Clears stored background logs.
  static Future<void> clearLogs() async {
    await SharedDeviceForegroundService.clearStoredLogs();
  }

  /// Adds a callback to listen to server logs.
  static void onLog(void Function(String log) callback) {
    _staticLogCallbacks.add(callback);
    if (Platform.isAndroid || Platform.isIOS) {
      SharedDeviceForegroundService.addLogCallback(callback);
    }
  }

  /// Removes a log listener callback.
  static void removeLogCallback(void Function(String log) callback) {
    _staticLogCallbacks.remove(callback);
    if (Platform.isAndroid || Platform.isIOS) {
      SharedDeviceForegroundService.removeLogCallback(callback);
    }
  }

  static void _ensureLocalServer() {
    _staticLocalServer ??= SharedDeviceUdpServer(
      port: _staticPort,
      discoveryPort: _staticDiscoveryPort,
      autoStartOnFirstDevice: true,
      autoStopOnEmptyDevices: true,
      enableForegroundService: false,
      notificationTitle: _staticNotificationTitle,
      notificationText: _staticNotificationText,
      onDataReceived: _dispatchDataReceived,
    );
  }

  static Future<Status> _dispatchDataReceived(String deviceId, dynamic message) async {
    if (_globalDataCallback == null) {
      return Status.success(
        message: 'Received for $deviceId',
        data: {'deviceId': deviceId},
      );
    }
    try {
      final res = await _globalDataCallback!(deviceId, message);
      if (res is Status) {
        return res;
      }
      return Status.success(
        message: 'Processed by shared device $deviceId',
        data: res,
      );
    } catch (e) {
      return Status.error(
        e.toString(),
        message: 'Exception in onDataReceived for device "$deviceId"',
      );
    }
  }

  static void _handleStaticBackgroundMessage(Object data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['event'] == 'onDataReceived') {
        final devId = map['deviceId']?.toString() ?? '';
        final payload = map['message'];
        _dispatchDataReceived(devId, payload);
      }
    }
  }

  static void _handleStaticBackgroundLog(String log) {
    _staticLogController.add(log);
  }

  static void _handleStaticDevicesUpdated(List<SharedDeviceRecord> updatedDevices) {
    _staticDevices.clear();
    for (final dev in updatedDevices) {
      _staticDevices[dev.deviceId] = dev;
    }
    _staticDevicesController.add(updatedDevices);
  }

  /// Resets static state (primarily for tests).
  static void resetStaticState() {
    _staticDevices.clear();
    _globalDataCallback = null;
    _staticLocalServer?.stop();
    _staticLocalServer = null;
  }
}

/// A UDP server running on a host device that shares local connected peripherals
/// (e.g. Bluetooth printers, USB scanners, cash drawers) across the local network.
class SharedDeviceUdpServer {
  /// Main UDP data port for receiving messages and sending ACKs (default: 8888).
  final int port;

  /// UDP discovery port for listening to client broadcast discovery (default: 8889).
  final int discoveryPort;

  /// Callback executed when data is received from a client for any hosted device.
  final OnDataReceivedCallback onDataReceived;

  /// Whether to automatically start listening when the first device is added (default: true).
  final bool autoStartOnFirstDevice;

  /// Whether to automatically stop the server when all devices are removed (default: true).
  final bool autoStopOnEmptyDevices;

  /// Whether to use the Android/iOS foreground service when running (default: false).
  final bool enableForegroundService;

  /// Notification title when foreground service is active.
  final String notificationTitle;

  /// Notification text when foreground service is active.
  final String notificationText;

  RawDatagramSocket? _dataSocket;
  RawDatagramSocket? _discoverySocket;
  bool _isRunning = false;

  /// Map of shared connected devices hosted on this server, keyed by deviceId.
  final Map<String, SharedDeviceRecord> _devices = {};

  /// Controller for broadcasting received messages to listeners.
  final _messageStreamController = StreamController<NetworkPacket>.broadcast();

  SharedDeviceUdpServer({
    required this.onDataReceived,
    this.port = 8888,
    this.discoveryPort = 8889,
    this.autoStartOnFirstDevice = true,
    this.autoStopOnEmptyDevices = true,
    this.enableForegroundService = false,
    this.notificationTitle = 'Shared Device Server Active',
    this.notificationText = 'Sharing connected devices on network...',
  }) {
    if (enableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      SharedDeviceForegroundService.addMessageCallback(_handleBackgroundDataCallback);
    }
  }

  void _handleBackgroundDataCallback(Object data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['event'] == 'onDataReceived') {
        final devId = map['deviceId']?.toString() ?? '';
        final payload = map['message'];
        onDataReceived(devId, payload);
      }
    }
  }

  /// Whether the UDP server is currently running and listening on sockets.
  bool get isRunning => _isRunning;

  /// List of currently registered shared connected devices.
  List<SharedDeviceRecord> get devices => _devices.values.toList();

  /// Total count of shared connected devices hosted on this server.
  int get deviceCount => _devices.length;

  /// Stream of incoming valid packets.
  Stream<NetworkPacket> get messageStream => _messageStreamController.stream;

  /// Adds a shared connected device to this server.
  ///
  /// Automatically starts the UDP server (and foreground service notification if enabled) on the first device.
  Future<bool> addDevice(
    String deviceId,
    String deviceName, {
    String? deviceDescription,
    String? pairKey,
    Map<String, dynamic>? metadata,
  }) async {
    if (deviceId.trim().isEmpty) return false;

    _devices[deviceId] = SharedDeviceRecord(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceDescription: deviceDescription,
      pairKey: pairKey,
      metadata: metadata,
      addedAt: DateTime.now(),
    );

    if (enableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      _isRunning = true;
      return await SharedDeviceForegroundService.addDeviceToBackgroundServer(
        deviceId: deviceId,
        deviceName: deviceName,
        deviceDescription: deviceDescription,
        pairKey: pairKey,
        metadata: metadata,
        port: port,
        discoveryPort: discoveryPort,
      );
    }

    // Auto-start local UDP server if not already running
    if (!_isRunning && autoStartOnFirstDevice) {
      await start();
    }

    return true;
  }

  /// Removes a shared connected device from this server.
  ///
  /// If all devices have been removed, automatically stops the UDP server
  /// and removes the foreground notification.
  Future<bool> removeDevice(String deviceId) async {
    final removed = _devices.remove(deviceId);
    if (enableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      await SharedDeviceForegroundService.removeDeviceFromBackgroundServer(deviceId);
      if (_devices.isEmpty && autoStopOnEmptyDevices) {
        _isRunning = false;
        await SharedDeviceForegroundService.stopService();
      }
      return true;
    }

    if (removed != null) {
      if (_devices.isEmpty) {
        if (autoStopOnEmptyDevices) {
          await stop();
        }
      }
      return true;
    }
    return false;
  }

  /// Checks if a device ID is hosted on this server.
  bool hasDevice(String deviceId) => _devices.containsKey(deviceId);

  /// Retrieves a registered shared device record.
  SharedDeviceRecord? getDevice(String deviceId) => _devices[deviceId];

  /// Starts listening for UDP discovery and data messages.
  Future<void> start() async {
    if (_isRunning) return;

    if (enableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      _isRunning = true;
      await SharedDeviceForegroundService.startBackgroundServer(
        port: port,
        discoveryPort: discoveryPort,
        initialDevices: _devices.values.toList(),
        notificationTitle: notificationTitle,
        notificationText: notificationText,
      );
      return;
    }

    try {
      // 1. Bind main data socket
      _dataSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: Platform.isIOS || Platform.isMacOS,
      );
      _dataSocket!.broadcastEnabled = true;
      _dataSocket!.listen(_handleDataSocketEvent);

      // 2. Bind discovery socket (if port is different from data port)
      if (discoveryPort != port) {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true,
          reusePort: Platform.isIOS || Platform.isMacOS,
        );
        _discoverySocket!.broadcastEnabled = true;
        _discoverySocket!.listen(_handleDiscoverySocketEvent);
      }

      _isRunning = true;
    } catch (e) {
      await stop();
      rethrow;
    }
  }

  /// Starts the server with an Android/iOS foreground service.
  Future<bool> startWithForegroundService({
    String? notificationTitle,
    String? notificationText,
  }) async {
    _isRunning = true;
    return await SharedDeviceForegroundService.startBackgroundServer(
      port: port,
      discoveryPort: discoveryPort,
      initialDevices: _devices.values.toList(),
      notificationTitle: notificationTitle ?? this.notificationTitle,
      notificationText: notificationText ?? this.notificationText,
    );
  }

  /// Stops the foreground service if running, removing the notification.
  Future<bool> stopForegroundService() async {
    _isRunning = false;
    return await SharedDeviceForegroundService.stopService();
  }

  /// Handles incoming datagrams on the data socket.
  void _handleDataSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read && _dataSocket != null) {
      final datagram = _dataSocket!.receive();
      if (datagram != null) {
        _processIncomingDatagram(datagram, _dataSocket!);
      }
    }
  }

  /// Handles incoming datagrams on the discovery socket.
  void _handleDiscoverySocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read && _discoverySocket != null) {
      final datagram = _discoverySocket!.receive();
      if (datagram != null) {
        _processIncomingDatagram(datagram, _discoverySocket!);
      }
    }
  }

  /// Processes an incoming datagram.
  Future<void> _processIncomingDatagram(
    Datagram datagram,
    RawDatagramSocket sourceSocket,
  ) async {
    final senderIp = datagram.address.address;
    final senderPort = datagram.port;

    final packet = NetworkPacket.fromUtf8Bytes(
      datagram.data,
      senderIp: senderIp,
      senderPort: senderPort,
    );

    if (packet == null) return;

    switch (packet.type) {
      case PacketType.discoveryRequest:
        await _handleDiscoveryRequest(packet, datagram.address, senderPort);
        break;

      case PacketType.message:
        await _handleMessage(packet, datagram.address, senderPort);
        break;

      case PacketType.ack:
        _messageStreamController.add(packet);
        break;

      case PacketType.discoveryResponse:
        break;
    }
  }

  /// Responds to a discovery request with all active shared connected devices on this server.
  Future<void> _handleDiscoveryRequest(
    NetworkPacket packet,
    InternetAddress remoteAddress,
    int remotePort,
  ) async {
    if (_devices.isEmpty) return;

    final localIp = await NetworkUtils.getPrimaryLocalIPv4();
    final replyPort = packet.senderPort != null && packet.senderPort! > 0
        ? packet.senderPort!
        : remotePort;

    final targetedId = packet.targetDeviceId;
    final List<Map<String, dynamic>> devicesToAnnounce = [];

    if (targetedId != null && targetedId.isNotEmpty) {
      final single = _devices[targetedId];
      if (single != null) {
        devicesToAnnounce.add(SharedDevice(
          deviceId: single.deviceId,
          deviceName: single.deviceName,
          deviceDescription: single.deviceDescription,
          deviceIp: localIp,
          devicePort: port,
          metadata: single.metadata,
        ).toMap());
      }
    } else {
      for (final dev in _devices.values) {
        devicesToAnnounce.add(SharedDevice(
          deviceId: dev.deviceId,
          deviceName: dev.deviceName,
          deviceDescription: dev.deviceDescription,
          deviceIp: localIp,
          devicePort: port,
          metadata: dev.metadata,
        ).toMap());
      }
    }

    if (devicesToAnnounce.isEmpty) return;

    final response = NetworkPacket(
      type: PacketType.discoveryResponse,
      senderDeviceId: 'server-host',
      payload: {
        'devices': devicesToAnnounce,
      },
    );

    _sendPacketDirect(response, remoteAddress, replyPort);
  }

  /// Handles incoming data message, routes it to the specific deviceId, and sends back ACK.
  Future<void> _handleMessage(
    NetworkPacket packet,
    InternetAddress remoteAddress,
    int remotePort,
  ) async {
    final messageId = packet.messageId;
    final targetId = packet.targetDeviceId;
    final senderId = packet.senderDeviceId;

    if (messageId == null) return;

    SharedDeviceRecord? matchedDevice;

    if (targetId != null && targetId.isNotEmpty) {
      matchedDevice = _devices[targetId];
      if (matchedDevice == null) {
        final notFoundStatus = Status.deviceNotFound(
          message: 'Device "$targetId" is not hosted on this server.',
        );
        _sendAck(messageId, senderId, notFoundStatus, remoteAddress, packet.senderPort ?? remotePort);
        return;
      }
    } else if (_devices.length == 1) {
      matchedDevice = _devices.values.first;
    } else {
      final badStatus = Status.badRequest(
        message: 'Multiple devices hosted. Please specify targetDeviceId in message.',
      );
      _sendAck(messageId, senderId, badStatus, remoteAddress, packet.senderPort ?? remotePort);
      return;
    }

    // Verify pairKey if configured on this specific shared device
    if (matchedDevice.pairKey != null && matchedDevice.pairKey!.isNotEmpty) {
      if (packet.pairKey != matchedDevice.pairKey) {
        final unauthStatus = Status.unauthorized(
          message: 'Invalid pair key provided for shared device "${matchedDevice.deviceId}".',
        );
        _sendAck(messageId, senderId, unauthStatus, remoteAddress, packet.senderPort ?? remotePort);
        return;
      }
    }

    _messageStreamController.add(packet);

    // Call onDataReceived for this specific device
    Status status;
    try {
      status = await onDataReceived(matchedDevice.deviceId, packet.payload);
    } catch (e) {
      status = Status.error(
        e.toString(),
        message: 'Exception occurred processing message for device "${matchedDevice.deviceId}"',
      );
    }

    // Send ACK back to sender
    final replyPort = packet.senderPort != null && packet.senderPort! > 0
        ? packet.senderPort!
        : remotePort;

    _sendAck(messageId, senderId, status, remoteAddress, replyPort);
  }

  /// Sends an ACK packet back to sender.
  void _sendAck(
    int messageId,
    String targetDeviceId,
    Status status,
    InternetAddress remoteAddress,
    int remotePort,
  ) {
    final ackPacket = NetworkPacket.ack(
      messageId: messageId,
      senderDeviceId: 'server-host',
      targetDeviceId: targetDeviceId,
      status: status,
    );

    _sendPacketDirect(ackPacket, remoteAddress, remotePort);
  }

  /// Sends a packet directly to destination IP and port.
  void _sendPacketDirect(
    NetworkPacket packet,
    InternetAddress destinationAddress,
    int destinationPort,
  ) {
    try {
      final bytes = packet.toUtf8Bytes();
      final socket = _dataSocket ?? _discoverySocket;
      if (socket != null) {
        socket.send(bytes, destinationAddress, destinationPort);
      }
    } catch (_) {}
  }

  /// Stops the server and closes all sockets.
  Future<void> stop() async {
    _isRunning = false;

    try {
      _dataSocket?.close();
    } catch (_) {}
    _dataSocket = null;

    try {
      _discoverySocket?.close();
    } catch (_) {}
    _discoverySocket = null;
  }

  /// Disposes resources and stream controllers.
  Future<void> dispose() async {
    if (enableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
      SharedDeviceForegroundService.removeMessageCallback(_handleBackgroundDataCallback);
    }
    await stop();
    await _messageStreamController.close();
  }
}
