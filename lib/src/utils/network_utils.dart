import 'network_utils_io.dart'
    if (dart.library.js_interop) 'network_utils_web.dart'
    as platform;

/// Cross-platform helper utilities for local network interface inspection.
class NetworkUtils {
  /// Retrieves a list of active local IPv4 addresses on the host machine/device.
  static Future<List<String>> getLocalIPv4Addresses({
    bool includeLoopback = false,
  }) {
    return platform.NetworkUtilsPlatform.getLocalIPv4Addresses(
      includeLoopback: includeLoopback,
    );
  }

  /// Retrieves the primary local IPv4 address string (e.g. `192.168.1.100`), or `127.0.0.1` if none found.
  static Future<String> getPrimaryLocalIPv4({
    String fallback = '127.0.0.1',
  }) {
    return platform.NetworkUtilsPlatform.getPrimaryLocalIPv4(
      fallback: fallback,
    );
  }
}
