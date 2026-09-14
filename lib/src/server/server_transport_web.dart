import '../models/cors_policy.dart';
import '../models/exceptions.dart';
import 'server_transport_interface.dart';

/// Web implementation of [ServerTransport].
///
/// Running an HTTP server is not possible in browser environments.
/// Web targets can only act as clients.
class ServerTransportWeb implements ServerTransport {
  @override
  bool get isRunning => false;

  @override
  int? get port => null;

  @override
  String? get host => null;

  @override
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
  }) async {
    throw const UnsupportedPlatformException(
      'Hosting a SharedDeviceNetworkServer is not supported on Flutter Web. '
      'Web applications can only act as clients using SharedDeviceNetworkClient.',
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Factory function for web platform.
ServerTransport createServerTransport() => ServerTransportWeb();
