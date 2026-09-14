import 'dart:async';

import '../discovery/discovery_provider.dart';
import '../models/exceptions.dart';
import '../models/shared_device.dart';
import '../models/shared_device_request.dart';
import '../models/shared_device_response.dart';
import '../models/shared_device_server.dart';
import '../utils/request_id_generator.dart';
import 'http_client_transport.dart';

/// A versatile client for local device discovery and HTTP-based peripheral communication.
///
/// Fully cross-platform: runs on Android, iOS, macOS, Windows, Linux, and Flutter Web.
///
/// ### Example Usage:
/// ```dart
/// final client = SharedDeviceNetworkClient();
///
/// // 1. Discover devices on local network via mDNS:
/// final devices = await client.discoverDevicesOnce();
/// for (final dev in devices) {
///   print('Found ${dev.deviceName} (${dev.deviceId}) at ${dev.deviceIp}:${dev.devicePort}');
/// }
///
/// // 2. Send command to a device:
/// final res = await client.sendToDevice('printer-01', {
///   'command': 'PRINT_BILL',
///   'total': 45.50,
/// });
/// ```
class SharedDeviceNetworkClient {
  /// Identifier of this client instance.
  final String clientId;

  /// Human-readable name of this client device.
  final String clientName;

  /// Default timeout waiting for HTTP responses.
  final Duration defaultTimeout;

  /// Default mDNS service type to discover (default: `_shared-device._tcp`).
  final String defaultServiceType;

  final HttpClientTransport _transport;
  final DiscoveryProvider _discovery;

  /// Currently selected target server (if any).
  SharedDeviceServer? _currentServer;

  /// Cache of discovered or registered servers, keyed by serverId.
  final Map<String, SharedDeviceServer> _knownServers = {};

  /// Cache of discovered or registered devices, keyed by deviceId.
  final Map<String, SharedDevice> _knownDevices = {};

  SharedDeviceNetworkClient({
    String? clientId,
    String? deviceId,
    String? deviceName,
    this.clientName = 'SharedDeviceClient',
    this.defaultTimeout = const Duration(seconds: 8),
    this.defaultServiceType = kDefaultServiceType,
    this.discoveryPort = 5353,
    this.defaultServerPort = 8080,
    int clientPort = 0,
    HttpClientTransport? transport,
    DiscoveryProvider? discovery,
  })  : clientId = clientId ?? deviceId ?? 'client_${RequestIdGenerator.generate().substring(4)}',
        _transport = transport ?? HttpClientTransport(defaultTimeout: defaultTimeout),
        _discovery = discovery ?? getDiscoveryProvider();

  // ---------------------------------------------------------------------------
  // Getters & State
  // ---------------------------------------------------------------------------

  /// Identifier of this client device (backward-compatibility alias for [clientId]).
  String get deviceId => clientId;

  /// Human-readable name of this client device (backward-compatibility alias for [clientName]).
  String get deviceName => clientName;

  /// Default discovery port (backward-compatibility getter).
  final int discoveryPort;

  /// Default server port (backward-compatibility getter).
  final int defaultServerPort;

  /// The currently selected server, if any.
  SharedDeviceServer? get currentServer => _currentServer;

  /// Whether native mDNS local network discovery is supported on this platform.
  /// (False on Flutter Web).
  bool get isDiscoverySupported => _discovery.isSupported;

  /// Map of known devices, keyed by deviceId.
  Map<String, SharedDevice> get knownDevices => Map.unmodifiable(_knownDevices);

  /// List of currently discovered or known peripheral devices.
  List<SharedDevice> get discoveredDevices => _knownDevices.values.toList();

  /// Map of known servers, keyed by serverId.
  Map<String, SharedDeviceServer> get knownServers =>
      Map.unmodifiable(_knownServers);

  /// Explicitly selects the active server for subsequent device queries and commands.
  void selectServer(SharedDeviceServer server) {
    _currentServer = server;
    _knownServers[server.serverId] = server;
  }

  /// Manually registers a known device in the cache.
  void registerKnownDevice(SharedDevice device) {
    _knownDevices[device.deviceId] = device;
  }

