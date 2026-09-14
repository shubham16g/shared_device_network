import 'dart:convert';

/// Represents the response / acknowledgment of a shared device network operation.
class SharedDeviceResponse {
  /// Unique request identifier matching the client request (if provided).
  final String? requestId;

  /// Indicates whether the operation or request succeeded.
  final bool isSuccess;

  /// HTTP-style status code for the operation (e.g. 200, 400, 401, 403, 404, 408, 409, 413, 500).
  final int statusCode;

  /// Human-readable message or description of the status.
  final String message;

  /// Optional payload data returned from the server or peripheral device.
  final dynamic data;

  /// Optional error details or exception message if the operation failed.
  final String? error;

  /// Timestamp when the response was generated.
  final DateTime timestamp;

  SharedDeviceResponse({
    this.requestId,
    required this.isSuccess,
    this.statusCode = 200,
    this.message = '',
    this.data,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates a successful [SharedDeviceResponse].
  factory SharedDeviceResponse.success({
    String? requestId,
    String message = 'Success',
    dynamic data,
    int statusCode = 200,
    DateTime? timestamp,
  }) {
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: true,
      statusCode: statusCode,
      message: message,
      data: data,
      timestamp: timestamp,
    );
  }

  /// Creates a failure / error [SharedDeviceResponse].
  factory SharedDeviceResponse.error(
    String error, {
    String? requestId,
    String message = 'Operation failed',
    int statusCode = 500,
    dynamic data,
    DateTime? timestamp,
  }) {
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: error,
      data: data,
      timestamp: timestamp,
    );
  }

  /// Creates a timeout [SharedDeviceResponse] when a response is not received within the time limit.
  factory SharedDeviceResponse.timeout({
    String? requestId,
    String message = 'Request timed out',
    Duration? timeout,
    int statusCode = 408,
  }) {
    final timeoutMsg = timeout != null
        ? '$message (${timeout.inMilliseconds}ms)'
        : message;
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: false,
      statusCode: statusCode,
      message: timeoutMsg,
      error: 'TIMEOUT',
    );
  }

  /// Creates an unauthorized [SharedDeviceResponse] when device authentication or pairKey validation fails.
  factory SharedDeviceResponse.unauthorized({
    String? requestId,
    String message = 'Unauthorized device or invalid pair key',
    int statusCode = 401,
  }) {
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'UNAUTHORIZED',
    );
  }

  /// Creates a forbidden [SharedDeviceResponse] when authenticated but access is denied.
  factory SharedDeviceResponse.forbidden({
    String? requestId,
    String message = 'Access forbidden to this resource',
    int statusCode = 403,
  }) {
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'FORBIDDEN',
    );
  }

  /// Creates a device not found [SharedDeviceResponse].
  factory SharedDeviceResponse.deviceNotFound({
    String? requestId,
    String message = 'Target device not found or unreachable',
    int statusCode = 404,
  }) {
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'DEVICE_NOT_FOUND',
    );
  }

  /// Creates a bad request [SharedDeviceResponse].
  factory SharedDeviceResponse.badRequest({
    String? requestId,
    String message = 'Invalid or malformed request',
    int statusCode = 400,
    dynamic data,
  }) {
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'BAD_REQUEST',
      data: data,
    );
  }

  /// Creates a conflict / duplicate [SharedDeviceResponse] (e.g. duplicate in-flight requestId).
  factory SharedDeviceResponse.conflict({
    String? requestId,
    String message = 'Duplicate request or state conflict',
    int statusCode = 409,
    dynamic data,
  }) {
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'CONFLICT',
      data: data,
    );
  }

  /// Creates a payload too large [SharedDeviceResponse] (e.g. large file upload).
  factory SharedDeviceResponse.payloadTooLarge({
    String? requestId,
    String message = 'Payload exceeds maximum permitted size',
    int statusCode = 413,
  }) {
    return SharedDeviceResponse(
      requestId: requestId,
      isSuccess: false,
      statusCode: statusCode,
      message: message,
      error: 'PAYLOAD_TOO_LARGE',
    );
  }

  /// Converts this [SharedDeviceResponse] to a Map.
  Map<String, dynamic> toMap() {
    return {
      if (requestId != null) 'requestId': requestId,
      'isSuccess': isSuccess,
      'statusCode': statusCode,
      'message': message,
      if (data != null) 'data': data,
      if (error != null) 'error': error,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Creates a [SharedDeviceResponse] from a Map.
  factory SharedDeviceResponse.fromMap(Map<String, dynamic> map) {
    return SharedDeviceResponse(
      requestId: map['requestId']?.toString(),
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

  /// Creates a [SharedDeviceResponse] from a JSON string or JSON Map.
  factory SharedDeviceResponse.fromJson(dynamic source) {
    if (source is String) {
      return SharedDeviceResponse.fromMap(
        json.decode(source) as Map<String, dynamic>,
      );
    } else if (source is Map<String, dynamic>) {
      return SharedDeviceResponse.fromMap(source);
    } else if (source is Map) {
      return SharedDeviceResponse.fromMap(Map<String, dynamic>.from(source));
    }
    throw ArgumentError(
      'Invalid source type for SharedDeviceResponse.fromJson: ${source.runtimeType}',
    );
  }

  /// Converts this [SharedDeviceResponse] to a JSON string.
  String toJson() => json.encode(toMap());

  /// Returns a copy with overridden properties.
  SharedDeviceResponse copyWith({
    String? requestId,
    bool? isSuccess,
    int? statusCode,
    String? message,
    dynamic data,
    String? error,
    DateTime? timestamp,
  }) {
    return SharedDeviceResponse(
      requestId: requestId ?? this.requestId,
      isSuccess: isSuccess ?? this.isSuccess,
      statusCode: statusCode ?? this.statusCode,
      message: message ?? this.message,
      data: data ?? this.data,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'SharedDeviceResponse(id: $requestId, success: $isSuccess, status: $statusCode, message: $message, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SharedDeviceResponse &&
        other.requestId == requestId &&
        other.isSuccess == isSuccess &&
        other.statusCode == statusCode &&
        other.message == message &&
        other.error == error;
  }

  @override
  int get hashCode {
    return Object.hash(requestId, isSuccess, statusCode, message, error);
  }
}

/// Backward compatibility alias for [SharedDeviceResponse].
typedef Status = SharedDeviceResponse;
