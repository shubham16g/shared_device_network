import 'dart:convert';

/// Represents the status / response of a network message operation or acknowledgment.
class Status {
  /// Indicates whether the operation or request succeeded.
  final bool isSuccess;

  /// HTTP-style status code for the operation (e.g. 200, 400, 401, 404, 408, 500).
  final int statusCode;

  /// Human-readable message or description of the status.
  final String message;

  /// Optional payload data returned from the server or receiver.
  final dynamic data;

  /// Optional error details or exception message if the operation failed.
  final String? error;

  /// Timestamp when the status was generated.
  final DateTime timestamp;

  Status({
    required this.isSuccess,
    this.statusCode = 200,
    this.message = '',
    this.data,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates a successful [Status].
  factory Status.success({
    String message = 'Success',
    dynamic data,
    int statusCode = 200,
    DateTime? timestamp,
  }) {
    return Status(
      isSuccess: true,
      statusCode: statusCode,
      message: message,
      data: data,
      timestamp: timestamp,
    );
  }

  /// Creates a failure / error [Status].
  factory Status.error(
    String error, {
    String message = 'Operation failed',
    int statusCode = 500,
    dynamic data,
    DateTime? timestamp,
  }) {
    return Status(
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: error,
      data: data,
      timestamp: timestamp,
    );
  }

  /// Creates a timeout [Status] when an ACK is not received within the time limit.
  factory Status.timeout({
    String message = 'Request timed out waiting for ACK',
    Duration? timeout,
    int statusCode = 408,
  }) {
    final timeoutMsg = timeout != null
        ? '$message (${timeout.inMilliseconds}ms)'
        : message;
    return Status(
      isSuccess: false,
      statusCode: statusCode,
      message: timeoutMsg,
      error: 'TIMEOUT',
    );
  }

  /// Creates an unauthorized [Status] when device authentication or pairKey validation fails.
  factory Status.unauthorized({
    String message = 'Unauthorized device or invalid pair key',
    int statusCode = 401,
  }) {
    return Status(
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'UNAUTHORIZED',
    );
  }

  /// Creates a device not found [Status].
  factory Status.deviceNotFound({
    String message = 'Target device not found or unreachable',
    int statusCode = 404,
  }) {
    return Status(
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'DEVICE_NOT_FOUND',
    );
  }

  /// Creates a bad request [Status].
  factory Status.badRequest({
    String message = 'Invalid or malformed request',
    int statusCode = 400,
    dynamic data,
  }) {
    return Status(
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'BAD_REQUEST',
      data: data,
    );
  }

  /// Converts this [Status] to a Map.
  Map<String, dynamic> toMap() {
    return {
      'isSuccess': isSuccess,
      'statusCode': statusCode,
      'message': message,
      if (data != null) 'data': data,
      if (error != null) 'error': error,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Creates a [Status] from a Map.
  factory Status.fromMap(Map<String, dynamic> map) {
    return Status(
      isSuccess: map['isSuccess'] == true,
      statusCode: (map['statusCode'] is int)
          ? map['statusCode'] as int
          : int.tryParse(map['statusCode']?.toString() ?? '200') ?? 200,
      message: map['message']?.toString() ?? '',
      data: map['data'],
      error: map['error']?.toString(),
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Creates a [Status] from a JSON string or JSON Map.
  factory Status.fromJson(dynamic source) {
    if (source is String) {
      return Status.fromMap(json.decode(source) as Map<String, dynamic>);
    } else if (source is Map<String, dynamic>) {
      return Status.fromMap(source);
    } else if (source is Map) {
      return Status.fromMap(Map<String, dynamic>.from(source));
    }
    throw ArgumentError('Invalid source type for Status.fromJson: ${source.runtimeType}');
  }

  /// Converts this [Status] to a JSON string.
  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'Status(isSuccess: $isSuccess, statusCode: $statusCode, message: $message, error: $error, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Status &&
        other.isSuccess == isSuccess &&
        other.statusCode == statusCode &&
        other.message == message &&
        other.error == error;
  }

  @override
  int get hashCode {
    return Object.hash(isSuccess, statusCode, message, error);
  }
}