  /// Clears the known devices cache.
  void clearKnownDevices() {
    _knownDevices.clear();
  }

  /// Clears the known servers cache.
  void clearKnownServers() {
    _knownServers.clear();
    _currentServer = null;
  }

  // ---------------------------------------------------------------------------
  // Device Discovery (mDNS + REST)
  // ---------------------------------------------------------------------------

  /// Discovers peripheral devices on the local LAN advertising via mDNS.
  ///
  /// Discovers host servers on the network in the background, queries their registered
  /// peripherals via `GET /api/v1/devices`, tags each peripheral with the hosting server's
  /// IP address and port ([SharedDevice.deviceIp], [SharedDevice.devicePort]), and emits
  /// [SharedDevice] instances.
  Stream<SharedDevice> discoverDevices({
    Duration timeout = const Duration(seconds: 4),
    String? serviceType,
  }) {
    late StreamController<SharedDevice> controller;
    final yieldedDeviceKeys = <String>{};

    controller = StreamController<SharedDevice>(
      onListen: () async {
        try {
          final serverStream = _discovery.discoverServers(
            serviceType: serviceType ?? defaultServiceType,
            timeout: timeout,
          );

          await for (final host in serverStream) {
            try {
              final rawList = await _transport.getDevices(
                host.baseUri,
                timeout: const Duration(seconds: 2),
              );
              for (final map in rawList) {
                try {
                  final dev = SharedDevice.fromMap(map);
                  // Ensure host's IP and port are tagged on the device
                  final resolved = dev.copyWith(
                    deviceIp: host.host,
                    devicePort: host.port,
                  );
                  _knownDevices[resolved.deviceId] = resolved;

                  final key = '${resolved.deviceIp}:${resolved.devicePort}:${resolved.deviceId}';
                  if (yieldedDeviceKeys.add(key)) {
                    if (!controller.isClosed) {
                      controller.add(resolved);
                    }
                  }
                } catch (_) {}
              }
            } catch (_) {}
          }

          if (!controller.isClosed) {
            controller.close();
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(e);
            controller.close();
          }
        }
      },
    );

    return controller.stream;
  }

  /// Discovers peripherals on the local network once and returns a List of all discovered [SharedDevice]s.
  Future<List<SharedDevice>> discoverDevicesOnce({
    Duration timeout = const Duration(seconds: 4),
    String? serviceType,
  }) async {
    final list = <SharedDevice>[];
    await for (final dev in discoverDevices(
      timeout: timeout,
      serviceType: serviceType,
    )) {
      list.add(dev);
    }
    return list;
  }

  // ---------------------------------------------------------------------------
  // Direct Host & Server Queries (Native & Web)
  // ---------------------------------------------------------------------------

  /// Retrieves peripheral devices hosted on a specific [host] and [port].
  ///
  /// Each returned peripheral is tagged with [host] and [port].
  /// Ideal for Flutter Web clients or direct network connection without mDNS.
  Future<List<SharedDevice>> getDevicesFromHost({
    required String host,
    required int port,
    bool isSecure = false,
    Duration? timeout,
  }) async {
    final scheme = isSecure ? 'https' : 'http';
    final baseUri = Uri(scheme: scheme, host: host, port: port);

    final rawList = await _transport.getDevices(baseUri, timeout: timeout);
    final devices = <SharedDevice>[];

    for (final map in rawList) {
      try {
        final dev = SharedDevice.fromMap(map);
        final resolved = dev.copyWith(
          deviceIp: host,
          devicePort: port,
        );
        _knownDevices[resolved.deviceId] = resolved;
        devices.add(resolved);
      } catch (_) {}
    }

    return devices;
  }

