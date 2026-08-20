import 'dart:convert';
import 'status.dart';

/// Supported types of network packets in the shared device network protocol.
enum PacketType {
  discoveryRequest('DISCOVERY_REQUEST'),
  discoveryResponse('DISCOVERY_RESPONSE'),
  message('MESSAGE'),
  ack('ACK');

  final String value;
  const PacketType(this.value);

  static PacketType fromString(String str) {
    for (final type in PacketType.values) {
      if (type.value.toUpperCase() == str.toUpperCase()) {
        return type;
      }
    }
    return PacketType.message;
  }
}

/// Represents an internal UDP network datagram in the shared device network protocol.
class NetworkPacket {
  /// Type of packet.
  final PacketType type;

  /// Incremental message ID (for MESSAGE and ACK).
  final int? messageId;

  /// Device ID of the sender.
  final String senderDeviceId;

  /// Optional name of sender device.
  final String? senderDeviceName;

  /// Optional sender IP (populated by socket receipt).
  final String? senderIp;

  /// Optional sender port (populated by socket receipt).
  final int? senderPort;

  /// Target device ID (if directed).
  final String? targetDeviceId;

  /// Optional pair key for authentication.
  final String? pairKey;

  /// Main payload of the packet.
  final dynamic payload;

  /// Status object (used in ACK packets).
  final Status? status;

  /// Creation timestamp (milliseconds since epoch).
  final int timestamp;

