import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';
import 'server_background_service.dart';

class BgServiceScreen extends StatefulWidget {
  const BgServiceScreen({super.key});

  @override
  State<BgServiceScreen> createState() => _BgServiceScreenState();
}

class _BgServiceScreenState extends State<BgServiceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  SharedDeviceNetworkClient? _client;

  bool _isServiceRunning = false;
  bool _isLoading = false;
  int _serverPort = kDefaultBgServerPort; // 9888
  int _discoveryPort = kDefaultBgDiscoveryPort; // 9889

  List<SharedDeviceRecord> _hostedDevices = [];
  List<SharedDevice> _discoveredDevices = [];
  bool _isDiscovering = false;

  final List<String> _logs = [];

  StreamSubscription? _statusSub;
  StreamSubscription? _logSub;
  StreamSubscription? _msgSub;

  int _sampleCounter = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _setupClient();
    _initBackgroundService();
  }

  void _setupClient() {
    _client?.dispose();
    _client = SharedDeviceNetworkClient(
      deviceId: 'bg-client-01',
      deviceName: 'Waiter Tablet (Bg Test)',
      discoveryPort: _discoveryPort,
      defaultTimeout: const Duration(seconds: 3),
    );
  }

  Future<void> _initBackgroundService() async {
    setState(() => _isLoading = true);

    // Request notification permission for foreground notification
    await ServerBackgroundServiceController.requestNotificationPermission();

    // Initialize background service configurations
    await ServerBackgroundServiceController.initialize();

    // Listen to background service events
    _statusSub = ServerBackgroundServiceController.onStatusUpdate.listen((data) {
      if (!mounted || data == null) return;

      final bool running = data['isRunning'] == true;
      final int port = (data['port'] as int?) ?? _serverPort;
      final int discPort = (data['discoveryPort'] as int?) ?? _discoveryPort;

      final rawDevices = data['devices'] as List<dynamic>? ?? [];
      final devices = <SharedDeviceRecord>[];
      for (final item in rawDevices) {
        if (item is Map<String, dynamic>) {
          devices.add(SharedDeviceRecord.fromMap(item));
        } else if (item is Map) {
          devices.add(
            SharedDeviceRecord.fromMap(Map<String, dynamic>.from(item)),
          );
        }
      }

      final portsChanged = discPort != _discoveryPort;

      setState(() {
        _isServiceRunning = running;
        _serverPort = port;
        _discoveryPort = discPort;
        _hostedDevices = devices;
        _isLoading = false;
      });

      if (portsChanged) {
        _setupClient();
      }
    });

    _logSub = ServerBackgroundServiceController.onLog.listen((data) {
      if (!mounted || data == null) return;
      final msg = data['message']?.toString();
      if (msg != null && msg.isNotEmpty) {
        _log(msg);
      }
    });

    _msgSub = ServerBackgroundServiceController.onMessageReceived.listen((data) {
      if (!mounted || data == null) return;
      final deviceId = data['deviceId']?.toString() ?? 'unknown';
      final message = data['message']?.toString() ?? '';
      _log('📥 Host received for "$deviceId": $message');
    });

    // Check if background service is already running
    final running = await ServerBackgroundServiceController.isRunning();
    if (running) {
      _log('ℹ️ Connected to active background service');
      ServerBackgroundServiceController.requestStatus();
      setState(() => _isLoading = false);
    } else {
      // Auto-start background server on distinct ports (9888 & 9889)
      _log(
        '🚀 Launching background server on port $_serverPort (discovery: $_discoveryPort)...',
      );
      await _startBackgroundService();
    }
  }

  Future<void> _startBackgroundService() async {
    setState(() => _isLoading = true);
    final success = await ServerBackgroundServiceController.start(
      port: _serverPort,
      discoveryPort: _discoveryPort,
    );

    if (success) {
      _log(
        '✅ Background service started (Port: $_serverPort, Discovery: $_discoveryPort)',
      );
      ServerBackgroundServiceController.requestStatus();
    } else {
      _log('⚠️ Failed to start background service or waiting for service isolate');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _stopBackgroundService() async {
    setState(() => _isLoading = true);
    await ServerBackgroundServiceController.stop();
    _log('⏹️ Background service stopped');
    setState(() {
      _isServiceRunning = false;
      _isLoading = false;
    });
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
    _client?.dispose();
    _statusSub?.cancel();
    _logSub?.cancel();
    _msgSub?.cancel();
    super.dispose();
  }

  // --- Background Server Actions ---

  Future<void> _addDevice({
    required String id,
    required String name,
    String? description,
    String? pairKey,
  }) async {
    ServerBackgroundServiceController.addDevice(
      deviceId: id,
      deviceName: name,
      deviceDescription: description,
      pairKey: pairKey,
    );
    _log('📤 Requested background service to add: $name ($id)');
  }

  Future<void> _removeDevice(String deviceId) async {
    ServerBackgroundServiceController.removeDevice(deviceId);
    _log('📤 Requested background service to remove: $deviceId');
  }

  void _showAddDeviceDialog({bool autoFillSample = false}) {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final keyController = TextEditingController();

    final samples = [
      {
        'id': 'printer-kitchen',
        'name': 'Kitchen ESC/POS Printer (BG)',
        'desc': 'Background Service 80mm Thermal Printer',
        'key': '1234',
      },
      {
        'id': 'scanner-barcode',
        'name': 'Warehouse Barcode Scanner (BG)',
        'desc': 'Background Service 2D Barcode Scanner',
        'key': 'pass456',
      },
      {
        'id': 'cash-drawer',
        'name': 'Cash Drawer (BG)',
        'desc': 'Background Service RJ11 Cash Drawer',
        'key': '',
      },
      {
        'id': 'scale-deli',
        'name': 'Deli Digital Scale (BG)',
        'desc': 'Background Service Serial Weight Scale',
        'key': '7788',
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
                'Add Device to BG Server',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                    hintText: 'e.g. printer-kitchen-01',
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

  void _showPortConfigDialog() {
    final portCtrl = TextEditingController(text: _serverPort.toString());
    final discCtrl = TextEditingController(text: _discoveryPort.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Background Ports Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Running on separate ports avoids conflict with the main foreground server (8888 & 8889).',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Server Port',
                hintText: 'Default: 9888',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: discCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Discovery Broadcast Port',
                hintText: 'Default: 9889',
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
              final newPort = int.tryParse(portCtrl.text.trim()) ?? _serverPort;
              final newDisc =
                  int.tryParse(discCtrl.text.trim()) ?? _discoveryPort;
              Navigator.pop(ctx);

              setState(() {
                _serverPort = newPort;
                _discoveryPort = newDisc;
              });
              _setupClient();
              _log('🔄 Restarting background server with ports $newPort / $newDisc...');
              await _startBackgroundService();
            },
            child: const Text('Apply & Restart'),
          ),
        ],
      ),
    );
  }

  // --- Client Actions ---

  Future<void> _discoverDevices() async {
    if (_client == null) return;
    setState(() => _isDiscovering = true);
    _log('🔍 Client broadcasting discovery on port $_discoveryPort...');
    try {
      final found = await _client!.discoverDevicesOnce(
        timeout: const Duration(seconds: 2),
      );
      setState(() {
        _discoveredDevices = found;
        _isDiscovering = false;
      });
      _log('🔍 Discovered ${found.length} device(s) on discovery port $_discoveryPort');
    } catch (e) {
      setState(() => _isDiscovering = false);
      _log('❌ Discovery error: $e');
    }
  }

  Future<void> _sendMessage(SharedDevice dev) async {
    if (_client == null) return;
    _log('📤 Client sending test command to "${dev.deviceName}" (${dev.deviceId})...');
    final status = await _client!.sendToDevice(dev.deviceId, {
      'action': 'PRINT_BG_JOB',
      'item': 'Espresso Single x1',
      'total': 4.25,
      'source': 'BackgroundServiceTester',
    }, targetDevice: dev);

    if (status.isSuccess) {
      _log('✅ ACK from ${dev.deviceId}: ${status.message}');
    } else {
      _log('❌ Failed [${status.statusCode}]: ${status.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceCount = _hostedDevices.length;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Background Service Server', style: TextStyle(fontSize: 18)),
            Text(
              'Runs SharedDeviceNetworkServer in OS background service',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Port Configuration',
            icon: const Icon(Icons.settings_ethernet),
            onPressed: _showPortConfigDialog,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton.filledTonal(
                    tooltip: _isServiceRunning ? 'Stop Service' : 'Start Service',
                    icon: Icon(
                      _isServiceRunning ? Icons.stop : Icons.play_arrow,
                      color: _isServiceRunning ? Colors.red : Colors.green,
                    ),
                    onPressed: _isServiceRunning
                        ? _stopBackgroundService
                        : _startBackgroundService,
                  ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.cloud_sync),
              text: 'BG Host ($deviceCount)',
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
          // Status Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _isServiceRunning
                ? Colors.green.shade50
                : Colors.amber.shade50,
            child: Row(
              children: [
                Icon(
                  _isServiceRunning
                      ? Icons.check_circle
                      : Icons.pause_circle_outline,
                  color: _isServiceRunning
                      ? Colors.green.shade700
                      : Colors.amber.shade800,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isServiceRunning
                            ? 'Background Service Active • Hosting $deviceCount device(s)'
                            : 'Background Service Stopped',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _isServiceRunning
                              ? Colors.green.shade900
                              : Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Data Port: $_serverPort | Discovery Port: $_discoveryPort (Distinct from Main 8888/8889)',
                        style: TextStyle(
                          fontSize: 11,
                          color: _isServiceRunning
                              ? Colors.green.shade800
                              : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _showPortConfigDialog,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Change Ports', style: TextStyle(fontSize: 11)),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top Info & Controls
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Background Service Architecture',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'The server instance runs in an isolated background service process with an ongoing foreground notification. Devices added here remain shared across LAN even when you leave this screen or close the UI.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.router, size: 16),
                      label: Text('Port: $_serverPort'),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      avatar: const Icon(Icons.radar, size: 16),
                      label: Text('Discovery: $_discoveryPort'),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      avatar: Icon(
                        _isServiceRunning ? Icons.check : Icons.close,
                        size: 16,
                        color: _isServiceRunning ? Colors.green : Colors.red,
                      ),
                      label: Text(_isServiceRunning ? 'Running' : 'Stopped'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Add Device button row
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () => _showAddDeviceDialog(),
                icon: const Icon(Icons.add, size: 22),
                label: const Text(
                  'Add Device to BG Server',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
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

        const SizedBox(height: 16),

        // Shared devices list
        Text(
          'Background Shared Devices (${_hostedDevices.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (_hostedDevices.isEmpty)
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No peripherals shared in background service yet.\nTap "Add Device to BG Server" above to share a peripheral.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
          )
        else
          ..._hostedDevices.map(
            (dev) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    dev.deviceId.contains('scanner')
                        ? Icons.qr_code_scanner
                        : dev.deviceId.contains('drawer')
                            ? Icons.inventory_2
                            : dev.deviceId.contains('scale')
                                ? Icons.scale
                                : Icons.print,
                  ),
                ),
                title: Text(
                  dev.deviceName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${dev.deviceId} • ${dev.deviceDescription ?? "No description"}'
                  '${dev.pairKey != null && dev.pairKey!.isNotEmpty ? " • Key: ***" : ""}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Remove device from background service',
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
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.radar, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Client scans discovery port $_discoveryPort to test background server peripherals.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Discovered LAN Peripherals (${_discoveredDevices.length})',
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
                  'No devices discovered on port yet.\nEnsure background server is running and tap "Discover".',
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
                  label: const Text('Send Test'),
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
