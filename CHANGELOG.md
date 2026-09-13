## 0.0.1

* Initial release of `shared_device_network`.
* `SharedDeviceNetworkServer`: Host local hardware and peripherals (thermal printers, barcode scanners, digital scales, cash drawers) across WiFi/LAN.
* `SharedDeviceNetworkClient`: Automated UDP discovery, peripheral lookup, and reliable direct messaging.
* Reliable UDP messaging with incremental message IDs and structured `SharedDeviceResponse` acknowledgments.
* Per-device pairing security with `pairKey` authorization.
* Complete example application demonstrating foreground server hosting, background service execution, and client device discovery.
