# Shared Device Network (`shared_device_network`)

A lightweight Flutter and Dart package for sharing connected hardware and peripheral devices (e.g. Bluetooth printers, USB barcode scanners, cash drawers, secondary customer displays, digital scales) across a local WiFi/LAN network using UDP discovery, reliable incremental ACK messaging, and per-device pairing keys.

---

## 💡 Concept & Architecture

1. **Host Server (`SharedDeviceNetworkServer`)**:
   - Runs on the host machine/terminal that has physical or Bluetooth connections to peripherals.
   - Binds a UDP data port (default: `8888`) and a UDP discovery port (default: `8889`).
   - Receives commands/data from network clients and routes them to the appropriate local device handler via `onMessageReceived`.
2. **Device Registration (`addDevice` & `removeDevice`)**:
   - Register peripherals dynamically with unique IDs, human-readable names, optional descriptions, pair keys, and metadata.
   - Throws clear `ArgumentError` exceptions if device IDs are empty or already registered.
3. **Multi-Device UDP Discovery (`SharedDeviceNetworkClient`)**:
   - When a client broadcasts a discovery request on the LAN, the server responds with details of all currently registered peripherals.
   - The client discovers the host and receives individual `SharedDevice` descriptors for each peripheral.
4. **Reliable Communication & Pairing Security**:
   - Packets include sequential message IDs and return structured `SharedDeviceResponse` acknowledgments (with status codes like `200`, `401`, `404`, `408`).
   - Devices can be protected with a `pairKey` to enforce authorization before commands are dispatched.

---

## 🚀 Features

- **📡 Multi-Device UDP Discovery**: Emits all shared connected peripherals hosted on a machine to discovering network clients.
- **🎛️ Explicit Lifecycle Control**: Start, stop, and dispose UDP sockets cleanly with `start()`, `stop()`, and `dispose()`.
- **🔢 Reliable Messaging & ACKs**: Sequence tracking with message IDs and structured `SharedDeviceResponse` acknowledgments.
- **🔐 Per-Device Pair Key Security**: Optional password/key per shared device (returns `401 Unauthorized` on mismatch).
- **🛡️ Robust Input Validation**: Validates device registration to prevent empty or duplicate device IDs.
- **🌐 Cross-Platform**: Android, iOS, Windows, macOS, and Linux.

---

## 📦 Installation

Add `shared_device_network` to your `pubspec.yaml`:

```yaml
dependencies:
  shared_device_network: ^0.0.1
```

Then run:

```bash
flutter pub get
```

---

## 🛠️ Usage

### 1. Host Device: Sharing Connected Devices

Instantiate `SharedDeviceNetworkServer` with your message handling callback, start it, and register your peripherals:

```dart
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Instantiate the server with the message handler
  final server = SharedDeviceNetworkServer(
    onMessageReceived: (deviceId, message) async {
      print('📥 Host received for "$deviceId": $message');

      if (deviceId == 'printer-bt-01') {
        // Forward print bytes to Bluetooth printer...
        return SharedDeviceResponse.success(
          message: 'Receipt printed successfully',
          data: {'printedAt': DateTime.now().toIso8601String()},
        );
      } else if (deviceId == 'scanner-usb-01') {
        // Trigger barcode scan...
        return SharedDeviceResponse.success(
          message: 'Scan completed',
          data: {'barcode': '890123456789'},
        );
      }

      return SharedDeviceResponse.deviceNotFound(
        message: 'Device "$deviceId" not found',
      );
    },
  );

  // 2. Start listening on UDP sockets (with optional custom ports)
  await server.start(
    port: 8888,
    discoveryPort: 8889,
  );

  // 3. Register shared peripherals
  await server.addDevice(
    'printer-bt-01',
    'Kitchen Bluetooth Printer',
    deviceDescription: 'Thermal 80mm ESC/POS receipt printer',
  );

  await server.addDevice(
    'scanner-usb-01',
    'Counter Barcode Scanner',
    deviceDescription: 'USB 2D Barcode & QR Scanner',
    pairKey: 'scanner-pass-123', // Optional authorization key
  );

  // 4. Remove a device when disconnected or unshared
  // await server.removeDevice('printer-bt-01');

  // 5. Cleanup when finished
  // await server.dispose();
}
```

