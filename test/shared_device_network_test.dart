import 'package:flutter_test/flutter_test.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedDevice Model Tests', () {
    test('Should serialize and deserialize SharedDevice properly', () {
      const device = SharedDevice(
        deviceId: 'dev-001',
        deviceName: 'Kitchen POS',
        deviceDescription: 'Kitchen order screen',
        deviceIp: '192.168.1.150',
        devicePort: 8888,
        metadata: {'role': 'display', 'version': 2},
      );

      final map = device.toMap();
      expect(map['deviceId'], 'dev-001');
      expect(map['deviceName'], 'Kitchen POS');
      expect(map['deviceDescription'], 'Kitchen order screen');
      expect(map['deviceIp'], '192.168.1.150');
      expect(map['devicePort'], 8888);
      expect(map['metadata']['role'], 'display');

      final jsonStr = device.toJson();
      final fromJson = SharedDevice.fromJson(jsonStr);

      expect(fromJson.deviceId, device.deviceId);
      expect(fromJson.deviceName, device.deviceName);
      expect(fromJson.deviceDescription, device.deviceDescription);
      expect(fromJson.deviceIp, device.deviceIp);
      expect(fromJson.devicePort, device.devicePort);
      expect(fromJson.metadata?['version'], 2);
      expect(fromJson, equals(device));
    });

    test('copyWith creates modified clone', () {
      const device = SharedDevice(
        deviceId: 'dev-1',
        deviceName: 'Device 1',
        deviceIp: '127.0.0.1',
        devicePort: 8080,
      );

      final updated = device.copyWith(deviceName: 'Device 1 Updated');
      expect(updated.deviceId, 'dev-1');
      expect(updated.deviceName, 'Device 1 Updated');
      expect(updated.devicePort, 8080);
    });
  });

  group('Status Model Tests', () {
    test('Status.success initializes correct values', () {
      final status = Status.success(
        message: 'Order received',
        data: {'orderId': 123},
      );

      expect(status.isSuccess, isTrue);
      expect(status.statusCode, 200);
      expect(status.message, 'Order received');
      expect(status.data['orderId'], 123);
      expect(status.error, isNull);
    });

    test('Status.error initializes correct error values', () {
      final status = Status.error(
        'Database write failed',
        message: 'Could not persist order',
        statusCode: 500,
      );

      expect(status.isSuccess, isFalse);
      expect(status.statusCode, 500);
      expect(status.error, 'Database write failed');
      expect(status.message, 'Could not persist order');
    });

    test('Status.timeout initializes timeout status', () {
      final status = Status.timeout(
        timeout: const Duration(seconds: 3),
      );

      expect(status.isSuccess, isFalse);
      expect(status.statusCode, 408);
      expect(status.error, 'TIMEOUT');
      expect(status.message.contains('3000ms'), isTrue);
    });

    test('Status.unauthorized initializes 401 status', () {
      final status = Status.unauthorized(message: 'Invalid key');

      expect(status.isSuccess, isFalse);
      expect(status.statusCode, 401);
      expect(status.error, 'UNAUTHORIZED');
      expect(status.message, 'Invalid key');
    });

    test('Status serialization and deserialization', () {
      final status = Status.success(
        message: 'OK',
        data: 'custom_data',
        statusCode: 200,
      );

      final jsonStr = status.toJson();
      final fromJson = Status.fromJson(jsonStr);

      expect(fromJson.isSuccess, isTrue);
      expect(fromJson.statusCode, 200);
      expect(fromJson.message, 'OK');
      expect(fromJson.data, 'custom_data');
    });
  });

  group('PairedDevice Model Tests', () {
    test('PairedDevice serialization and copyWith', () {
      final paired = PairedDevice(
        deviceId: 'client-1',
        deviceName: 'Mobile Scanner',
        deviceDescription: 'Barcode Scanner',
        pairKey: 'secret-123',
      );

      final jsonStr = paired.toJson();
      final fromJson = PairedDevice.fromJson(jsonStr);

      expect(fromJson.deviceId, 'client-1');
      expect(fromJson.deviceName, 'Mobile Scanner');
      expect(fromJson.deviceDescription, 'Barcode Scanner');
      expect(fromJson.pairKey, 'secret-123');
    });
  });

  group('MessageIdGenerator Tests', () {
    test('Generates incremental integer IDs and increments sequentially', () {
      final generator = MessageIdGenerator();
      expect(generator.next(), 1);
      expect(generator.next(), 2);
      expect(generator.next(), 3);
    });

    test('Wraps to 1 when reaching maxId', () {
      final generator = MessageIdGenerator(MessageIdGenerator.maxId);
      expect(generator.next(), 1);
    });
  });

  group('NetworkPacket Tests', () {
    test('Encodes and decodes message and ACK packets correctly', () {
      final packet = NetworkPacket.message(
        messageId: 42,
        senderDeviceId: 'phone-01',
        senderDeviceName: 'Manager Phone',
        targetDeviceId: 'server-01',
        pairKey: 'key123',
        payload: {'action': 'PRINT_BILL', 'table': 5},
      );

      final bytes = packet.toUtf8Bytes();
      final decoded = NetworkPacket.fromUtf8Bytes(bytes);

      expect(decoded, isNotNull);
      expect(decoded!.type, PacketType.message);
      expect(decoded.messageId, 42);
      expect(decoded.senderDeviceId, 'phone-01');
      expect(decoded.senderDeviceName, 'Manager Phone');
      expect(decoded.targetDeviceId, 'server-01');
      expect(decoded.pairKey, 'key123');
      expect(decoded.payload['action'], 'PRINT_BILL');
    });

    test('Encodes and decodes ACK packet with Status payload', () {
      final ackStatus = Status.success(message: 'Printed successfully', data: {'jobId': 99});
      final ackPacket = NetworkPacket.ack(
        messageId: 42,
        senderDeviceId: 'server-01',
        status: ackStatus,
        targetDeviceId: 'phone-01',
      );

      final bytes = ackPacket.toUtf8Bytes();
      final decoded = NetworkPacket.fromUtf8Bytes(bytes);

      expect(decoded, isNotNull);
      expect(decoded!.type, PacketType.ack);
      expect(decoded.messageId, 42);
      expect(decoded.status, isNotNull);
      expect(decoded.status!.isSuccess, isTrue);
      expect(decoded.status!.message, 'Printed successfully');
      expect(decoded.status!.data['jobId'], 99);
    });
  });

  group('UDP Server & Client Integration Tests', () {
    late SharedDeviceNetworkServer server;
    late SharedDeviceNetworkClient client;
    const testServerPort = 9988;
    const testDiscoveryPort = 9989;

    tearDown(() async {
      await server.stop();
      await client.dispose();
    });

    test('Server responds to Client discovery request with SharedDevice details', () async {
      server = SharedDeviceNetworkServer(
        deviceId: 'server-pos-01',
        deviceName: 'POS Master',
        deviceDescription: 'Counter POS terminal',
        port: testServerPort,
        discoveryPort: testDiscoveryPort,
        onDataReceived: (senderDeviceId, message) async => Status.success(),
      );

      await server.start();

      client = SharedDeviceNetworkClient(
        deviceId: 'client-waiter-01',
        deviceName: 'Waiter Tablet',
        discoveryPort: testDiscoveryPort,
      );

      final discovered = await client.discoverDevicesOnce(
        timeout: const Duration(milliseconds: 1500),
      );

      expect(discovered.isNotEmpty, isTrue);
      final found = discovered.firstWhere((d) => d.deviceId == 'server-pos-01');
      expect(found.deviceName, 'POS Master');
      expect(found.deviceDescription, 'Counter POS terminal');
      expect(found.devicePort, testServerPort);

      // Now send message using cached discovery resolution
      final status = await client.sendToDevice(
        'server-pos-01',
        {'cmd': 'GET_TABLE_LIST'},
      );
      expect(status.isSuccess, isTrue);
    });

    test('Server and Client full loopback communication with incremental ACK', () async {
      final receivedMessages = <Map<String, dynamic>>[];

      server = SharedDeviceNetworkServer(
        deviceId: 'test-server',
        deviceName: 'Test Server',
        port: testServerPort,
        discoveryPort: testDiscoveryPort,
        onDataReceived: (senderDeviceId, message) async {
          receivedMessages.add({
            'senderDeviceId': senderDeviceId,
            'message': message,
          });
          return Status.success(
            message: 'Acknowledged: $message',
            data: {'echo': message, 'processedBy': 'test-server'},
          );
        },
      );

      await server.start();
      expect(server.isRunning, isTrue);

      client = SharedDeviceNetworkClient(
        deviceId: 'test-client',
        deviceName: 'Test Client',
        defaultTimeout: const Duration(seconds: 3),
        discoveryPort: testDiscoveryPort,
      );

      // Send 1st message to server address directly
      final status1 = await client.sendToAddress(
        '127.0.0.1',
        testServerPort,
        'Hello World #1',
      );

      expect(status1.isSuccess, isTrue);
      expect(status1.statusCode, 200);
      expect(status1.message, 'Acknowledged: Hello World #1');
      expect(status1.data['echo'], 'Hello World #1');
      expect(receivedMessages.length, 1);
      expect(receivedMessages[0]['senderDeviceId'], 'test-client');

      // Send 2nd message
      final status2 = await client.sendToAddress(
        '127.0.0.1',
        testServerPort,
        'Hello World #2',
      );

      expect(status2.isSuccess, isTrue);
      expect(status2.message, 'Acknowledged: Hello World #2');
      expect(receivedMessages.length, 2);

      // Test sendToDevice alias
      final status3 = await client.sendToDeivce(
        'test-server',
        'Hello World #3',
        ip: '127.0.0.1',
        port: testServerPort,
      );

      expect(status3.isSuccess, isTrue);
      expect(status3.message, 'Acknowledged: Hello World #3');
      expect(receivedMessages.length, 3);
    });

    test('Client handles timeout when server is unreachable or fails to ACK', () async {
      server = SharedDeviceNetworkServer(
        deviceId: 'test-server',
        port: testServerPort,
        discoveryPort: testDiscoveryPort,
        onDataReceived: (senderDeviceId, message) async {
          return Status.success();
        },
      );

      client = SharedDeviceNetworkClient(
        deviceId: 'test-client',
        defaultTimeout: const Duration(milliseconds: 300),
      );

      // Send to non-existent port
      final status = await client.sendToAddress(
        '127.0.0.1',
        19999,
        'Test unacknowledged',
        timeout: const Duration(milliseconds: 200),
      );

      expect(status.isSuccess, isFalse);
      expect(status.statusCode, 408);
      expect(status.error, 'TIMEOUT');
    });

    test('Device pairing and authorization validation on server', () async {
      server = SharedDeviceNetworkServer(
        deviceId: 'secure-server',
        port: testServerPort,
        discoveryPort: testDiscoveryPort,
        requirePairKey: true,
        onDataReceived: (senderDeviceId, message) async {
          return Status.success(message: 'Access Granted');
        },
      );

      // Add authorized device
      final added = await server.addDevice(
        'trusted-device',
        'Trusted Scanner',
        pairKey: 'secret-pass-key',
      );
      expect(added, isTrue);
      expect(server.isDevicePaired('trusted-device'), isTrue);

      await server.start();

      client = SharedDeviceNetworkClient(
        deviceId: 'untrusted-device',
        defaultTimeout: const Duration(seconds: 2),
      );

      // 1. Untrusted device should be rejected
      final statusUnauth = await client.sendToAddress(
        '127.0.0.1',
        testServerPort,
        'Secret request',
      );
      expect(statusUnauth.isSuccess, isFalse);
      expect(statusUnauth.statusCode, 401);
      expect(statusUnauth.error, 'UNAUTHORIZED');

      // 2. Trusted device with wrong key should be rejected
      final client2 = SharedDeviceNetworkClient(
        deviceId: 'trusted-device',
        defaultTimeout: const Duration(seconds: 2),
      );
      final statusWrongKey = await client2.sendToAddress(
        '127.0.0.1',
        testServerPort,
        'Secret request',
        pairKey: 'wrong-key',
      );
      expect(statusWrongKey.isSuccess, isFalse);
      expect(statusWrongKey.statusCode, 401);

      // 3. Trusted device with correct key should succeed
      final statusSuccess = await client2.sendToAddress(
        '127.0.0.1',
        testServerPort,
        'Secret request',
        pairKey: 'secret-pass-key',
      );
      expect(statusSuccess.isSuccess, isTrue);
      expect(statusSuccess.message, 'Access Granted');

      // 4. Remove device and verify it gets rejected afterwards
      final removed = await server.removeDevice('trusted-device');
      expect(removed, isTrue);
      expect(server.isDevicePaired('trusted-device'), isFalse);

      final statusAfterRemove = await client2.sendToAddress(
        '127.0.0.1',
        testServerPort,
        'Secret request',
        pairKey: 'secret-pass-key',
      );
      expect(statusAfterRemove.isSuccess, isFalse);
      expect(statusAfterRemove.statusCode, 401);

      await client2.dispose();
    });
  });
}
