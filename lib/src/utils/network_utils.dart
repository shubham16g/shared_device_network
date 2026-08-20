import 'dart:io';

/// Helper utilities for local network interface inspection and UDP broadcast discovery.
class NetworkUtils {
  /// Retrieves a list of active local IPv4 addresses on the host machine/device.
  static Future<List<InternetAddress>> getLocalIPv4Addresses({
    bool includeLoopback = false,
  }) async {
    final addresses = <InternetAddress>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: includeLoopback,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4) {
            if (!includeLoopback && (address.isLoopback || address.address.startsWith('127.'))) {
              continue;
            }
            addresses.add(address);
          }
        }
      }
    } catch (_) {}

    if (addresses.isEmpty && includeLoopback) {
      addresses.add(InternetAddress.loopbackIPv4);
    }

    return addresses;
  }

  /// Retrieves the primary local IPv4 address string (e.g. `192.168.1.100`), or `127.0.0.1` if none found.
  static Future<String> getPrimaryLocalIPv4({String fallback = '127.0.0.1'}) async {
    final addresses = await getLocalIPv4Addresses(includeLoopback: false);
    if (addresses.isNotEmpty) {
      return addresses.first.address;
    }
    return fallback;
  }

  /// Retrieves broadcast addresses suitable for discovery across all active network interfaces.
  /// Always includes the universal broadcast address `255.255.255.255`.
  static Future<List<InternetAddress>> getBroadcastAddresses() async {
    final broadcastSet = <String>{};
    final broadcastAddresses = <InternetAddress>[];

    // Always include universal broadcast
    final universal = InternetAddress('255.255.255.255');
    broadcastAddresses.add(universal);
    broadcastSet.add(universal.address);

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
            final parts = address.address.split('.');
            if (parts.length == 4) {
              // Subnet /24 broadcast (e.g. 192.168.1.255)
              final subnet24 = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              if (broadcastSet.add(subnet24)) {
                try {
                  broadcastAddresses.add(InternetAddress(subnet24));
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}

    return broadcastAddresses;
  }
}
