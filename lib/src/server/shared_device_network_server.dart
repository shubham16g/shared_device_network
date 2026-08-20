import 'dart:async';
import 'dart:io';

import '../models/network_packet.dart';
import '../models/paired_device.dart';
import '../models/shared_device.dart';
import '../models/status.dart';
import '../utils/network_utils.dart';
import '../service/foreground_service_helper.dart';
import 'server_config.dart';

/// Callback invoked when a message is received from a device.
typedef OnDataReceivedCallback = Future<Status> Function(
  String deviceId,
  dynamic message,
);

/// A UDP server that provides local network discovery, paired device management,
/// and incremental ACK message handling with optional foreground service execution.
class SharedDeviceNetworkServer {
  /// Unique identifier of this server device.
  final String deviceId;

  /// Human-readable name of this server device.
  final String deviceName;

  /// Optional description for this server device.
  final String? deviceDescription;

  /// Main UDP data port.
  final int port;

  /// UDP discovery port.
  final int discoveryPort;

  /// Optional default pair key.
  final String? defaultPairKey;

  /// Whether registration / pair key is required to accept incoming messages.
  final bool requirePairKey;

  /// Callback executed when data is received from a client device.
  final OnDataReceivedCallback onDataReceived;

  /// Metadata included in discovery responses.
  final Map<String, dynamic>? metadata;

  RawDatagramSocket? _dataSocket;
  RawDatagramSocket? _discoverySocket;
  bool _isRunning = false;

  /// Map of paired/whitelisted devices keyed by deviceId.
  final Map<String, PairedDevice> _pairedDevices = {};

  /// Controller for broadcasting received messages to listeners if needed.
  final _messageStreamController = StreamController<NetworkPacket>.broadcast();

  SharedDeviceNetworkServer({
    required this.onDataReceived,
    this.deviceId = '',
    this.deviceName = 'SharedDeviceServer',
    this.deviceDescription,
    this.port = 8888,
    this.discoveryPort = 8889,
    this.requirePairKey = false,
    this.defaultPairKey,
    this.metadata,
  });

  /// Creates a [SharedDeviceNetworkServer] with a [ServerConfig] object.
  factory SharedDeviceNetworkServer.fromConfig({
    required OnDataReceivedCallback onDataReceived,
    required String deviceId,
    required String deviceName,
    String? deviceDescription,
    ServerConfig config = const ServerConfig(),
    Map<String, dynamic>? metadata,
  }) {
    return SharedDeviceNetworkServer(
      onDataReceived: onDataReceived,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceDescription: deviceDescription,
      port: config.port,
      discoveryPort: config.discoveryPort,
      requirePairKey: config.requirePairing,
      defaultPairKey: config.defaultPairKey,
      metadata: metadata,
    );
  }

  /// Whether the UDP server is currently running.
  bool get isRunning => _isRunning;

  /// List of currently paired/authorized devices.
  List<PairedDevice> get pairedDevices => _pairedDevices.values.toList();

  /// Stream of all valid incoming network packets received by this server.
  Stream<NetworkPacket> get messageStream => _messageStreamController.stream;

