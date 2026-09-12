import 'dart:async';
import 'dart:io';

import '../models/network_packet.dart';
import '../models/shared_device.dart';
import '../models/shared_device_response.dart';
import '../utils/message_id_generator.dart';
import '../utils/network_utils.dart';
import 'client_config.dart';

/// A UDP client that enables local device discovery and incremental ACK-based message transmission.
class SharedDeviceNetworkClient {
  /// Identifier of this client device.
  final String deviceId;

  /// Human-readable name of this client device.
  final String deviceName;

  /// Default timeout waiting for an ACK.
  final Duration defaultTimeout;

  /// UDP port used for broadcasting discovery requests.
  final int discoveryPort;

  /// Default server data port if target port is unknown.
  final int defaultServerPort;

  /// Optional fixed local port for client socket (0 = system assigned).
  final int clientPort;

  /// Thread-safe generator for incremental message IDs.
  final MessageIdGenerator _idGenerator = MessageIdGenerator();

  /// Socket used for data communication and ACK receiving.
  RawDatagramSocket? _socket;
  bool _isInitialized = false;

  /// Pending ACK completers keyed by incremental messageId.
  final Map<int, Completer<SharedDeviceResponse>> _pendingAcks = {};

  /// Cache of discovered devices keyed by deviceId.
  final Map<String, SharedDevice> _knownDevices = {};

  SharedDeviceNetworkClient({
    this.deviceId = '',
    this.deviceName = 'SharedDeviceClient',
    this.defaultTimeout = const Duration(seconds: 5),
    this.discoveryPort = 8889,
    this.defaultServerPort = 8888,
    this.clientPort = 0,
  });

  /// Creates a [SharedDeviceNetworkClient] with a [ClientConfig] object.
  factory SharedDeviceNetworkClient.fromConfig({
    String deviceId = '',
    String deviceName = 'SharedDeviceClient',
    ClientConfig config = const ClientConfig(),
  }) {
    return SharedDeviceNetworkClient(
      deviceId: deviceId,
      deviceName: deviceName,
      defaultTimeout: config.defaultTimeout,
      discoveryPort: config.discoveryPort,
      defaultServerPort: config.defaultServerPort,
      clientPort: config.clientPort,
    );
  }

  /// Map of known devices discovered or registered.
  Map<String, SharedDevice> get knownDevices => Map.unmodifiable(_knownDevices);

  /// Registers or manually updates a known device in the cache.
  void registerKnownDevice(SharedDevice device) {
    _knownDevices[device.deviceId] = device;
  }

  /// Clears the known devices cache.
  void clearKnownDevices() {
    _knownDevices.clear();
  }

