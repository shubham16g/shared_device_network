/// Policy defining Cross-Origin Resource Sharing (CORS) behavior for the HTTP server.
///
/// Required when serving web browser clients making fetch/XHR requests to local network servers.
class CorsPolicy {
  /// Allowed origin list (e.g. `['http://localhost:3000', 'https://pos.mycompany.com']`).
  /// Use `['*']` to allow all origins in open environments.
  final List<String> allowedOrigins;

  /// HTTP methods permitted for cross-origin requests.
  final List<String> allowedMethods;

  /// HTTP headers permitted in cross-origin requests.
  final List<String> allowedHeaders;

  /// Whether the server allows credentials (cookies, HTTP authorization headers).
  final bool allowCredentials;

  /// Cache duration for CORS preflight options.
  final Duration maxAge;

  const CorsPolicy({
    this.allowedOrigins = const ['*'],
    this.allowedMethods = const ['GET', 'POST', 'OPTIONS', 'DELETE'],
    this.allowedHeaders = const [
      'Content-Type',
      'Authorization',
      'X-Request-Id',
      'X-File-Name',
      'X-Pair-Key',
      'Accept',
      'Origin',
    ],
    this.allowCredentials = true,
    this.maxAge = const Duration(hours: 24),
  });

  /// Permissive policy allowing all origins and standard headers.
  static const CorsPolicy allowAll = CorsPolicy(
    allowedOrigins: ['*'],
    allowCredentials: false,
  );

  /// Restricted policy allowing only specific origins with credentials.
  factory CorsPolicy.restricted({required List<String> origins}) {
    return CorsPolicy(
      allowedOrigins: origins,
      allowCredentials: true,
    );
  }

  /// Evaluates whether an incoming origin header is permitted under this policy.
  bool isOriginAllowed(String? origin) {
    if (allowedOrigins.contains('*')) return true;
    if (origin == null || origin.isEmpty) return false;
    return allowedOrigins.contains(origin);
  }

  /// Applies standard CORS headers to an outgoing response.
  void applyHeaders(
    void Function(String name, Object value) setHeader, {
    String? requestOrigin,
  }) {
    if (allowedOrigins.contains('*')) {
      setHeader('Access-Control-Allow-Origin', '*');
    } else if (requestOrigin != null && allowedOrigins.contains(requestOrigin)) {
      setHeader('Access-Control-Allow-Origin', requestOrigin);
      setHeader('Vary', 'Origin');
    }

    setHeader(
      'Access-Control-Allow-Methods',
      allowedMethods.join(', '),
    );
    setHeader(
      'Access-Control-Allow-Headers',
      allowedHeaders.join(', '),
    );

    if (allowCredentials && !allowedOrigins.contains('*')) {
      setHeader('Access-Control-Allow-Credentials', 'true');
    }

    setHeader('Access-Control-Max-Age', maxAge.inSeconds.toString());
  }
}
