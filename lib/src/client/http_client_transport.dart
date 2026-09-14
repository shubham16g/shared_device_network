import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/exceptions.dart';
import '../models/shared_device_request.dart';
import '../models/shared_device_response.dart';

/// Cross-platform HTTP transport for client requests using `package:http`.
///
/// Works seamlessly on Android, iOS, macOS, Windows, Linux, and Flutter Web.
class HttpClientTransport {
  final http.Client _client;
  final Duration defaultTimeout;

  HttpClientTransport({
    http.Client? client,
    this.defaultTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  /// Performs `GET /api/v1/info`.
  Future<Map<String, dynamic>> getInfo(
    Uri baseUri, {
    Duration? timeout,
  }) async {
    final uri = baseUri.replace(path: '/api/v1/info');
    final response = await _get(uri, timeout: timeout ?? defaultTimeout);

    final decoded = _decodeJson(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const ConnectionException('Invalid server info response');
  }

  /// Performs `GET /api/v1/devices`.
  Future<List<Map<String, dynamic>>> getDevices(
    Uri baseUri, {
    Duration? timeout,
  }) async {
    final uri = baseUri.replace(path: '/api/v1/devices');
    final response = await _get(uri, timeout: timeout ?? defaultTimeout);

    final decoded = _decodeJson(response.body);
    if (decoded is Map && decoded['devices'] is List) {
      return (decoded['devices'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Performs `GET /api/v1/devices/:deviceId`.
  Future<Map<String, dynamic>?> getDevice(
    Uri baseUri,
    String deviceId, {
    Duration? timeout,
  }) async {
    final encodedId = Uri.encodeComponent(deviceId);
    final uri = baseUri.replace(path: '/api/v1/devices/$encodedId');
    try {
      final response = await _get(uri, timeout: timeout ?? defaultTimeout);
      final decoded = _decodeJson(response.body);
      if (decoded is Map && decoded['device'] is Map) {
        return Map<String, dynamic>.from(decoded['device'] as Map);
      }
      return null;
    } on SharedDeviceNetworkException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Performs `POST /api/v1/devices/:deviceId/command`.
  Future<SharedDeviceResponse> sendCommand(
    Uri baseUri,
    String deviceId,
    SharedDeviceRequest request, {
    String? pairKey,
    Duration? timeout,
  }) async {
    final encodedId = Uri.encodeComponent(deviceId);
    final uri = baseUri.replace(path: '/api/v1/devices/$encodedId/command');

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'X-Request-Id': request.requestId,
      if (pairKey != null && pairKey.isNotEmpty)
        'Authorization': 'Bearer $pairKey',
    };

    final actualTimeout = timeout ?? defaultTimeout;

    try {
      final httpResponse = await _client
          .post(uri, headers: headers, body: request.toJson())
          .timeout(actualTimeout);

      return _parseSharedDeviceResponse(
        httpResponse.body,
        statusCode: httpResponse.statusCode,
        fallbackRequestId: request.requestId,
      );
    } on TimeoutException {
      return SharedDeviceResponse.timeout(
        requestId: request.requestId,
        message: 'Request timed out after ${actualTimeout.inMilliseconds}ms',
        timeout: actualTimeout,
      );
    } catch (e) {
      return SharedDeviceResponse.error(
        e.toString(),
        requestId: request.requestId,
        message: 'Failed to communicate with server at $uri',
      );
    }
  }

  /// Performs binary upload via `POST /api/v1/devices/:deviceId/content` (`application/octet-stream` or raw mime).
  Future<SharedDeviceResponse> sendBinary(
    Uri baseUri,
    String deviceId,
    List<int> bytes, {
    required String contentType,
    String? fileName,
    String? requestId,
    String? pairKey,
    Duration? timeout,
  }) async {
    final encodedId = Uri.encodeComponent(deviceId);
    final uri = baseUri.replace(path: '/api/v1/devices/$encodedId/content');

    final headers = <String, String>{
      'Content-Type': contentType,
      if (requestId != null) 'X-Request-Id': requestId,
      if (fileName != null) 'X-File-Name': fileName,
      if (pairKey != null && pairKey.isNotEmpty)
        'Authorization': 'Bearer $pairKey',
    };

    final actualTimeout = timeout ?? defaultTimeout;

    try {
      final httpResponse = await _client
          .post(uri, headers: headers, body: bytes)
          .timeout(actualTimeout);

      return _parseSharedDeviceResponse(
        httpResponse.body,
        statusCode: httpResponse.statusCode,
        fallbackRequestId: requestId,
      );
    } on TimeoutException {
      return SharedDeviceResponse.timeout(
        requestId: requestId,
        message: 'Binary upload timed out after ${actualTimeout.inMilliseconds}ms',
        timeout: actualTimeout,
      );
    } catch (e) {
      return SharedDeviceResponse.error(
        e.toString(),
        requestId: requestId,
        message: 'Failed to upload binary to $uri',
      );
    }
  }

  /// Performs multipart upload via `POST /api/v1/devices/:deviceId/content`.
  Future<SharedDeviceResponse> sendMultipart(
    Uri baseUri,
    String deviceId,
    List<int> bytes, {
    required String fileName,
    String fieldName = 'file',
    String? requestId,
    String? pairKey,
    Duration? timeout,
  }) async {
    final encodedId = Uri.encodeComponent(deviceId);
    final uri = baseUri.replace(path: '/api/v1/devices/$encodedId/content');

    final multipartRequest = http.MultipartRequest('POST', uri);
    if (requestId != null) {
      multipartRequest.headers['X-Request-Id'] = requestId;
    }
    if (pairKey != null && pairKey.isNotEmpty) {
      multipartRequest.headers['Authorization'] = 'Bearer $pairKey';
    }

    multipartRequest.files.add(
      http.MultipartFile.fromBytes(fieldName, bytes, filename: fileName),
    );

    final actualTimeout = timeout ?? defaultTimeout;

    try {
      final streamedResponse =
          await _client.send(multipartRequest).timeout(actualTimeout);
      final responseBody = await streamedResponse.stream.bytesToString();

      return _parseSharedDeviceResponse(
        responseBody,
        statusCode: streamedResponse.statusCode,
        fallbackRequestId: requestId,
      );
    } on TimeoutException {
      return SharedDeviceResponse.timeout(
        requestId: requestId,
        message: 'Multipart upload timed out after ${actualTimeout.inMilliseconds}ms',
        timeout: actualTimeout,
      );
    } catch (e) {
      return SharedDeviceResponse.error(
        e.toString(),
        requestId: requestId,
        message: 'Failed to upload multipart to $uri',
      );
    }
  }

  Future<http.Response> _get(Uri uri, {required Duration timeout}) async {
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }

      final errorMsg = 'HTTP GET $uri failed with status ${response.statusCode}';
      if (response.statusCode == 401) {
        throw AuthenticationException(errorMsg, statusCode: response.statusCode);
      } else if (response.statusCode == 404) {
        throw SharedDeviceNetworkException(errorMsg, statusCode: 404);
      }
      throw ConnectionException(errorMsg, statusCode: response.statusCode);
    } on TimeoutException {
      throw RequestTimeoutException('HTTP GET $uri timed out');
    } catch (e) {
      if (e is SharedDeviceNetworkException) rethrow;
      throw ConnectionException('Failed to connect to $uri: $e');
    }
  }

  SharedDeviceResponse _parseSharedDeviceResponse(
    String body, {
    required int statusCode,
    String? fallbackRequestId,
  }) {
    if (body.isEmpty) {
      if (statusCode >= 200 && statusCode < 300) {
        return SharedDeviceResponse.success(
          requestId: fallbackRequestId,
          statusCode: statusCode,
        );
      }
      return SharedDeviceResponse.error(
        'HTTP $statusCode',
        requestId: fallbackRequestId,
        statusCode: statusCode,
      );
    }

    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        final res = SharedDeviceResponse.fromMap(decoded);
        return res.requestId == null && fallbackRequestId != null
            ? res.copyWith(requestId: fallbackRequestId)
            : res;
      } else if (decoded is Map) {
        final res = SharedDeviceResponse.fromMap(
          Map<String, dynamic>.from(decoded),
        );
        return res.requestId == null && fallbackRequestId != null
            ? res.copyWith(requestId: fallbackRequestId)
            : res;
      }
    } catch (_) {}

    // Non-JSON response body fallback
    if (statusCode >= 200 && statusCode < 300) {
      return SharedDeviceResponse.success(
        requestId: fallbackRequestId,
        statusCode: statusCode,
        data: body,
      );
    }

    return SharedDeviceResponse.error(
      body,
      requestId: fallbackRequestId,
      statusCode: statusCode,
    );
  }

  dynamic _decodeJson(String body) {
    try {
      return json.decode(body);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
