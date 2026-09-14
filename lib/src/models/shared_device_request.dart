import 'dart:convert';

/// Represents a command request sent to a peripheral device hosted on a shared device server.
class SharedDeviceRequest {
  /// Unique request identifier for logging and idempotency tracking.
  final String requestId;

  /// Target peripheral device ID on the server.
  final String deviceId;

  /// Name of the command or operation (e.g. 'PRINT_RECEIPT', 'SCAN_BARCODE').
  final String command;

  /// Optional payload data associated with the command (e.g. print parameters, totals).
  final dynamic data;

  /// Optional client metadata or telemetry tags.
  final Map<String, dynamic>? metadata;

  /// Timestamp when the request was originated.
  final DateTime timestamp;

  SharedDeviceRequest({
    required this.requestId,
    required this.deviceId,
    required this.command,
    this.data,
    this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Converts this [SharedDeviceRequest] to a Map.
  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'deviceId': deviceId,
      'command': command,
      if (data != null) 'data': data,
      if (metadata != null) 'metadata': metadata,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Creates a [SharedDeviceRequest] from a Map.
  factory SharedDeviceRequest.fromMap(Map<String, dynamic> map) {
    return SharedDeviceRequest(
      requestId: map['requestId']?.toString() ?? '',
      deviceId: map['deviceId']?.toString() ?? '',
      command: map['command']?.toString() ?? '',
      data: map['data'],
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Creates a [SharedDeviceRequest] from a JSON string or Map.
  factory SharedDeviceRequest.fromJson(dynamic source) {
    if (source is String) {
      return SharedDeviceRequest.fromMap(
        json.decode(source) as Map<String, dynamic>,
      );
    } else if (source is Map<String, dynamic>) {
      return SharedDeviceRequest.fromMap(source);
    } else if (source is Map) {
      return SharedDeviceRequest.fromMap(Map<String, dynamic>.from(source));
    }
    throw ArgumentError(
      'Invalid source type for SharedDeviceRequest.fromJson: ${source.runtimeType}',
    );
  }

  /// Converts this request to a JSON string.
  String toJson() => json.encode(toMap());

  /// Creates a copy with optionally overridden fields.
  SharedDeviceRequest copyWith({
    String? requestId,
    String? deviceId,
    String? command,
    dynamic data,
    Map<String, dynamic>? metadata,
    DateTime? timestamp,
  }) {
    return SharedDeviceRequest(
      requestId: requestId ?? this.requestId,
      deviceId: deviceId ?? this.deviceId,
      command: command ?? this.command,
      data: data ?? this.data,
      metadata: metadata ?? this.metadata,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'SharedDeviceRequest(id: $requestId, device: $deviceId, cmd: $command)';
  }
}
