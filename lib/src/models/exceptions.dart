/// Base exception class for all shared_device_network errors.
class SharedDeviceNetworkException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;

  const SharedDeviceNetworkException(
    this.message, {
    this.statusCode,
    this.details,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return '$runtimeType [$statusCode]: $message';
    }
    return '$runtimeType: $message';
  }
}

/// Thrown when local mDNS server discovery fails or encounters an error.
class ServerDiscoveryException extends SharedDeviceNetworkException {
  const ServerDiscoveryException(super.message, {super.statusCode, super.details});
}

/// Thrown when a network connection to a shared device server fails.
class ConnectionException extends SharedDeviceNetworkException {
  const ConnectionException(super.message, {super.statusCode, super.details});
}

/// Thrown when authentication or pairKey validation fails (HTTP 401).
class AuthenticationException extends SharedDeviceNetworkException {
  const AuthenticationException(
    super.message, {
    super.statusCode = 401,
    super.details,
  });
}

/// Thrown when a request or command times out waiting for server processing (HTTP 408).
class RequestTimeoutException extends SharedDeviceNetworkException {
  const RequestTimeoutException(
    super.message, {
    super.statusCode = 408,
    super.details,
  });
}

/// Thrown when the target peripheral device is not found on the server (HTTP 404).
class DeviceNotFoundException extends SharedDeviceNetworkException {
  final String deviceId;

  const DeviceNotFoundException(
    this.deviceId, {
    String? message,
    super.statusCode = 404,
    super.details,
  }) : super(message ?? 'Device "$deviceId" not found on server');
}

/// Thrown when an operation is attempted on an unsupported platform (e.g. hosting a server on Web).
class UnsupportedPlatformException extends SharedDeviceNetworkException {
  const UnsupportedPlatformException(super.message, {super.statusCode = 501, super.details});
}

/// Thrown when a duplicate request is currently in-flight (HTTP 409).
class IdempotencyConflictException extends SharedDeviceNetworkException {
  final String requestId;

  const IdempotencyConflictException(
    this.requestId, {
    String? message,
    super.statusCode = 409,
    super.details,
  }) : super(message ?? 'Request with ID "$requestId" is already being processed');
}

/// Thrown when the request payload or file upload exceeds size limits (HTTP 413).
class PayloadTooLargeException extends SharedDeviceNetworkException {
  const PayloadTooLargeException(
    super.message, {
    super.statusCode = 413,
    super.details,
  });
}
