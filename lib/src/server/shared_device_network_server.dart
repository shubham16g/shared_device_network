import 'dart:async';
import 'dart:io';

import '../models/network_packet.dart';
import '../models/shared_device.dart';
import '../models/shared_device_record.dart';
import '../models/shared_device_response.dart';
import '../utils/network_utils.dart';

/// Callback invoked when a message or command is received for a shared connected peripheral.
///
/// Returns a [SharedDeviceResponse], [Map], [bool], or any serializable value.
typedef OnMessageReceivedCallback =
    FutureOr<dynamic> Function(String deviceId, dynamic message);

/// Backward-compatibility alias for [OnMessageReceivedCallback].
typedef OnDataReceivedCallback = OnMessageReceivedCallback;

/// A lightweight, high-performance UDP server running on a host device that shares
/// local connected peripherals (e.g. Bluetooth printers, USB barcode scanners, cash drawers)
/// across the local network.
///
/// ### Quick Start:
/// ```dart
/// final server = SharedDeviceNetworkServer();
///
/// server.onMessageReceived((deviceId, message) async {
///   print('Received command for device $deviceId: $message');
///
///   if (deviceId == 'printer-bt-01') {
///     // Forward print bytes to Bluetooth printer...
///     return SharedDeviceResponse.success(message: 'Receipt printed successfully');
///   } else if (deviceId == 'scanner-usb-01') {
///     // Trigger barcode scan...
///     return SharedDeviceResponse.success(
///       message: 'Scan triggered',
///       data: {'barcode': '890123456789'},
///     );
///   }
///
///   return SharedDeviceResponse.deviceNotFound();
/// });
///
/// await server.start(port: 8888, discoveryPort: 8889);
///
/// await server.addDevice(
///   'printer-bt-01',
///   'Kitchen Bluetooth Printer',
///   deviceDescription: 'Thermal 80mm ESC/POS printer',
/// );
///
/// // await server.removeDevice('printer-bt-01');
/// ```
class SharedDeviceNetworkServer {
  int _port = 8888;
  int _discoveryPort = 8889;

  /// UDP data port for receiving messages and sending ACKs (default: 8888).
  int get port => _port;

  /// UDP discovery port for listening to client broadcast discovery (default: 8889).
  int get discoveryPort => _discoveryPort;

  OnMessageReceivedCallback? _onMessageReceived;

  /// Registers the callback invoked when a message or command is received for a shared connected peripheral.
  void onMessageReceived(OnMessageReceivedCallback callback) {
    _onMessageReceived = callback;
  }

  /// Backward-compatibility alias for [onMessageReceived].
  void onDataReceived(OnMessageReceivedCallback callback) =>
      onMessageReceived(callback);

  RawDatagramSocket? _dataSocket;
  RawDatagramSocket? _discoverySocket;
  bool _isRunning = false;

  /// Map of shared connected devices hosted on this server, keyed by deviceId.
  final Map<String, SharedDeviceRecord> _devices = {};

  /// Controller for broadcasting received network packets to internal listeners.
  final StreamController<NetworkPacket> _messageStreamController =
      StreamController<NetworkPacket>.broadcast();

  /// Creates a new [SharedDeviceNetworkServer] instance.
  ///
  /// Optionally accepts an initial [onMessageReceived] callback, or register
  /// it dynamically using [onMessageReceived(callback)].
  SharedDeviceNetworkServer({OnMessageReceivedCallback? onMessageReceived}) {
    if (onMessageReceived != null) {
      _onMessageReceived = onMessageReceived;
    }
  }

  // ---------------------------------------------------------------------------
  // Instance Properties & Getters
  // ---------------------------------------------------------------------------

  /// Whether the UDP server is currently running and listening on sockets.
  bool get isRunning => _isRunning;

  /// List of currently registered shared connected devices.
  List<SharedDeviceRecord> get devices => List.unmodifiable(_devices.values);

