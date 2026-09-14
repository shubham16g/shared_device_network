import 'server_transport_interface.dart';
import 'server_transport_stub.dart'
    if (dart.library.io) 'http_server_transport_io.dart'
    if (dart.library.js_interop) 'server_transport_web.dart'
    as transport_impl;

export 'server_transport_interface.dart';

/// Creates the platform-appropriate [ServerTransport] instance.
ServerTransport getServerTransport() => transport_impl.createServerTransport();
