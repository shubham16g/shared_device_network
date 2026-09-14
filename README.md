# Shared Device Network (`shared_device_network`)

A powerful Flutter and Dart package for local **mDNS / DNS-SD discovery**, **HTTP (REST + Binary/Multipart) communication**, peripheral sharing, and device pairing across **Android, iOS, macOS, Windows, Linux**, and **Flutter Web**.

---

## 💡 Architecture Overview

`shared_device_network` provides seamless device discovery and communication across the local area network:

- **Device-Centric Discovery (mDNS + REST)**: Clients discover available **devices** across the LAN. In the background, host servers are detected via mDNS (`_shared-device._tcp`), and each peripheral is automatically tagged with its hosting IP address and port (`deviceIp`, `devicePort`).
- **Transparent Host Servers**: The host server acts as a lightweight network host for connected hardware without requiring `serverId` or `serverName` configuration or publishing server identities to clients.
- **Communication (HTTP/1.1 REST + Binary)**: All application requests, peripheral commands, and file transfers operate over versioned HTTP (`/api/v1/...`).
- **Flutter Web Client Support**: Flutter Web compiles and functions as a full-featured HTTP client. Web clients connect directly to hosts by IP and port (`client.getDevicesFromHost`) with full CORS support.

```
                      Local WiFi / LAN
                             │
            ┌────────────────┴────────────────┐
            │                                 │
     Native Host A                     Native Host B
  Android/iOS/Desktop               Android/iOS/Desktop
   (dart:io HttpServer)              (dart:io HttpServer)
     [Printer, Scanner]               [Display, Scale]
            │                                 │
      HTTP REST API                     HTTP REST API
            │                                 │
            └────────────────┬────────────────┘
                             │
                       mDNS / DNS-SD
                   (_shared-device._tcp)
                             │
            ┌────────────────┴────────────────┐
            │                                 │
       Flutter App                       Flutter Web
      Native Client                     Browser Client
  (mDNS Scan -> Devices)             (Query by IP -> Devices)
```

---

## 🚀 Key Features

- **📡 Zero-Conf mDNS Device Discovery**: Discovers devices across the LAN with automatic IP and port tagging (`deviceIp:devicePort`).
- **🌐 HTTP REST Application Transport**: Replaces raw UDP datagrams with clean HTTP endpoints (`/api/v1/info`, `/api/v1/devices`, `/command`, `/content`).
- **💻 Flutter Web Support**: Compiles for Web as an HTTP client. Communicates with native hosts with full CORS support.
- **📦 Binary & File Uploads**: Native support for images, PDFs, ESC/POS byte arrays, and multipart forms without base64 JSON bloat.
- **🔁 Request IDs & Idempotency**: Automatic `requestId` generation and server-side response caching to prevent duplicate execution of critical commands (e.g. receipt printing, cash drawer triggering).
- **🔐 Pair Key Authentication**: Secure device authorization via `Authorization: Bearer <pairKey>` or `X-Pair-Key`. Secrets are never logged or broadcast over mDNS.
- **📱 Android Foreground Service**: Built-in support for continuous background server operation on Android.
- **🛡️ Configurable CORS**: Configurable cross-origin policies for serving browser clients.
- **🔒 TLS / HTTPS Ready**: Pass a `SecurityContext` for encrypted communications where required.

---

## 📦 Installation

Add `shared_device_network` to your `pubspec.yaml`:

```yaml
dependencies:
  shared_device_network: ^0.1.0
```

Then run:

```bash
flutter pub get
```

---

## 📱 Platform Configuration

### Android

Add local network, multicast, and foreground service permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
</manifest>
```

### iOS / macOS

Add the local network usage description and Bonjour service type to `ios/Runner/Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Shared Device Network requires local network access to discover and communicate with POS hardware.</string>
<key>NSBonjourServices</key>
<array>
    <string>_shared-device._tcp</string>
