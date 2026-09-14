import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/exceptions.dart';
import '../models/shared_device_server.dart';
import 'discovery_provider_interface.dart';

/// Web implementation of [DiscoveryProvider] using HTTP subnet range probing.
///
/// Because web browsers lack access to raw UDP multicast sockets for native mDNS,
/// this provider automatically scans local candidate hosts (`127.0.0.1`, `localhost`,
/// the host's subnet extracted from `Uri.base`, and common LAN subnets) via concurrent
/// HTTP requests to `/api/v1/info`.
class WebDiscoveryProvider implements DiscoveryProvider {
  final http.Client _client;
  final List<String> defaultSubnetPrefixes;
  final int defaultPort;

  WebDiscoveryProvider({
    http.Client? client,
    this.defaultSubnetPrefixes = const ['192.168.1.', '192.168.0.'],
    this.defaultPort = 8080,
  }) : _client = client ?? http.Client();

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
    throw const UnsupportedPlatformException(
      'Server hosting and mDNS advertisement are not supported in web browsers. '
      'Run the server on a native platform (Android, iOS, Windows, macOS, Linux).',
    );
  }

  @override
  Future<void> stopBroadcast() async {
    // No-op on web
  }

  @override
  Stream<SharedDeviceServer> discoverServers({
    required String serviceType,
    Duration timeout = const Duration(seconds: 4),
    String? excludeServerId,
  }) {
    late StreamController<SharedDeviceServer> controller;
    bool isCancelled = false;

    controller = StreamController<SharedDeviceServer>(
      onListen: () async {
        try {
          final foundEndpoints = <String>{};

          // 1. Initial immediate local targets (for same-machine dev testing)
          final initialTargets = <String>['127.0.0.1', 'localhost'];

          // 2. Extract subnet from current browser URL if loaded via LAN IP
          final subnets = <String>{...defaultSubnetPrefixes};
          final currentHost = Uri.base.host;

          final ipMatch = RegExp(r'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.)\d{1,3}$').firstMatch(currentHost);
          if (ipMatch != null) {
            final detectedSubnet = ipMatch.group(1)!;
            subnets.add(detectedSubnet);
            initialTargets.insert(0, currentHost);
          }

          // Probe immediate targets first
          for (final target in initialTargets) {
            if (isCancelled || controller.isClosed) return;
            final server = await _probeHost(target, defaultPort, timeout: const Duration(milliseconds: 300));
            if (server != null && foundEndpoints.add('$target:$defaultPort')) {
              if (excludeServerId == null || server.serverId != excludeServerId) {
                if (!controller.isClosed) controller.add(server);
              }
            }
          }

          // 3. Build IP candidate list for subnets
          final ipCandidates = <String>[];
          for (final prefix in subnets) {
            for (var i = 1; i <= 254; i++) {
              ipCandidates.add('$prefix$i');
            }
          }

          // Concurrently probe in batches of 25
          const batchSize = 25;
          final probeTimeout = Duration(
            milliseconds: (timeout.inMilliseconds ~/ (ipCandidates.length / batchSize)).clamp(300, 800),
          );

          for (var i = 0; i < ipCandidates.length; i += batchSize) {
            if (isCancelled || controller.isClosed) break;
            final end = (i + batchSize < ipCandidates.length) ? i + batchSize : ipCandidates.length;
            final batch = ipCandidates.sublist(i, end);

            final futures = batch.map((ip) async {
              if (foundEndpoints.contains('$ip:$defaultPort')) return;
              final server = await _probeHost(ip, defaultPort, timeout: probeTimeout);
              if (server != null && foundEndpoints.add('$ip:$defaultPort')) {
                if (excludeServerId == null || server.serverId != excludeServerId) {
                  if (!controller.isClosed && !isCancelled) {
                    controller.add(server);
                  }
                }
              }
            });

            await Future.wait(futures);
          }

          if (!controller.isClosed) {
            controller.close();
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError(e);
            controller.close();
          }
        }
      },
      onCancel: () {
        isCancelled = true;
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
    final list = <SharedDeviceServer>[];
    await for (final srv in discoverServers(
      serviceType: serviceType,
      timeout: timeout,
      excludeServerId: excludeServerId,
    )) {
      list.add(srv);
    }
    return list;
  }

  Future<SharedDeviceServer?> _probeHost(
    String host,
    int port, {
    Duration timeout = const Duration(milliseconds: 600),
  }) async {
    try {
      final uri = Uri(scheme: 'http', host: host, port: port, path: '/api/v1/info');
      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = json.decode(res.body);
        if (data is Map) {
          final version = data['protocolVersion']?.toString() ?? '1.0';
          final deviceCount = data['deviceCount'] is int ? data['deviceCount'] as int : null;
          final caps = data['capabilities'] is List
              ? (data['capabilities'] as List).map((e) => e.toString()).toList()
              : <String>[];

          return SharedDeviceServer(
            serverId: '$host:$port',
            serverName: 'Host ($host:$port)',
            host: host,
            port: port,
            protocolVersion: version,
            capabilities: caps,
            deviceCount: deviceCount,
            discoveredAt: DateTime.now(),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> dispose() async {
    _client.close();
  }
}

/// Factory function for web platform.
DiscoveryProvider createDiscoveryProvider() => WebDiscoveryProvider();
