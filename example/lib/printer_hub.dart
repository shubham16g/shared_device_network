// The printer hub: runs in an Android foreground service, in its own isolate,
// so the printers stay shared with the screen off or the app closed.
//
// It hosts a SharedDeviceNetworkServer with one shared device per Bluetooth
// printer, and turns every job it receives into bytes on the printer.
import 'dart:convert';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_device_network/shared_device_network.dart';

import 'escpos.dart';

/// A paired Bluetooth printer that the hub shares.
///
/// The list is saved with the foreground task's data store, which both the app
/// and the background isolate can read.
class SharedPrinter {
  const SharedPrinter({required this.name, required this.address});

  final String name;

  /// Bluetooth MAC address. Stays on this phone; clients only see [id] and [name].
  final String address;

  String get id => 'bt-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';

  static Future<List<SharedPrinter>> load() async {
    final raw = await FlutterForegroundTask.getData<String>(key: 'printers');
    if (raw == null) return [];
    return [
      for (final m in json.decode(raw) as List)
        SharedPrinter(name: m['name'] as String, address: m['address'] as String),
    ];
  }

  static Future<void> save(List<SharedPrinter> printers) => FlutterForegroundTask.saveData(
        key: 'printers',
        value: json.encode([
          for (final p in printers) {'name': p.name, 'address': p.address},
        ]),
      );
}

/// Entry point of the background isolate. Must be a top-level function.
@pragma('vm:entry-point')
void startPrinterHub() => FlutterForegroundTask.setTaskHandler(PrinterHub());

class PrinterHub extends TaskHandler {
  static const port = 8080;

  final _server = SharedDeviceNetworkServer();
  final _bluetooth = FlutterClassicBluetooth();
  final Map<String, SharedPrinter> _printers = {}; // shared deviceId -> printer
  final Map<String, BtcConnection> _links = {}; // shared deviceId -> open Bluetooth link
  String _address = '';
  int _printed = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // JSON jobs (client.sendToDevice) become a text receipt.
    _server.onMessageReceived((deviceId, job) => _print(deviceId, escPosReceipt(job)));

    // Raw bytes and file uploads (sendBinaryToDevice / sendMultipartToDevice) go
    // straight to the printer, so only ESC/POS or plain text makes sense.
    _server.onBinaryReceived((deviceId, bytes, {required contentType, fileName, requestId}) {
      if (!contentType.startsWith('text/') && contentType != 'application/octet-stream') {
        return SharedDeviceResponse.error(
          'UNSUPPORTED_MEDIA_TYPE',
          statusCode: 415,
          message: 'Printers take ESC/POS bytes or text, not $contentType',
        );
      }
      return _print(deviceId, bytes);
    });

    await _syncPrinters();
    try {
      await _server.start(port: port); // HTTP server + mDNS advertisement
    } catch (e) {
      _log('Could not start on port $port: $e', 'error');
      await FlutterForegroundTask.stopService();
      return;
    }
    _address = '${await NetworkUtils.getPrimaryLocalIPv4()}:$port';
    _log('Sharing on http://$_address', 'info');
    _report();
  }

  /// Makes the server's devices match the saved printer list.
  Future<void> _syncPrinters() async {
    final saved = {for (final p in await SharedPrinter.load()) p.id: p};
    for (final id in _printers.keys.where((id) => !saved.containsKey(id)).toList()) {
      await _server.removeDevice(id);
      _printers.remove(id);
      await _disconnect(id);
    }
    for (final p in saved.values.where((p) => !_printers.containsKey(p.id))) {
      await _server.addDevice(
        p.id,
        p.name,
        deviceDescription: 'Bluetooth printer',
        capabilities: const ['escpos', 'print'],
      );
      _printers[p.id] = p;
    }
  }

  /// Prints one job. The server runs jobs for one printer one at a time,
  /// so receipts from different phones never mix on the paper.
  Future<SharedDeviceResponse> _print(String deviceId, List<int> bytes) async {
    final printer = _printers[deviceId]!; // the server only routes known devices
    _log('Job for ${printer.name} (${bytes.length} bytes)', 'received');
    try {
      try {
        await _write(deviceId, printer, bytes);
      } on Exception {
        // The printer dropped the link (went to sleep, was switched off): reconnect once.
        await _disconnect(deviceId);
        await _write(deviceId, printer, bytes);
      }
      _printed++;
      _log('Printed on ${printer.name}', 'success');
      return SharedDeviceResponse.success(message: 'Printed');
    } on Exception catch (e) {
      await _disconnect(deviceId);
      _log('${printer.name}: $e', 'error');
      return SharedDeviceResponse.error('$e', message: '${printer.name} is off or out of range');
    } finally {
      _report();
    }
  }

  /// Connects on the first job and keeps the link open for the next ones.
  Future<void> _write(String deviceId, SharedPrinter printer, List<int> bytes) async {
    var link = _links[deviceId];
    if (link == null || !link.isConnected) {
      link = await _bluetooth.connect(
        address: printer.address,
        timeout: const Duration(seconds: 15), // a sleeping printer can take ~5 s
      );
      _links[deviceId] = link;
    }
    await link.output.writeBytes(bytes);
  }

  Future<void> _disconnect(String deviceId) async {
    final link = _links.remove(deviceId);
    if (link == null) return;
    try {
      await link.close();
    } catch (_) {} // already gone
    link.dispose();
  }

  /// Tells the app (if open) and the notification what the hub is doing.
  void _report() {
    FlutterForegroundTask.sendDataToMain({
      'type': 'status',
      'address': _address,
      'printed': _printed,
      'connected': [
        for (final e in _links.entries)
          if (e.value.isConnected) e.key,
      ],
    });
    final n = _printers.length;
    FlutterForegroundTask.updateService(
      notificationTitle: 'Sharing $n printer${n == 1 ? '' : 's'} on Wi-Fi',
      notificationText: 'http://$_address · $_printed printed',
      notificationButtons: const [NotificationButton(id: 'stop', text: 'Stop sharing')],
    );
  }

  void _log(String message, String kind) =>
      FlutterForegroundTask.sendDataToMain({'type': 'log', 'kind': kind, 'message': message});

  /// Messages from the app: 'sync' after the printer list changed, 'status' to refresh.
  @override
  void onReceiveData(Object data) async {
    if (data == 'sync') await _syncPrinters();
    _report();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp('/');

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    for (final id in _links.keys.toList()) {
      await _disconnect(id);
    }
    await _server.dispose();
    FlutterForegroundTask.sendDataToMain({'type': 'stopped'});
  }
}
