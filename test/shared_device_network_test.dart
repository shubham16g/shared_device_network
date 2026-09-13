import 'package:flutter_test/flutter_test.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() {
  group('SharedDeviceNetworkServer Tests', () {
    const testPort = 18888;
    const testDiscoveryPort = 18889;

    late SharedDeviceNetworkServer server;
    late SharedDeviceNetworkClient client;

    tearDown(() async {
      try {
        await server.dispose();
      } catch (_) {}
      try {
        await client.dispose();
      } catch (_) {}
    });

    test(
      'Server lifecycle, device management, discovery, and message dispatch',
      () async {
        // 1. Initialize server using constructor and onMessageReceived method
        server = SharedDeviceNetworkServer();
        server.onMessageReceived((deviceId, message) async {
          if (deviceId == 'printer-bt-01') {
            return SharedDeviceResponse.success(
              message: 'Receipt printed successfully',
            );
          } else if (deviceId == 'scanner-usb-01') {
            return SharedDeviceResponse.success(
              message: 'Scan triggered',
              data: {'barcode': '890123456789'},
            );
          }

          return SharedDeviceResponse.deviceNotFound();
        });

        expect(server.isRunning, isFalse);
        await server.start(port: testPort, discoveryPort: testDiscoveryPort);
        expect(server.isRunning, isTrue);
        expect(server.port, testPort);
        expect(server.discoveryPort, testDiscoveryPort);
        expect(server.deviceCount, 0);

        // 2. Add devices
        await server.addDevice(
          'printer-bt-01',
          'Kitchen Bluetooth Printer',
          deviceDescription: 'Thermal 80mm ESC/POS printer',
        );

        await server.addDevice(
          'scanner-usb-01',
          'Barcode Scanner',
          deviceDescription: 'USB 2D Scanner',
        );

        expect(server.deviceCount, 2);
        expect(server.hasDevice('printer-bt-01'), isTrue);
        expect(server.hasDevice('scanner-usb-01'), isTrue);
        expect(
          server.getDevice('printer-bt-01')?.deviceName,
          'Kitchen Bluetooth Printer',
        );

        // 3. Validation: duplicate and empty device ID
        expect(
          () => server.addDevice('', 'Empty ID Device'),
          throwsArgumentError,
        );
        expect(
          () => server.addDevice('printer-bt-01', 'Duplicate Printer'),
          throwsArgumentError,
        );

        // 4. Client discovery
        client = SharedDeviceNetworkClient(
          deviceId: 'pos-terminal-1',
          discoveryPort: testDiscoveryPort,
          defaultServerPort: testPort,
          defaultTimeout: const Duration(seconds: 2),
        );

        final discovered = await client.discoverDevicesOnce(
          timeout: const Duration(milliseconds: 1500),
        );
        expect(discovered.length, 2);

        // 5. Send message to printer-bt-01
        final printerRes = await client.sendToDevice('printer-bt-01', {
          'bytes': [0x1B, 0x40],
        });
        expect(printerRes.isSuccess, isTrue);
        expect(printerRes.message, 'Receipt printed successfully');

        // 6. Send message to scanner-usb-01
        final scannerRes = await client.sendToDevice('scanner-usb-01', {
          'trigger': true,
        });
        expect(scannerRes.isSuccess, isTrue);
        expect(scannerRes.message, 'Scan triggered');
        expect(scannerRes.data, {'barcode': '890123456789'});

        // 7. Send message to unknown device
        final unknownRes = await client.sendToDevice('unknown-device', {
          'test': true,
        });
        expect(unknownRes.isSuccess, isFalse);
        expect(unknownRes.statusCode, 404);

        // 8. Remove devices
        await server.removeDevice('printer-bt-01');
        expect(server.deviceCount, 1);
        expect(server.hasDevice('printer-bt-01'), isFalse);
        expect(server.isRunning, isTrue);

        await server.removeDevice('scanner-usb-01');
        expect(server.deviceCount, 0);
        expect(server.hasDevice('scanner-usb-01'), isFalse);

        // 9. Stop server
        await server.stop();
        expect(server.isRunning, isFalse);
      },
    );

    test('Supports pair key security on devices', () async {
      server = SharedDeviceNetworkServer();
      server.onMessageReceived((deviceId, message) async {
        return SharedDeviceResponse.success(message: 'Authorized access');
      });
      await server.start(port: 18890, discoveryPort: 18891);

      await server.addDevice(
        'secure-device',
        'Secure Peripheral',
        pairKey: 'secret-key-123',
      );

      client = SharedDeviceNetworkClient(
        deviceId: 'pos-terminal-2',
        discoveryPort: 18891,
        defaultServerPort: 18890,
        defaultTimeout: const Duration(seconds: 2),
      );

      // Wrong key -> 401 Unauthorized
      final unauthRes = await client.sendToDevice('secure-device', {
        'command': 'OPEN',
      }, pairKey: 'wrong-key');
      expect(unauthRes.isSuccess, isFalse);
      expect(unauthRes.statusCode, 401);

      // Correct key -> 200 OK
      final authRes = await client.sendToDevice('secure-device', {
        'command': 'OPEN',
      }, pairKey: 'secret-key-123');
      expect(authRes.isSuccess, isTrue);
      expect(authRes.message, 'Authorized access');
    });

    test('Handles timeout when target is unreachable', () async {
      client = SharedDeviceNetworkClient(
        deviceId: 'timeout-client',
        defaultTimeout: const Duration(milliseconds: 300),
      );

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

    test('start() respects default ports and discoverPort alias', () async {
      final defaultServer = SharedDeviceNetworkServer();
      expect(defaultServer.port, 8888);
      expect(defaultServer.discoveryPort, 8889);

      final customServer = SharedDeviceNetworkServer();
      await customServer.start(port: 19888, discoverPort: 19889);
      expect(customServer.port, 19888);
      expect(customServer.discoveryPort, 19889);
      await customServer.dispose();
    });

    test(
      'Dynamic callback configuration with server.onMessageReceived',
      () async {
        server = SharedDeviceNetworkServer();
        await server.start(port: 19990, discoveryPort: 19991);
        await server.addDevice('test-dyn', 'Dynamic Device');

        client = SharedDeviceNetworkClient(
          deviceId: 'dyn-client',
          discoveryPort: 19991,
          defaultServerPort: 19990,
          defaultTimeout: const Duration(seconds: 2),
        );

        // 1. Before handler registered -> returns 404 No message handler
        final noHandlerRes = await client.sendToDevice('test-dyn', 'ping');
        expect(noHandlerRes.isSuccess, isFalse);
        expect(noHandlerRes.statusCode, 404);

        // 2. Dynamically register handler via server.onMessageReceived(...)
        server.onMessageReceived((deviceId, message) {
          return SharedDeviceResponse.success(message: 'pong from $deviceId');
        });

        final handlerRes = await client.sendToDevice('test-dyn', 'ping');
        expect(handlerRes.isSuccess, isTrue);
        expect(handlerRes.message, 'pong from test-dyn');
      },
    );
  });
}
