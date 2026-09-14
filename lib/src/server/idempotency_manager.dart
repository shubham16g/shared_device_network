import 'dart:async';
import '../models/shared_device_response.dart';

class _CachedResponse {
  final SharedDeviceResponse response;
  final DateTime expiresAt;

  _CachedResponse(this.response, this.expiresAt);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Manages request IDs and idempotency caching to prevent duplicate command executions.
///
/// Critical for hardware peripherals such as receipt printers, barcode triggers,
/// or cash drawers where executing retried requests multiple times causes real-world issues.
class IdempotencyManager {
  final Duration ttl;
  final int maxCapacity;

  final Map<String, _CachedResponse> _cache = {};
  final Set<String> _inFlight = {};

  IdempotencyManager({
    this.ttl = const Duration(minutes: 5),
    this.maxCapacity = 1000,
  });

  /// Checks if a request with [requestId] is currently in-flight.
  bool isInFlight(String requestId) => _inFlight.contains(requestId);

  /// Checks if a cached response exists for [requestId].
  SharedDeviceResponse? getCached(String requestId) {
    _evictExpired();
    final cached = _cache[requestId];
    if (cached != null) {
      if (cached.isExpired) {
        _cache.remove(requestId);
        return null;
      }
      return cached.response;
    }
    return null;
  }

  /// Executes an operation with idempotency protection.
  ///
  /// - If [requestId] is empty, executes [action] directly without caching.
  /// - If [requestId] has a cached response, returns it immediately without executing [action].
  /// - If [requestId] is already in-flight, returns HTTP 409 Conflict.
  /// - Otherwise executes [action], caches the resulting response for [ttl], and returns it.
  Future<SharedDeviceResponse> handleRequest(
    String? requestId,
    Future<SharedDeviceResponse> Function() action,
  ) async {
    if (requestId == null || requestId.trim().isEmpty) {
      return await action();
    }

    final id = requestId.trim();

    // 1. Check for cached response
    final cached = getCached(id);
    if (cached != null) {
      return cached;
    }

    // 2. Check for in-flight conflict
    if (_inFlight.contains(id)) {
      return SharedDeviceResponse.conflict(
        requestId: id,
        message: 'Request "$id" is currently being processed.',
      );
    }

    // 3. Mark in-flight and execute
    _inFlight.add(id);
    try {
      final response = await action();
      _cacheResponse(id, response);
      return response;
    } finally {
      _inFlight.remove(id);
    }
  }

  void _cacheResponse(String requestId, SharedDeviceResponse response) {
    _evictExpired();
    if (_cache.length >= maxCapacity) {
      // Remove oldest entry
      final oldestKey = _cache.keys.firstOrNull;
      if (oldestKey != null) {
        _cache.remove(oldestKey);
      }
    }
    _cache[requestId] = _CachedResponse(response, DateTime.now().add(ttl));
  }

  void _evictExpired() {
    final now = DateTime.now();
    _cache.removeWhere((_, entry) => entry.expiresAt.isBefore(now));
  }

  /// Clears the idempotency cache.
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}
