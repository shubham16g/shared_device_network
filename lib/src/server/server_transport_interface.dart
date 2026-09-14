import 'dart:async';
import '../models/cors_policy.dart';
import '../models/shared_device_request.dart';
import '../models/shared_device_response.dart';

/// Callbacks supplied by the server engine to the network transport.
typedef ServerInfoHandler = Map<String, dynamic> Function();
typedef DeviceListHandler = List<Map<String, dynamic>> Function();
typedef DeviceLookupHandler = Map<String, dynamic>? Function(String deviceId);
typedef CommandHandler = Future<SharedDeviceResponse> Function(
  String deviceId,
  SharedDeviceRequest request,
  String? authHeader,
);
typedef BinaryHandler = Future<SharedDeviceResponse> Function(
  String deviceId,
  List<int> bytes, {
  required String contentType,
  String? fileName,
  String? requestId,
  String? authHeader,
});

/// Internal abstraction interface for the HTTP server transport.
abstract interface class ServerTransport {
  /// Whether the HTTP server is currently listening.
  bool get isRunning;

  /// The active listening port of the server.
  int? get port;

  /// The bound address or hostname of the server.
  String? get host;

  /// Starts listening for HTTP requests.
  Future<void> start({
    required String host,
    required int port,
    required CorsPolicy corsPolicy,
    required int maxBodySizeBytes,
    required ServerInfoHandler onInfo,
    required DeviceListHandler onDevices,
    required DeviceLookupHandler onDeviceLookup,
    required CommandHandler onCommand,
    required BinaryHandler onBinary,
    dynamic securityContext,
  });

  /// Stops listening and closes active connections.
  Future<void> stop();

  /// Disposes resources.
  Future<void> dispose();
}