  /// Connects directly to a server by [host] and [port] without requiring mDNS.
  ///
  /// Queries server info, discovers hosted peripherals, and automatically selects it.
  /// This is the primary mechanism for browser-based Flutter Web clients.
  Future<SharedDeviceServer> connectToServer({
    required String host,
    required int port,
    bool isSecure = false,
    Duration? timeout,
  }) async {
    final scheme = isSecure ? 'https' : 'http';
    final baseUri = Uri(scheme: scheme, host: host, port: port);

    final info = await _transport.getInfo(baseUri, timeout: timeout);

    final serverId = info['serverId']?.toString() ?? 'server_${host}_$port';
    final serverName = info['serverName']?.toString() ?? 'Server ($host)';
    final version = info['protocolVersion']?.toString() ?? '1.0';
    final caps = info['capabilities'] is List
        ? (info['capabilities'] as List).map((e) => e.toString()).toList()
        : <String>[];
    final metadata = info['metadata'] is Map
        ? Map<String, dynamic>.from(info['metadata'] as Map)
        : <String, dynamic>{};
    final deviceCount = info['deviceCount'] is int
        ? info['deviceCount'] as int
        : null;

    final server = SharedDeviceServer(
      serverId: serverId,
      serverName: serverName,
      host: host,
      port: port,
      protocolVersion: version,
      capabilities: caps,
      metadata: metadata,
      deviceCount: deviceCount,
      isSecure: isSecure,
    );

    selectServer(server);
    await getDevicesFromHost(host: host, port: port, isSecure: isSecure, timeout: timeout);
    return server;
  }

  /// Retrieves server info from the [targetServer] or [currentServer].
  Future<Map<String, dynamic>> getServerInfo({
    SharedDeviceServer? targetServer,
    Duration? timeout,
  }) async {
    final server = targetServer ?? _currentServer;
    if (server == null) {
      throw const ConnectionException(
        'No server selected. Call connectToServer() or selectServer() first.',
      );
    }
    return await _transport.getInfo(server.baseUri, timeout: timeout);
  }

  /// Discovers local servers on the LAN advertising via mDNS.
  Stream<SharedDeviceServer> discoverServers({
    Duration timeout = const Duration(seconds: 4),
    bool excludeSelf = true,
    String? serviceType,
  }) {
    final stream = _discovery.discoverServers(
      serviceType: serviceType ?? defaultServiceType,
      timeout: timeout,
      excludeServerId: excludeSelf ? clientId : null,
    );

    return stream.map((server) {
      _knownServers[server.serverId] = server;
      return server;
    });
  }

  /// Discovers local servers and returns a List of all discovered [SharedDeviceServer]s.
  Future<List<SharedDeviceServer>> discoverServersOnce({
    Duration timeout = const Duration(seconds: 4),
    bool excludeSelf = true,
    String? serviceType,
  }) async {
    final list = await _discovery.discoverServersOnce(
      serviceType: serviceType ?? defaultServiceType,
      timeout: timeout,
      excludeServerId: excludeSelf ? clientId : null,
    );

    for (final s in list) {
      _knownServers[s.serverId] = s;
    }
    return list;
  }

  /// Retrieves peripheral devices from a specific host or cache.
  Future<List<SharedDevice>> getDevices({
    String? host,
    int? port,
    SharedDeviceServer? targetServer,
    Duration? timeout,
  }) async {
    if (host != null && port != null) {
      return getDevicesFromHost(host: host, port: port, timeout: timeout);
    }
    if (targetServer != null) {
      return getDevicesFromHost(
        host: targetServer.host,
        port: targetServer.port,
        isSecure: targetServer.isSecure,
        timeout: timeout,
      );
    }
    if (_currentServer != null) {
      return getDevicesFromHost(
        host: _currentServer!.host,
        port: _currentServer!.port,
        isSecure: _currentServer!.isSecure,
        timeout: timeout,
      );
    }
    return _knownDevices.values.toList();
  }

