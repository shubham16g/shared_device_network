import 'dart:async';

import '../discovery/discovery_provider.dart';
import '../models/cors_policy.dart';
import '../models/shared_device_record.dart';
import '../models/shared_device_request.dart';
import '../models/shared_device_response.dart';
import 'idempotency_manager.dart';
import 'server_transport.dart';

/// Callback invoked when a command message is received for a peripheral.
///
/// Returns a [SharedDeviceResponse], [Map], [bool], or any serializable value.
typedef OnMessageReceivedCallback =
    FutureOr<dynamic> Function(String deviceId, dynamic message);


/// Callback invoked when binary data (e.g. image, PDF, raw bytes) is received for a peripheral.
typedef OnBinaryReceivedCallback =
    FutureOr<dynamic> Function(
      String deviceId,
      List<int> bytes, {
      required String contentType,
      String? fileName,
      String? requestId,
    });

/// A high-performance local network server that hosts and shares connected hardware peripherals
/// (e.g. receipt printers, barcode scanners, cash drawers, scales) over HTTP with mDNS discovery.
///
/// Native platforms (Android, iOS, macOS, Windows, Linux) can act as servers.
/// Flutter Web cannot host a server and will throw [UnsupportedPlatformException] if start is attempted.
class SharedDeviceNetworkServer {
  /// Protocol version exposed by this server.
  final String protocolVersion;

  /// Configurable CORS policy for web browser clients.
  final CorsPolicy corsPolicy;

  /// Optional TLS/SSL SecurityContext for HTTPS operation.
  final dynamic securityContext;

  /// Maximum permitted request body size in bytes (default: 50MB).
  final int maxBodySizeBytes;

  /// Extra metadata advertised in mDNS and returned in `/api/v1/info`.
  final Map<String, dynamic> metadata;

  final Map<String, SharedDeviceRecord> _devices = {};
  final IdempotencyManager _idempotencyManager;
  final ServerTransport _transport;
  final DiscoveryProvider _discovery;

  DateTime? _startedAt;
  OnMessageReceivedCallback? _onMessageReceived;
  OnBinaryReceivedCallback? _onBinaryReceived;

  SharedDeviceNetworkServer({
    @Deprecated('No longer used.') String? serverId,
    @Deprecated('No longer used.') String? serverName,
    this.protocolVersion = '1.0',
    CorsPolicy? corsPolicy,
    this.securityContext,
    this.maxBodySizeBytes = 50 * 1024 * 1024, // 50 MB
    Duration idempotencyTtl = const Duration(minutes: 5),
    int idempotencyCapacity = 1000,
    Map<String, dynamic>? metadata,
    OnMessageReceivedCallback? onMessageReceived,
    OnBinaryReceivedCallback? onBinaryReceived,
    ServerTransport? transport,
    DiscoveryProvider? discovery,
  })  : corsPolicy = corsPolicy ?? const CorsPolicy(),
        metadata = metadata != null ? Map<String, dynamic>.from(metadata) : {},
        _onMessageReceived = onMessageReceived,
        _onBinaryReceived = onBinaryReceived,
        _idempotencyManager = IdempotencyManager(
          ttl: idempotencyTtl,
          maxCapacity: idempotencyCapacity,
        ),
        _transport = transport ?? getServerTransport(),
        _discovery = discovery ?? getDiscoveryProvider();

  // ---------------------------------------------------------------------------
  // Getters & Properties
  // ---------------------------------------------------------------------------

  /// Whether the HTTP server is currently running.
  bool get isRunning => _transport.isRunning;

  /// Active listening HTTP port.
  int? get port => _transport.port;

  /// Standard mDNS discovery port (5353) or configured port (backward compatibility getter).
  int get discoveryPort => _discoveryPort ?? 5353;
  int? _discoveryPort;

  /// Bound host address.
  String? get host => _transport.host;

  /// List of registered shared devices.
  List<SharedDeviceRecord> get devices => List.unmodifiable(_devices.values);

  /// Number of registered devices on this server.
  int get deviceCount => _devices.length;

  /// Server uptime in seconds, or 0 if not running.
  int get uptimeSeconds => _startedAt == null
      ? 0
      : DateTime.now().difference(_startedAt!).inSeconds;

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  /// Registers the callback for command requests.
  void onMessageReceived(OnMessageReceivedCallback callback) {
    _onMessageReceived = callback;
  }

