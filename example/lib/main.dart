import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize communication port for background task if on mobile
  if (Platform.isAndroid || Platform.isIOS) {
    await SharedDeviceForegroundService.init();
  }
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD0BCFF),
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
  SharedDeviceNetworkServer? _localServer;
  bool _isServerRunning = false;
  bool _runInBackgroundService = true;
  final List<String> _serverLogs = [];

  // Client state
  late SharedDeviceNetworkClient _client;
  List<SharedDevice> _discoveredDevices = [];
  bool _isDiscovering = false;
  final List<String> _clientLogs = [];

  // Inputs
  final _serverPortController = TextEditingController(text: '8888');
  final _serverNameController = TextEditingController(text: 'Kitchen POS Server');
  final _clientMessageController = TextEditingController(text: 'Print Order #1042');
  final _pairKeyController = TextEditingController(text: 'secret123');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _client = SharedDeviceNetworkClient(
      deviceId: 'client-mobile-01',
      deviceName: 'Waiter Tablet',
      defaultTimeout: const Duration(seconds: 4),
    );

    // Listen for messages received by background isolate server
    SharedDeviceForegroundService.addMessageCallback(_handleBackgroundServerData);
    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    final running = await SharedDeviceForegroundService.isRunning();
    if (running && mounted) {
      setState(() {
        _isServerRunning = true;
        _serverLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] Background server is currently running.');
      });
    }
  }

  void _handleBackgroundServerData(Object data) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['event'] == 'onDataReceived') {
        final sender = map['senderDeviceId'];
        final msg = map['message'];
        setState(() {
          _serverLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] (Background Server) From $sender: "$msg"');
        });
      }
    }
  }

  @override
  void dispose() {
    SharedDeviceForegroundService.removeMessageCallback(_handleBackgroundServerData);
    _localServer?.stop();
    _client.dispose();
    _tabController.dispose();
    _serverPortController.dispose();
    _serverNameController.dispose();
    _clientMessageController.dispose();
    _pairKeyController.dispose();
    super.dispose();
  }

  // --- Server Actions ---

  Future<void> _toggleServer() async {
    final port = int.tryParse(_serverPortController.text) ?? 8888;
    final serverName = _serverNameController.text.trim();

    if (_isServerRunning) {
      if (_runInBackgroundService && (Platform.isAndroid || Platform.isIOS)) {
        await SharedDeviceForegroundService.stopService();
      } else {
        await _localServer?.stop();
      }
      setState(() {
        _isServerRunning = false;
        _serverLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] Server stopped.');
      });
    } else {
      if (_runInBackgroundService && (Platform.isAndroid || Platform.isIOS)) {
        // Start in persistent background isolate (keeps running even if app is killed!)
        final started = await SharedDeviceForegroundService.startBackgroundServer(
          deviceId: 'server-pos-001',
          deviceName: serverName,
          deviceDescription: 'Kitchen Display Station (Background)',
          port: port,
          notificationTitle: '$serverName Active',
          notificationText: 'Listening on port $port (Keeps running when app is closed)',
        );

        setState(() {
          _isServerRunning = started;
          _serverLogs.insert(
            0,
            started
                ? '[${DateTime.now().toIso8601String().substring(11, 19)}] Started in background foreground service (Persistent).'
                : 'Failed to start background foreground service.',
          );
        });
      } else {
        // Start as in-memory server
        _localServer = SharedDeviceNetworkServer(
          deviceId: 'server-pos-001',
          deviceName: serverName,
          deviceDescription: 'Main Kitchen Display Station',
          port: port,
          requirePairKey: false,
          onDataReceived: (senderDeviceId, message) async {
            setState(() {
              _serverLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] Received from $senderDeviceId: "$message"');
            });
            return Status.success(
              message: 'Order processed successfully by POS',
              data: {'processedAt': DateTime.now().toIso8601String(), 'code': 100},
            );
          },
        );

        try {
          await _localServer!.start();
          setState(() {
            _isServerRunning = true;
            _serverLogs.insert(0, '[${DateTime.now().toIso8601String().substring(11, 19)}] Server listening on port $port');
          });
        } catch (e) {
          setState(() {
            _serverLogs.insert(0, 'Error starting server: $e');
          });
        }
      }
    }
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
        _clientLogs.insert(0, 'Found ${devices.length} device(s) on network.');
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

    _clientLogs.insert(0, 'Sending to ${device.deviceName} (${device.deviceIp}:${device.devicePort})...');
    setState(() {});

    final status = await _client.sendToDevice(
      device.deviceId,
      msg,
      targetDevice: device,
      pairKey: _pairKeyController.text.trim().isNotEmpty ? _pairKeyController.text.trim() : null,
      timeout: const Duration(seconds: 4),
    );

    setState(() {
      if (status.isSuccess) {
        _clientLogs.insert(0, '✅ ACK Received: "${status.message}" Data: ${status.data}');
      } else {
        _clientLogs.insert(0, '❌ Failed [${status.statusCode}]: ${status.message}');
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
          tabs: const [
            Tab(icon: Icon(Icons.dns), text: 'Server'),
            Tab(icon: Icon(Icons.devices), text: 'Client'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildServerTab(),
          _buildClientTab(),
        ],
      ),
    );
  }

  Widget _buildServerTab() {
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
                Text(
                  'UDP Server Configuration',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _serverNameController,
                  decoration: const InputDecoration(
                    labelText: 'Server Device Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _serverPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'UDP Port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep running when app is killed'),
                  subtitle: const Text('Uses persistent Android Foreground Service & background isolate'),
                  value: _runInBackgroundService,
                  onChanged: (val) => setState(() => _runInBackgroundService = val),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _toggleServer,
                  style: FilledButton.styleFrom(
                    backgroundColor: _isServerRunning ? Colors.red : null,
                  ),
                  icon: Icon(_isServerRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(_isServerRunning ? 'Stop Server' : 'Start Server'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Received Messages & Logs', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          height: 250,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _serverLogs.isEmpty
              ? const Center(child: Text('No messages received yet.'))
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
                    Text(
                      'Discovered Devices',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
                    child: Text('No devices discovered. Press "Discover" to broadcast on UDP network.'),
                  )
                else
                  ..._discoveredDevices.map(
                    (device) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(child: Icon(Icons.wifi_tethering)),
                      title: Text(device.deviceName),
                      subtitle: Text('${device.deviceIp}:${device.devicePort} (${device.deviceId})'),
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
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Message Dispatch',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientMessageController,
                  decoration: const InputDecoration(
                    labelText: 'Payload / Message Content',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pairKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Pair Key (Optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Client Dispatch & ACK Logs', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          height: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _clientLogs.isEmpty
              ? const Center(child: Text('No client operations recorded.'))
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
