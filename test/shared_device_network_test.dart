import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_device_network/shared_device_network.dart';
import 'package:shared_device_network/src/discovery/discovery_provider_interface.dart';
import 'package:shared_device_network/src/discovery/discovery_provider_web.dart';
import 'package:shared_device_network/src/models/shared_device_server.dart';
import 'package:shared_device_network/src/server/server_transport_web.dart';

/// Mock DiscoveryProvider for deterministic in-memory tests
class MockDiscoveryProvider implements DiscoveryProvider {
  final List<SharedDeviceServer> mockServers;
  bool isBroadcasting = false;

  MockDiscoveryProvider({this.mockServers = const []});

  @override
  bool get isSupported => true;

  @override
  Future<void> startBroadcast({
    required String serviceType,
    required int port,
    String? serviceName,
    String protocolVersion = '1.0',
    List<String> capabilities = const [],
    Map<String, String> metadata = const {},
  }) async {
    isBroadcasting = true;
  }

  @override
  Future<void> stopBroadcast() async {
    isBroadcasting = false;
  }

  @override
  Stream<SharedDeviceServer> discoverServers({
    required String serviceType,
    Duration timeout = const Duration(seconds: 4),
    String? excludeServerId,
  }) {
    final filtered = mockServers.where(
      (s) => excludeServerId == null || s.serverId != excludeServerId,
    );
    return Stream.fromIterable(filtered);
  }

  @override
  Future<List<SharedDeviceServer>> discoverServersOnce({
    required String serviceType,
    Duration timeout = const Duration(seconds: 4),
    String? excludeServerId,
  }) async {
    return mockServers
        .where((s) => excludeServerId == null || s.serverId != excludeServerId)
        .toList();
  }

  @override
  Future<void> dispose() async {
    await stopBroadcast();
  }
}