  /// Initializes the client socket if not already open.
  Future<void> _ensureSocket() async {
    if (_isInitialized && _socket != null) return;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      clientPort,
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    );
    _socket!.broadcastEnabled = true;
    _socket!.listen(_handleSocketEvents);
    _isInitialized = true;
  }

  /// Handles incoming datagrams (e.g. ACKs and Discovery Responses).
  void _handleSocketEvents(RawSocketEvent event) {
    if (event == RawSocketEvent.read && _socket != null) {
      final datagram = _socket!.receive();
      if (datagram != null) {
        final senderIp = datagram.address.address;
        final senderPort = datagram.port;

        final packet = NetworkPacket.fromUtf8Bytes(
          datagram.data,
          senderIp: senderIp,
          senderPort: senderPort,
        );

        if (packet == null) return;

        if (packet.type == PacketType.ack && packet.messageId != null) {
          _handleAck(packet);
        } else if (packet.type == PacketType.discoveryResponse) {
          _handleDiscoveryResponse(packet, senderIp, senderPort);
        }
      }
    }
  }

  /// Handles an ACK packet by completing the matching pending Completer.
  void _handleAck(NetworkPacket packet) {
    final messageId = packet.messageId!;
    final completer = _pendingAcks.remove(messageId);
    if (completer != null && !completer.isCompleted) {
      final status = packet.status ??
          (packet.payload is Map
              ? SharedDeviceResponse.fromMap(Map<String, dynamic>.from(packet.payload as Map))
              : SharedDeviceResponse.success(data: packet.payload));
      completer.complete(status);
    }
  }

  /// Handles a discovery response and caches the devices.
  void _handleDiscoveryResponse(NetworkPacket packet, String senderIp, int senderPort) {
    if (packet.payload is Map) {
      final map = Map<String, dynamic>.from(packet.payload as Map);
      if (map['devices'] is List) {
        for (final item in (map['devices'] as List)) {
          if (item is Map) {
            try {
              final device = SharedDevice.fromMap(Map<String, dynamic>.from(item));
              final resolvedDevice = device.deviceIp.isEmpty || device.deviceIp == '0.0.0.0'
                  ? device.copyWith(deviceIp: senderIp)
                  : device;
              _knownDevices[resolvedDevice.deviceId] = resolvedDevice;
            } catch (_) {}
          }
        }
      } else {
        try {
          final device = SharedDevice.fromMap(map);
          final resolvedDevice = device.deviceIp.isEmpty || device.deviceIp == '0.0.0.0'
              ? device.copyWith(deviceIp: senderIp)
              : device;
          _knownDevices[resolvedDevice.deviceId] = resolvedDevice;
        } catch (_) {}
      }
    }
  }

  /// Discovers available devices on the local network via UDP broadcast.
  ///
  /// Listens for responses for the specified [timeout] (default 3 seconds).
  Stream<SharedDevice> discoverDevices({
    Duration timeout = const Duration(seconds: 3),
    int? discoveryPort,
  }) {
    final targetDiscoveryPort = discoveryPort ?? this.discoveryPort;
    late StreamController<SharedDevice> controller;
    final discoveredIds = <String>{};
    RawDatagramSocket? discSocket;
    Timer? timer;

    void cleanup() {
      timer?.cancel();
      try {
        discSocket?.close();
      } catch (_) {}
      discSocket = null;
    }

    controller = StreamController<SharedDevice>(
      onListen: () async {
        try {
          discSocket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
            reuseAddress: true,
            reusePort: !Platform.isWindows,
          );
          discSocket!.broadcastEnabled = true;

          discSocket!.listen((event) {
            if (event == RawSocketEvent.read && discSocket != null) {
              final datagram = discSocket!.receive();
              if (datagram != null) {
                final packet = NetworkPacket.fromUtf8Bytes(
                  datagram.data,
                  senderIp: datagram.address.address,
                  senderPort: datagram.port,
                );

                if (packet != null && packet.type == PacketType.discoveryResponse) {
                  if (packet.payload is Map) {
                    final map = Map<String, dynamic>.from(packet.payload as Map);
                    final List<Map<String, dynamic>> rawDevices = [];
                    if (map['devices'] is List) {
                      for (final d in (map['devices'] as List)) {
                        if (d is Map) rawDevices.add(Map<String, dynamic>.from(d));
                      }
                    } else if (map.containsKey('deviceId')) {
                      rawDevices.add(map);
                    }

                    for (final raw in rawDevices) {
                      try {
                        final dev = SharedDevice.fromMap(raw);
                        final resolved = dev.deviceIp.isEmpty || dev.deviceIp == '0.0.0.0'
                            ? dev.copyWith(deviceIp: datagram.address.address)
                            : dev;

                        if (discoveredIds.add(resolved.deviceId)) {
                          _knownDevices[resolved.deviceId] = resolved;
                          if (!controller.isClosed) {
                            controller.add(resolved);
                          }
                        }
                      } catch (_) {}
                    }
                  }
                }
              }
            }
          });

          // Prepare discovery request packet
          final request = NetworkPacket.discoveryRequest(
            senderDeviceId: deviceId,
            senderDeviceName: deviceName,
            replyPort: discSocket!.port,
          );
          final bytes = request.toUtf8Bytes();

          // Broadcast to all active subnet interfaces and universal 255.255.255.255
          final broadcastAddresses = await NetworkUtils.getBroadcastAddresses();
          for (final address in broadcastAddresses) {
            try {
              discSocket!.send(bytes, address, targetDiscoveryPort);
            } catch (_) {}
          }

          // Also send directly on loopback for local tests/instances
          try {
            discSocket!.send(bytes, InternetAddress.loopbackIPv4, targetDiscoveryPort);
          } catch (_) {}

          // Wait for timeout, then close
          timer = Timer(timeout, () {
            if (!controller.isClosed) {
              cleanup();
              controller.close();
            }
          });
        } catch (e) {
          if (!controller.isClosed) {
            cleanup();
            controller.addError(e);
            controller.close();
          }
        }
      },
      onCancel: () {
        cleanup();
      },
    );

    return controller.stream;
  }

  /// Discovers devices and returns a List of all responding [SharedDevice]s.
  Future<List<SharedDevice>> discoverDevicesOnce({
    Duration timeout = const Duration(seconds: 3),
    int? discoveryPort,
  }) async {
    final devices = <SharedDevice>[];
    await for (final device in discoverDevices(timeout: timeout, discoveryPort: discoveryPort)) {
      devices.add(device);
    }
    return devices;
  }

  /// Sends a message to a specific [deviceId] and waits for an acknowledgment (ACK).
  ///
  /// Increments the message ID for this transmission.
  /// If the target device's IP and port are known or supplied in [targetDevice]/[ip]/[port],
  /// the message is sent directly. Otherwise, it attempts discovery to locate the device.
  Future<SharedDeviceResponse> sendToDevice(
    String deviceId,
    dynamic message, {
    String? pairKey,
    Duration? timeout,
    SharedDevice? targetDevice,
    String? ip,
    int? port,
  }) async {
    // 1. Resolve target device IP and Port
    String? targetIp = ip ?? targetDevice?.deviceIp;
    int? targetPort = port ?? targetDevice?.devicePort;

    if (targetIp == null || targetPort == null) {
      final cached = _knownDevices[deviceId];
      if (cached != null) {
        targetIp = cached.deviceIp;
        targetPort = cached.devicePort;
      }
    }

    // 2. If still unknown, attempt quick discovery
    if (targetIp == null || targetPort == null) {
      final discoveredList = await discoverDevicesOnce(
        timeout: const Duration(milliseconds: 1500),
      );
      final found = discoveredList.where((d) => d.deviceId == deviceId).firstOrNull;
      if (found != null) {
        targetIp = found.deviceIp;
        targetPort = found.devicePort;
      }
    }

    // If still not found, return deviceNotFound status
    if (targetIp == null || targetPort == null) {
      return SharedDeviceResponse.deviceNotFound(
        message: 'Could not find device "$deviceId" on the network.',
      );
    }

    return sendToAddress(
      targetIp,
      targetPort,
      message,
      targetDeviceId: deviceId,
      pairKey: pairKey,
      timeout: timeout,
    );
  }

  /// Alias for [sendToDevice] to support alternative spelling.
  Future<SharedDeviceResponse> sendToDeivce(
    String deviceId,
    dynamic message, {
    String? pairKey,
    Duration? timeout,
    SharedDevice? targetDevice,
    String? ip,
    int? port,
  }) =>
      sendToDevice(
        deviceId,
        message,
        pairKey: pairKey,
        timeout: timeout,
        targetDevice: targetDevice,
        ip: ip,
        port: port,
      );

  /// Sends a message directly to an IP and Port with an incremental message ID and waits for ACK.
  Future<SharedDeviceResponse> sendToAddress(
    String ip,
    int port,
    dynamic message, {
    String? targetDeviceId,
    String? pairKey,
    Duration? timeout,
  }) async {
    await _ensureSocket();

    final actualTimeout = timeout ?? defaultTimeout;
    final messageId = _idGenerator.next();

    final packet = NetworkPacket.message(
      messageId: messageId,
      senderDeviceId: deviceId,
      senderDeviceName: deviceName,
      targetDeviceId: targetDeviceId,
      pairKey: pairKey,
      payload: message,
      replyPort: _socket!.port,
    );

    final completer = Completer<SharedDeviceResponse>();
    _pendingAcks[messageId] = completer;

    // Timeout timer
    final timer = Timer(actualTimeout, () {
      final pending = _pendingAcks.remove(messageId);
      if (pending != null && !pending.isCompleted) {
        pending.complete(
          SharedDeviceResponse.timeout(
            message: 'Timed out waiting for ACK from $ip:$port for message ID #$messageId',
            timeout: actualTimeout,
          ),
        );
      }
    });

    try {
      final bytes = packet.toUtf8Bytes();
      final destination = InternetAddress(ip);
      _socket!.send(bytes, destination, port);

      final status = await completer.future;
      timer.cancel();
      return status;
    } catch (e) {
      timer.cancel();
      _pendingAcks.remove(messageId);
      return SharedDeviceResponse.error(
        e.toString(),
        message: 'Failed to send UDP datagram to $ip:$port',
      );
    }
  }

  /// Closes client socket and clears resources.
  Future<void> dispose() async {
    _isInitialized = false;

    for (final completer in _pendingAcks.values) {
      if (!completer.isCompleted) {
        completer.complete(SharedDeviceResponse.error('Client disposed'));
      }
    }
    _pendingAcks.clear();

    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
