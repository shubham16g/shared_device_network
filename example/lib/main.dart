import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ContinuousForegroundService.initCommunicationPort();
  if (Platform.isAndroid || Platform.isIOS) {
    await ContinuousForegroundService.init();
  }
  runApp(const SharedDeviceApp());
}

class SharedDeviceApp extends StatelessWidget {
  const SharedDeviceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shared Connected Devices Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF64B5F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Server state
  late SharedDeviceNetworkServer _server;
  final List<String> _serverLogs = [];

  // Client state
  late SharedDeviceNetworkClient _client;
  List<SharedDevice> _discoveredDevices = [];
  bool _isDiscovering = false;
  final List<String> _clientLogs = [];

  // Controllers for adding a new shared device on server
  final _deviceIdController = TextEditingController(text: 'printer-bt-01');
  final _deviceNameController = TextEditingController(text: 'Bluetooth Receipt Printer');
  final _deviceDescController = TextEditingController(text: 'Kitchen 80mm ESC/POS Thermal Printer');
  final _pairKeyController = TextEditingController(text: '1234');

  // Client input
  final _clientMessageController = TextEditingController(text: '{"action":"PRINT","text":"Hello Receipt"}');
  final _clientPairKeyController = TextEditingController(text: '1234');

  // Continuous Foreground Service state
  bool _isContinuousServiceRunning = false;
  int _continuousServiceTick = 0;
  String _continuousServiceLastUpdate = 'Not running';
  bool _isIgnoringBatteryOpt = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _server = SharedDeviceNetworkServer(
      port: 8888,
      discoveryPort: 8889,
      enableForegroundService: true,
      onDataReceived: (deviceId, message) async {
        final log = 'Received for "$deviceId": "$message"';
        setState(() {
          _serverLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] $log');
        });
        return Status.success(
          message: 'Handled by shared device $deviceId',
          data: {'deviceId': deviceId, 'processedAt': DateTime.now().toIso8601String()},
        );
      },
    );

    _client = SharedDeviceNetworkClient(
      deviceId: 'mobile-client-01',
      deviceName: 'Waiter App',
      discoveryPort: 8889,
      defaultTimeout: const Duration(seconds: 4),
    );

    SharedDeviceForegroundService.addMessageCallback(_handleBackgroundServerData);
    ContinuousForegroundService.addDataCallback(_handleContinuousServiceData);
    _checkContinuousServiceStatus();
  }

  Future<void> _checkContinuousServiceStatus() async {
    final running = await ContinuousForegroundService.isRunning();
    final batteryOpt = await ContinuousForegroundService.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _isContinuousServiceRunning = running;
        _isIgnoringBatteryOpt = batteryOpt;
      });
    }
  }

  void _handleContinuousServiceData(Object data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final status = map['status']?.toString();
      final tick = map['tick'] as int? ?? _continuousServiceTick;
      final timestamp = map['timestamp']?.toString() ?? DateTime.now().toIso8601String();
      if (mounted) {
        setState(() {
          if (status == 'started' || status == 'running') {
            _isContinuousServiceRunning = true;
          } else if (status == 'stopped') {
            _isContinuousServiceRunning = false;
          }
          _continuousServiceTick = tick;
          _continuousServiceLastUpdate = timestamp.length >= 19 ? timestamp.substring(11, 19) : timestamp;
        });
      }
    }
  }

  Future<void> _startContinuousForegroundService() async {
    final success = await ContinuousForegroundService.startService(
      notificationTitle: 'Foreground Service Active',
      notificationText: 'Running indefinitely in background',
    );
    if (mounted) {
      setState(() {
        _isContinuousServiceRunning = success;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '✅ Foreground service started indefinitely!' : '❌ Failed to start service.'),
          backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _stopContinuousForegroundService() async {
    final success = await ContinuousForegroundService.stopService();
    if (mounted) {
      setState(() {
        if (success) _isContinuousServiceRunning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Foreground service stopped.' : 'Failed to stop service.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    final granted = await ContinuousForegroundService.requestIgnoreBatteryOptimization();
    if (mounted) {
      setState(() {
        _isIgnoringBatteryOpt = granted;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted
              ? 'Battery optimization ignored for non-stop execution.'
              : 'Battery optimization settings unchanged.'),
        ),
      );
    }
  }

  void _handleBackgroundServerData(Object data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['event'] == 'onDataReceived') {
        final devId = map['deviceId'];
        final msg = map['message'];
        setState(() {
          _serverLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] (BG) For $devId: "$msg"');
        });
      }
    }
  }

  @override
  void dispose() {
    SharedDeviceForegroundService.removeMessageCallback(_handleBackgroundServerData);
    ContinuousForegroundService.removeDataCallback(_handleContinuousServiceData);
    _server.stop();
    _client.dispose();
    _tabController.dispose();
    _deviceIdController.dispose();
    _deviceNameController.dispose();
    _deviceDescController.dispose();
    _pairKeyController.dispose();
    _clientMessageController.dispose();
    _clientPairKeyController.dispose();
    super.dispose();
  }

  // --- Server Actions ---

  Future<void> _addSharedDevice() async {
    final devId = _deviceIdController.text.trim();
    final devName = _deviceNameController.text.trim();
    final devDesc = _deviceDescController.text.trim();
    final pairKey = _pairKeyController.text.trim().isNotEmpty ? _pairKeyController.text.trim() : null;

    if (devId.isEmpty || devName.isEmpty) return;

    await _server.addDevice(
      devId,
      devName,
      deviceDescription: devDesc.isNotEmpty ? devDesc : null,
      pairKey: pairKey,
    );

    setState(() {
      _serverLogs.insert(
        0,
        '[${DateTime.now().toIso8601String().substring(11, 19)}] Added shared device "$devName" ($devId). Server running: ${_server.isRunning}',
      );
    });
  }

  Future<void> _removeSharedDevice(String deviceId) async {
    await _server.removeDevice(deviceId);
    setState(() {
      _serverLogs.insert(
        0,
        '[${DateTime.now().toIso8601String().substring(11, 19)}] Removed device "$deviceId". Remaining: ${_server.deviceCount}, Server running: ${_server.isRunning}',
      );
    });
  }

  // --- Client Actions ---

  Future<void> _startDiscovery() async {
    setState(() {
      _isDiscovering = true;
      _discoveredDevices = [];
    });

    try {
      final devices = await _client.discoverDevicesOnce(
        timeout: const Duration(seconds: 3),
      );
      setState(() {
        _discoveredDevices = devices;
        _isDiscovering = false;
        _clientLogs.insert(0, 'Discovery finished: found ${devices.length} shared device(s).');
      });
    } catch (e) {
      setState(() {
        _isDiscovering = false;
        _clientLogs.insert(0, 'Discovery error: $e');
      });
    }
  }

  Future<void> _sendMessageToDevice(SharedDevice device) async {
    final msg = _clientMessageController.text.trim();
    if (msg.isEmpty) return;

    _clientLogs.insert(0, 'Sending to ${device.deviceName} (${device.deviceId})...');
    setState(() {});

    final status = await _client.sendToDevice(
      device.deviceId,
      msg,
      targetDevice: device,
      pairKey: _clientPairKeyController.text.trim().isNotEmpty
          ? _clientPairKeyController.text.trim()
          : null,
      timeout: const Duration(seconds: 4),
    );

    setState(() {
      if (status.isSuccess) {
        _clientLogs.insert(0, '✅ ACK Received from ${device.deviceId}: "${status.message}"');
      } else {
        _clientLogs.insert(0, '❌ Error [${status.statusCode}]: ${status.message}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Device Network'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.hub),
              text: 'Host Server (${_server.deviceCount})',
            ),
            Tab(
              icon: const Icon(Icons.devices),
              text: 'Client Discover (${_discoveredDevices.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildServiceControlCard(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildServerTab(),
                _buildClientTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceControlCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isRunning = _isContinuousServiceRunning;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRunning
            ? (isDark ? const Color(0xFF1B3B2B) : const Color(0xFFE8F5E9))
            : (isDark ? const Color(0xFF2C241E) : const Color(0xFFFFF3E0)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning
              ? (isDark ? Colors.green.shade700 : Colors.green.shade300)
              : (isDark ? Colors.orange.shade700 : Colors.orange.shade300),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isRunning ? Colors.green : Colors.orange,
                  boxShadow: isRunning
                      ? [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isRunning ? 'Foreground Service: RUNNING' : 'Foreground Service: STOPPED',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isRunning ? Colors.green.shade800 : Colors.orange.shade900,
                  ),
                ),
              ),
              if (Platform.isAndroid && !_isIgnoringBatteryOpt)
                TextButton.icon(
                  onPressed: _requestBatteryOptimizationExemption,
                  icon: const Icon(Icons.battery_alert, size: 16),
                  label: const Text('Unrestrict', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isRunning
                ? 'Runs continuously in dedicated isolate • Heartbeat tick: $_continuousServiceTick (Last: $_continuousServiceLastUpdate)'
                : 'Service is inactive. Press "Start Service" to begin continuous execution indefinitely.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isRunning ? null : _startContinuousForegroundService,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start Service'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: !isRunning ? null : _stopContinuousForegroundService,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                  ),
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Stop Service'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServerTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status header
        Card(
          color: _server.isRunning
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.15),
          child: ListTile(
            leading: Icon(
              _server.isRunning ? Icons.radio_button_checked : Icons.radio_button_off,
              color: _server.isRunning ? Colors.green : Colors.orange,
            ),
            title: Text(
              _server.isRunning ? 'UDP Server Active (Port 8888)' : 'UDP Server Inactive',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _server.isRunning
                  ? 'Sharing ${_server.deviceCount} connected peripheral(s)'
                  : 'Add a connected device below to automatically start the server',
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Shared Devices List
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected Devices Shared by this Phone (${_server.deviceCount})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_server.devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No devices shared yet. Add a Bluetooth printer or USB scanner below.'),
                  )
                else
                  ..._server.devices.map(
                    (dev) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.print)),
                      title: Text(dev.deviceName),
                      subtitle: Text('${dev.deviceId}${dev.deviceDescription != null ? " • ${dev.deviceDescription}" : ""}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Remove device',
                        onPressed: () => _removeSharedDevice(dev.deviceId),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Add Device Form
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share a New Connected Device (e.g. Bluetooth/USB)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deviceIdController,
                  decoration: const InputDecoration(
                    labelText: 'Device ID (e.g. printer-bt-01, scanner-01)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _deviceNameController,
                  decoration: const InputDecoration(
                    labelText: 'Device Name (e.g. Kitchen ESC/POS Printer)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _deviceDescController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pairKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Pair Key (Optional password for this device)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _addSharedDevice,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Shared Device & Auto-Start Server'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Server Logs', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          height: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _serverLogs.isEmpty
              ? const Center(child: Text('No activity logged.'))
              : ListView.builder(
                  itemCount: _serverLogs.length,
                  itemBuilder: (context, i) => Text(
                    _serverLogs[i],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Discovered Shared Devices',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _isDiscovering ? null : _startDiscovery,
                      icon: _isDiscovering
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: const Text('Discover'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_discoveredDevices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Press "Discover" to find shared devices available on this WiFi/network.'),
                  )
                else
                  ..._discoveredDevices.map(
                    (device) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.devices_other)),
                      title: Text(device.deviceName),
                      subtitle: Text('${device.deviceId} (${device.deviceIp}:${device.devicePort})'),
                      trailing: FilledButton.icon(
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('Send'),
                        onPressed: () => _sendMessageToDevice(device),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Message & Pair Key',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _clientMessageController,
                  decoration: const InputDecoration(
                    labelText: 'Payload / Command (JSON or string)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _clientPairKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Device Pair Key',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Client Dispatch Logs', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          height: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _clientLogs.isEmpty
              ? const Center(child: Text('No client transmissions yet.'))
              : ListView.builder(
                  itemCount: _clientLogs.length,
                  itemBuilder: (context, i) => Text(
                    _clientLogs[i],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
        ),
      ],
    );
  }
}