  /// Backward-compatibility alias for [onMessageReceived].
  void onDataReceived(OnMessageReceivedCallback callback) =>
      onMessageReceived(callback);

  /// Registers the callback for binary/multipart uploads.
  void onBinaryReceived(OnBinaryReceivedCallback callback) {
    _onBinaryReceived = callback;
  }

  // ---------------------------------------------------------------------------
  // Device Management
  // ---------------------------------------------------------------------------

  /// Adds a shared connected peripheral to this server.
  Future<void> addDevice(
    String deviceId,
    String deviceName, {
    String? deviceDescription,
    String? pairKey,
    List<String> capabilities = const [],
    Map<String, dynamic>? metadata,
  }) async {
    final trimmedId = deviceId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('Device ID cannot be empty');
    }
    if (_devices.containsKey(trimmedId)) {
      throw ArgumentError('Device ID "$trimmedId" already exists on this server');
    }

    _devices[trimmedId] = SharedDeviceRecord(
      deviceId: trimmedId,
      deviceName: deviceName.trim(),
      deviceDescription: deviceDescription?.trim(),
      pairKey: pairKey,
      capabilities: capabilities,
      metadata: metadata,
      addedAt: DateTime.now(),
    );
  }

  /// Removes a peripheral from this server.
  Future<void> removeDevice(String deviceId) async {
    final trimmedId = deviceId.trim();
    _devices.remove(trimmedId);
  }

  /// Checks if a device ID is hosted on this server.
  bool hasDevice(String deviceId) => _devices.containsKey(deviceId.trim());

  /// Retrieves a registered device record.
  SharedDeviceRecord? getDevice(String deviceId) => _devices[deviceId.trim()];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts the HTTP server and advertises it on the LAN via mDNS/DNS-SD.
  ///
  /// [port] is the HTTP listening port (default: 8080, use 0 for system-assigned).
  /// [host] is the address to bind (default: '0.0.0.0' for all IPv4 interfaces).
  /// [advertise] whether to advertise this server via mDNS (default: true).
  /// [serviceType] the mDNS service type (default: `_shared-device._tcp`).
  Future<void> start({
    int port = 8080,
    String host = '0.0.0.0',
    bool advertise = true,
    String serviceType = kDefaultServiceType,
    int? discoveryPort,
    int? discoverPort,
  }) async {
    _discoveryPort = discoveryPort ?? discoverPort;
    if (_transport.isRunning) {
      return;
    }

    // 1. Start HTTP transport
    await _transport.start(
      host: host,
      port: port,
      corsPolicy: corsPolicy,
      maxBodySizeBytes: maxBodySizeBytes,
      onInfo: _handleGetInfo,
      onDevices: _handleGetDevices,
      onDeviceLookup: _handleGetDeviceLookup,
      onCommand: _handleIncomingCommand,
      onBinary: _handleIncomingBinary,
      securityContext: securityContext,
    );

    _startedAt = DateTime.now();
    final actualPort = _transport.port ?? port;

    // 2. Start mDNS advertisement if enabled and supported
    if (advertise && _discovery.isSupported) {
      try {
        final caps = <String>{};
        for (final d in _devices.values) {
          caps.addAll(d.capabilities);
        }

        final mDnsMeta = <String, String>{};
        metadata.forEach((k, v) {
          if (v != null) mDnsMeta[k] = v.toString();
        });

        await _discovery.startBroadcast(
          serviceType: serviceType,
          port: actualPort,
          protocolVersion: protocolVersion,
          capabilities: caps.toList(),
          metadata: mDnsMeta,
        );
      } catch (_) {}
    }
  }

  /// Stops the HTTP server and unregisters mDNS advertisement.
  Future<void> stop() async {
    _startedAt = null;
    try {
      await _discovery.stopBroadcast();
    } catch (_) {}

    try {
      await _transport.stop();
    } catch (_) {}
  }

  /// Disposes resources, clears devices and cached responses.
  Future<void> dispose() async {
    await stop();
    _devices.clear();
    _idempotencyManager.clear();
    await _discovery.dispose();
    await _transport.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal Request Handlers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _handleGetInfo() {
    final caps = <String>{};
    for (final d in _devices.values) {
      caps.addAll(d.capabilities);
    }

    return {
      'protocolVersion': protocolVersion,
      'port': _transport.port,
      'deviceCount': _devices.length,
      'uptimeSeconds': uptimeSeconds,
      'capabilities': caps.toList(),
      'metadata': metadata,
    };
  }

  List<Map<String, dynamic>> _handleGetDevices() {
    final hostIp = _transport.host ?? '127.0.0.1';
    final portNum = _transport.port ?? 8080;

    return _devices.values
        .map(
          (record) => record
              .toPublicDevice(
                host: hostIp,
                port: portNum,
              )
              .toMap(),
        )
        .toList();
  }

  Map<String, dynamic>? _handleGetDeviceLookup(String deviceId) {
    final record = _devices[deviceId];
    if (record == null) return null;

    final hostIp = _transport.host ?? '127.0.0.1';
    final portNum = _transport.port ?? 8080;

    return record
        .toPublicDevice(
          host: hostIp,
          port: portNum,
        )
        .toMap();
  }

  Future<SharedDeviceResponse> _handleIncomingCommand(
    String deviceId,
    SharedDeviceRequest request,
    String? authHeader,
  ) async {
    final device = _devices[deviceId];
    if (device == null) {
      return SharedDeviceResponse.deviceNotFound(
        requestId: request.requestId,
        message: 'Device "$deviceId" not found on this server',
      );
    }

    // Verify pairKey authentication if required
    if (!_validatePairKey(device, authHeader)) {
      return SharedDeviceResponse.unauthorized(
        requestId: request.requestId,
        message: 'Invalid or missing pair key for device "$deviceId"',
      );
    }

    // Execute with idempotency tracking
    return await _idempotencyManager.handleRequest(request.requestId, () async {
      final handler = _onMessageReceived;
      if (handler == null) {
        return SharedDeviceResponse.deviceNotFound(
          requestId: request.requestId,
          message: 'No message handler registered on server',
        );
      }

      try {
        final result = await handler(deviceId, request.data);
        return _normalizeResponse(result, requestId: request.requestId);
      } catch (e) {
        return SharedDeviceResponse.error(
          e.toString(),
          requestId: request.requestId,
          message: 'Exception occurred processing command for device "$deviceId"',
        );
      }
    });
  }

  Future<SharedDeviceResponse> _handleIncomingBinary(
    String deviceId,
    List<int> bytes, {
    required String contentType,
    String? fileName,
    String? requestId,
    String? authHeader,
  }) async {
    final device = _devices[deviceId];
    if (device == null) {
      return SharedDeviceResponse.deviceNotFound(
        requestId: requestId,
        message: 'Device "$deviceId" not found on this server',
      );
    }

    if (!_validatePairKey(device, authHeader)) {
      return SharedDeviceResponse.unauthorized(
        requestId: requestId,
        message: 'Invalid or missing pair key for device "$deviceId"',
      );
    }

    return await _idempotencyManager.handleRequest(requestId, () async {
      final handler = _onBinaryReceived;
      if (handler == null) {
        return SharedDeviceResponse.deviceNotFound(
          requestId: requestId,
          message: 'No binary handler registered on server',
        );
      }

      try {
        final result = await handler(
          deviceId,
          bytes,
          contentType: contentType,
          fileName: fileName,
          requestId: requestId,
        );
        return _normalizeResponse(result, requestId: requestId);
      } catch (e) {
        return SharedDeviceResponse.error(
          e.toString(),
          requestId: requestId,
          message: 'Exception occurred processing binary for device "$deviceId"',
        );
      }
    });
  }

  bool _validatePairKey(SharedDeviceRecord device, String? authHeader) {
    if (!device.isSecured) return true;
    if (authHeader == null || authHeader.isEmpty) return false;

    var token = authHeader.trim();
    if (token.startsWith('Bearer ') || token.startsWith('bearer ')) {
      token = token.substring(7).trim();
    }

    return token == device.pairKey;
  }

  SharedDeviceResponse _normalizeResponse(dynamic result, {String? requestId}) {
    if (result is SharedDeviceResponse) {
      return result.requestId == null && requestId != null
          ? result.copyWith(requestId: requestId)
          : result;
    } else if (result is Map<String, dynamic>) {
      return SharedDeviceResponse.success(requestId: requestId, data: result);
    } else if (result is bool) {
      return result
          ? SharedDeviceResponse.success(requestId: requestId)
          : SharedDeviceResponse.error(
              'Operation returned false',
              requestId: requestId,
            );
    } else if (result == null) {
      return SharedDeviceResponse.success(requestId: requestId);
    } else {
      return SharedDeviceResponse.success(requestId: requestId, data: result);
    }
  }
}