---

### 2. Client Device: Discovering & Sending to Shared Devices

Clients discover available peripherals on the LAN and dispatch commands:

```dart
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  // 1. Create client instance
  final client = SharedDeviceNetworkClient(
    deviceId: 'waiter-tablet-01',
    deviceName: 'Waiter Tablet #1',
    discoveryPort: 8889,
    defaultTimeout: const Duration(seconds: 3),
  );

  // 2. Discover shared devices on the local network
  final List<SharedDevice> devices = await client.discoverDevicesOnce(
    timeout: const Duration(seconds: 2),
  );

  for (final device in devices) {
    print('Found: ${device.deviceName} (${device.deviceId}) at ${device.deviceIp}:${device.devicePort}');
  }

  // 3. Send command to the printer
  final printResponse = await client.sendToDevice(
    'printer-bt-01',
    {'cmd': 'PRINT_BILL', 'table': 4, 'total': 45.50},
  );

  if (printResponse.isSuccess) {
    print('✅ Print ACK: ${printResponse.message}');
  } else {
    print('❌ Print failed [${printResponse.statusCode}]: ${printResponse.message}');
  }

  // 4. Send command to the protected scanner with pairKey
  final scanResponse = await client.sendToDevice(
    'scanner-usb-01',
    {'cmd': 'TRIGGER_SCAN'},
    pairKey: 'scanner-pass-123',
  );

  if (scanResponse.isSuccess) {
    print('✅ Scanned barcode: ${scanResponse.data?['barcode']}');
  }

  // 5. Cleanup client when done
  // await client.dispose();
}
```

---

## 📋 API Overview

### `SharedDeviceNetworkServer`

| Method / Property | Description |
| :--- | :--- |
| `SharedDeviceNetworkServer({required onMessageReceived})` | Creates a new server instance. |
| `start({port = 8888, discoveryPort = 8889, discoverPort})` | Binds the UDP data and discovery sockets and begins listening. |
| `port` | Active UDP data port. |
| `discoveryPort` | Active UDP discovery broadcast port. |
| `stop()` | Closes UDP sockets and stops listening. |
| `dispose()` | Stops the server, clears registered devices, and closes streams. |
| `addDevice(id, name, {deviceDescription, pairKey, metadata})` | Registers a shared peripheral. Throws `ArgumentError` if ID is empty or duplicate. |
| `removeDevice(id)` | Unregisters a shared peripheral. |
| `hasDevice(id)` | Returns `true` if device with ID is registered. |
| `getDevice(id)` | Retrieves the `SharedDeviceRecord` for the given ID. |
| `devices` | Returns a list of all currently registered `SharedDeviceRecord` items. |
| `deviceCount` | Number of currently registered devices. |
| `isRunning` | Whether the server UDP sockets are active. |
| `messageStream` | Stream of incoming valid `NetworkPacket` objects. |

### `SharedDeviceResponse`

| Status Factory | Status Code | Description |
| :--- | :--- | :--- |
| `SharedDeviceResponse.success(...)` | `200` | Successful operation ACK. |
| `SharedDeviceResponse.deviceNotFound(...)` | `404` | Target peripheral is not registered on the server. |
| `SharedDeviceResponse.unauthorized(...)` | `401` | Invalid or missing `pairKey`. |
| `SharedDeviceResponse.badRequest(...)` | `400` | Malformed message or ambiguous target. |
| `SharedDeviceResponse.error(...)` | `500` | Processing error / unhandled exception. |

---

## 🧪 Testing

Run unit and integration tests:

```bash
flutter test
```

To run the interactive demo app:

```bash
cd example
flutter run
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
