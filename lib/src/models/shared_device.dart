import 'dart:convert';

/// Represents a network device discovered or communicating within the shared device network.
class SharedDevice {
  /// Unique identifier of the device.
  final String deviceId;

  /// Human-readable name of the device.
  final String deviceName;

  /// Optional description of the device or service.
  final String? deviceDescription;

  /// IP address of the device on the local network.
  final String deviceIp;

  /// UDP port number the device is listening on.
  final int devicePort;

  /// Optional additional metadata attached to the device broadcast.
  final Map<String, dynamic>? metadata;

  const SharedDevice({
    required this.deviceId,
    required this.deviceName,
    this.deviceDescription,
    required this.deviceIp,
    required this.devicePort,
    this.metadata,
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
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
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
      if (metadata != null) 'metadata': metadata,
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
    throw ArgumentError('Invalid source type for SharedDevice.fromJson: ${source.runtimeType}');
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
    Map<String, dynamic>? metadata,
  }) {
    return SharedDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceDescription: deviceDescription ?? this.deviceDescription,
      deviceIp: deviceIp ?? this.deviceIp,
      devicePort: devicePort ?? this.devicePort,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'SharedDevice(deviceId: $deviceId, deviceName: $deviceName, deviceIp: $deviceIp, devicePort: $devicePort, deviceDescription: $deviceDescription)';
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
