import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mime/mime.dart';

import '../models/cors_policy.dart';
import '../models/shared_device_request.dart';
import '../models/shared_device_response.dart';
import '../utils/request_id_generator.dart';
import 'server_transport_interface.dart';

/// Native Dart [HttpServer] implementation of [ServerTransport].
class HttpServerTransportIo implements ServerTransport {
  HttpServer? _server;
  bool _isRunning = false;
  int? _port;
  String? _host;

  @override
  bool get isRunning => _isRunning;

  @override
  int? get port => _port;

  @override
  String? get host => _host;

  @override
  Future<void> start({
    required String host,
    required int port,
    required CorsPolicy corsPolicy,
    required int maxBodySizeBytes,
    required ServerInfoHandler onInfo,
    required DeviceListHandler onDevices,
    required DeviceLookupHandler onDeviceLookup,
    required CommandHandler onCommand,
    required BinaryHandler onBinary,
    dynamic securityContext,
  }) async {
    if (_isRunning) return;

    try {
      final bindAddress = (host == '0.0.0.0' || host.isEmpty)
          ? InternetAddress.anyIPv4
          : (host == 'localhost' || host == '127.0.0.1')
              ? InternetAddress.loopbackIPv4
              : InternetAddress(host);

      if (securityContext != null && securityContext is SecurityContext) {
        _server = await HttpServer.bindSecure(
          bindAddress,
          port,
          securityContext,
          shared: true,
        );
      } else {
        _server = await HttpServer.bind(
          bindAddress,
          port,
          shared: true,
        );
      }

      _port = _server!.port;
      _host = host.isEmpty ? '0.0.0.0' : host;
      _isRunning = true;

      _server!.listen(
        (request) => _handleHttpRequest(
          request,
          corsPolicy: corsPolicy,
          maxBodySizeBytes: maxBodySizeBytes,
          onInfo: onInfo,
          onDevices: onDevices,
          onDeviceLookup: onDeviceLookup,
          onCommand: onCommand,
          onBinary: onBinary,
        ),
      );
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _port = null;
    _host = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  Future<void> _handleHttpRequest(
    HttpRequest request, {
    required CorsPolicy corsPolicy,
    required int maxBodySizeBytes,
    required ServerInfoHandler onInfo,
    required DeviceListHandler onDevices,
    required DeviceLookupHandler onDeviceLookup,
    required CommandHandler onCommand,
    required BinaryHandler onBinary,
  }) async {
    final response = request.response;
    final origin = request.headers.value('origin');

    // Apply CORS headers to all responses
    corsPolicy.applyHeaders(
      (name, val) => response.headers.set(name, val),
      requestOrigin: origin,
    );

    // Handle pre-flight OPTIONS
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    final pathSegments = request.uri.pathSegments;

    try {
      // Versioned API routing: /api/v1/...
      if (pathSegments.length < 2 ||
          pathSegments[0] != 'api' ||
          pathSegments[1] != 'v1') {
        _sendJsonResponse(
          response,
          HttpStatus.notFound,
          SharedDeviceResponse.deviceNotFound(
            message: 'API route not found. Use /api/v1/...',
          ),
        );
        return;
      }

      final subPath = pathSegments.sublist(2);

      // GET /api/v1/info
      if (subPath.length == 1 && subPath[0] == 'info' && request.method == 'GET') {
        final info = onInfo();
        _sendRawJson(response, HttpStatus.ok, {'status': 200, ...info});
        return;
      }

      // GET /api/v1/devices
      if (subPath.length == 1 && subPath[0] == 'devices' && request.method == 'GET') {
        final devices = onDevices();
        _sendRawJson(response, HttpStatus.ok, {'status': 200, 'devices': devices});
        return;
      }

      // GET /api/v1/devices/:deviceId
      if (subPath.length == 2 && subPath[0] == 'devices' && request.method == 'GET') {
        final deviceId = Uri.decodeComponent(subPath[1]);
        final dev = onDeviceLookup(deviceId);
        if (dev != null) {
          _sendRawJson(response, HttpStatus.ok, {'status': 200, 'device': dev});
        } else {
          _sendJsonResponse(
            response,
            HttpStatus.notFound,
            SharedDeviceResponse.deviceNotFound(
              message: 'Device "$deviceId" not found on this server',
            ),
          );
        }
        return;
      }

      // POST /api/v1/devices/:deviceId/command
      if (subPath.length == 3 &&
          subPath[0] == 'devices' &&
          subPath[2] == 'command' &&
          request.method == 'POST') {
        final deviceId = Uri.decodeComponent(subPath[1]);
        await _handleCommandRequest(
          request,
          response,
          deviceId: deviceId,
          maxBodySizeBytes: maxBodySizeBytes,
          onCommand: onCommand,
        );
        return;
      }

      // POST /api/v1/devices/:deviceId/content
      if (subPath.length == 3 &&
          subPath[0] == 'devices' &&
          subPath[2] == 'content' &&
          request.method == 'POST') {
        final deviceId = Uri.decodeComponent(subPath[1]);
        await _handleBinaryRequest(
          request,
          response,
          deviceId: deviceId,
          maxBodySizeBytes: maxBodySizeBytes,
          onBinary: onBinary,
        );
        return;
      }

      // Route not recognized
      _sendJsonResponse(
        response,
        HttpStatus.notFound,
        SharedDeviceResponse.deviceNotFound(
          message: 'Unknown endpoint: ${request.uri.path}',
        ),
      );
    } catch (_) {
      _sendJsonResponse(
        response,
        HttpStatus.internalServerError,
        SharedDeviceResponse.error(
          'Internal server error',
          message: 'An error occurred while processing the request',
        ),
      );
    }
  }

  Future<void> _handleCommandRequest(
    HttpRequest request,
    HttpResponse response, {
    required String deviceId,
    required int maxBodySizeBytes,
    required CommandHandler onCommand,
  }) async {
    // Check Content-Length header
    if (request.contentLength > maxBodySizeBytes) {
      _sendJsonResponse(
        response,
        HttpStatus.requestEntityTooLarge,
        SharedDeviceResponse.payloadTooLarge(
          message: 'Command payload exceeds limit ($maxBodySizeBytes bytes)',
        ),
      );
      return;
    }

    final authHeader = request.headers.value('authorization') ??
        request.headers.value('x-pair-key');
    final headerRequestId = request.headers.value('x-request-id');

    // Read body
    final bodyBuffer = <int>[];
    await for (final chunk in request) {
      bodyBuffer.addAll(chunk);
      if (bodyBuffer.length > maxBodySizeBytes) {
        _sendJsonResponse(
          response,
          HttpStatus.requestEntityTooLarge,
          SharedDeviceResponse.payloadTooLarge(
            message: 'Command payload exceeds limit ($maxBodySizeBytes bytes)',
          ),
        );
        return;
      }
    }

    if (bodyBuffer.isEmpty) {
      _sendJsonResponse(
        response,
        HttpStatus.badRequest,
        SharedDeviceResponse.badRequest(message: 'Empty request body'),
      );
      return;
    }

    dynamic decoded;
    try {
      final jsonString = utf8.decode(bodyBuffer);
      decoded = json.decode(jsonString);
    } catch (_) {
      _sendJsonResponse(
        response,
        HttpStatus.badRequest,
        SharedDeviceResponse.badRequest(message: 'Malformed JSON payload'),
      );
      return;
    }

    if (decoded is! Map) {
      _sendJsonResponse(
        response,
        HttpStatus.badRequest,
        SharedDeviceResponse.badRequest(message: 'JSON payload must be an object'),
      );
      return;
    }

    final map = Map<String, dynamic>.from(decoded);
    final reqId = headerRequestId ??
        map['requestId']?.toString() ??
        RequestIdGenerator.generate();
    final cmd = map['command']?.toString() ??
        map['cmd']?.toString() ??
        map['action']?.toString() ??
        'DEFAULT';
    final data = map.containsKey('data') ? map['data'] : map['payload'] ?? map;
    final metadata = map['metadata'] is Map
        ? Map<String, dynamic>.from(map['metadata'] as Map)
        : null;

    final sharedReq = SharedDeviceRequest(
      requestId: reqId,
      deviceId: deviceId,
      command: cmd,
      data: data,
      metadata: metadata,
    );

    final res = await onCommand(deviceId, sharedReq, authHeader);
    final statusToUse = res.statusCode > 0 ? res.statusCode : HttpStatus.ok;
    _sendJsonResponse(response, statusToUse, res);
  }

  Future<void> _handleBinaryRequest(
    HttpRequest request,
    HttpResponse response, {
    required String deviceId,
    required int maxBodySizeBytes,
    required BinaryHandler onBinary,
  }) async {
    if (request.contentLength > maxBodySizeBytes) {
      _sendJsonResponse(
        response,
        HttpStatus.requestEntityTooLarge,
        SharedDeviceResponse.payloadTooLarge(
          message: 'Binary payload exceeds limit ($maxBodySizeBytes bytes)',
        ),
      );
      return;
    }

    final authHeader = request.headers.value('authorization') ??
        request.headers.value('x-pair-key');
    final headerRequestId = request.headers.value('x-request-id') ??
        request.uri.queryParameters['requestId'] ??
        RequestIdGenerator.generate();
    var fileName = request.headers.value('x-file-name') ??
        request.uri.queryParameters['fileName'];

    final contentType = request.headers.contentType;
    final primaryType = contentType?.primaryType ?? 'application';
    final subType = contentType?.subType ?? 'octet-stream';
    final mimeString = '$primaryType/$subType';

    List<int> fileBytes = [];

    if (primaryType == 'multipart' && subType == 'form-data') {
      final boundary = contentType?.parameters['boundary'];
      if (boundary == null || boundary.isEmpty) {
        _sendJsonResponse(
          response,
          HttpStatus.badRequest,
          SharedDeviceResponse.badRequest(message: 'Missing multipart boundary'),
        );
        return;
      }

      final transformer = MimeMultipartTransformer(boundary);
      final parts = transformer.bind(request);

      await for (final part in parts) {
        final contentDisp = part.headers['content-disposition'] ?? '';
        final fnMatch = RegExp(r'filename="?([^";\r\n]+)"?').firstMatch(contentDisp);
        if (fnMatch != null) {
          fileName = fnMatch.group(1);
        }

        await for (final chunk in part) {
          fileBytes.addAll(chunk);
          if (fileBytes.length > maxBodySizeBytes) {
            _sendJsonResponse(
              response,
              HttpStatus.requestEntityTooLarge,
              SharedDeviceResponse.payloadTooLarge(
                message: 'Binary payload exceeds limit ($maxBodySizeBytes bytes)',
              ),
            );
            return;
          }
        }
      }
    } else {
      // Octet-stream or direct file upload
      await for (final chunk in request) {
        fileBytes.addAll(chunk);
        if (fileBytes.length > maxBodySizeBytes) {
          _sendJsonResponse(
            response,
            HttpStatus.requestEntityTooLarge,
            SharedDeviceResponse.payloadTooLarge(
              message: 'Binary payload exceeds limit ($maxBodySizeBytes bytes)',
            ),
          );
          return;
        }
      }
    }

    final result = await onBinary(
      deviceId,
      fileBytes,
      contentType: mimeString,
      fileName: fileName,
      requestId: headerRequestId,
      authHeader: authHeader,
    );

    final statusToUse = result.statusCode > 0 ? result.statusCode : HttpStatus.ok;
    _sendJsonResponse(response, statusToUse, result);
  }

  void _sendJsonResponse(
    HttpResponse response,
    int statusCode,
    SharedDeviceResponse data,
  ) {
    _sendRawJson(response, statusCode, data.toMap());
  }

  void _sendRawJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> jsonMap,
  ) {
    try {
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.json;
      response.write(json.encode(jsonMap));
      response.close();
    } catch (_) {}
  }
}

/// Factory function for native platform.
ServerTransport createServerTransport() => HttpServerTransportIo();
