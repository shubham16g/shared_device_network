import 'dart:io';

/// Native implementation of network interface inspection.
class NetworkUtilsPlatform {
  /// Retrieves a list of active local IPv4 address strings.
  static Future<List<String>> getLocalIPv4Addresses({
    bool includeLoopback = false,
  }) async {
    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: includeLoopback,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            if (!includeLoopback &&
                (address.isLoopback || address.address.startsWith('127.'))) {
              continue;
            }
            addresses.add(address.address);
          }
        }
      }
    } catch (_) {}

    if (addresses.isEmpty && includeLoopback) {
      addresses.add('127.0.0.1');
    }

    return addresses;
  }

  /// Retrieves the primary local IPv4 address string (e.g. `192.168.1.100`).
  static Future<String> getPrimaryLocalIPv4({
    String fallback = '127.0.0.1',
  }) async {
    final addresses = await getLocalIPv4Addresses(includeLoopback: false);
    if (addresses.isNotEmpty) {
      return addresses.first;
    }
    return fallback;
  }
}
