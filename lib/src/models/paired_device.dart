import 'dart:convert';

/// Represents an authorized or paired device registered on the server.
class PairedDevice {
  /// Unique identifier of the device.
  final String deviceId;

  /// Human-readable name of the device.
  final String deviceName;

  /// Optional description of the device.
  final String? deviceDescription;

  /// Optional pairing key required to authenticate messages from this device.
  final String? pairKey;

  /// Timestamp when the device was added/paired.
  final DateTime addedAt;

  /// Timestamp when the device was last seen communicating.
  final DateTime? lastSeenAt;

  PairedDevice({
    required this.deviceId,
    required this.deviceName,
    this.deviceDescription,
    this.pairKey,
    DateTime? addedAt,
    this.lastSeenAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Converts this [PairedDevice] to a Map.
  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (deviceDescription != null) 'deviceDescription': deviceDescription,
      if (pairKey != null) 'pairKey': pairKey,
      'addedAt': addedAt.toIso8601String(),
      if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
    };
  }

  /// Creates a [PairedDevice] from a Map.
  factory PairedDevice.fromMap(Map<String, dynamic> map) {
    return PairedDevice(
      deviceId: map['deviceId']?.toString() ?? '',
      deviceName: map['deviceName']?.toString() ?? '',
      deviceDescription: map['deviceDescription']?.toString(),
      pairKey: map['pairKey']?.toString(),
      addedAt: map['addedAt'] != null
          ? DateTime.tryParse(map['addedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastSeenAt: map['lastSeenAt'] != null
          ? DateTime.tryParse(map['lastSeenAt'].toString())
          : null,
    );
  }

  /// Creates a [PairedDevice] from a JSON string or Map.
  factory PairedDevice.fromJson(dynamic source) {
    if (source is String) {
      return PairedDevice.fromMap(json.decode(source) as Map<String, dynamic>);
    } else if (source is Map<String, dynamic>) {
      return PairedDevice.fromMap(source);
    } else if (source is Map) {
      return PairedDevice.fromMap(Map<String, dynamic>.from(source));
    }
    throw ArgumentError('Invalid source type for PairedDevice.fromJson: ${source.runtimeType}');
  }

  /// Converts this [PairedDevice] to a JSON string.
  String toJson() => json.encode(toMap());

  /// Returns a copy with updated properties.
  PairedDevice copyWith({
    String? deviceId,
    String? deviceName,
    String? deviceDescription,
    String? pairKey,
    DateTime? addedAt,
    DateTime? lastSeenAt,
  }) {
    return PairedDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceDescription: deviceDescription ?? this.deviceDescription,
      pairKey: pairKey ?? this.pairKey,
      addedAt: addedAt ?? this.addedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  @override
  String toString() {
    return 'PairedDevice(deviceId: $deviceId, deviceName: $deviceName, deviceDescription: $deviceDescription, pairKey: $pairKey, addedAt: $addedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PairedDevice &&
        other.deviceId == deviceId &&
        other.deviceName == deviceName &&
        other.deviceDescription == deviceDescription &&
        other.pairKey == pairKey;
  }

  @override
  int get hashCode {
    return Object.hash(deviceId, deviceName, deviceDescription, pairKey);
  }
}
