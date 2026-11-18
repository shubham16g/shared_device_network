// Printer Hub: shared_device_network example.
//
// One phone shares its Bluetooth printers on the Wi-Fi; every other phone prints on them.
//   Share    : turn the hub on/off and pick printers. The hub itself runs in a
//              background service, see printer_hub.dart (all the server code).
//   Print    : find shared printers on the Wi-Fi and send them jobs (the client code below).
//   Activity : everything that happened.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_device_network/shared_device_network.dart';

import 'escpos.dart';
import 'pages/activity_page.dart';
import 'pages/print_page.dart';
import 'pages/share_page.dart';
import 'printer_hub.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort(); // app <-> background hub messages
  runApp(const DemoApp());
}

class AppController extends ChangeNotifier {
  // ── Hub: shares this phone's printers. Runs in printer_hub.dart. ────────────

  /// The hub needs an Android foreground service. Other platforms can still print.
  bool get canHost => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool hubRunning = false;
  bool hubBusy = false;
  String hubAddress = '';
  int printed = 0;
  Set<String> connectedPrinters = {};
  List<SharedPrinter> printers = [];

  Future<void> init() async {
    if (!canHost) return;
    FlutterForegroundTask.addTaskDataCallback(_onHubMessage);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'printer_hub',
        channelName: 'Printer hub',
        channelDescription: 'Shown while printers are shared on Wi-Fi',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true, // if sharing was on, it comes back after a reboot
        allowWakeLock: true, // keep the CPU awake for incoming jobs
        allowWifiLock: true, // keep Wi-Fi awake with the screen off
      ),
    );
    try {
      printers = await SharedPrinter.load();
      hubRunning = await FlutterForegroundTask.isRunningService;
      if (hubRunning) FlutterForegroundTask.sendDataToTask('status');
    } catch (e) {
      log('Hub unavailable: $e', ActivityKind.error);
    }
    notifyListeners();
  }

  Future<void> setSharing(bool on) async {
    hubBusy = true;
    notifyListeners();
    try {
      if (on) {
        await _askPermissions();
        final result = await FlutterForegroundTask.startService(
          serviceId: PrinterHub.port,
          serviceTypes: [ForegroundServiceTypes.connectedDevice],
          notificationTitle: 'Printer hub',
          notificationText: 'Starting…',
          notificationButtons: const [NotificationButton(id: 'stop', text: 'Stop sharing')],
          notificationInitialRoute: '/',
          callback: startPrinterHub,
        );
        hubRunning = result is ServiceRequestSuccess;
        if (result is ServiceRequestFailure) {
          log('Could not start the hub: ${result.error}', ActivityKind.error);
        }
      } else {
        await FlutterForegroundTask.stopService();
        _hubStopped();
      }
    } on Exception catch (e) {
      log('$e', ActivityKind.error);
    }
    hubBusy = false;
    notifyListeners();
  }

  Future<void> _askPermissions() async {
    await _askBluetoothPermission();
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission(); // shows "Sharing printers"
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization(); // so Android won't kill the hub
    }
  }

  Future<void> _askBluetoothPermission() async {
    // Scan too: connecting cancels any running discovery, which needs BLUETOOTH_SCAN.
    // Both are the single "Nearby devices" permission on Android 12+.
    final status = await FlutterClassicBluetooth().requestPermissions(
      permissions: {BtcPermission.scan, BtcPermission.connect},
    );
    if (status != BtcPermissionStatus.granted) {
      throw Exception('Allow "Nearby devices" so the hub can reach the printer');
    }
  }

  /// Paired devices, serial (SPP) ones first: that is how Bluetooth Classic printers talk.
  Future<List<BtcDevice>> pairedDevices() async {
    await _askBluetoothPermission();
    bool spp(BtcDevice d) => d.uuids.any((u) => u.toLowerCase().startsWith('00001101'));
    return [
      for (final d in await FlutterClassicBluetooth().getPairedDevices())
        if (!printers.any((p) => p.address == d.address)) d,
    ]..sort((a, b) => (spp(b) ? 1 : 0) - (spp(a) ? 1 : 0));
  }

  Future<void> addPrinter(BtcDevice device) async {
    final printer = SharedPrinter(name: device.name ?? device.address, address: device.address);
    printers = [...printers, printer];
    log('Added ${printer.name}', ActivityKind.info);
    await _savePrinters();
  }

  Future<void> removePrinter(SharedPrinter printer) async {
    printers = printers.where((p) => p.address != printer.address).toList();
    log('Removed ${printer.name}', ActivityKind.info);
    await _savePrinters();
  }

  Future<void> _savePrinters() async {
    await SharedPrinter.save(printers);
    if (hubRunning) FlutterForegroundTask.sendDataToTask('sync'); // hub updates its devices
    notifyListeners();
  }

  void _onHubMessage(Object data) {
    if (data is! Map) return;
    switch (data['type']) {
      case 'status':
        hubRunning = true;
        hubAddress = data['address'] as String? ?? '';
        printed = data['printed'] as int? ?? 0;
        connectedPrinters = {...(data['connected'] as List? ?? const []).cast<String>()};
      case 'log':
        log('Hub: ${data['message']}', ActivityKind.values.byName(data['kind'] as String));
      case 'stopped':
        _hubStopped();
    }
    notifyListeners();
  }

  void _hubStopped() {
    hubRunning = false;
    hubAddress = '';
    connectedPrinters = {};
  }

  // ── Client: print on printers that any phone on the Wi-Fi shares ────────────

  final client = SharedDeviceNetworkClient(clientName: 'Printer Hub example');
  List<SharedDevice> devices = [];
  bool scanning = false;

  /// Pair keys the user typed, per device (for hosts that protect their devices).
  final Map<String, String> pairKeys = {};

  /// Finds every hub on the Wi-Fi via mDNS and lists the printers each one shares.
  Future<void> scan() async {
    scanning = true;
    notifyListeners();
    try {
      devices = await client.discoverDevicesOnce();
      log('Found ${devices.length} printer(s) on the Wi-Fi', ActivityKind.info);
    } catch (e) {
      log('Scan failed: $e', ActivityKind.error);
    }
    scanning = false;
    notifyListeners();
  }

  /// Lists a known hub's printers without mDNS (e.g. another subnet).
  Future<void> connect(String host, int port) async {
    try {
      final found = await client.getDevicesFromHost(host: host, port: port);
      devices = [
        ...devices.where((d) => d.deviceIp != host || d.devicePort != port),
        ...found,
      ];
      log('$host:$port shares ${found.length} printer(s)', ActivityKind.info);
    } catch (e) {
      log('Could not reach $host:$port', ActivityKind.error);
    }
    notifyListeners();
  }

  /// Sends [text] to [device] in one of the three ways the client supports.
  Future<SharedDeviceResponse> send(SharedDevice device, SendMode mode, String text) async {
    final key = pairKeys[device.deviceId];
    log('Sending ${mode.label} to ${device.deviceName}', ActivityKind.sent);
    final Future<SharedDeviceResponse> request = switch (mode) {
      SendMode.json => client.sendToDevice(
          device.deviceId,
          {'text': text},
          targetDevice: device,
          pairKey: key,
        ),
      SendMode.bytes => client.sendBinaryToDevice(
          device.deviceId,
          escPosReceipt({'text': text}),
          targetDevice: device,
          pairKey: key,
        ),
      SendMode.file => client.sendMultipartToDevice(
          device.deviceId,
          utf8.encode('$text\n\n\n\n'),
          fileName: 'receipt.txt',
          targetDevice: device,
          pairKey: key,
        ),
    };
    final response = await request;
    log(
      response.isSuccess
          ? '${device.deviceName}: ${response.message}'
          : '${device.deviceName} failed (${response.statusCode}): ${response.message}',
      response.isSuccess ? ActivityKind.success : ActivityKind.error,
    );
    return response;
  }

  // ── Activity feed ────────────────────────────────────────────────────────

  final List<Activity> activity = [];

  void log(String message, ActivityKind kind) {
    debugPrint(message);
    activity.insert(0, Activity(DateTime.now(), message, kind));
    if (activity.length > 200) activity.removeLast();
    notifyListeners();
  }

  void clearActivity() {
    activity.clear();
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners(); // late network callbacks after close
  }

  @override
  void dispose() {
    _disposed = true;
    if (canHost) FlutterForegroundTask.removeTaskDataCallback(_onHubMessage);
    client.dispose(); // the hub keeps running: it lives in its own service
    super.dispose();
  }
}

/// The three ways [SharedDeviceNetworkClient] can send to a device.
enum SendMode {
  json('JSON', Icons.data_object, 'client.sendToDevice()'),
  bytes('Bytes', Icons.memory, 'client.sendBinaryToDevice()'),
  file('File', Icons.attach_file, 'client.sendMultipartToDevice()');

  const SendMode(this.label, this.icon, this.method);
  final String label;
  final IconData icon;
  final String method;
}

enum ActivityKind { info, sent, received, success, error }

class Activity {
  Activity(this.time, this.message, this.kind);
  final DateTime time;
  final String message;
  final ActivityKind kind;
}

// ── App shell ──────────────────────────────────────────────────────────────

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  final app = AppController();
  var tab = 0;

  @override
  void initState() {
    super.initState();
    app.init();
  }

  @override
  void dispose() {
    app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Printer Hub',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          body: IndexedStack(
            index: tab,
            children: [SharePage(app: app), PrintPage(app: app), ActivityPage(app: app)],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.wifi_tethering), label: 'Share'),
              NavigationDestination(
                icon: Icon(Icons.print_outlined),
                selectedIcon: Icon(Icons.print),
                label: 'Print',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Activity',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00796B), brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
