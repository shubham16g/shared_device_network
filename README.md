# Shared Device Network (`shared_device_network`)

A Flutter and Dart package for sharing connected hardware/peripheral devices (e.g. Bluetooth printers, USB barcode scanners, cash drawers, secondary screens) over the local WiFi/LAN network using UDP discovery, incremental ACK messaging, per-device pairing authorization, and automated foreground service execution.

---

## 💡 Concept & Architecture

1. **One Host Server per Device / Phone**:
   - The host machine/phone exposes peripherals through `SharedDeviceNetworkServer`.
   - The phone has locally connected peripherals (e.g. Bluetooth Receipt Printer, USB Scanner).
2. **Sharing Connected Devices via `addDevice`**:
   - Calling `SharedDeviceNetworkServer.addDevice('printer-1', 'Bluetooth Printer')` registers the peripheral and **automatically starts the UDP server** (and launches the Android foreground notification).
   - Calling `SharedDeviceNetworkServer.addDevice('scanner-1', 'Barcode Scanner')` appends the new peripheral to the running server.
3. **Lazy Start & Auto-Stop Lifecycle**:
   - `SharedDeviceNetworkServer.init(...)` prepares configurations and background service without showing any notification or opening network sockets.
   - The UDP server and foreground notification **only start when at least one device is added**.
   - When all shared devices are removed via `SharedDeviceNetworkServer.removeDevice(...)`, the UDP server and foreground notification **automatically stop**.
4. **Multi-Device Discovery on Client**:
   - When a client broadcasts a discovery request, the host server responds with **all** its currently shared connected devices.
   - The client discovers 1 UDP server host, and receives separate `SharedDevice` records for each peripheral!

---

## 🚀 Features

- **📡 Multi-Device UDP Discovery**: Emits all shared connected devices hosted on a machine/phone to discovering clients.
- **⚡ Automatic Lifecycle Management**: UDP server and foreground notification auto-start on the first `addDevice()` and auto-stop when the last device is removed.
- **🔢 Incremental Message IDs & Reliable ACKs**: Tracks message transmission with incremental IDs and returns structured `SharedDeviceResponse` responses.
- **🔐 Per-Device Pairing & Authorization**: Optional `pairKey` per shared device.
- **📱 Persistent Background Service**: Keeps the server running and peripherals shared even when the app UI is closed or killed.
- **🌐 Cross-Platform**: Android, iOS, Windows, macOS, Linux.

---

## 📦 Installation

```yaml
dependencies:
  shared_device_network: ^0.0.1
```

---

## 🛠️ Usage

### 1. Host Phone: Sharing Connected Devices

All server capabilities are accessed through the unified `SharedDeviceNetworkServer` class:

```dart
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize server configuration (does not start server or show notification yet)
  await SharedDeviceNetworkServer.init(
    port: 8888,
    discoveryPort: 8889,
    notificationChannelName: 'Shared Device Service',
    notificationChannelDescription: 'Shares peripherals over LAN',
    notificationId: 888,
    notificationTitle: 'POS Device Server Active',
    notificationText: 'Sharing connected peripherals on network...',
  );

  // 2. Register incoming data/command handler
  SharedDeviceNetworkServer.onDataReceived((deviceId, message) async {
    print('Received command for device $deviceId: $message');

    if (deviceId == 'printer-bt-01') {
      // Forward print bytes to Bluetooth printer...
      return SharedDeviceResponse.success(message: 'Receipt printed successfully');
    } else if (deviceId == 'scanner-usb-01') {
      // Trigger barcode scan...
      return SharedDeviceResponse.success(message: 'Scan triggered', data: {'barcode': '890123456789'});
    }

    return SharedDeviceResponse.deviceNotFound();
  });

  runApp(const MyApp());
}

// Sharing Peripherals
Future<void> shareDevices() async {
  // 3. Add first device -> Automatically starts the UDP server & shows notification!
  await SharedDeviceNetworkServer.addDevice(
    'printer-bt-01',
    'Kitchen Bluetooth Printer',
    deviceDescription: 'Thermal 80mm ESC/POS printer',
  );

  // 4. Add second device -> Appends to existing running server
  await SharedDeviceNetworkServer.addDevice(
    'scanner-usb-01',
    'Counter Barcode Scanner',
    pairKey: 'scanner-key-123',
  );

  // 5. Remove a device
  // await SharedDeviceNetworkServer.removeDevice('printer-bt-01');

  // When all devices are removed, the UDP server automatically stops and the notification is dismissed!
  // await SharedDeviceNetworkServer.removeDevice('scanner-usb-01');
}
```

---

### 2. Client Device: Discovering & Sending to Shared Devices

```dart
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  final client = SharedDeviceNetworkClient(
    deviceId: 'waiter-tablet-01',
    deviceName: 'Waiter Tablet #1',
    discoveryPort: 8889,
    defaultTimeout: Duration(seconds: 4),
  );

  // Discover all shared devices across the network
  final devices = await client.discoverDevicesOnce();
  for (final device in devices) {
    print('Found: ${device.deviceName} (ID: ${device.deviceId}) at ${device.deviceIp}:${device.devicePort}');
  }

  // Send print job to the Bluetooth Printer
  final printResponse = await client.sendToDevice(
    'printer-bt-01',
    {'cmd': 'PRINT_BILL', 'table': 4, 'total': 45.50},
  );

  if (printResponse.isSuccess) {
    print('✅ Printed: ${printResponse.message}');
  }

  // Send command to the Barcode Scanner with pairKey
  final scanResponse = await client.sendToDevice(
    'scanner-usb-01',
    {'cmd': 'TRIGGER_SCAN'},
    pairKey: 'scanner-key-123',
  );

  print('Scan Result: ${scanResponse.data}');
}
```

---

## 🤖 Android Foreground Service Setup

In `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Network & Bluetooth Permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />

    <!-- Foreground Service & Keep-Alive Permissions -->
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />

    <application ...>
        <!-- Declare BackgroundService with stopWithTask=false so it survives app termination -->
        <service
            android:name="id.flutter.flutter_background_service.BackgroundService"
            android:foregroundServiceType="connectedDevice|dataSync"
            android:stopWithTask="false"
            android:enabled="true"
            android:exported="true" />
    </application>
</manifest>
```

### Runtime Permissions

On Android 13+ (API 33+), request notification and battery optimization permissions:

```dart
await SharedDeviceNetworkServer.requestPermissions();
```

---

## 🧪 Testing

```bash
flutter test
```
