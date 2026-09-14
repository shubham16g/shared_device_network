import 'discovery_provider_interface.dart';

/// Fallback factory for unknown platforms.
DiscoveryProvider createDiscoveryProvider() {
  throw UnsupportedError('Cannot create DiscoveryProvider on this platform');
}