  /// Total count of shared connected devices hosted on this server.
  int get deviceCount => _devices.length;

  /// Stream of incoming valid packets.
  Stream<NetworkPacket> get messageStream => _messageStreamController.stream;

  // ---------------------------------------------------------------------------
  // Device Management
  // ---------------------------------------------------------------------------

  /// Adds a shared connected device to this server.
  ///
  /// Throws [ArgumentError] if [deviceId] is empty or already exists.
  Future<void> addDevice(
    String deviceId,
    String deviceName, {
    String? deviceDescription,
    String? pairKey,
    Map<String, dynamic>? metadata,
  }) async {
    final trimmedId = deviceId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('Device ID cannot be empty');
    }
    if (_devices.containsKey(trimmedId)) {
      throw ArgumentError('Device ID $trimmedId already exists');
    }

    _devices[trimmedId] = SharedDeviceRecord(
      deviceId: trimmedId,
      deviceName: deviceName.trim(),
      deviceDescription: deviceDescription?.trim(),
      pairKey: pairKey,
      metadata: metadata,
      addedAt: DateTime.now(),
    );
  }

  /// Removes a shared connected device from this server.
  Future<void> removeDevice(String deviceId) async {
    final trimmedId = deviceId.trim();
    _devices.remove(trimmedId);
  }

  /// Checks if a device ID is hosted on this server.
  bool hasDevice(String deviceId) => _devices.containsKey(deviceId.trim());

  /// Retrieves a registered shared device record.
  SharedDeviceRecord? getDevice(String deviceId) => _devices[deviceId.trim()];

  // ---------------------------------------------------------------------------
  // Socket Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts listening for UDP discovery and data messages.
  ///
  /// [port] is the UDP data port (default: 8888).
  /// [discoveryPort] is the UDP discovery broadcast port (default: 8889).
  /// Also accepts [discoverPort] as an alias.
  Future<void> start({
    int port = 8888,
    int? discoveryPort,
    int? discoverPort,
  }) async {
    if (_isRunning) return;

    _port = port;
    _discoveryPort = discoveryPort ?? discoverPort ?? 8889;

    try {
      // 1. Bind main data socket
      _dataSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _port,
        reuseAddress: true,
        reusePort: Platform.isIOS || Platform.isMacOS,
      );
      _dataSocket!.broadcastEnabled = true;
      _dataSocket!.listen(_handleDataSocketEvent);

      // 2. Bind discovery socket (if discoveryPort is different from data port)
      if (_discoveryPort != _port) {
        _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _discoveryPort,
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

  /// Stops the server and closes all active sockets.
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

  /// Disposes resources, stops listening, and closes streams.
  Future<void> dispose() async {
    await stop();
    _devices.clear();
    await _messageStreamController.close();
  }

  // ---------------------------------------------------------------------------
  // Socket Event & Packet Handling
  // ---------------------------------------------------------------------------

  void _handleDataSocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read && _dataSocket != null) {
      final datagram = _dataSocket!.receive();
      if (datagram != null) {
        _processIncomingDatagram(datagram, _dataSocket!);
      }
    }
  }

  void _handleDiscoverySocketEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read && _discoverySocket != null) {
      final datagram = _discoverySocket!.receive();
      if (datagram != null) {
        _processIncomingDatagram(datagram, _discoverySocket!);
      }
    }
  }

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

  /// Responds to client discovery request with all active shared peripherals on this server.
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
        devicesToAnnounce.add(
          SharedDevice(
            deviceId: single.deviceId,
            deviceName: single.deviceName,
            deviceDescription: single.deviceDescription,
            deviceIp: localIp,
            devicePort: port,
            metadata: single.metadata,
          ).toMap(),
        );
      }
    } else {
      for (final dev in _devices.values) {
        devicesToAnnounce.add(
          SharedDevice(
            deviceId: dev.deviceId,
            deviceName: dev.deviceName,
            deviceDescription: dev.deviceDescription,
            deviceIp: localIp,
            devicePort: port,
            metadata: dev.metadata,
          ).toMap(),
        );
      }
    }

    if (devicesToAnnounce.isEmpty) return;

    final response = NetworkPacket(
      type: PacketType.discoveryResponse,
      senderDeviceId: 'server-host',
      payload: {'devices': devicesToAnnounce},
    );

    _sendPacketDirect(response, remoteAddress, replyPort);
  }

  /// Handles incoming data message, routes it to target peripheral, and sends back ACK.
  Future<void> _handleMessage(
    NetworkPacket packet,
    InternetAddress remoteAddress,
    int remotePort,
  ) async {
    final messageId = packet.messageId;
    final targetId = packet.targetDeviceId;
    final senderId = packet.senderDeviceId;

    if (messageId == null) return;

    final replyPort = packet.senderPort != null && packet.senderPort! > 0
        ? packet.senderPort!
        : remotePort;

    SharedDeviceRecord? matchedDevice;

    if (targetId != null && targetId.isNotEmpty) {
      matchedDevice = _devices[targetId];
      if (matchedDevice == null) {
        final notFoundStatus = SharedDeviceResponse.deviceNotFound(
          message: 'Device "$targetId" is not hosted on this server.',
        );
        _sendAck(messageId, senderId, notFoundStatus, remoteAddress, replyPort);
        return;
      }
    } else if (_devices.length == 1) {
      matchedDevice = _devices.values.first;
    } else if (_devices.isEmpty) {
      final notFoundStatus = SharedDeviceResponse.deviceNotFound(
        message: 'No shared devices currently registered on this server.',
      );
      _sendAck(messageId, senderId, notFoundStatus, remoteAddress, replyPort);
      return;
    } else {
      final badStatus = SharedDeviceResponse.badRequest(
        message:
            'Multiple devices hosted. Please specify targetDeviceId in message.',
      );
      _sendAck(messageId, senderId, badStatus, remoteAddress, replyPort);
      return;
    }

    // Verify pairKey if configured for this specific peripheral
    if (matchedDevice.pairKey != null && matchedDevice.pairKey!.isNotEmpty) {
      if (packet.pairKey != matchedDevice.pairKey) {
        final unauthStatus = SharedDeviceResponse.unauthorized(
          message:
              'Invalid pair key provided for shared device "${matchedDevice.deviceId}".',
        );
        _sendAck(messageId, senderId, unauthStatus, remoteAddress, replyPort);
        return;
      }
    }

    _messageStreamController.add(packet);

    // Call onMessageReceived callback if registered
    SharedDeviceResponse response;
    final handler = _onMessageReceived;
    if (handler != null) {
      try {
        final result = await handler(matchedDevice.deviceId, packet.payload);

        if (result is SharedDeviceResponse) {
          response = result;
        } else if (result is Map<String, dynamic>) {
          response = SharedDeviceResponse.success(data: result);
        } else if (result is bool) {
          response = result
              ? SharedDeviceResponse.success()
              : SharedDeviceResponse.error('Operation returned false');
        } else if (result == null) {
          response = SharedDeviceResponse.success();
        } else {
          response = SharedDeviceResponse.success(data: result);
        }
      } catch (e) {
        response = SharedDeviceResponse.error(
          e.toString(),
          message:
              'Exception occurred processing message for device "${matchedDevice.deviceId}"',
        );
      }
    } else {
      response = SharedDeviceResponse.deviceNotFound(
        message: 'No message handler registered on server.',
      );
    }

    // Send ACK back to sender
    _sendAck(messageId, senderId, response, remoteAddress, replyPort);
  }

  /// Sends an ACK packet back to sender.
  void _sendAck(
    int messageId,
    String targetDeviceId,
    SharedDeviceResponse status,
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
}
