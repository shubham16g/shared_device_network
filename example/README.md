# Printer Hub: `shared_device_network` example

One Android phone shares its Bluetooth printers with the Wi-Fi. Every other phone
on the same Wi-Fi finds them automatically and prints on them.

| Tab | What it does |
|---|---|
| **Share** | Turn the hub on or off and pick paired Bluetooth printers. The hub runs in a background service, so it keeps sharing with the screen off or the app closed. |
| **Print** | Find shared printers on the Wi-Fi (mDNS) and send a job as JSON, raw ESC/POS bytes, or a file. |
| **Activity** | Every job sent and received. |

## Where the code is

- [`lib/printer_hub.dart`](lib/printer_hub.dart): the hub. A `SharedDeviceNetworkServer` running in an
  Android foreground service (`flutter_foreground_task`) that writes each job to the printer over
  Bluetooth Classic (`flutter_classic_bluetooth`).
- [`lib/main.dart`](lib/main.dart): the app. Starts and stops the hub, and uses
  `SharedDeviceNetworkClient` to discover printers and send jobs.
- `lib/pages/`: the screens only.

## Run it

1. Pair the Bluetooth printer in Android settings.
2. `flutter run` on the hub phone, open **Share**, add the printer, and turn sharing on.
3. Run the app on any other phone on the same Wi-Fi, open **Print**, tap **Scan**, and send a job.

Hosting needs Android (a foreground service with type `connectedDevice`). The Print tab also works on
iOS and desktop.
