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
/// Calling [addDevice] registers a shared connected device and automatically starts the UDP server.
/// Calling [removeDevice] removes the device, and automatically stops the UDP server when all devices are removed.
class SharedDeviceNetworkServer {
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

  SharedDeviceNetworkServer({
    required this.onDataReceived,
    this.port = 8888,
    this.discoveryPort = 8889,
    this.autoStartOnFirstDevice = true,
    this.autoStopOnEmptyDevices = true,
    this.enableForegroundService = false,
    this.notificationTitle = 'Shared Device Server Active',
    this.notificationText = 'Sharing connected devices on network...',
  });

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
  /// If the server is not yet running and [autoStartOnFirstDevice] is true,
  /// this automatically starts the UDP server.
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

    // Auto-start server if not already running
    if (!_isRunning && autoStartOnFirstDevice) {
      if (enableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
        await startWithForegroundService(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
        );
      } else {
        await start();
      }
    }

    return true;
  }

  /// Removes a shared connected device from this server.
  ///
  /// If all devices have been removed and [autoStopOnEmptyDevices] is true,
  /// this automatically stops the UDP server.
  Future<bool> removeDevice(String deviceId) async {
    final removed = _devices.remove(deviceId);
    if (removed != null) {
      if (_devices.isEmpty && _isRunning && autoStopOnEmptyDevices) {
        if (enableForegroundService && (Platform.isAndroid || Platform.isIOS)) {
          await stopForegroundService();
        }
        await stop();
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

    try {
      // 1. Bind main data socket
      _dataSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      _dataSocket!.broadcastEnabled = true;
      _dataSocket!.listen(_handleDataSocketEvent);

      // 2. Bind discovery socket (if port is different from data port)
      if (discoveryPort != port) {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true,
          reusePort: !Platform.isWindows,
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
    await start();
    return await SharedDeviceForegroundService.startService(
      notificationTitle: notificationTitle ?? this.notificationTitle,
      notificationText: notificationText ?? this.notificationText,
    );
  }

  /// Stops the foreground service if running.
  Future<bool> stopForegroundService() async {
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
    // If no devices are shared on this server, do not announce
    if (_devices.isEmpty) return;

    final localIp = await NetworkUtils.getPrimaryLocalIPv4();
    final replyPort = packet.senderPort != null && packet.senderPort! > 0
        ? packet.senderPort!
        : remotePort;

    // Check if request was targeted at a specific device ID
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
      // Single device fallback
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
    await stop();
    await _messageStreamController.close();
  }
}
