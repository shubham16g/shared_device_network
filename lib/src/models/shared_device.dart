import 'dart:convert';

/// Represents a peripheral device (e.g. printer, scanner, display) hosted by a shared device network node.
class SharedDevice {
  /// Unique identifier of the peripheral device (e.g. 'printer-01').
  final String deviceId;

  /// Human-readable name of the peripheral device (e.g. 'Kitchen Thermal Printer').
  final String deviceName;

  /// Optional description of the device or service.
  final String? deviceDescription;

  /// IP address or hostname of the hosting device.
  final String deviceIp;

  /// HTTP port number the hosting device is listening on.
  final int devicePort;

  /// Whether this peripheral requires authentication (pairKey).
  final bool isSecured;

  /// List of capabilities advertised for this peripheral (e.g. ['escpos', 'thermal', 'cut']).
  final List<String> capabilities;

  /// Optional additional metadata attached to the peripheral.
  final Map<String, dynamic>? metadata;

  /// Timestamp when this peripheral was registered on the server.
  final DateTime? addedAt;

  const SharedDevice({
    required this.deviceId,
    required this.deviceName,
    this.deviceDescription,
    required this.deviceIp,
    required this.devicePort,
    this.isSecured = false,
    this.capabilities = const [],
    this.metadata,
    this.addedAt,
  });

  /// Creates a [SharedDevice] from a Map.
  factory SharedDevice.fromMap(Map<String, dynamic> map) {
    return SharedDevice(
      deviceId: map['deviceId']?.toString() ?? '',
      deviceName: map['deviceName']?.toString() ?? '',
      deviceDescription: map['deviceDescription']?.toString(),
      deviceIp: map['deviceIp']?.toString() ?? '',
      devicePort: (map['devicePort'] is int)
          ? map['devicePort'] as int
          : int.tryParse(map['devicePort']?.toString() ?? '0') ?? 0,
      isSecured: map['isSecured'] == true,
      capabilities: map['capabilities'] is List
          ? (map['capabilities'] as List).map((e) => e.toString()).toList()
          : const [],
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
      addedAt: map['addedAt'] != null
          ? DateTime.tryParse(map['addedAt'].toString())
          : null,
    );
  }

  /// Converts this [SharedDevice] instance to a Map.
  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (deviceDescription != null) 'deviceDescription': deviceDescription,
      'deviceIp': deviceIp,
      'devicePort': devicePort,
      'isSecured': isSecured,
      if (capabilities.isNotEmpty) 'capabilities': capabilities,
      if (metadata != null) 'metadata': metadata,
      if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
    };
  }

  /// Creates a [SharedDevice] from a JSON string or JSON Map.
  factory SharedDevice.fromJson(dynamic source) {
    if (source is String) {
      return SharedDevice.fromMap(json.decode(source) as Map<String, dynamic>);
    } else if (source is Map<String, dynamic>) {
      return SharedDevice.fromMap(source);
    } else if (source is Map) {
      return SharedDevice.fromMap(Map<String, dynamic>.from(source));
    }
    throw ArgumentError(
      'Invalid source type for SharedDevice.fromJson: ${source.runtimeType}',
    );
  }

  /// Converts this [SharedDevice] to a JSON string.
  String toJson() => json.encode(toMap());

  /// Returns a copy with updated properties.
  SharedDevice copyWith({
    String? deviceId,
    String? deviceName,
    String? deviceDescription,
    String? deviceIp,
    int? devicePort,
    bool? isSecured,
    List<String>? capabilities,
    Map<String, dynamic>? metadata,
    DateTime? addedAt,
  }) {
    return SharedDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceDescription: deviceDescription ?? this.deviceDescription,
      deviceIp: deviceIp ?? this.deviceIp,
      devicePort: devicePort ?? this.devicePort,
      isSecured: isSecured ?? this.isSecured,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  String toString() {
    return 'SharedDevice(id: $deviceId, name: $deviceName, ip: $deviceIp:$devicePort, secured: $isSecured)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SharedDevice &&
        other.deviceId == deviceId &&
        other.deviceName == deviceName &&
        other.deviceDescription == deviceDescription &&
        other.deviceIp == deviceIp &&
        other.devicePort == devicePort;
  }

  @override
  int get hashCode {
    return Object.hash(
      deviceId,
      deviceName,
      deviceDescription,
      deviceIp,
      devicePort,
    );
  }
}