  NetworkPacket({
    required this.type,
    this.messageId,
    required this.senderDeviceId,
    this.senderDeviceName,
    this.senderIp,
    this.senderPort,
    this.targetDeviceId,
    this.pairKey,
    this.payload,
    this.status,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  /// Creates a discovery request packet.
  factory NetworkPacket.discoveryRequest({
    required String senderDeviceId,
    String? senderDeviceName,
    int? replyPort,
  }) {
    return NetworkPacket(
      type: PacketType.discoveryRequest,
      senderDeviceId: senderDeviceId,
      senderDeviceName: senderDeviceName,
      senderPort: replyPort,
    );
  }

  /// Creates a discovery response packet.
  factory NetworkPacket.discoveryResponse({
    required String senderDeviceId,
    required String senderDeviceName,
    String? deviceDescription,
    required String deviceIp,
    required int devicePort,
    Map<String, dynamic>? metadata,
  }) {
    return NetworkPacket(
      type: PacketType.discoveryResponse,
      senderDeviceId: senderDeviceId,
      senderDeviceName: senderDeviceName,
      payload: {
        'deviceId': senderDeviceId,
        'deviceName': senderDeviceName,
        if (deviceDescription != null) 'deviceDescription': deviceDescription,
        'deviceIp': deviceIp,
        'devicePort': devicePort,
        if (metadata != null) 'metadata': metadata,
      },
    );
  }

  /// Creates a regular data message packet with an incremental [messageId].
  factory NetworkPacket.message({
    required int messageId,
    required String senderDeviceId,
    String? senderDeviceName,
    String? targetDeviceId,
    String? pairKey,
    required dynamic payload,
    int? replyPort,
  }) {
    return NetworkPacket(
      type: PacketType.message,
      messageId: messageId,
      senderDeviceId: senderDeviceId,
      senderDeviceName: senderDeviceName,
      targetDeviceId: targetDeviceId,
      pairKey: pairKey,
      payload: payload,
      senderPort: replyPort,
    );
  }

  /// Creates an acknowledgment (ACK) packet replying to [messageId].
  factory NetworkPacket.ack({
    required int messageId,
    required String senderDeviceId,
    required Status status,
    String? targetDeviceId,
  }) {
    return NetworkPacket(
      type: PacketType.ack,
      messageId: messageId,
      senderDeviceId: senderDeviceId,
      targetDeviceId: targetDeviceId,
      status: status,
      payload: status.toMap(),
    );
  }

  /// Converts this [NetworkPacket] to a Map.
  Map<String, dynamic> toMap() {
    return {
      'type': type.value,
      if (messageId != null) 'messageId': messageId,
      'senderDeviceId': senderDeviceId,
      if (senderDeviceName != null) 'senderDeviceName': senderDeviceName,
      if (senderIp != null) 'senderIp': senderIp,
      if (senderPort != null) 'senderPort': senderPort,
      if (targetDeviceId != null) 'targetDeviceId': targetDeviceId,
      if (pairKey != null) 'pairKey': pairKey,
      if (payload != null) 'payload': payload,
      if (status != null) 'status': status!.toMap(),
      'timestamp': timestamp,
    };
  }

  /// Creates a [NetworkPacket] from a Map.
  factory NetworkPacket.fromMap(Map<String, dynamic> map) {
    return NetworkPacket(
      type: PacketType.fromString(map['type']?.toString() ?? 'MESSAGE'),
      messageId: map['messageId'] is int
          ? map['messageId'] as int
          : int.tryParse(map['messageId']?.toString() ?? ''),
      senderDeviceId: map['senderDeviceId']?.toString() ?? '',
      senderDeviceName: map['senderDeviceName']?.toString(),
      senderIp: map['senderIp']?.toString(),
      senderPort: (map['senderPort'] is int)
          ? map['senderPort'] as int
          : int.tryParse(map['senderPort']?.toString() ?? ''),
      targetDeviceId: map['targetDeviceId']?.toString(),
      pairKey: map['pairKey']?.toString(),
      payload: map['payload'],
      status: map['status'] != null
          ? (map['status'] is Map
              ? Status.fromMap(Map<String, dynamic>.from(map['status'] as Map))
              : null)
          : null,
      timestamp: (map['timestamp'] is int)
          ? map['timestamp'] as int
          : int.tryParse(map['timestamp']?.toString() ?? '') ??
              DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Encodes this packet to a JSON string.
  String toJson() => json.encode(toMap());

  /// Encodes this packet to UTF-8 bytes for datagram transmission.
  List<int> toUtf8Bytes() => utf8.encode(toJson());

  /// Parses a [NetworkPacket] from UTF-8 byte datagram.
  static NetworkPacket? fromUtf8Bytes(List<int> bytes, {String? senderIp, int? senderPort}) {
    try {
      final jsonString = utf8.decode(bytes);
      final dynamic decoded = json.decode(jsonString);
      if (decoded is Map<String, dynamic>) {
        final packet = NetworkPacket.fromMap(decoded);
        return packet.copyWith(
          senderIp: senderIp ?? packet.senderIp,
          senderPort: senderPort ?? packet.senderPort,
        );
      } else if (decoded is Map) {
        final packet = NetworkPacket.fromMap(Map<String, dynamic>.from(decoded));
        return packet.copyWith(
          senderIp: senderIp ?? packet.senderIp,
          senderPort: senderPort ?? packet.senderPort,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Creates a copy with optionally overridden values.
  NetworkPacket copyWith({
    PacketType? type,
    int? messageId,
    String? senderDeviceId,
    String? senderDeviceName,
    String? senderIp,
    int? senderPort,
    String? targetDeviceId,
    String? pairKey,
    dynamic payload,
    Status? status,
    int? timestamp,
  }) {
    return NetworkPacket(
      type: type ?? this.type,
      messageId: messageId ?? this.messageId,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      senderDeviceName: senderDeviceName ?? this.senderDeviceName,
      senderIp: senderIp ?? this.senderIp,
      senderPort: senderPort ?? this.senderPort,
      targetDeviceId: targetDeviceId ?? this.targetDeviceId,
      pairKey: pairKey ?? this.pairKey,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'NetworkPacket(type: ${type.value}, id: $messageId, sender: $senderDeviceId, target: $targetDeviceId)';
  }
}
