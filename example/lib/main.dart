import 'dart:math';
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
  late final SharedDeviceNetworkClient _client;

  final SharedDeviceNetworkServer server = SharedDeviceNetworkServer();

  final List<String> _logs = [];
  List<SharedDevice> _discoveredDevices = [];
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    server.onMessageReceived((deviceId, message) async {
      _log('📥 Host received for "$deviceId": $message');
      return SharedDeviceResponse.success(
        message: 'Processed by $deviceId',
        data: {'echo': message, 'time': DateTime.now().toIso8601String()},
      );
    });
    server.start(port: 8888, discoveryPort: 8889);

    // 3. Initialize client for testing discovery and dispatch
    _client = SharedDeviceNetworkClient(
      deviceId: 'client-app-01',
      deviceName: 'Waiter Tablet',
      discoveryPort: 8889,
      defaultTimeout: const Duration(seconds: 3),
    );
  }

  void _log(String text) {
    if (!mounted) return;
    final time = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _logs.insert(0, '[$time] $text');
      if (_logs.length > 50) _logs.removeLast();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _client.dispose();
    server.dispose();
    super.dispose();
  }

  // --- Server Actions ---

  int _sampleCounter = 1;

  Future<void> _addDevice({
    required String id,
    required String name,
    String? description,
    String? pairKey,
  }) async {
    await server.addDevice(
      id,
      name,
      deviceDescription: description,
      pairKey: pairKey,
    );

    _log('✅ Shared device added: $name ($id)');
    setState(() {});
  }

  Future<void> _removeDevice(String deviceId) async {
    await server.removeDevice(deviceId);

    _log('🗑️ Removed device: $deviceId');
    setState(() {});
  }

  void _showAddDeviceDialog({bool autoFillSample = false}) {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final keyController = TextEditingController();

    final samples = [
      {
        'id': 'printer-bt',
        'name': 'Kitchen ESC/POS Printer',
        'desc': 'Bluetooth 80mm Thermal Receipt Printer',
        'key': '1234',
      },
      {
        'id': 'scanner-usb',
        'name': 'Counter 2D Barcode Scanner',
        'desc': 'USB Handheld QR / Barcode Scanner',
        'key': 'pass456',
      },
      {
        'id': 'drawer-pos',
        'name': 'Automated Cash Drawer',
        'desc': 'RJ11 24V Heavy Duty Cash Drawer',
        'key': '',
      },
      {
        'id': 'scale-deli',
        'name': 'Deli Digital Weighing Scale',
        'desc': 'Serial RS232 Accurate Weight Scale',
        'key': '7788',
      },
      {
        'id': 'screen-cust',
        'name': 'Secondary Customer Display',
        'desc': 'HDMI Pole Display 2x20 Lines',
        'key': '',
      },
    ];

    void fillRandom() {
      final sample = samples[Random().nextInt(samples.length)];
      final num = _sampleCounter++;
      idController.text = '${sample['id']}-$num';
      nameController.text = '${sample['name']} #$num';
      descController.text = sample['desc']!;
      keyController.text = sample['key']!;
    }

    if (autoFillSample) {
      fillRandom();
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Add Device',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton.filledTonal(
                tooltip: 'Randomly fill form',
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  fillRandom();
                  setDialogState(() {});
                },
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: idController,
                  decoration: const InputDecoration(
                    labelText: 'Device ID',
                    hintText: 'e.g. printer-bt-01',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Device Name',
                    hintText: 'e.g. Kitchen Printer',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'e.g. Thermal 80mm ESC/POS',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  decoration: const InputDecoration(
                    labelText: 'Pair Key (Optional)',
                    hintText: 'Password for this device',
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
            FilledButton.icon(
              onPressed: () async {
                final id = idController.text.trim();
                final name = nameController.text.trim();
                final desc = descController.text.trim();
                final key = keyController.text.trim();
                if (id.isNotEmpty && name.isNotEmpty) {
                  Navigator.pop(ctx);
                  await _addDevice(
                    id: id,
                    name: name,
                    description: desc.isNotEmpty ? desc : null,
                    pairKey: key.isNotEmpty ? key : null,
                  );
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Device'),
            ),
          ],
        ),
      ),
    );
  }

  // --- Client Actions ---

  Future<void> _discoverDevices() async {
    setState(() => _isDiscovering = true);
    _log('🔍 Client broadcasting discovery request...');
    try {
      final found = await _client.discoverDevicesOnce(
        timeout: const Duration(seconds: 2),
      );
      setState(() {
        _discoveredDevices = found;
        _isDiscovering = false;
      });
      _log('🔍 Found ${found.length} shared device(s) on LAN');
    } catch (e) {
      setState(() => _isDiscovering = false);
      _log('❌ Discovery error: $e');
    }
  }

  Future<void> _sendMessage(SharedDevice dev) async {
    _log('📤 Client sending to "${dev.deviceName}" (${dev.deviceId})...');
    final status = await _client.sendToDevice(dev.deviceId, {
      'action': 'PRINT_TEST',
      'item': 'Coffee x2',
      'total': 9.50,
    }, targetDevice: dev);
    if (status.isSuccess) {
      _log('✅ ACK from ${dev.deviceId}: ${status.message}');
    } else {
      _log('❌ Failed [${status.statusCode}]: ${status.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = server.isRunning;
    final deviceCount = server.deviceCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Device Network'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => BgServiceScreen()),
              );
            },
            child: Text('Run as Background Service'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.router),
              text: 'Host Server ($deviceCount)',
            ),
            Tab(
              icon: const Icon(Icons.devices),
              text: 'Client (${_discoveredDevices.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Status banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: isRunning ? Colors.green.shade50 : Colors.amber.shade50,
            child: Row(
              children: [
                Icon(
                  isRunning ? Icons.check_circle : Icons.pause_circle_outline,
                  color: isRunning
                      ? Colors.green.shade700
                      : Colors.amber.shade800,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isRunning
                        ? 'Server Active • Sharing $deviceCount device(s)'
                        : 'Server Inactive (add a device below to start)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isRunning
                          ? Colors.green.shade900
                          : Colors.amber.shade900,
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
    final devices = server.devices;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Centered Big Add Device Button with Sample Refresh Button
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: () => _showAddDeviceDialog(),
                  icon: const Icon(Icons.add, size: 24),
                  label: const Text(
                    'Add Device',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Sample (randomly fills form)',
                  icon: const Icon(Icons.refresh),
                  iconSize: 22,
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _showAddDeviceDialog(autoFillSample: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Shared devices list
        Text(
          'Currently Shared on LAN (${devices.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (devices.isEmpty)
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No peripherals shared yet.\nTap a button above to add a device and auto-start the server.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          )
        else
          ...devices.map(
            (dev) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    dev.deviceId.contains('scanner')
                        ? Icons.qr_code_scanner
                        : Icons.print,
                  ),
                ),
                title: Text(
                  dev.deviceName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${dev.deviceId} • ${dev.deviceDescription ?? "No description"}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Remove device',
                  onPressed: () => _removeDevice(dev.deviceId),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildClientTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Discovered LAN Peripherals',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            FilledButton.tonalIcon(
              onPressed: _isDiscovering ? null : _discoverDevices,
              icon: _isDiscovering
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('Discover'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_discoveredDevices.isEmpty)
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No devices discovered yet.\nTap "Discover" to scan for shared peripherals on this WiFi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          )
        else
          ..._discoveredDevices.map(
            (dev) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.devices)),
                title: Text(
                  dev.deviceName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${dev.deviceId} • ${dev.deviceIp}:${dev.devicePort}',
                ),
                trailing: FilledButton.icon(
                  icon: const Icon(Icons.send, size: 14),
                  label: const Text('Send'),
                  onPressed: () => _sendMessage(dev),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLogsPanel() {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Activity Logs',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                if (_logs.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _logs.clear()),
                    child: const Text(
                      'Clear',
                      style: TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'No activity yet',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: _logs.length,
                    itemBuilder: (ctx, i) => Text(
                      _logs[i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
