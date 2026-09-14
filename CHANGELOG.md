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

## 0.0.1

* Initial release of `shared_device_network`.
* `SharedDeviceNetworkServer`: Host local hardware and peripherals across WiFi/LAN.
* `SharedDeviceNetworkClient`: Automated UDP discovery, peripheral lookup, and reliable direct messaging.
* Reliable UDP messaging with incremental message IDs and structured `SharedDeviceResponse` acknowledgments.
* Per-device pairing security with `pairKey` authorization.
* Complete example application demonstrating foreground server hosting, background service execution, and client device discovery.
