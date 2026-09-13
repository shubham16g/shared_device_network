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

Instantiate `SharedDeviceNetworkServer`, register your message handling callback with `server.onMessageReceived(...)`, start it, and register your peripherals:

```dart
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Instantiate the server
  final server = SharedDeviceNetworkServer();

  // 2. Register callback for incoming messages/commands
  server.onMessageReceived((deviceId, message) async {
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
  });

  // 3. Start listening on UDP sockets (with optional custom ports)
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

## 🔄 Running as a Background Service

When using a mobile device or tablet as the host server (e.g. at a counter or POS terminal), you often want the server to continue listening for UDP discovery and processing peripheral commands even when the app is minimized, running in the background, or the screen is turned off.

You can integrate `shared_device_network` with [`flutter_background_service`](https://pub.dev/packages/flutter_background_service) to run the server continuously in an Android Foreground Service.

> **📱 Complete Working Example Included**:
> A complete, production-ready example is available in the [`example/`](example) directory:
> - [**`example/lib/server_background_service.dart`**](example/lib/server_background_service.dart): Implements background isolate lifecycle, device persistence with `shared_preferences`, and bidirectional event communication between UI and background service.
> - [**`example/lib/bg_service_screen.dart`**](example/lib/bg_service_screen.dart): Interactive UI with server controls, hosted device manager, real-time packet logs, and an internal test client.
> - [**`example/lib/main.dart`**](example/lib/main.dart): Demonstrates host & client tabs with one-tap access to background service mode via the **"In Background"** button.

### 1. Add Dependencies

Add the background service and permission handler to your app's `pubspec.yaml`:

```yaml
dependencies:
  shared_device_network: ^0.0.1
  flutter_background_service: ^5.1.0
  permission_handler: ^11.3.1
```

### 2. Android Manifest Configuration

In `android/app/src/main/AndroidManifest.xml`, declare the required permissions and foreground service:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Network & WakeLock permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <!-- Foreground service permissions (Android 14+ requires specific types) -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application ...>
        <!-- Declare BackgroundService with connectedDevice & dataSync types -->
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:foregroundServiceType="connectedDevice|dataSync"
            android:stopWithTask="false"
            android:enabled="true"
            android:exported="true" />
    </application>
</manifest>
```

### 3. Background Service Implementation (Pure Dart / Flutter)

Configure and start the `SharedDeviceNetworkServer` inside your background isolate:

```dart
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_device_network/shared_device_network.dart';

// 1. Entry point for the background isolate
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final server = SharedDeviceNetworkServer();

  // Register peripheral message handler
  server.onMessageReceived((deviceId, message) async {
    // Notify UI isolate via service pipe
    service.invoke('messageReceived', {
      'deviceId': deviceId,
      'message': message,
      'time': DateTime.now().toIso8601String(),
    });

    // Update foreground notification status
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Shared Device Background Server',
        content: 'Processed command for "$deviceId"',
      );
    }

    return SharedDeviceResponse.success(
      message: 'Processed by Background Service for $deviceId',
      data: {'echo': message},
    );
  });

  // Start server on dedicated background ports
  await server.start(port: 9888, discoveryPort: 9889);

  // Register shared peripherals
  await server.addDevice('printer-bt-01', 'Counter Thermal Printer');

  // Handle stop signal from UI
  service.on('stopService').listen((_) async {
    await server.stop();
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// 2. Configure service from UI isolate (no native Kotlin/Java edits required!)
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      // Omitting notificationChannelId lets the plugin automatically create
      // and manage its internal FOREGROUND_DEFAULT notification channel.
      initialNotificationTitle: 'Shared Device Service',
      initialNotificationContent: 'Shared Device background server is running',
      foregroundServiceNotificationId: 988,
      foregroundServiceTypes: [
        AndroidForegroundType.connectedDevice,
        AndroidForegroundType.dataSync,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

// 3. Start or stop the service
Future<void> startServerService() async {
  await initializeBackgroundService();
  await FlutterBackgroundService().startService();
}

void stopServerService() {
  FlutterBackgroundService().invoke('stopService');
}
```

---

## 📋 API Overview

### `SharedDeviceNetworkServer`

| Method / Property | Description |
| :--- | :--- |
| `SharedDeviceNetworkServer()` | Creates a new server instance. |
| `onMessageReceived(callback)` | Registers callback invoked when a message is received for a peripheral. |
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

## 🧪 Testing & Example App

Run the test suite:

```bash
flutter test
```

### 📱 Running the Example Project

The repository includes a comprehensive Flutter example application under [`example/`](example):

```bash
cd example
flutter run
```

The example app includes:
- **Host Server Mode**: Create virtual peripherals, adjust UDP ports, inspect incoming packets, and toggle discovery.
- **Client Discovery Mode**: Auto-discover servers on the local WiFi network, list peripherals, and dispatch test commands with status response inspection.
- **Background Service Mode**: Tap **"In Background"** in the top bar to launch the dedicated background service controller, allowing the host server to run in an Android foreground service with persistent notifications and background isolate execution.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
