import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';
import 'package:shared_device_network_example/bg_service_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SharedDeviceApp());
}

class SharedDeviceApp extends StatelessWidget {
  const SharedDeviceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shared Device Network Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Server instance (native only, not started if web)
  final SharedDeviceNetworkServer _server = SharedDeviceNetworkServer();

  // Client instance (works on Native & Web)
  late final SharedDeviceNetworkClient _client;

  final List<String> _logs = [];

  // Client state: discovered devices
  List<SharedDevice> _discoveredDevices = [];
  bool _isDiscovering = false;
  final Map<String, String> _devicePairKeys = {};

  final int _serverPort = 8080;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _client = SharedDeviceNetworkClient(
      clientId: 'client-app-01',
      clientName: 'Waiter Tablet',
      defaultTimeout: const Duration(seconds: 5),
    );

    // If native platform, setup and start server
    if (!kIsWeb) {
      _initServer();
    } else {
      _log('🌐 Running on Flutter Web (Client mode only)');
    }
  }

  Future<void> _initServer() async {
    _server.onMessageReceived((deviceId, message) async {
      _log('📥 [HTTP Server] Command for "$deviceId": $message');
      return SharedDeviceResponse.success(
        message: 'Processed by $deviceId',
        data: {'echo': message, 'time': DateTime.now().toIso8601String()},
      );
    });

    _server.onBinaryReceived((deviceId, bytes, {required contentType, fileName, requestId}) async {
      _log('📥 [HTTP Server] Binary for "$deviceId" ($contentType, ${bytes.length} bytes, file: $fileName)');
      return SharedDeviceResponse.success(
        message: 'Binary content received (${bytes.length} bytes)',
        data: {'bytesReceived': bytes.length, 'contentType': contentType},
      );
    });

    try {
      await _server.start(port: _serverPort, advertise: true);
      _log('🚀 Server started on :$_serverPort with mDNS (_shared-device._tcp)');

      // Pre-register sample peripherals
      await _server.addDevice(
        'printer-pos-01',
        'Counter Thermal Printer',
        deviceDescription: '80mm ESC/POS High-Speed Receipt Printer',
        capabilities: ['escpos', 'print', 'cut', 'thermal'],
      );
      await _server.addDevice(
        'scanner-qr-01',
        'Fixed Barcode & QR Scanner',
        deviceDescription: 'Omnidirectional 2D presentation scanner',
        pairKey: 'pos123',
        capabilities: ['barcode', 'qrcode', 'scan'],
      );
      _log('✅ Registered 2 sample peripherals on host');
    } catch (e) {
      _log('❌ Server start failed: $e');
    }

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _server.dispose();
    _client.dispose();
    super.dispose();
  }

  void _log(String message) {
    debugPrint(message);
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $message');
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  // --- Server Actions ---

  Future<void> _toggleServer() async {
    if (_server.isRunning) {
      await _server.stop();
      _log('🛑 HTTP Server stopped (mDNS unregistered)');
    } else {
      await _server.start(port: _serverPort, advertise: true);
      _log('🚀 HTTP Server restarted on :$_serverPort (mDNS active)');
    }
    setState(() {});
  }

  Future<void> _addDevice({
    required String id,
    required String name,
    String? description,
    String? pairKey,
    List<String> capabilities = const [],
  }) async {
    try {
      await _server.addDevice(
        id,
        name,
        deviceDescription: description,
        pairKey: pairKey,
        capabilities: capabilities,
      );
      _log('✅ Shared peripheral added: $name ($id)');
      setState(() {});
    } catch (e) {
      _log('❌ Error adding device: $e');
    }
  }

  Future<void> _removeDevice(String deviceId) async {
    await _server.removeDevice(deviceId);
    _log('🗑️ Peripheral removed: $deviceId');
    setState(() {});
  }

  void _showAddDeviceDialog({bool autoFillSample = false}) {
    if (kIsWeb) {
      _showServerWebAlert();
      return;
    }

    final idController = TextEditingController();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final keyController = TextEditingController();
    final capsController = TextEditingController();

    int sampleNum = Random().nextInt(900) + 100;
    void fillRandom() {
      idController.text = 'printer-$sampleNum';
      nameController.text = 'Receipt Printer #$sampleNum';
      descController.text = '80mm Thermal POS Printer';
      keyController.text = '1234';
      capsController.text = 'escpos, cut, thermal';
    }

    if (autoFillSample) fillRandom();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Peripheral Device'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: 'Device ID',
                  hintText: 'e.g. printer-01',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Device Name',
                  hintText: 'e.g. Kitchen Printer',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'e.g. ESC/POS 80mm',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: capsController,
                decoration: const InputDecoration(
                  labelText: 'Capabilities (comma-separated)',
                  hintText: 'e.g. print, cut',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'Pair Key (Optional)',
                  hintText: 'Leave empty for open access',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final id = idController.text.trim();
              final name = nameController.text.trim();
              final desc = descController.text.trim();
              final key = keyController.text.trim();
              final caps = capsController.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();

              if (id.isNotEmpty && name.isNotEmpty) {
                Navigator.pop(ctx);
                await _addDevice(
                  id: id,
                  name: name,
                  description: desc.isNotEmpty ? desc : null,
                  pairKey: key.isNotEmpty ? key : null,
                  capabilities: caps,
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // --- Client Actions ---

  Future<void> _discoverDevices() async {
    setState(() => _isDiscovering = true);
    _log(kIsWeb
        ? '🔍 Scanning local network via HTTP subnet prober...'
        : '🔍 Scanning local network for devices via mDNS...');
    try {
      final devices = await _client.discoverDevicesOnce(
        timeout: const Duration(seconds: 4),
      );
      setState(() {
        _discoveredDevices = devices;
        _isDiscovering = false;
      });
      _log('🔍 Discovered ${devices.length} device(s) on LAN');
    } catch (e) {
      setState(() => _isDiscovering = false);
      _log('❌ Discovery error: $e');
    }
  }

  void _showAddByIpDialog() {
    final hostController = TextEditingController(text: '127.0.0.1');
    final portController = TextEditingController(text: '8080');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Query Devices by Host IP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the host IP/domain and HTTP port. '
              'Ideal for Flutter Web or direct LAN connection.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'Host / IP Address',
                hintText: '192.168.1.100 or localhost',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'HTTP Port',
                hintText: '8080',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final host = hostController.text.trim();
              final port = int.tryParse(portController.text.trim()) ?? 8080;
              Navigator.pop(ctx);
              await _fetchDevicesFromHost(host, port);
            },
            child: const Text('Query'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchDevicesFromHost(String host, int port) async {
    _log('🔌 Querying devices from http://$host:$port/api/v1/devices...');
    try {
      final devices = await _client.getDevicesFromHost(host: host, port: port);
      setState(() {
        for (final dev in devices) {
          if (!_discoveredDevices.any((d) => d.deviceId == dev.deviceId && d.deviceIp == dev.deviceIp)) {
            _discoveredDevices.add(dev);
          }
        }
      });
      _log('✅ Retrieved ${devices.length} device(s) from $host:$port');
    } catch (e) {
      _log('❌ Query failed: $e');
    }
  }

  void _showSetPairKeyDialog(SharedDevice dev) {
    final currentKey = _devicePairKeys[dev.deviceId] ?? '';
    final keyController = TextEditingController(text: currentKey);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pair Key: ${dev.deviceName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set authorization token for this device. Requests without the matching pair key will produce HTTP 401 Unauthorized.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'Pair Key / Token',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          if (currentKey.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _devicePairKeys.remove(dev.deviceId));
                Navigator.pop(ctx);
                _log('🔑 Cleared pair key for ${dev.deviceId}');
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final key = keyController.text.trim();
              setState(() {
                if (key.isNotEmpty) {
                  _devicePairKeys[dev.deviceId] = key;
                } else {
                  _devicePairKeys.remove(dev.deviceId);
                }
              });
              Navigator.pop(ctx);
              _log('🔑 Saved pair key for "${dev.deviceId}"');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCommand(SharedDevice dev) async {
    final key = _devicePairKeys[dev.deviceId];
    _log('📤 Sending POST command to "${dev.deviceName}" (${dev.deviceId}) at ${dev.deviceIp}:${dev.devicePort}...');
    final response = await _client.sendToDevice(
      dev.deviceId,
      {
        'command': 'PRINT_BILL',
        'table': 12,
        'total': 84.50,
      },
      targetDevice: dev,
      pairKey: key,
    );

    if (response.isSuccess) {
      _log('✅ [${response.statusCode}] Success: ${response.message} (id: ${response.requestId})');
    } else {
      _log('❌ [${response.statusCode}] Failed: ${response.message} (error: ${response.error})');
    }
  }

  Future<void> _sendBinary(SharedDevice dev) async {
    final key = _devicePairKeys[dev.deviceId];
    _log('📤 Uploading binary payload (PNG signature) to "${dev.deviceId}" at ${dev.deviceIp}:${dev.devicePort}...');
    final sampleBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01];

    final response = await _client.sendBinaryToDevice(
      dev.deviceId,
      sampleBytes,
      contentType: 'image/png',
      fileName: 'receipt_logo.png',
      targetDevice: dev,
      pairKey: key,
    );

    if (response.isSuccess) {
      _log('✅ [${response.statusCode}] Binary uploaded successfully: ${response.message}');
    } else {
      _log('❌ [${response.statusCode}] Binary upload failed: ${response.message}');
    }
  }

  Future<void> _sendMultipart(SharedDevice dev) async {
    final key = _devicePairKeys[dev.deviceId];
    _log('📤 Uploading multipart file to "${dev.deviceId}" at ${dev.deviceIp}:${dev.devicePort}...');
    final sampleBytes = utf8.encode('ESC/POS Sample File\nHeader: Shared Device Network\n');

    final response = await _client.sendMultipartToDevice(
      dev.deviceId,
      sampleBytes,
      fileName: 'receipt.txt',
      targetDevice: dev,
      pairKey: key,
    );

    if (response.isSuccess) {
      _log('✅ [${response.statusCode}] Multipart uploaded successfully: ${response.message}');
    } else {
      _log('❌ [${response.statusCode}] Multipart upload failed: ${response.message}');
    }
  }

  void _showServerWebAlert() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server Hosting on Web'),
        content: const Text(
          'Web browsers cannot bind listening HTTP sockets to host peripherals. '
          'Host your peripherals on an Android, iOS, Windows, macOS, or Linux device, and discover them here from Web.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = !kIsWeb && _server.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Device Network'),
        actions: [
          if (!kIsWeb)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const BgServiceScreen()),
                );
              },
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Android Bg Service'),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.dns),
              text: kIsWeb ? 'Host (Disabled on Web)' : 'Host Server (${_server.deviceCount})',
            ),
            Tab(
              icon: const Icon(Icons.devices),
              text: 'Client (${_discoveredDevices.length} Devices)',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Platform & Status Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: kIsWeb
                ? Colors.blue.shade50
                : (isRunning ? Colors.green.shade50 : Colors.amber.shade50),
            child: Row(
              children: [
                Icon(
                  kIsWeb
                      ? Icons.web
                      : (isRunning ? Icons.check_circle : Icons.pause_circle_outline),
                  color: kIsWeb
                      ? Colors.blue.shade700
                      : (isRunning ? Colors.green.shade700 : Colors.amber.shade800),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kIsWeb
                        ? 'Flutter Web Client Mode • Scan LAN subnet or enter host IP directly'
                        : (isRunning
                            ? 'Server Active on :$_serverPort • mDNS broadcasting _shared-device._tcp'
                            : 'Server Inactive • Tap start to launch HTTP server and mDNS'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kIsWeb
                          ? Colors.blue.shade900
                          : (isRunning ? Colors.green.shade900 : Colors.amber.shade900),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildHostServerTab(), _buildClientTab()],
            ),
          ),

          // Collapsible Activity Logs
          _buildLogsPanel(),
        ],
      ),
    );
  }

  Widget _buildHostServerTab() {
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'Server Hosting Not Supported on Web',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Web browsers cannot bind listening HTTP sockets or broadcast mDNS records. '
                'Switch to the Client tab to discover and connect to devices on your local network.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final devices = _server.devices;
    final isRunning = _server.isRunning;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Server Info Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Local Host Server',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _toggleServer,
                      icon: Icon(isRunning ? Icons.stop : Icons.play_arrow, size: 18),
                      label: Text(isRunning ? 'Stop Server' : 'Start Server'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Port: $_serverPort • Protocol: ${_server.protocolVersion}'),
                Text('HTTP API: http://0.0.0.0:$_serverPort/api/v1 • Status: ${isRunning ? "Active" : "Stopped"}'),
                Text('mDNS Service: _shared-device._tcp (${isRunning ? "Broadcasting" : "Inactive"})'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Add Device button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Hosted Peripherals (${devices.length})', style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Add random sample peripheral',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => _showAddDeviceDialog(autoFillSample: true),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _showAddDeviceDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Peripheral'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (devices.isEmpty)
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No peripherals registered yet. Tap "Add Peripheral" above.'),
              ),
            ),
          )
        else
          ...devices.map((dev) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(dev.deviceId.contains('scanner') ? Icons.qr_code_scanner : Icons.print),
                  ),
                  title: Text(dev.deviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${dev.deviceId} • ${dev.deviceDescription ?? "No description"}\n'
                    'Capabilities: ${dev.capabilities.join(", ")}${dev.isSecured ? " • Secured (PairKey)" : ""}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeDevice(dev.deviceId),
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildClientTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Discovery Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Discovered Devices', style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _showAddByIpDialog,
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text('Add by IP'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _isDiscovering ? null : _discoverDevices,
                  icon: _isDiscovering
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search, size: 16),
                  label: Text(kIsWeb ? 'Scan LAN' : 'mDNS Scan'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_discoveredDevices.isEmpty)
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  kIsWeb
                      ? 'No devices discovered yet.\nTap "Scan LAN" to probe your local subnet or "Add by IP" for direct connection.'
                      : 'No devices discovered yet.\nTap "mDNS Scan" to scan on LAN or "Add by IP" to query a known host.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          )
        else
          ..._discoveredDevices.map((dev) {
            final key = _devicePairKeys[dev.deviceId];
            final hasKey = key != null && key.isNotEmpty;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          child: Icon(dev.deviceId.contains('scanner')
                              ? Icons.qr_code_scanner
                              : Icons.print),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dev.deviceName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${dev.deviceId} • ${dev.deviceDescription ?? "Peripheral"}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // IP Tag Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lan, size: 12, color: Colors.blue.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${dev.deviceIp}:${dev.devicePort}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (dev.isSecured)
                          Chip(
                            avatar: const Icon(Icons.lock, size: 14),
                            label: Text(
                              hasKey ? 'Secured' : 'Needs Key',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (dev.capabilities.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: dev.capabilities
                            .map((c) => Chip(
                                  label: Text(c, style: const TextStyle(fontSize: 10)),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ))
                            .toList(),
                      ),
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    // Action buttons directly for this device
                    Row(
                      children: [
                        if (dev.isSecured)
                          OutlinedButton.icon(
                            onPressed: () => _showSetPairKeyDialog(dev),
                            icon: const Icon(Icons.key, size: 14),
                            label: const Text('Pair Key', style: TextStyle(fontSize: 12)),
                          ),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: () => _sendBinary(dev),
                          icon: const Icon(Icons.image, size: 14),
                          label: const Text('Binary', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        FilledButton.tonalIcon(
                          onPressed: () => _sendMultipart(dev),
                          icon: const Icon(Icons.upload_file, size: 14),
                          label: const Text('File', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 6),
                        FilledButton.icon(
                          onPressed: () => _sendCommand(dev),
                          icon: const Icon(Icons.send, size: 14),
                          label: const Text('JSON', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildLogsPanel() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Activity Logs', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                if (_logs.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _logs.clear()),
                    child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.blue)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _logs.isEmpty
                ? const Center(child: Text('No activity yet', style: TextStyle(fontSize: 11, color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: _logs.length,
                    itemBuilder: (ctx, i) => Text(
                      _logs[i],
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
