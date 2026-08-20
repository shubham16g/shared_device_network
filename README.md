# Shared Device Network (`shared_device_network`)

A high-performance Flutter and Dart package for local UDP device discovery, incremental ACK messaging, paired device authorization, and foreground service background execution.

---

## 🚀 Features

- **📡 Zero-Config UDP Discovery**: Discover devices on the local WiFi/LAN subnet or universal broadcast with a simple stream or single-shot method.
- **🔢 Incremental Message IDs & Reliable ACKs**: Automatically tracks every sent message with an incremental ID, waits for an acknowledgment (ACK), and returns a structured `Status` object.
- **⏱️ Configurable Timeout Handling**: Automatic timeout detection when targets are unreachable or fail to acknowledge within the threshold.
- **🔐 Device Pairing & Authorization**: Secure your server by registering authorized devices (`addDevice`, `removeDevice`) and verifying pair keys.
- **📱 Foreground Service Support**: Integrated with `flutter_foreground_task` to keep the UDP listener active continuously in the background on mobile devices.
- **🌐 Cross-Platform**: Runs natively on Android, iOS, Windows, macOS, and Linux.

---

## 📦 Installation

Add `shared_device_network` to your `pubspec.yaml`:

```yaml
dependencies:
  shared_device_network: ^0.0.1
```

---

## 🛠️ Usage

### 1. Starting a Network Server

```dart
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  final server = SharedDeviceNetworkServer(
    deviceId: 'server-pos-001',
    deviceName: 'Kitchen POS Master',
    deviceDescription: 'Kitchen order screen terminal',
    port: 8888,
    discoveryPort: 8889,
    requirePairKey: true,
    onDataReceived: (senderDeviceId, message) async {
      print('Received from $senderDeviceId: $message');
      
      // Process the message (e.g. print receipt, save order, etc.)
      return Status.success(
        message: 'Order received and queued for cooking',
        data: {'orderId': 1042, 'estimatedMinutes': 15},
      );
    },
  );

  // Add authorized devices
  await server.addDevice(
    'waiter-tablet-01',
    'Waiter Tablet #1',
    pairKey: 'secret_key_123',
  );

  // Start listening on UDP sockets
  await server.start();
  
  // Or start with Android foreground notification:
  // await server.startWithForegroundService(
  //   notificationTitle: 'POS Server Running',
  //   notificationText: 'Listening for incoming order transmissions...',
  // );
}
```

---

### 2. Discovering Devices & Sending Messages from Client

```dart
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  final client = SharedDeviceNetworkClient(
    deviceId: 'waiter-tablet-01',
    deviceName: 'Waiter Tablet #1',
    defaultTimeout: Duration(seconds: 5),
  );

  // --- Option A: Discover devices on local network ---
  final discoveredDevices = await client.discoverDevicesOnce();
  for (final device in discoveredDevices) {
    print('Found: ${device.deviceName} at ${device.deviceIp}:${device.devicePort}');
  }

  // --- Option B: Listen to real-time discovery stream ---
  client.discoverDevices().listen((device) {
    print('Discovered device in real-time: ${device.deviceName}');
  });

  // --- Sending message to device with incremental ID & ACK ---
  final status = await client.sendToDevice(
    'server-pos-001',
    {'action': 'PLACE_ORDER', 'table': 4, 'items': ['Burger', 'Fries']},
    pairKey: 'secret_key_123',
    timeout: Duration(seconds: 4),
  );

  if (status.isSuccess) {
    print('✅ Message delivered and ACKed: ${status.message}');
    print('Response Data: ${status.data}');
  } else {
    print('❌ Failed (${status.statusCode}): ${status.error} - ${status.message}');
  }
}
```

---

## 📋 Core Classes

### `SharedDevice`
Represents a device discovered or connected across the network:
- `deviceId` (`String`): Unique identifier of the device.
- `deviceName` (`String`): Human-readable device name.
- `deviceDescription` (`String?`): Description or role of the device.
- `deviceIp` (`String`): IP address on the local network.
- `devicePort` (`int`): UDP port number for data communication.
- `metadata` (`Map<String, dynamic>?`): Optional custom metadata.

### `Status`
Response/acknowledgment returned from message dispatches:
- `isSuccess` (`bool`): Whether the operation succeeded.
- `statusCode` (`int`): Code (`200`, `400`, `401`, `404`, `408`, `500`).
- `message` (`String`): Descriptive message.
- `data` (`dynamic`): Payload data returned by the recipient.
- `error` (`String?`): Error identifier (`TIMEOUT`, `UNAUTHORIZED`, `DEVICE_NOT_FOUND`, etc.).

### `SharedDeviceNetworkServer`
- `addDevice(deviceId, deviceName, {deviceDescription, pairKey})`: Registers an authorized client.
- `removeDevice(deviceId)`: Removes an authorized client.
- `start()`: Binds data and discovery UDP sockets.
- `stop()`: Closes sockets and releases ports.
- `startWithForegroundService(...)`: Starts the server with an Android/iOS foreground notification.

### `SharedDeviceNetworkClient`
- `discoverDevices({timeout, discoveryPort})`: Returns a `Stream<SharedDevice>`.
- `discoverDevicesOnce({timeout, discoveryPort})`: Returns `Future<List<SharedDevice>>`.
- `sendToDevice(deviceId, message, {pairKey, timeout, targetDevice, ip, port})`: Sends message with incremental ID and waits for ACK.
- `sendToDeivce(...)`: Alias for `sendToDevice`.
- `sendToAddress(ip, port, message, ...)`: Sends directly to IP and Port.

---

### 3. Running Persistent Server in Background (Even When App is Killed)

To run the server in a dedicated background isolate that continues listening on UDP even if the user closes or kills the app:

```dart
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SharedDeviceForegroundService.init();
  runApp(const MyApp());
}

// Start persistent server in background isolate
Future<void> startBackgroundServer() async {
  final success = await SharedDeviceForegroundService.startBackgroundServer(
    deviceId: 'server-pos-001',
    deviceName: 'Kitchen POS Master',
    deviceDescription: 'Kitchen order screen terminal',
    port: 8888,
    notificationTitle: 'POS Server Active',
    notificationText: 'Listening for device orders in background...',
  );
}

// Receive messages in UI when app is open
void listenToBackgroundServerMessages() {
  SharedDeviceForegroundService.addMessageCallback((data) {
    if (data is Map && data['event'] == 'onDataReceived') {
      print('Received from: ${data['senderDeviceId']}, Message: ${data['message']}');
    }
  });
}
```

---

## 🤖 Android Foreground Service Setup (Keeps Running When App Is Killed)

To enable the foreground service to stay alive even when the app task is swiped away/killed by the user, configure `android:stopWithTask="false"` and add the required permissions in your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Permissions required for UDP and Foreground Service -->
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
        <!-- Notice stopWithTask="false" so Android does not kill the server service when the app is swiped away -->
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

Run automated tests:

```bash
flutter test
```
