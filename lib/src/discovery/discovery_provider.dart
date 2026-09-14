import 'discovery_provider_interface.dart';
import 'discovery_provider_stub.dart'
    if (dart.library.io) 'discovery_provider_bonsoir.dart'
    if (dart.library.js_interop) 'discovery_provider_web.dart'
    as provider_impl;

export 'discovery_provider_interface.dart';

/// Creates the platform-appropriate [DiscoveryProvider] instance.
DiscoveryProvider getDiscoveryProvider() => provider_impl.createDiscoveryProvider();
