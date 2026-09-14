import 'dart:convert';

/// Represents a host server discovered or connected within the local network.
///
/// A server hosts one or more peripheral devices (e.g. printers, scanners, scales)
/// and exposes a versioned HTTP API for management and peripheral communication.
class SharedDeviceServer {
  /// Unique identifier of the server (e.g. 'pos-terminal-01').
  final String serverId;

  /// Human-readable name of the server (e.g. 'Main Counter POS').
  final String serverName;

  /// IP address or hostname of the server.
  final String host;

  /// Port number the HTTP server is listening on (e.g. 8080).
  final int port;

  /// Protocol/API version supported by this server (e.g. '1.0').
  final String protocolVersion;

  /// Advertised capabilities of the server (e.g. ['printer', 'scanner']).
  final List<String> capabilities;

  /// Additional metadata or tags advertised by the server.
  final Map<String, dynamic> metadata;

  /// Number of registered peripheral devices hosted on this server (if reported).
  final int? deviceCount;

  /// Timestamp when this server record was discovered or created.
  final DateTime discoveredAt;

  /// Whether HTTPS/TLS is required or enabled on this server.
  final bool isSecure;

  SharedDeviceServer({
    required this.serverId,
    required this.serverName,
    required this.host,
    required this.port,
    this.protocolVersion = '1.0',
    this.capabilities = const [],
    this.metadata = const {},
    this.deviceCount,
    this.isSecure = false,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  /// Returns the base URI to communicate with this server over HTTP(S).
  Uri get baseUri {
    final scheme = isSecure ? 'https' : 'http';
    return Uri(scheme: scheme, host: host, port: port);
  }

  /// Converts this [SharedDeviceServer] instance to a Map.
  Map<String, dynamic> toMap() {
    return {
      'serverId': serverId,
      'serverName': serverName,
      'host': host,
      'port': port,
      'protocolVersion': protocolVersion,
      if (capabilities.isNotEmpty) 'capabilities': capabilities,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (deviceCount != null) 'deviceCount': deviceCount,
      'isSecure': isSecure,
      'discoveredAt': discoveredAt.toIso8601String(),
    };
  }

  /// Creates a [SharedDeviceServer] from a Map.
  factory SharedDeviceServer.fromMap(Map<String, dynamic> map) {
    return SharedDeviceServer(
      serverId: map['serverId']?.toString() ?? '',
      serverName: map['serverName']?.toString() ?? '',
      host: map['host']?.toString() ?? '',
      port: (map['port'] is int)
          ? map['port'] as int
          : int.tryParse(map['port']?.toString() ?? '8080') ?? 8080,
      protocolVersion: map['protocolVersion']?.toString() ?? '1.0',
      capabilities: map['capabilities'] is List
          ? (map['capabilities'] as List).map((e) => e.toString()).toList()
          : const [],
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : const {},
      deviceCount: map['deviceCount'] is int
          ? map['deviceCount'] as int
          : int.tryParse(map['deviceCount']?.toString() ?? ''),
      isSecure: map['isSecure'] == true,
      discoveredAt: map['discoveredAt'] != null
          ? DateTime.tryParse(map['discoveredAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Creates a [SharedDeviceServer] from a JSON string or Map.
  factory SharedDeviceServer.fromJson(dynamic source) {
    if (source is String) {
      return SharedDeviceServer.fromMap(
        json.decode(source) as Map<String, dynamic>,
      );
    } else if (source is Map<String, dynamic>) {
      return SharedDeviceServer.fromMap(source);
    } else if (source is Map) {
      return SharedDeviceServer.fromMap(Map<String, dynamic>.from(source));
    }
    throw ArgumentError(
      'Invalid source type for SharedDeviceServer.fromJson: ${source.runtimeType}',
    );
  }

  /// Converts this [SharedDeviceServer] to a JSON string.
  String toJson() => json.encode(toMap());

  /// Returns a copy with overridden properties.
  SharedDeviceServer copyWith({
    String? serverId,
    String? serverName,
    String? host,
    int? port,
    String? protocolVersion,
    List<String>? capabilities,
    Map<String, dynamic>? metadata,
    int? deviceCount,
    bool? isSecure,
    DateTime? discoveredAt,
  }) {
    return SharedDeviceServer(
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      host: host ?? this.host,
      port: port ?? this.port,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
      deviceCount: deviceCount ?? this.deviceCount,
      isSecure: isSecure ?? this.isSecure,
      discoveredAt: discoveredAt ?? this.discoveredAt,
    );
  }

  @override
  String toString() {
    return 'SharedDeviceServer(serverId: $serverId, serverName: $serverName, host: $host, port: $port, version: $protocolVersion)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SharedDeviceServer &&
        other.serverId == serverId &&
        other.host == host &&
        other.port == port;
  }

  @override
  int get hashCode => Object.hash(serverId, host, port);
}
