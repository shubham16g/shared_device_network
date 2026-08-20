/// A thread-safe incremental message ID generator.
class MessageIdGenerator {
  int _counter = 0;
  static const int maxId = 2147483647; // 31-bit signed int max

  MessageIdGenerator([int initialValue = 0]) : _counter = initialValue;

  /// Generates the next incremental message ID, wrapping to 1 if max reached.
  int next() {
    _counter++;
    if (_counter > maxId || _counter <= 0) {
      _counter = 1;
    }
    return _counter;
  }

  /// Current ID value without incrementing.
  int get current => _counter;

  /// Resets the counter.
  void reset([int value = 0]) {
    _counter = value;
  }
}