  /// Looks up a specific peripheral device by [deviceId].
  Future<SharedDevice?> getDevice(
    String deviceId, {
    String? host,
    int? port,
    SharedDeviceServer? targetServer,
    Duration? timeout,
  }) async {
    if (host != null && port != null) {
      final uri = Uri(scheme: 'http', host: host, port: port);
      final raw = await _transport.getDevice(uri, deviceId, timeout: timeout);
      if (raw == null) return null;
      final dev = SharedDevice.fromMap(raw).copyWith(deviceIp: host, devicePort: port);
      _knownDevices[dev.deviceId] = dev;
      return dev;
    }

    if (_knownDevices.containsKey(deviceId)) {
      return _knownDevices[deviceId];
    }

    if (_discovery.isSupported) {
      final discovered = await discoverDevicesOnce(timeout: const Duration(seconds: 2));
      return discovered.where((d) => d.deviceId == deviceId).firstOrNull;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Command & Binary Transmission
  // ---------------------------------------------------------------------------

  /// Sends a command to a peripheral device and waits for a structured response.
  ///
  /// Supports [pairKey] for authentication if required by the peripheral.
  /// Automatically resolves destination using the peripheral's tagged IP and port.
  Future<SharedDeviceResponse> sendToDevice(
    String deviceId,
    dynamic message, {
    String? pairKey,
    Duration? timeout,
    SharedDevice? targetDevice,
    SharedDeviceServer? targetServer,
    String? ip,
    int? port,
    String? requestId,
  }) async {
    var baseUri = _resolveTargetUri(
      deviceId: deviceId,
      targetDevice: targetDevice,
      targetServer: targetServer,
      ip: ip,
      port: port,
    );

    // If still not resolved and discovery is supported, attempt quick discovery
    if (baseUri == null && _discovery.isSupported) {
      try {
        final discovered = await discoverDevicesOnce(
          timeout: const Duration(seconds: 2),
        );
        final match = discovered.where((d) => d.deviceId == deviceId).firstOrNull;
        if (match != null && match.deviceIp.isNotEmpty && match.devicePort > 0) {
          baseUri = Uri(scheme: 'http', host: match.deviceIp, port: match.devicePort);
        }
      } catch (_) {}
    }

    if (baseUri == null) {
      return SharedDeviceResponse.deviceNotFound(
        requestId: requestId,
        message: 'Could not resolve server address for device "$deviceId"',
      );
    }

    final reqId = requestId ?? RequestIdGenerator.generate();
    final commandName = message is Map && message.containsKey('command')
        ? message['command'].toString()
        : 'COMMAND';

    final request = SharedDeviceRequest(
      requestId: reqId,
      deviceId: deviceId,
      command: commandName,
      data: message,
    );

    return await _transport.sendCommand(
      baseUri,
      deviceId,
      request,
      pairKey: pairKey,
      timeout: timeout,
    );
  }

  /// Alias for [sendToDevice] to preserve backward compatibility with v0.0.1 typo.
  Future<SharedDeviceResponse> sendToDeivce(
    String deviceId,
    dynamic message, {
    String? pairKey,
    Duration? timeout,
    SharedDevice? targetDevice,
    SharedDeviceServer? targetServer,
    String? ip,
    int? port,
    String? requestId,
  }) =>
      sendToDevice(
        deviceId,
        message,
        pairKey: pairKey,
        timeout: timeout,
        targetDevice: targetDevice,
        targetServer: targetServer,
        ip: ip,
        port: port,
        requestId: requestId,
      );

  /// Sends raw or formatted binary content (e.g. image, PDF, ESC/POS byte array) to a peripheral.
  Future<SharedDeviceResponse> sendBinaryToDevice(
    String deviceId,
    List<int> bytes, {
    String contentType = 'application/octet-stream',
    String? fileName,
    String? pairKey,
    Duration? timeout,
    SharedDevice? targetDevice,
    SharedDeviceServer? targetServer,
    String? ip,
    int? port,
    String? requestId,
  }) async {
    var baseUri = _resolveTargetUri(
      deviceId: deviceId,
      targetDevice: targetDevice,
      targetServer: targetServer,
      ip: ip,
      port: port,
    );

    if (baseUri == null && _discovery.isSupported) {
      try {
        final discovered = await discoverDevicesOnce(
          timeout: const Duration(seconds: 2),
        );
        final match = discovered.where((d) => d.deviceId == deviceId).firstOrNull;
        if (match != null && match.deviceIp.isNotEmpty && match.devicePort > 0) {
          baseUri = Uri(scheme: 'http', host: match.deviceIp, port: match.devicePort);
        }
      } catch (_) {}
    }

    if (baseUri == null) {
      return SharedDeviceResponse.deviceNotFound(
        requestId: requestId,
        message: 'Could not resolve server address for device "$deviceId"',
      );
    }

    final reqId = requestId ?? RequestIdGenerator.generate();

    return await _transport.sendBinary(
      baseUri,
      deviceId,
      bytes,
      contentType: contentType,
      fileName: fileName,
      requestId: reqId,
      pairKey: pairKey,
      timeout: timeout,
    );
  }

  /// Sends a file via `multipart/form-data` to a peripheral device.
  Future<SharedDeviceResponse> sendMultipartToDevice(
    String deviceId,
    List<int> bytes, {
    required String fileName,
    String fieldName = 'file',
    String? pairKey,
    Duration? timeout,
    SharedDevice? targetDevice,
    SharedDeviceServer? targetServer,
    String? ip,
    int? port,
    String? requestId,
  }) async {
    var baseUri = _resolveTargetUri(
      deviceId: deviceId,
      targetDevice: targetDevice,
      targetServer: targetServer,
      ip: ip,
      port: port,
    );

    if (baseUri == null && _discovery.isSupported) {
      try {
        final discovered = await discoverDevicesOnce(
          timeout: const Duration(seconds: 2),
        );
        final match = discovered.where((d) => d.deviceId == deviceId).firstOrNull;
        if (match != null && match.deviceIp.isNotEmpty && match.devicePort > 0) {
          baseUri = Uri(scheme: 'http', host: match.deviceIp, port: match.devicePort);
        }
      } catch (_) {}
    }

    if (baseUri == null) {
      return SharedDeviceResponse.deviceNotFound(
        requestId: requestId,
        message: 'Could not resolve server address for device "$deviceId"',
      );
    }

    final reqId = requestId ?? RequestIdGenerator.generate();

    return await _transport.sendMultipart(
      baseUri,
      deviceId,
      bytes,
      fileName: fileName,
      fieldName: fieldName,
      requestId: reqId,
      pairKey: pairKey,
      timeout: timeout,
    );
  }

  /// Sends a command directly to a host IP and port.
  Future<SharedDeviceResponse> sendToAddress(
    String ip,
    int port,
    dynamic message, {
    String? targetDeviceId,
    String? pairKey,
    Duration? timeout,
    String? requestId,
    bool isSecure = false,
  }) async {
    final scheme = isSecure ? 'https' : 'http';
    final baseUri = Uri(scheme: scheme, host: ip, port: port);
    final devId = targetDeviceId ?? 'default';

    final reqId = requestId ?? RequestIdGenerator.generate();
    final request = SharedDeviceRequest(
      requestId: reqId,
      deviceId: devId,
      command: 'COMMAND',
      data: message,
    );

    return await _transport.sendCommand(
      baseUri,
      devId,
      request,
      pairKey: pairKey,
      timeout: timeout,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Uri? _resolveTargetUri({
    required String deviceId,
    SharedDevice? targetDevice,
    SharedDeviceServer? targetServer,
    String? ip,
    int? port,
  }) {
    // 1. Explicit ip and port
    if (ip != null && ip.isNotEmpty && port != null && port > 0) {
      return Uri(scheme: 'http', host: ip, port: port);
    }

    // 2. targetDevice host/port
    if (targetDevice != null &&
        targetDevice.deviceIp.isNotEmpty &&
        targetDevice.devicePort > 0) {
      return Uri(
        scheme: 'http',
        host: targetDevice.deviceIp,
        port: targetDevice.devicePort,
      );
    }

    // 3. Cached device in _knownDevices (with tagged IP & port)
    final cachedDev = _knownDevices[deviceId];
    if (cachedDev != null &&
        cachedDev.deviceIp.isNotEmpty &&
        cachedDev.devicePort > 0) {
      return Uri(
        scheme: 'http',
        host: cachedDev.deviceIp,
        port: cachedDev.devicePort,
      );
    }

    // 4. Explicit targetServer
    if (targetServer != null) {
      return targetServer.baseUri;
    }

    // 5. Current active server
    if (_currentServer != null) {
      return _currentServer!.baseUri;
    }

    return null;
  }

  /// Closes client HTTP session and releases discovery resources.
  Future<void> dispose() async {
    _transport.dispose();
    await _discovery.dispose();
    _knownServers.clear();
    _knownDevices.clear();
    _currentServer = null;
  }
}
