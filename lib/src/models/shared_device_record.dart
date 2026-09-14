import 'dart:convert';
import 'shared_device.dart';

/// Represents a shared connected device/service registered and hosted by the server.
///
/// Holds server-side state including private credentials (such as [pairKey])
/// that are kept confidential and never returned directly to network clients.
class SharedDeviceRecord {
  /// Unique identifier of the shared device (e.g. 'printer-bluetooth-01').
  final String deviceId;

  /// Human-readable name of the device (e.g. 'Epson TM-T88VI').
  final String deviceName;

  /// Optional description or details (e.g. 'Kitchen Thermal Printer').
  final String? deviceDescription;

  /// Optional pairing key required to communicate with this shared device.
  /// Kept private on the server.
  final String? pairKey;

  /// Supported peripheral capabilities (e.g. ['escpos', 'thermal', 'cut']).
  final List<String> capabilities;

  /// Optional metadata associated with the device.
  final Map<String, dynamic>? metadata;

  /// Timestamp when the device was added to the server.
  final DateTime addedAt;

  SharedDeviceRecord({
    required this.deviceId,
    required this.deviceName,
    this.deviceDescription,
    this.pairKey,
    this.capabilities = const [],
    this.metadata,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// Whether this device requires a pair key for access.
  bool get isSecured => pairKey != null && pairKey!.isNotEmpty;

  /// Converts this server record into a public [SharedDevice] instance safe to transmit over HTTP.
  SharedDevice toPublicDevice({
    required String host,
    required int port,
  }) {
    return SharedDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      deviceDescription: deviceDescription,
      deviceIp: host,
      devicePort: port,
      isSecured: isSecured,
      capabilities: capabilities,
      metadata: metadata,
      addedAt: addedAt,
    );
  }

  /// Converts to Map.
  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      if (deviceDescription != null) 'deviceDescription': deviceDescription,
      if (pairKey != null) 'pairKey': pairKey,
      if (capabilities.isNotEmpty) 'capabilities': capabilities,
      if (metadata != null) 'metadata': metadata,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  /// Creates from Map.
  factory SharedDeviceRecord.fromMap(Map<String, dynamic> map) {
    return SharedDeviceRecord(
      deviceId: map['deviceId']?.toString() ?? '',
      deviceName: map['deviceName']?.toString() ?? '',
      deviceDescription: map['deviceDescription']?.toString(),
      pairKey: map['pairKey']?.toString(),
      capabilities: map['capabilities'] is List
          ? (map['capabilities'] as List).map((e) => e.toString()).toList()
          : const [],
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
      addedAt: map['addedAt'] != null
          ? DateTime.tryParse(map['addedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Converts to JSON string.
  String toJson() => json.encode(toMap());

  /// Creates from JSON string or Map.
  factory SharedDeviceRecord.fromJson(dynamic source) {
    if (source is String) {
      return SharedDeviceRecord.fromMap(
        json.decode(source) as Map<String, dynamic>,
      );
    } else if (source is Map<String, dynamic>) {
      return SharedDeviceRecord.fromMap(source);
    } else if (source is Map) {
      return SharedDeviceRecord.fromMap(Map<String, dynamic>.from(source));
    }
    throw ArgumentError(
      'Invalid source type for SharedDeviceRecord.fromJson: ${source.runtimeType}',
    );
  }

  /// Copies with modifications.
  SharedDeviceRecord copyWith({
    String? deviceId,
    String? deviceName,
    String? deviceDescription,
    String? pairKey,
    List<String>? capabilities,
    Map<String, dynamic>? metadata,
    DateTime? addedAt,
  }) {
    return SharedDeviceRecord(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      deviceDescription: deviceDescription ?? this.deviceDescription,
      pairKey: pairKey ?? this.pairKey,
      capabilities: capabilities ?? this.capabilities,
      metadata: metadata ?? this.metadata,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  String toString() {
    return 'SharedDeviceRecord(deviceId: $deviceId, deviceName: $deviceName, secured: $isSecured)';
  }
}
