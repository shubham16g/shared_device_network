import '../models/shared_device_server.dart';

/// Default mDNS service type for the shared device network protocol.
const String kDefaultServiceType = '_shared-device._tcp';

/// Internal abstraction interface for mDNS/DNS-SD discovery and advertisement.
abstract interface class DiscoveryProvider {
  /// Whether mDNS discovery and advertisement are supported on the current runtime platform.
  bool get isSupported;

  /// Starts advertising a local server via mDNS/DNS-SD (Bonjour).
  Future<void> startBroadcast({
    required String serviceType,
    required int port,
    String? serviceName,
    String protocolVersion = '1.0',
    List<String> capabilities = const [],
    Map<String, String> metadata = const {},
  });

  /// Stops advertising the local server.
  Future<void> stopBroadcast();

  /// Starts listening for servers on the local network.
  ///
  /// Returns a stream of unique [SharedDeviceServer]s discovered.
  /// If [excludeServerId] is provided, matching servers will be omitted (for self-filtering).
  Stream<SharedDeviceServer> discoverServers({
    required String serviceType,
    Duration timeout = const Duration(seconds: 4),
    String? excludeServerId,
  });

  /// Discovers servers on the local network once within the [timeout].
  Future<List<SharedDeviceServer>> discoverServersOnce({
    required String serviceType,
    Duration timeout = const Duration(seconds: 4),
    String? excludeServerId,
  });

  /// Releases resources, stops active broadcasts and discoveries.
  Future<void> dispose();
}
