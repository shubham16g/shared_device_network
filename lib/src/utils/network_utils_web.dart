/// Web implementation of network interface inspection (stubbed as browsers cannot inspect OS interfaces).
class NetworkUtilsPlatform {
  /// Always returns localhost on web platforms.
  static Future<List<String>> getLocalIPv4Addresses({
    bool includeLoopback = false,
  }) async {
    return includeLoopback ? ['127.0.0.1'] : [];
  }

  /// Returns fallback on web platforms.
  static Future<String> getPrimaryLocalIPv4({
    String fallback = '127.0.0.1',
  }) async {
    return fallback;
  }
}