</array>
```

---

## 🛠️ Usage Guide

### 1. Running a Host Server (Native)

Instantiate `SharedDeviceNetworkServer`, register command and binary callbacks, start the server, and register peripherals:

```dart
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  // 1. Create server instance
  final server = SharedDeviceNetworkServer();

  // 2. Handle incoming JSON commands
  server.onMessageReceived((deviceId, message) async {
    print('Command for $deviceId: $message');

    if (deviceId == 'printer-01') {
      // Forward print bytes to physical ESC/POS printer...
      return SharedDeviceResponse.success(
        message: 'Receipt printed successfully',
        data: {'printedAt': DateTime.now().toIso8601String()},
      );
    }

    return SharedDeviceResponse.deviceNotFound();
  });

  // 3. Handle incoming binary/file uploads (e.g. logos, receipts)
  server.onBinaryReceived((deviceId, bytes, {required contentType, fileName, requestId}) async {
    print('Received $contentType (${bytes.length} bytes) for $deviceId');
    return SharedDeviceResponse.success(
      message: 'Binary content received',
      data: {'bytes': bytes.length},
    );
  });

  // 4. Start HTTP server and mDNS broadcast
  await server.start(port: 8080);

  // 5. Register shared peripherals
  await server.addDevice(
    'printer-01',
    'Kitchen Thermal Printer',
    deviceDescription: '80mm ESC/POS Printer',
    pairKey: 'secret-1234', // Optional authentication
    capabilities: ['escpos', 'thermal', 'cut'],
  );
}
```

---

### 2. Client Mode: Device Discovery & Direct Connection

#### A. Native Client (Device Discovery)

```dart
final client = SharedDeviceNetworkClient();

// Discover devices advertising across the LAN
final devices = await client.discoverDevicesOnce(
  timeout: const Duration(seconds: 3),
);

for (final dev in devices) {
  print('Found ${dev.deviceName} (${dev.deviceId}) at ${dev.deviceIp}:${dev.devicePort}');
}

// Send command to peripheral directly (resolves address automatically)
final response = await client.sendToDevice(
  'printer-01',
  {'command': 'PRINT_BILL', 'table': 4, 'total': 45.50},
  pairKey: 'secret-1234',
);

print('Result: ${response.message} [Status: ${response.statusCode}]');
```

#### B. Flutter Web Client (Direct Connection)

Web browsers cannot perform raw mDNS multicast scans or host servers. Instead, query devices directly by host IP and port:

```dart
final client = SharedDeviceNetworkClient();

// Query devices from a known host IP on the LAN
final devices = await client.getDevicesFromHost(
  host: '192.168.1.100',
  port: 8080,
);

for (final dev in devices) {
  print('Device: ${dev.deviceName} at ${dev.deviceIp}:${dev.devicePort}');
}

// Send command to peripheral identical to native
final response = await client.sendToDevice('printer-01', {'command': 'PRINT'});
```

---

### 3. Binary & File Uploads

Send images, PDFs, or raw ESC/POS byte buffers directly over HTTP without base64 overhead:

```dart
// 1. Raw byte buffer (e.g. image/png or application/octet-stream)
final pngBytes = await File('receipt_logo.png').readAsBytes();

final response = await client.sendBinaryToDevice(
  'printer-01',
  pngBytes,
  contentType: 'image/png',
  fileName: 'logo.png',
  pairKey: 'secret-1234',
);

// 2. Multipart form upload
final multiResponse = await client.sendMultipartToDevice(
  'printer-01',
  pngBytes,
  fileName: 'logo.png',
  pairKey: 'secret-1234',
);
```

---

### 4. Idempotency & Duplicate Protection

Every client request carries a unique `requestId`. The server tracks in-flight and recently executed requests:
- **Duplicate in-flight request**: Server returns `HTTP 409 Conflict`.
- **Retried completed request**: Server returns the cached `SharedDeviceResponse` immediately without re-executing peripheral actions (preventing double prints or accidental charges).

---

### 5. CORS (Cross-Origin Resource Sharing)

The server provides a configurable CORS policy to safely support browser-based clients:

```dart
final server = SharedDeviceNetworkServer(
  corsPolicy: CorsPolicy(
    allowedOrigins: ['http://localhost:3000', 'https://pos.mycompany.com'],
    allowCredentials: true,
  ),
);
```

---

## 🔒 Security Considerations

- **Pair Keys**: Credentials are sent via `Authorization: Bearer <key>` headers. They are **never** published in mDNS TXT records and are stripped from public `GET /devices` responses.
- **Request Limits**: Configurable body size limits (`maxBodySizeBytes`, default 50MB) protect against out-of-memory and denial-of-service attacks.
- **HTTP vs. HTTPS**: While plain HTTP is standard for isolated LAN setups, production environments can provide a `SecurityContext` to enable TLS encryption on the server.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
