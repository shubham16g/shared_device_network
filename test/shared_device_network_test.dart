import 'package:flutter_test/flutter_test.dart';
import 'package:shared_device_network/shared_device_network.dart';
import 'package:shared_device_network/src/models/network_packet.dart';
import 'package:shared_device_network/src/server/shared_device_network_server.dart';
import 'package:shared_device_network/src/utils/message_id_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedDevice Model Tests', () {
    test('Should serialize and deserialize SharedDevice properly', () {
      const device = SharedDevice(
        deviceId: 'dev-001',
        deviceName: 'Kitchen POS Printer',
        deviceDescription: 'Thermal receipt printer',
        deviceIp: '192.168.1.150',
        devicePort: 8888,
        metadata: {'type': 'printer', 'paperWidth': 80},
      );

      final map = device.toMap();
      expect(map['deviceId'], 'dev-001');
      expect(map['deviceName'], 'Kitchen POS Printer');
      expect(map['deviceDescription'], 'Thermal receipt printer');
      expect(map['deviceIp'], '192.168.1.150');
      expect(map['devicePort'], 8888);
      expect(map['metadata']['type'], 'printer');

      final jsonStr = device.toJson();
      final fromJson = SharedDevice.fromJson(jsonStr);

      expect(fromJson.deviceId, device.deviceId);
      expect(fromJson.deviceName, device.deviceName);
      expect(fromJson.deviceDescription, device.deviceDescription);
      expect(fromJson.deviceIp, device.deviceIp);
      expect(fromJson.devicePort, device.devicePort);
      expect(fromJson.metadata?['paperWidth'], 80);
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

  group('SharedDeviceResponse Model Tests', () {
    test('SharedDeviceResponse.success initializes correct values', () {
      final status = SharedDeviceResponse.success(
        message: 'Order received',
        data: {'orderId': 123},
      );

      expect(status.isSuccess, isTrue);
      expect(status.statusCode, 200);
      expect(status.message, 'Order received');
      expect(status.data['orderId'], 123);
      expect(status.error, isNull);
    });

    test('SharedDeviceResponse.error initializes correct error values', () {
      final status = SharedDeviceResponse.error(
        'Database write failed',
        message: 'Could not persist order',
        statusCode: 500,
      );

      expect(status.isSuccess, isFalse);
      expect(status.statusCode, 500);
      expect(status.error, 'Database write failed');
      expect(status.message, 'Could not persist order');
    });

    test('SharedDeviceResponse.timeout initializes timeout status', () {
      final status = SharedDeviceResponse.timeout(
        timeout: const Duration(seconds: 3),
      );

      expect(status.isSuccess, isFalse);
      expect(status.statusCode, 408);
      expect(status.error, 'TIMEOUT');
      expect(status.message.contains('3000ms'), isTrue);
    });

    test('SharedDeviceResponse.unauthorized initializes 401 status', () {
      final status = SharedDeviceResponse.unauthorized(message: 'Invalid key');

      expect(status.isSuccess, isFalse);
      expect(status.statusCode, 401);
      expect(status.error, 'UNAUTHORIZED');
      expect(status.message, 'Invalid key');
    });

    test('SharedDeviceResponse serialization and deserialization', () {
      final status = SharedDeviceResponse.success(
        message: 'OK',
        data: 'custom_data',
        statusCode: 200,
      );

      final jsonStr = status.toJson();
      final fromJson = SharedDeviceResponse.fromJson(jsonStr);

      expect(fromJson.isSuccess, isTrue);
      expect(fromJson.statusCode, 200);
      expect(fromJson.message, 'OK');
      expect(fromJson.data, 'custom_data');
    });

    test('Status typedef alias works for backward compatibility', () {
      final status = Status.success(message: 'Legacy OK');
      expect(status, isA<SharedDeviceResponse>());
      expect(status.isSuccess, isTrue);
      expect(status.message, 'Legacy OK');
    });
  });

  group('SharedDeviceRecord Model Tests', () {
    test('SharedDeviceRecord serialization and copyWith', () {
      final record = SharedDeviceRecord(
        deviceId: 'bt-printer-01',
        deviceName: 'Bluetooth POS Printer',
        deviceDescription: 'Thermal 80mm',
        pairKey: 'secret-123',
      );

      final jsonStr = record.toJson();
      final fromJson = SharedDeviceRecord.fromJson(jsonStr);

      expect(fromJson.deviceId, 'bt-printer-01');
      expect(fromJson.deviceName, 'Bluetooth POS Printer');
      expect(fromJson.deviceDescription, 'Thermal 80mm');
      expect(fromJson.pairKey, 'secret-123');
    });

    test('SharedDeviceRecord list serialization for background persistence', () {
      final records = [
        SharedDeviceRecord(
          deviceId: 'printer-01',
          deviceName: 'Kitchen Printer',
          pairKey: '1234',
        ),
        SharedDeviceRecord(
          deviceId: 'scanner-01',
          deviceName: 'Barcode Scanner',
          deviceDescription: 'USB 2D scanner',
        ),
      ];

      final serializedList = records.map((r) => r.toMap()).toList();
      final reconstructed = serializedList
          .map((m) => SharedDeviceRecord.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      expect(reconstructed.length, 2);
      expect(reconstructed[0].deviceId, 'printer-01');
      expect(reconstructed[0].pairKey, '1234');
      expect(reconstructed[1].deviceId, 'scanner-01');
      expect(reconstructed[1].deviceDescription, 'USB 2D scanner');
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
        targetDeviceId: 'printer-01',
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
      expect(decoded.targetDeviceId, 'printer-01');
      expect(decoded.pairKey, 'key123');
      expect(decoded.payload['action'], 'PRINT_BILL');
    });

    test('Encodes and decodes ACK packet with SharedDeviceResponse payload', () {
      final ackStatus = SharedDeviceResponse.success(message: 'Printed successfully', data: {'jobId': 99});
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

  group('NotificationTemplate Tests', () {
    test('Replaces {devices}, {count}, and {port} placeholders correctly', () {
      final formatted = NotificationTemplate.format(
        '{devices} ({count} Active) : {port}',
        deviceNames: ['Thermal Printer'],
        count: 1,
        port: 8888,
      );
      expect(formatted, 'Thermal Printer (1 Active) : 8888');
    });

    test('Formats {devices} with multiple devices under maxLimit', () {
      final formatted = NotificationTemplate.format(
        'Devices: {devices}',
        deviceNames: ['Printer', 'Scanner'],
        count: 2,
      );
      expect(formatted, 'Devices: Printer, Scanner');
    });

    test('Formats {devices} with max limit and trailing ellipsis when exceeded', () {
      final formatted = NotificationTemplate.format(
        '{devices}',
        deviceNames: ['Printer', 'Scanner', 'Cash Drawer', 'Card Terminal', 'Scale'],
        maxDevices: 3,
        count: 5,
      );
      expect(formatted, 'Printer, Scanner, Cash Drawer, ...');
    });

    test('Supports custom maxDevices limit for {devices}', () {
      final formatted = NotificationTemplate.format(
        '{devices}',
        deviceNames: ['Printer', 'Scanner', 'Cash Drawer'],
        maxDevices: 2,
        count: 3,
      );
      expect(formatted, 'Printer, Scanner, ...');
    });

    test('NotificationTemplate.formatDevices utility formats correctly with ellipsis', () {
      expect(
        NotificationTemplate.formatDevices(['A', 'B', 'C', 'D'], maxLimit: 2),
        'A, B, ...',
      );
      expect(
        NotificationTemplate.formatDevices(['A', 'B']),
        'A, B',
      );
      expect(
        NotificationTemplate.formatDevices([]),
        '',
      );
    });

    test('Replaces last event placeholders', () {
      final formatted = NotificationTemplate.format(
        '{lastEventDevice} received {lastMessage}',
        lastEventDevice: 'scanner-1',
        lastMessage: 'BARCODE_123',
      );
      expect(formatted, 'scanner-1 received BARCODE_123');
    });

    test('Leaves static text unchanged without placeholders', () {
      final formatted = NotificationTemplate.format(
        'POS Device Server',
        count: 1,
      );
      expect(formatted, 'POS Device Server');
    });

    test('Returns empty string when template is empty', () {
      final formatted = NotificationTemplate.format(
        '',
        count: 1,
      );
      expect(formatted, '');
    });
  });

  group('UDP Server & Client Shared Devices Multi-Device Tests', () {
    late SharedDeviceUdpServer server;
    late SharedDeviceNetworkClient client;
    const testServerPort = 9988;
    const testDiscoveryPort = 9989;

    tearDown(() async {
      await server.stop();
      await client.dispose();
    });

    test('1 UDP server shares multiple connected devices; auto-starts on first, auto-stops when empty', () async {
      final receivedData = <String, dynamic>{};

      server = SharedDeviceUdpServer(
        port: testServerPort,
        discoveryPort: testDiscoveryPort,
        onDataReceived: (deviceId, message) async {
          receivedData[deviceId] = message;
          return SharedDeviceResponse.success(
            message: 'Handled by $deviceId',
            data: {'deviceId': deviceId, 'echo': message},
          );
        },
      );

      // 1. Initially server is not running
      expect(server.isRunning, isFalse);
      expect(server.deviceCount, 0);

      // 2. Add 1st device (e.g. Bluetooth Printer) -> auto starts server
      await server.addDevice(
        'printer-bt-01',
        'Kitchen Printer',
        deviceDescription: 'Thermal 80mm Bluetooth Printer',
      );

      expect(server.isRunning, isTrue);
      expect(server.deviceCount, 1);
      expect(server.hasDevice('printer-bt-01'), isTrue);

      // 3. Add 2nd device (e.g. Barcode Scanner) to same running UDP server
      await server.addDevice(
        'scanner-usb-01',
        'Counter Scanner',
        deviceDescription: '2D QR / Barcode Scanner',
        pairKey: 'scanner-pass-123',
      );

      expect(server.isRunning, isTrue);
      expect(server.deviceCount, 2);

      // 4. Client discovers devices on the network
      client = SharedDeviceNetworkClient(
        deviceId: 'waiter-app-01',
        deviceName: 'Waiter Phone',
        discoveryPort: testDiscoveryPort,
        defaultTimeout: const Duration(seconds: 3),
      );

      final discoveredList = await client.discoverDevicesOnce(
        timeout: const Duration(milliseconds: 1500),
      );

      // Client discovers 1 UDP server, but finds 2 shared devices!
      expect(discoveredList.length, 2);
      final printer = discoveredList.firstWhere((d) => d.deviceId == 'printer-bt-01');
      final scanner = discoveredList.firstWhere((d) => d.deviceId == 'scanner-usb-01');

      expect(printer.deviceName, 'Kitchen Printer');
      expect(printer.devicePort, testServerPort);
      expect(scanner.deviceName, 'Counter Scanner');
      expect(scanner.devicePort, testServerPort);

      // 5. Send message to 1st shared device (Printer)
      final printerStatus = await client.sendToDevice(
        'printer-bt-01',
        {'cmd': 'PRINT_KOT', 'table': 3},
      );
      expect(printerStatus.isSuccess, isTrue);
      expect(printerStatus.message, 'Handled by printer-bt-01');
      expect(receivedData['printer-bt-01']['cmd'], 'PRINT_KOT');

      // 6. Send message to 2nd shared device with valid pairKey (Scanner)
      final scannerStatus = await client.sendToDevice(
        'scanner-usb-01',
        {'cmd': 'SCAN_BARCODE'},
        pairKey: 'scanner-pass-123',
      );
      expect(scannerStatus.isSuccess, isTrue);
      expect(scannerStatus.message, 'Handled by scanner-usb-01');
      expect(receivedData['scanner-usb-01']['cmd'], 'SCAN_BARCODE');

      // 7. Send message to Scanner with wrong pairKey -> rejected
      final wrongKeyStatus = await client.sendToDevice(
        'scanner-usb-01',
        {'cmd': 'SCAN_BARCODE'},
        pairKey: 'wrong-key',
      );
      expect(wrongKeyStatus.isSuccess, isFalse);
      expect(wrongKeyStatus.statusCode, 401);

      // 8. Test alias sendToDeivce
      final aliasStatus = await client.sendToDeivce(
        'printer-bt-01',
        {'cmd': 'PRINT_RECEIPT'},
      );
      expect(aliasStatus.isSuccess, isTrue);

      // 9. Remove 1st device -> server remains running for 2nd device
      final removedFirst = await server.removeDevice('printer-bt-01');
      expect(removedFirst, isTrue);
      expect(server.deviceCount, 1);
      expect(server.isRunning, isTrue);

      // 10. Remove 2nd device -> all devices removed, server automatically stops!
      final removedSecond = await server.removeDevice('scanner-usb-01');
      expect(removedSecond, isTrue);
      expect(server.deviceCount, 0);
      expect(server.isRunning, isFalse);
    });

    test('Client handles timeout when target device is unreachable or fails to ACK', () async {
      server = SharedDeviceUdpServer(
        port: testServerPort,
        discoveryPort: testDiscoveryPort,
        onDataReceived: (deviceId, message) async => SharedDeviceResponse.success(),
      );

      client = SharedDeviceNetworkClient(
        deviceId: 'test-client',
        defaultTimeout: const Duration(milliseconds: 300),
      );

      // Send to unhosted port
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
  });

  group('SharedDeviceNetworkServer Static API Tests', () {
    const staticTestPort = 9977;
    const staticTestDiscoveryPort = 9978;
    late SharedDeviceNetworkClient client;

    setUp(() {
      SharedDeviceNetworkServer.resetStaticState();
    });

    tearDown(() async {
      await SharedDeviceNetworkServer.stop();
      SharedDeviceNetworkServer.resetStaticState();
      try {
        await client.dispose();
      } catch (_) {}
    });

    test('Static API: init, onDataReceived, auto-start on addDevice, and auto-stop on removeDevice', () async {
      final receivedData = <String, dynamic>{};

      // 1. Init without starting UDP server yet
      await SharedDeviceNetworkServer.init(
        port: staticTestPort,
        discoveryPort: staticTestDiscoveryPort,
        enableForegroundService: false,
      );

      expect(SharedDeviceNetworkServer.isRunning, isFalse);
      expect(SharedDeviceNetworkServer.deviceCount, 0);
      expect(SharedDeviceNetworkServer.devices, isEmpty);

      // 2. Set onDataReceived callback
      SharedDeviceNetworkServer.onDataReceived((deviceId, message) {
        receivedData[deviceId] = message;
        return {'handled': true, 'deviceId': deviceId};
      });

      // 3. Add first device -> starts the UDP server automatically
      final added1 = await SharedDeviceNetworkServer.addDevice(
        'static-printer-01',
        'Kitchen Bluetooth Printer',
        deviceDescription: 'Thermal ESC/POS',
      );

      expect(added1, isTrue);
      expect(SharedDeviceNetworkServer.isRunning, isTrue);
      expect(SharedDeviceNetworkServer.deviceCount, 1);
      expect(SharedDeviceNetworkServer.hasDevice('static-printer-01'), isTrue);
      expect(SharedDeviceNetworkServer.getDevice('static-printer-01')?.deviceName, 'Kitchen Bluetooth Printer');

      // 4. Add second device
      final added2 = await SharedDeviceNetworkServer.addDevice(
        'static-scanner-01',
        'USB Barcode Scanner',
        pairKey: 'pass456',
      );

      expect(added2, isTrue);
      expect(SharedDeviceNetworkServer.deviceCount, 2);

      // 5. Client discovers both shared devices
      client = SharedDeviceNetworkClient(
        deviceId: 'pos-terminal-01',
        discoveryPort: staticTestDiscoveryPort,
        defaultTimeout: const Duration(seconds: 3),
      );

      final discovered = await client.discoverDevicesOnce(
        timeout: const Duration(milliseconds: 1500),
      );

      expect(discovered.length, 2);
      expect(discovered.any((d) => d.deviceId == 'static-printer-01'), isTrue);
      expect(discovered.any((d) => d.deviceId == 'static-scanner-01'), isTrue);

      // 6. Send to printer via client
      final printStatus = await client.sendToDevice(
        'static-printer-01',
        {'cmd': 'PRINT_ORDER', 'items': 3},
      );

      expect(printStatus.isSuccess, isTrue);
      expect(receivedData['static-printer-01']['cmd'], 'PRINT_ORDER');

      // 7. Send to scanner with valid pairKey
      final scanStatus = await client.sendToDevice(
        'static-scanner-01',
        {'cmd': 'TRIGGER_SCAN'},
        pairKey: 'pass456',
      );

      expect(scanStatus.isSuccess, isTrue);
      expect(receivedData['static-scanner-01']['cmd'], 'TRIGGER_SCAN');

      // 8. Remove 1st device -> 1 remaining, server stays running
      final removed1 = await SharedDeviceNetworkServer.removeDevice('static-printer-01');
      expect(removed1, isTrue);
      expect(SharedDeviceNetworkServer.deviceCount, 1);
      expect(SharedDeviceNetworkServer.isRunning, isTrue);

      // 9. Remove 2nd device -> 0 remaining, server automatically stops
      final removed2 = await SharedDeviceNetworkServer.removeDevice('static-scanner-01');
      expect(removed2, isTrue);
      expect(SharedDeviceNetworkServer.deviceCount, 0);
      expect(SharedDeviceNetworkServer.isRunning, isFalse);
    });

    test('Static API supports configurable notification title and text with placeholders', () async {
      await SharedDeviceNetworkServer.init(
        port: 9911,
        discoveryPort: 9912,
        notificationTitle: '{devices} ({deviceCount} Active)',
        notificationText: 'Sharing on port {port}',
        enableForegroundService: false,
      );

      final added = await SharedDeviceNetworkServer.addDevice(
        'pos-printer-01',
        'Kitchen Printer',
      );
      expect(added, isTrue);

      final formattedTitle = NotificationTemplate.format(
        '{devices} ({deviceCount} Active)',
        deviceNames: SharedDeviceNetworkServer.devices.map((d) => d.deviceName).toList(),
        count: SharedDeviceNetworkServer.deviceCount,
      );
      expect(formattedTitle, 'Kitchen Printer (1 Active)');

      await SharedDeviceNetworkServer.updateNotification(
        notificationTitle: 'Custom Server - {deviceCount}',
      );

      final updatedTitle = NotificationTemplate.format(
        'Custom Server - {deviceCount}',
        count: SharedDeviceNetworkServer.deviceCount,
      );
      expect(updatedTitle, 'Custom Server - 1');

      await SharedDeviceNetworkServer.removeDevice('pos-printer-01');
    });
  });
}
