/// Utility for formatting notification title and content strings with dynamic placeholders.
class NotificationTemplate {
  /// Formats a template string by replacing placeholders with runtime values.
  ///
  /// Supported placeholders:
  /// - `{devices}`: Comma-separated list of active device names (with max limit and `...` if exceeded).
  /// - `{deviceCount}` / `{device_count}` / `{count}`: Number of active shared devices.
  /// - `{port}`: Main UDP server port.
  /// - `{discoveryPort}` / `{discovery_port}`: Discovery broadcast port.
  /// - `{lastEventDevice}` / `{last_event_device}`: Device identifier from the last data event.
  /// - `{lastMessage}` / `{last_message}`: Last received message payload.
  static String format(
    String template, {
    int count = 0,
    int port = 0,
    int discoveryPort = 0,
    String lastEventDevice = '',
    String lastMessage = '',
    List<String> deviceNames = const [],
    int maxDevices = 3,
  }) {
    if (template.isEmpty) return '';

    String result = template;

    final formattedDevices = formatDevices(deviceNames, maxLimit: maxDevices);

    final replacements = <String, String>{
      '{devices}': formattedDevices,

      '{deviceCount}': count.toString(),
      '{device_count}': count.toString(),
      '{count}': count.toString(),

      '{port}': port > 0 ? port.toString() : '',
      '{discoveryPort}': discoveryPort > 0 ? discoveryPort.toString() : '',
      '{discovery_port}': discoveryPort > 0 ? discoveryPort.toString() : '',

      '{lastEventDevice}': lastEventDevice,
      '{last_event_device}': lastEventDevice,

      '{lastMessage}': lastMessage,
      '{last_message}': lastMessage,
    };

    replacements.forEach((placeholder, value) {
      result = result.replaceAll(placeholder, value);
    });

    return result.trim();
  }

  /// Formats a list of device names as a comma-separated string.
  /// If the number of devices exceeds [maxLimit], it appends ', ...' (e.g. 'Printer, Scanner, ...').
  static String formatDevices(List<String> deviceNames, {int maxLimit = 3}) {
    final validNames = deviceNames.where((n) => n.trim().isNotEmpty).toList();
    if (validNames.isEmpty) return '';

    if (maxLimit > 0 && validNames.length > maxLimit) {
      final shown = validNames.take(maxLimit).join(', ');
      return '$shown, ...';
    }

    return validNames.join(', ');
  }
}