  /// Adds an authorized device to the server's paired list.
  Future<bool> addDevice(
    String deviceId,
    String deviceName, {
    String? deviceDescription,
    String? pairKey,
  }) async {
    if (deviceId.trim().isEmpty) return false;
    _pairedDevices[deviceId] = PairedDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceDescription: deviceDescription,
      pairKey: pairKey ?? defaultPairKey,
      addedAt: DateTime.now(),
    );
    return true;
  }

  /// Removes an authorized device from the paired list.
  Future<bool> removeDevice(String deviceId) async {
    final removed = _pairedDevices.remove(deviceId);
    return removed != null;
  }

  /// Checks if a device is registered/paired.
  bool isDevicePaired(String deviceId) => _pairedDevices.containsKey(deviceId);

  /// Retrieves a paired device entry.
  PairedDevice? getPairedDevice(String deviceId) => _pairedDevices[deviceId];

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

  /// Starts the server and automatically manages an Android/iOS foreground service.
  Future<bool> startWithForegroundService({
    String notificationTitle = 'Shared Device Server Active',
    String notificationText = 'Listening for incoming device connections...',
  }) async {
    await start();
    return await SharedDeviceForegroundService.startService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
  }

  /// Stops the foreground service if running.
  Future<bool> stopForegroundService() async {
    return await SharedDeviceForegroundService.stopService();
  }

  /// Handles incoming datagrams on the main data socket.
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

  /// Processes an incoming datagram from either socket.
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

    // Ignore self messages if loopback/broadcasted
    if (packet.senderDeviceId.isNotEmpty && packet.senderDeviceId == deviceId) {
      return;
    }

    switch (packet.type) {
      case PacketType.discoveryRequest:
        await _handleDiscoveryRequest(packet, datagram.address, senderPort);
        break;

      case PacketType.message:
        await _handleMessage(packet, datagram.address, senderPort);
        break;

      case PacketType.ack:
        // Pass to stream in case anyone listens
        _messageStreamController.add(packet);
        break;

      case PacketType.discoveryResponse:
        // Typically handled by clients
        break;
    }
  }

  /// Responds to a discovery request with this server's SharedDevice information.
  Future<void> _handleDiscoveryRequest(
    NetworkPacket packet,
    InternetAddress remoteAddress,
    int remotePort,
  ) async {
    // If request targeted a specific device ID and it's not ours, ignore
    if (packet.targetDeviceId != null &&
        packet.targetDeviceId!.isNotEmpty &&
        packet.targetDeviceId != deviceId) {
      return;
    }

    final localIp = await NetworkUtils.getPrimaryLocalIPv4();
    final response = NetworkPacket.discoveryResponse(
      senderDeviceId: deviceId,
      senderDeviceName: deviceName,
      deviceDescription: deviceDescription,
      deviceIp: localIp,
      devicePort: port,
      metadata: metadata,
    );

    final replyPort = packet.senderPort != null && packet.senderPort! > 0
        ? packet.senderPort!
        : remotePort;

    _sendPacketDirect(response, remoteAddress, replyPort);
  }

  /// Handles incoming data message, executes callback, and replies with ACK packet.
  Future<void> _handleMessage(
    NetworkPacket packet,
    InternetAddress remoteAddress,
    int remotePort,
  ) async {
    final messageId = packet.messageId;
    final senderId = packet.senderDeviceId;

    if (messageId == null) return;

    // Direct targeted check
    if (packet.targetDeviceId != null &&
        packet.targetDeviceId!.isNotEmpty &&
        packet.targetDeviceId != deviceId) {
      return;
    }

    // Verify pairing / authorization if enabled
    if (requirePairKey || _pairedDevices.isNotEmpty) {
      final pairedDevice = _pairedDevices[senderId];
      if (pairedDevice == null) {
        // Device not in paired whitelist
        final unauthStatus = Status.unauthorized(
          message: 'Device "$senderId" is not authorized on this server.',
        );
        _sendAck(messageId, senderId, unauthStatus, remoteAddress, packet.senderPort ?? remotePort);
        return;
      }

      // If pairKey is required on paired device or default pairKey is set
      final expectedKey = pairedDevice.pairKey ?? defaultPairKey;
      if (expectedKey != null && expectedKey.isNotEmpty) {
        if (packet.pairKey != expectedKey) {
          final unauthStatus = Status.unauthorized(
            message: 'Invalid pair key provided for device "$senderId".',
          );
          _sendAck(messageId, senderId, unauthStatus, remoteAddress, packet.senderPort ?? remotePort);
          return;
        }
      }

      // Update last seen timestamp
      _pairedDevices[senderId] = pairedDevice.copyWith(
        lastSeenAt: DateTime.now(),
      );
    }

    _messageStreamController.add(packet);

    // Execute user callback to handle message
    Status status;
    try {
      status = await onDataReceived(senderId, packet.payload);
    } catch (e) {
      status = Status.error(
        e.toString(),
        message: 'Exception occurred processing message on server',
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
      senderDeviceId: deviceId,
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

  /// Converts this server instance to a [SharedDevice] model.
  Future<SharedDevice> toSharedDevice() async {
    final localIp = await NetworkUtils.getPrimaryLocalIPv4();
    return SharedDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceDescription: deviceDescription,
      deviceIp: localIp,
      devicePort: port,
      metadata: metadata,
    );
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
