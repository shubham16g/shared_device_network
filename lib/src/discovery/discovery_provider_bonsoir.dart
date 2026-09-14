import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import '../models/shared_device_server.dart';
import 'discovery_provider_interface.dart';

/// Native implementation of [DiscoveryProvider] using mDNS/DNS-SD (Bonjour) via Bonsoir.
class NativeDiscoveryProvider implements DiscoveryProvider {
  BonsoirBroadcast? _broadcast;
  bool _isBroadcasting = false;

  @override
  bool get isSupported => true;

  @override
  Future<void> startBroadcast({
    required String serviceType,
    required int port,
    String? serviceName,
    String protocolVersion = '1.0',
    List<String> capabilities = const [],
    Map<String, String> metadata = const {},
  }) async {
    if (_isBroadcasting) {
      await stopBroadcast();
    }

    final name = serviceName ?? 'sdn-$port';

    // Attributes for TXT record (kept lightweight, RFC 6763 keys < 9 chars)
    final attributes = <String, String>{
      'ver': protocolVersion,
      if (capabilities.isNotEmpty) 'caps': capabilities.join(','),
      ...metadata,
    };

    try {
      final service = BonsoirService(
        name: name,
        type: serviceType,
        port: port,
        attributes: attributes,
      );

      _broadcast = BonsoirBroadcast(service: service, printLogs: false);
      await _broadcast!.initialize();
      await _broadcast!.start();
      _isBroadcasting = true;
    } catch (_) {
      await stopBroadcast();
      rethrow;
    }
  }

  @override
  Future<void> stopBroadcast() async {
    if (!_isBroadcasting && _broadcast == null) return;
    try {
      await _broadcast?.stop();
    } catch (_) {
    } finally {
      _broadcast = null;
      _isBroadcasting = false;
    }
  }

  @override
  Stream<SharedDeviceServer> discoverServers({
    required String serviceType,
    Duration timeout = const Duration(seconds: 4),
    String? excludeServerId,
  }) {
    late StreamController<SharedDeviceServer> controller;
    final discoveredServerIds = <String>{};
    BonsoirDiscovery? discovery;
    StreamSubscription? subscription;
    Timer? timeoutTimer;

    Future<void> cleanup() async {
      timeoutTimer?.cancel();
      await subscription?.cancel();
      try {
        await discovery?.stop();
      } catch (_) {}
      discovery = null;
    }

    controller = StreamController<SharedDeviceServer>(
      onListen: () async {
        try {
          discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
          await discovery!.initialize();

          subscription = discovery!.eventStream?.listen((event) {
            if (event is BonsoirDiscoveryServiceFoundEvent) {
              // Resolve the service to retrieve IP address, port and TXT attributes
              try {
                discovery?.serviceResolver.resolveService(event.service);
              } catch (_) {}
            } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
              final resolved = event.service;
              final server = _parseDiscoveredService(resolved);
              if (server != null) {
                // Self-discovery filtering
                if (excludeServerId != null && server.serverId == excludeServerId) {
                  return;
                }

                if (discoveredServerIds.add(server.serverId)) {
                  if (!controller.isClosed) {
                    controller.add(server);
                  }
                }
              }
            }
          });

          await discovery!.start();

          timeoutTimer = Timer(timeout, () async {
            await cleanup();
            if (!controller.isClosed) {
              controller.close();
            }
          });
        } catch (e) {
          await cleanup();
          if (!controller.isClosed) {
            controller.addError(e);
            controller.close();
          }
        }
      },
      onCancel: () async {
        await cleanup();
      },
    );

    return controller.stream;
  }

  @override
  Future<List<SharedDeviceServer>> discoverServersOnce({
    required String serviceType,
    Duration timeout = const Duration(seconds: 4),
    String? excludeServerId,
  }) async {
    final servers = <SharedDeviceServer>[];
    await for (final server in discoverServers(
      serviceType: serviceType,
      timeout: timeout,
      excludeServerId: excludeServerId,
    )) {
      servers.add(server);
    }
    return servers;
  }

  SharedDeviceServer? _parseDiscoveredService(BonsoirService service) {
    // Attempt to extract IP or hostname
    String? host = service.hostAddress;
    if (host == null || host.isEmpty || host == '0.0.0.0') {
      if (service.hostAddresses.isNotEmpty) {
        // Prefer IPv4
        host = service.hostAddresses.firstWhere(
          (addr) => !addr.contains(':'),
          orElse: () => service.hostAddresses.first,
        );
      }
    }
    host ??= service.hostname;
    if (host == null || host.isEmpty) return null;

    final attrs = service.attributes;
    final serverId = attrs['id'] ?? service.name;
    final serverName = attrs['name'] ?? service.name;
    final version = attrs['ver'] ?? '1.0';
    final capsRaw = attrs['caps'] ?? '';
    final caps = capsRaw.isNotEmpty
        ? capsRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    final metadata = Map<String, dynamic>.from(attrs);
    metadata.remove('id');
    metadata.remove('name');
    metadata.remove('ver');
    metadata.remove('caps');

    return SharedDeviceServer(
      serverId: serverId,
      serverName: serverName,
      host: host,
      port: service.port,
      protocolVersion: version,
      capabilities: caps,
      metadata: metadata,
      discoveredAt: DateTime.now(),
    );
  }

  @override
  Future<void> dispose() async {
    await stopBroadcast();
  }
}

/// Factory function for native platform.
DiscoveryProvider createDiscoveryProvider() => NativeDiscoveryProvider();
