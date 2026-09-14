import 'dart:math';

/// Utility to generate unique, traceable request IDs for HTTP operations.
class RequestIdGenerator {
  static final Random _random = Random();
  static int _counter = 0;

  /// Generates a new unique request ID (e.g. `req_1726251234567_a1b2_1`).
  static String generate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = _random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    _counter = (_counter + 1) & 0xFFFF;
    return 'req_${now}_${rand}_$_counter';
  }
}
