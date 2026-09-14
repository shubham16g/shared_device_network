import 'server_transport_interface.dart';

/// Fallback factory for unknown platforms.
ServerTransport createServerTransport() {
  throw UnsupportedError('Cannot create ServerTransport on this platform');
}