void main() {
  group('SharedDeviceNetwork Server & Client HTTP Integration Tests', () {
    late SharedDeviceNetworkServer server;
    late SharedDeviceNetworkClient client;
    final int testPort = 18880;

    setUp(() {
      server = SharedDeviceNetworkServer();
      client = SharedDeviceNetworkClient(
        clientId: 'client-test-01',
        clientName: 'Waiter Tablet',
      );
    });

    tearDown(() async {
      try {
        await server.dispose();
      } catch (_) {}
      try {
        await client.dispose();
      } catch (_) {}
    });

    test('Server lifecycle: start, idempotent start, stop, idempotent stop, dispose', () async {
      expect(server.isRunning, isFalse);
      expect(server.port, isNull);

      // Start on localhost
      await server.start(port: testPort, host: '127.0.0.1', advertise: false);
      expect(server.isRunning, isTrue);
      expect(server.port, testPort);

      // Calling start a second time is safe and idempotent
      await server.start(port: testPort, host: '127.0.0.1', advertise: false);
      expect(server.isRunning, isTrue);

      // Stop
      await server.stop();
      expect(server.isRunning, isFalse);

      // Stopping again is safe
      await server.stop();
      expect(server.isRunning, isFalse);

      // Dispose
      await server.dispose();
      expect(server.deviceCount, 0);
    });

    test('Device management: registration, lookup, duplicates, and removal', () async {
      expect(server.deviceCount, 0);

      // Add device
      await server.addDevice(
        'printer-01',
        'Kitchen Printer',
        deviceDescription: 'Thermal 80mm',
        capabilities: ['print', 'escpos'],
      );
      expect(server.deviceCount, 1);
      expect(server.hasDevice('printer-01'), isTrue);
      expect(server.getDevice('printer-01')?.deviceName, 'Kitchen Printer');
      expect(server.getDevice('printer-01')?.capabilities, ['print', 'escpos']);

      // Empty ID throws ArgumentError
      expect(
        () => server.addDevice('', 'Empty ID'),
        throwsArgumentError,
      );

      // Duplicate ID throws ArgumentError
      expect(
        () => server.addDevice('printer-01', 'Duplicate Printer'),
        throwsArgumentError,
      );

      // Remove device
      await server.removeDevice('printer-01');
      expect(server.deviceCount, 0);
      expect(server.hasDevice('printer-01'), isFalse);
    });

    test('HTTP API: GET /info, GET /devices with IP tagging, GET /devices/:id', () async {
      await server.addDevice(
        'printer-01',
        'Kitchen Printer',
        capabilities: ['escpos'],
      );
      await server.addDevice(
        'scanner-01',
        'Barcode Scanner',
        capabilities: ['barcode'],
      );
      await server.start(port: testPort + 1, host: '127.0.0.1', advertise: false);

      // Connect client and retrieve devices
      final devices = await client.getDevicesFromHost(
        host: '127.0.0.1',
        port: testPort + 1,
      );
      expect(devices.length, 2);
      expect(devices.any((d) => d.deviceId == 'printer-01'), isTrue);
      expect(devices.any((d) => d.deviceId == 'scanner-01'), isTrue);

      // Verify IP and port are properly tagged
      final printer = devices.firstWhere((d) => d.deviceId == 'printer-01');
      expect(printer.deviceIp, '127.0.0.1');
      expect(printer.devicePort, testPort + 1);

      // GET /api/v1/devices/:id
      final dev = await client.getDevice(
        'printer-01',
        host: '127.0.0.1',
        port: testPort + 1,
      );
      expect(dev, isNotNull);
      expect(dev!.deviceName, 'Kitchen Printer');
      expect(dev.capabilities, ['escpos']);
      expect(dev.deviceIp, '127.0.0.1');
      expect(dev.devicePort, testPort + 1);

      // Non-existent device returns null
      final notFound = await client.getDevice(
        'non-existent',
        host: '127.0.0.1',
        port: testPort + 1,
      );
      expect(notFound, isNull);
    });

    test('HTTP Command Dispatch: successful command using tagged device IP', () async {
      int commandsReceived = 0;
      server.onMessageReceived((deviceId, message) async {
        commandsReceived++;
        if (deviceId == 'printer-01') {
          return SharedDeviceResponse.success(
            message: 'Receipt printed',
            data: {'total': message['total']},
          );
        }
        return SharedDeviceResponse.deviceNotFound();
      });

      await server.addDevice('printer-01', 'Printer');
      await server.start(port: testPort + 2, host: '127.0.0.1', advertise: false);

      // Fetch devices so client caches the device with its IP tag
      final devices = await client.getDevicesFromHost(
        host: '127.0.0.1',
        port: testPort + 2,
      );
      final printer = devices.first;

      // Send to device directly using the tagged device
      final res = await client.sendToDevice('printer-01', {
        'command': 'PRINT_RECEIPT',
        'total': 45.50,
      }, targetDevice: printer);

      expect(res.isSuccess, isTrue);
      expect(res.statusCode, 200);
      expect(res.message, 'Receipt printed');
      expect(res.data, {'total': 45.50});
      expect(res.requestId, isNotNull);
      expect(commandsReceived, 1);
    });

    test('HTTP Authentication: pairKey security validation', () async {
      server.onMessageReceived((deviceId, message) async {
        return SharedDeviceResponse.success(message: 'Authorized access');
      });

      await server.addDevice(
        'secure-lock-01',
        'Electronic Door Lock',
        pairKey: 'top-secret-42',
      );
      await server.start(port: testPort + 3, host: '127.0.0.1', advertise: false);

      final devices = await client.getDevicesFromHost(
        host: '127.0.0.1',
        port: testPort + 3,
      );
      final lock = devices.first;
      expect(lock.isSecured, isTrue);

      // Missing or wrong key returns 401 Unauthorized
      final unauthRes = await client.sendToDevice(
        'secure-lock-01',
        {'cmd': 'UNLOCK'},
        targetDevice: lock,
        pairKey: 'wrong-key',
      );
      expect(unauthRes.isSuccess, isFalse);
      expect(unauthRes.statusCode, 401);

      // Correct key returns 200 OK
      final authRes = await client.sendToDevice(
        'secure-lock-01',
        {'cmd': 'UNLOCK'},
        targetDevice: lock,
        pairKey: 'top-secret-42',
      );
      expect(authRes.isSuccess, isTrue);
      expect(authRes.statusCode, 200);
      expect(authRes.message, 'Authorized access');
    });

    test('Idempotency: duplicate request IDs return cached response without re-executing', () async {
      int executions = 0;
      server.onMessageReceived((deviceId, message) async {
        executions++;
        return SharedDeviceResponse.success(
          message: 'Drawer kicked #$executions',
          data: {'count': executions},
        );
      });

      await server.addDevice('drawer-01', 'Cash Drawer');
      await server.start(port: testPort + 4, host: '127.0.0.1', advertise: false);
      await client.getDevicesFromHost(host: '127.0.0.1', port: testPort + 4);

      const reqId = 'req_unique_idempotent_test_01';

      // First call -> executes callback
      final res1 = await client.sendToDevice(
        'drawer-01',
        {'cmd': 'KICK'},
        requestId: reqId,
      );
      expect(res1.isSuccess, isTrue);
      expect(res1.data, {'count': 1});
      expect(executions, 1);

      // Second call with same requestId -> returns cached response
      final res2 = await client.sendToDevice(
        'drawer-01',
        {'cmd': 'KICK'},
        requestId: reqId,
      );
      expect(res2.isSuccess, isTrue);
      expect(res2.data, {'count': 1});
      expect(executions, 1); // Callback was NOT invoked a second time!
    });

    test('Binary / Image Transfer: sendBinaryToDevice and sendMultipartToDevice', () async {
      List<int>? receivedBinaryBytes;
      String? receivedContentType;
      String? receivedFileName;

      server.onBinaryReceived((deviceId, bytes, {required contentType, fileName, requestId}) async {
        receivedBinaryBytes = bytes;
        receivedContentType = contentType;
        receivedFileName = fileName;
        return SharedDeviceResponse.success(
          message: 'Image received',
          data: {'size': bytes.length},
        );
      });

      await server.addDevice('printer-01', 'Thermal Printer');
      await server.start(port: testPort + 5, host: '127.0.0.1', advertise: false);
      await client.getDevicesFromHost(host: '127.0.0.1', port: testPort + 5);

      // 1. Raw binary upload
      final rawBytes = [0x1B, 0x40, 0x1B, 0x69]; // ESC @, ESC i (sample ESC/POS)
      final binRes = await client.sendBinaryToDevice(
        'printer-01',
        rawBytes,
        contentType: 'application/octet-stream',
        fileName: 'raw_print.bin',
      );
      expect(binRes.isSuccess, isTrue);
      expect(receivedBinaryBytes, rawBytes);
      expect(receivedContentType, 'application/octet-stream');
      expect(receivedFileName, 'raw_print.bin');

      // 2. Multipart file upload
      final multipartBytes = [0x89, 0x50, 0x4E, 0x47]; // PNG header
      final multiRes = await client.sendMultipartToDevice(
        'printer-01',
        multipartBytes,
        fileName: 'logo.png',
      );
      expect(multiRes.isSuccess, isTrue);
      expect(receivedBinaryBytes, multipartBytes);
      expect(receivedFileName, 'logo.png');
    });

    test('Error Handling: missing device returns 404', () async {
      await server.start(port: testPort + 6, host: '127.0.0.1', advertise: false);

      final res = await client.sendToDevice(
        'missing-device',
        {'test': 123},
        ip: '127.0.0.1',
        port: testPort + 6,
      );
      expect(res.isSuccess, isFalse);
      expect(res.statusCode, 404);
      expect(res.error, 'DEVICE_NOT_FOUND');
    });

    test('Timeout handling when target host is unreachable', () async {
      final res = await client.sendToAddress(
        '127.0.0.1',
        19999, // Nothing listening here
        {'test': true},
        timeout: const Duration(milliseconds: 300),
      );
      expect(res.isSuccess, isFalse);
    });

    test('Direct sendToAddress works with host and port', () async {
      server.onMessageReceived((deviceId, message) async {
        return SharedDeviceResponse.success(message: 'pong from $deviceId');
      });
      await server.addDevice('default', 'Default Device');
      await server.start(port: testPort + 7, host: '127.0.0.1', advertise: false);

      final res = await client.sendToAddress(
        '127.0.0.1',
        testPort + 7,
        {'action': 'ping'},
        targetDeviceId: 'default',
      );
      expect(res.isSuccess, isTrue);
      expect(res.message, 'pong from default');
    });
  });

  group('Device Discovery & Multi-Host Tests', () {
    test('Client discovers devices across network hosts with proper IP tagging', () async {
      final server = SharedDeviceNetworkServer();
      await server.addDevice(
        'printer-kitchen',
        'Kitchen Printer',
        deviceDescription: 'Thermal 80mm',
        capabilities: ['escpos', 'print'],
      );
      await server.addDevice(
        'scanner-front',
        'Front Barcode Scanner',
        capabilities: ['barcode'],
      );

      final livePort = 18895;
      await server.start(port: livePort, host: '127.0.0.1', advertise: false);

      final mockHost = SharedDeviceServer(
        serverId: 'host-1',
        serverName: 'Local Host',
        host: '127.0.0.1',
        port: livePort,
      );

      final mockDiscovery = MockDiscoveryProvider(
        mockServers: [mockHost],
      );

      final client = SharedDeviceNetworkClient(
        discovery: mockDiscovery,
      );

      // Perform device discovery
      final discoveredDevices = await client.discoverDevicesOnce();
      expect(discoveredDevices.length, 2);

      // Verify each device is tagged with the host's IP and port
      final printer = discoveredDevices.firstWhere((d) => d.deviceId == 'printer-kitchen');
      expect(printer.deviceName, 'Kitchen Printer');
      expect(printer.deviceIp, '127.0.0.1');
      expect(printer.devicePort, livePort);

      final scanner = discoveredDevices.firstWhere((d) => d.deviceId == 'scanner-front');
      expect(scanner.deviceName, 'Front Barcode Scanner');
      expect(scanner.deviceIp, '127.0.0.1');
      expect(scanner.devicePort, livePort);

      // Client cache contains the discovered devices
      expect(client.discoveredDevices.length, 2);

      // Direct send to device without specifying IP works because of cached IP tagging
      server.onMessageReceived((deviceId, message) async {
        return SharedDeviceResponse.success(message: 'Printed on $deviceId');
      });

      final printRes = await client.sendToDevice('printer-kitchen', {'print': 'test'});
      expect(printRes.isSuccess, isTrue);
      expect(printRes.message, 'Printed on printer-kitchen');

      await server.dispose();
      await client.dispose();
    });
  });

  group('Web Platform Compatibility Stubs Tests', () {
    test('ServerTransportWeb throws UnsupportedPlatformException on start', () async {
      final webTransport = ServerTransportWeb();
      expect(webTransport.isRunning, isFalse);
      expect(webTransport.port, isNull);

      expect(
        () => webTransport.start(
          host: '0.0.0.0',
          port: 8080,
          corsPolicy: const CorsPolicy(),
          maxBodySizeBytes: 1024,
          onInfo: () => {},
          onDevices: () => [],
          onDeviceLookup: (_) => null,
          onCommand: (_, __, ___) async => SharedDeviceResponse.success(),
          onBinary: (_, __, {required contentType, fileName, requestId, authHeader}) async =>
              SharedDeviceResponse.success(),
        ),
        throwsA(isA<UnsupportedPlatformException>()),
      );
    });

    test('WebDiscoveryProvider reports isSupported = true, supports discoverServers, and throws on broadcast', () async {
      final webDiscovery = WebDiscoveryProvider();
      expect(webDiscovery.isSupported, isTrue);

      expect(
        () => webDiscovery.startBroadcast(
          serviceType: '_test._tcp',
          port: 8080,
        ),
        throwsA(isA<UnsupportedPlatformException>()),
      );

      // discoverServersOnce runs HTTP prober and completes cleanly
      final discovered = await webDiscovery.discoverServersOnce(
        serviceType: '_test._tcp',
        timeout: const Duration(milliseconds: 200),
      );
      expect(discovered, isA<List<SharedDeviceServer>>());
    });
  });
}
