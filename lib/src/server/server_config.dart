/// Configuration options for [SharedDeviceNetworkServer].
class ServerConfig {
  /// UDP port for data messages and direct ACKs (default: 8888).
  final int port;

  /// UDP port for discovery requests and announcements (default: 8889).
  final int discoveryPort;

  /// Whether the server requires device registration / valid pairKey to accept messages.
  final bool requirePairing;

  /// Default pair key accepted for all requests if device-specific pair key is not set.
  final String? defaultPairKey;

  /// Custom broadcast address to bind/respond to if applicable.
  final String? bindAddress;

  const ServerConfig({
    this.port = 8888,
    this.discoveryPort = 8889,
    this.requirePairing = false,
    this.defaultPairKey,
    this.bindAddress,
  });
}
