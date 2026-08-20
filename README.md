# Shared Device Network (`shared_device_network`)

A Flutter and Dart package for sharing connected hardware/peripheral devices (e.g. Bluetooth printers, USB barcode scanners, cash drawers, secondary screens) over the local WiFi/LAN network using UDP discovery, incremental ACK messaging, per-device pairing authorization, and foreground service background execution.

---

## 💡 Concept & Architecture

1. **One UDP Server per Host Device / Phone**:
   - The phone or host machine runs **one** UDP server.
   - The phone has locally connected peripherals (e.g. Bluetooth Receipt Printer, USB Scanner).
2. **Sharing Connected Devices via `addDevice`**:
   - Calling `addDevice('printer-1', 'Bluetooth Printer')` registers the peripheral and **automatically starts the UDP server**.
   - Calling `addDevice('scanner-1', 'Barcode Scanner')` again appends the new peripheral to the running server.
3. **Multi-Device Discovery on Client**:
   - When a client broadcasts a discovery request, the host server responds with **all** its currently shared connected devices.
   - The client discovers 1 UDP server host, but its discovery stream emits **2 separate `SharedDevice` records**!
4. **Auto-Stop on Removal**:
   - Calling `removeDevice('printer-1')` removes the device.
   - When all shared devices are removed, the UDP server **automatically stops**.

---

## 🚀 Features

- **📡 Multi-Device UDP Discovery**: Emits all shared connected devices hosted on a machine/phone to discovering clients.
- **⚡ Automatic Lifecycle Management**: UDP server auto-starts on the first `addDevice()` and auto-stops when the last device is removed.
- **🔢 Incremental Message IDs & Reliable ACKs**: Tracks message transmission with incremental IDs and returns structured `Status` responses.
- **🔐 Per-Device Pairing & Authorization**: Optional `pairKey` per shared device.
- **📱 Persistent Background Isolate**: Keeps the server running and peripherals shared even when the app UI is closed or killed.
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

```dart
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  final server = SharedDeviceNetworkServer(
    port: 8888,
    discoveryPort: 8889,
    onDataReceived: (deviceId, message) async {
      print('Received command for device $deviceId: $message');

      if (deviceId == 'printer-bt-01') {
        // Forward print bytes to Bluetooth printer
        return Status.success(message: 'Receipt printed successfully');
      } else if (deviceId == 'scanner-usb-01') {
        // Trigger barcode scan
        return Status.success(message: 'Scan triggered', data: {'barcode': '890123456789'});
      }

      return Status.deviceNotFound();
    },
  );

  // 1. Add first device -> Automatically starts the UDP server
  await server.addDevice(
    'printer-bt-01',
    'Kitchen Bluetooth Printer',
    deviceDescription: 'Thermal 80mm ESC/POS printer',
  );

  // 2. Add second device -> Appends to existing running server
  await server.addDevice(
    'scanner-usb-01',
    'Counter Barcode Scanner',
    pairKey: 'scanner-key-123',
  );

  // 3. Remove a device (Server auto-stops when all devices are removed)
  // await server.removeDevice('printer-bt-01');
  // await server.removeDevice('scanner-usb-01'); // Server stops automatically
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
    defaultTimeout: Duration(seconds: 4),
  );

  // Discover all shared devices across the network
  final devices = await client.discoverDevicesOnce();
  for (final device in devices) {
    print('Found: ${device.deviceName} (ID: ${device.deviceId}) at ${device.deviceIp}:${device.devicePort}');
  }

  // Send print job to the Bluetooth Printer
  final printStatus = await client.sendToDevice(
    'printer-bt-01',
    {'cmd': 'PRINT_BILL', 'table': 4, 'total': 45.50},
  );

  if (printStatus.isSuccess) {
    print('✅ Printed: ${printStatus.message}');
  }

  // Send command to the Barcode Scanner with pairKey
  final scanStatus = await client.sendToDevice(
    'scanner-usb-01',
    {'cmd': 'TRIGGER_SCAN'},
    pairKey: 'scanner-key-123',
  );

  print('Scan Result: ${scanStatus.data}');
}
```

---

### 3. Persistent Background Service (Keeps Running When App Is Killed)

```dart
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedDeviceForegroundService.init();
  runApp(const MyApp());
}

// Start persistent server in background isolate
Future<void> startBackgroundHost() async {
  await SharedDeviceForegroundService.startBackgroundServer(
    port: 8888,
    initialDevices: [
      SharedDeviceRecord(
        deviceId: 'printer-bt-01',
        deviceName: 'Kitchen Bluetooth Printer',
      ),
      SharedDeviceRecord(
        deviceId: 'scanner-usb-01',
        deviceName: 'Counter Scanner',
        pairKey: 'secret123',
      ),
    ],
  );
}
```

---

## 🤖 Android Foreground Service Setup

In `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />

    <application ...>
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="connectedDevice"
            android:stopWithTask="false"
            android:exported="false" />
    </application>
</manifest>
```

---

## 🧪 Testing

```bash
flutter test
```
