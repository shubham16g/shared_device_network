## 0.1.0

* **Major Architecture Redesign**:
  - Replaced UDP datagram transport with HTTP/1.1 REST (`dart:io` `HttpServer` on native, `package:http` on clients).
  - Replaced UDP broadcast discovery with Zero-configuration mDNS / DNS-SD (`_shared-device._tcp` via `bonsoir`).
  - Separated Server discovery (`SharedDeviceServer`) from Peripheral discovery (`SharedDevice`).
  - Added full support for Flutter Web as an HTTP client.
  - Added binary and multipart file upload support (`sendBinaryToDevice`, `sendMultipartToDevice`) without base64 JSON encoding.
  - Added request ID tracking and server-side idempotency caching (`IdempotencyManager`) to prevent duplicate command executions.
  - Added configurable CORS policies (`CorsPolicy`) for browser clients.
  - Added TLS/HTTPS support via `SecurityContext`.
  - Modernized example application with host, client, and Android background service modes.
* **Fixes found testing on real devices (Pixel 7 host, Mi A3 client, Bluetooth printer)**:
  - `GET /devices` and `GET /devices/:id` now report the address the client reached the host on, instead of the unusable bind address `0.0.0.0`.
  - Commands/uploads for the same device are serialized on the host, so concurrent print jobs no longer interleave.
  - Idempotency no longer caches failed responses; a retry with the same `requestId` runs again.
  - Multipart uploads pass the file part's own content type (not `multipart/form-data`) and ignore non-file form fields.
  - Clients rediscover once and retry (same `requestId`) when a cached host is unreachable; connection failures are now `503` instead of `500`.
  - Client `defaultTimeout` raised from 8s to 20s so slow peripherals (Bluetooth connect + print) are not reported as failed.
  - `stop()` closes the HTTP server before mDNS teardown, so the port is freed even if mDNS hangs.
  - Unhandled errors from client disconnects while responding are suppressed.
  - Exported `NetworkUtils` (local IPv4 lookup); removed unused `MessageIdGenerator`.
  - **Breaking:** removed no-op UDP-era parameters: `start(discoveryPort:, discoverPort:)`, `server.discoveryPort`, and the client's `discoveryPort`, `defaultServerPort`, `clientPort`. mDNS always uses port 5353.
  - `NetworkUtils` prefers Wi-Fi/Ethernet interfaces, so a phone with mobile data on no longer reports its carrier IP as the LAN address.
  - Example rewritten as **Printer Hub**: shares Bluetooth Classic (SPP) printers from an Android foreground service (`flutter_foreground_task`, `connectedDevice`, Wi-Fi lock, restart on boot) using `flutter_classic_bluetooth`, plus Print and Activity tabs. Android build fix (`kotlin.incremental=false` when the pub cache and project are on different drives).

## 0.0.1

* Initial release of `shared_device_network`.
* `SharedDeviceNetworkServer`: Host local hardware and peripherals across WiFi/LAN.
* `SharedDeviceNetworkClient`: Automated UDP discovery, peripheral lookup, and reliable direct messaging.
* Reliable UDP messaging with incremental message IDs and structured `SharedDeviceResponse` acknowledgments.
* Per-device pairing security with `pairKey` authorization.
* Complete example application demonstrating foreground server hosting, background service execution, and client device discovery.
