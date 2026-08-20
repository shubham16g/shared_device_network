/// Configuration options for [SharedDeviceNetworkClient].
class ClientConfig {
  /// Default timeout for waiting for an acknowledgment (ACK).
  final Duration defaultTimeout;

  /// UDP port used for broadcasting discovery requests.
  final int discoveryPort;

  /// Default server data port if target port is unspecified.
  final int defaultServerPort;

  /// Optional fixed local port to bind client socket to.
  final int clientPort;

  const ClientConfig({
    this.defaultTimeout = const Duration(seconds: 5),
    this.discoveryPort = 8889,
    this.defaultServerPort = 8888,
    this.clientPort = 0,
  });
}
