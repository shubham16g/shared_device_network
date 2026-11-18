import 'package:flutter/material.dart';
import 'package:shared_device_network/shared_device_network.dart';

import '../main.dart';
import '../widgets.dart';

/// Client side: find printers shared on the Wi-Fi and send them jobs.
class PrintPage extends StatelessWidget {
  const PrintPage({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final byHost = <String, List<SharedDevice>>{};
    for (final d in app.devices) {
      byHost.putIfAbsent('${d.deviceIp}:${d.devicePort}', () => []).add(d);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Print')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          StatusCard(
            icon: Icons.radar,
            title: 'Find printers on this Wi-Fi',
            message: 'Every phone that shares printers shows up here, including this one.',
            footer: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: app.scanning ? null : app.scan,
                  icon: app.scanning
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(app.scanning ? 'Scanning…' : 'Scan'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _connectDialog(context),
                  icon: const Icon(Icons.add_link),
                  label: const Text('Connect by address'),
                ),
              ],
            ),
          ),
          if (byHost.isEmpty && !app.scanning)
            const EmptyState(
              icon: Icons.wifi_find,
              title: 'No printers yet',
              message: 'Make sure the hub phone is sharing and on the same Wi-Fi, then tap Scan.',
            ),
          for (final MapEntry(key: host, value: devices) in byHost.entries) ...[
            SectionTitle(
              host == app.hubAddress ? 'This phone · $host' : host,
              icon: host == app.hubAddress ? Icons.smartphone : Icons.dns_outlined,
            ),
            CardList(
              children: [
                for (final d in devices)
                  ListTile(
                    leading: DeviceAvatar(d.capabilities),
                    title: Text(d.deviceName),
                    subtitle: Text(d.deviceDescription ?? d.deviceId),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (d.isSecured) const Icon(Icons.lock_outline, size: 18),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      useSafeArea: true,
                      builder: (_) => SendSheet(app: app, device: d),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _connectDialog(BuildContext context) async {
    final host = TextEditingController();
    final port = TextEditingController(text: '8080');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect by address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Shown on the Share tab of the hub phone.'),
            const SizedBox(height: 16),
            TextField(
              controller: host,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'IP address', hintText: '192.168.1.20'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Connect')),
        ],
      ),
    );
    final h = host.text.trim();
    final p = int.tryParse(port.text.trim()) ?? 8080;
    host.dispose();
    port.dispose();
    if (ok == true && h.isNotEmpty) await app.connect(h, p);
  }
}

/// Bottom sheet for sending a message to one device.
class SendSheet extends StatefulWidget {
  const SendSheet({super.key, required this.app, required this.device});

  final AppController app;
  final SharedDevice device;

  @override
  State<SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<SendSheet> {
  var _mode = SendMode.json;
  var _sending = false;
  SharedDeviceResponse? _result;
  final _message = TextEditingController(text: 'Hello from Printer Hub!');
  late final _pairKey = TextEditingController(text: widget.app.pairKeys[widget.device.deviceId]);

  @override
  void dispose() {
    _message.dispose();
    _pairKey.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final d = widget.device;
    if (d.isSecured) widget.app.pairKeys[d.deviceId] = _pairKey.text.trim();
    setState(() {
      _sending = true;
      _result = null;
    });
    final result = await widget.app.send(d, _mode, _message.text);
    if (mounted) {
      setState(() {
        _sending = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DeviceAvatar(d.capabilities),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.deviceName, style: text.titleLarge),
                      Text(
                        '${d.deviceId} · ${d.deviceIp}:${d.devicePort}',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (d.isSecured) ...[
              TextField(
                controller: _pairKey,
                decoration: const InputDecoration(
                  labelText: 'Pair key',
                  prefixIcon: Icon(Icons.key),
                  helperText: 'This device is protected. The phone sharing it shows the key.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _message,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
            const SizedBox(height: 20),
            SegmentedButton<SendMode>(
              showSelectedIcon: false,
              segments: [
                for (final m in SendMode.values)
                  ButtonSegment(value: m, label: Text(m.label), icon: Icon(m.icon)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              'Uses ${_mode.method}',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(fontFamily: 'monospace', color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_sending ? 'Sending…' : 'Send'),
            ),
            if (_result != null) ...[const SizedBox(height: 16), _ResultBanner(_result!)],
          ],
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner(this.response);

  final SharedDeviceResponse response;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ok = response.isSuccess;
    final fg = ok ? scheme.onPrimaryContainer : scheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ok ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok ? 'Delivered' : 'Failed (${response.statusCode})',
                  style: text.titleSmall?.copyWith(color: fg),
                ),
                Text(response.message, style: text.bodyMedium?.copyWith(color: fg)),
                if (!ok && response.error != null)
                  Text(response.error!, style: text.bodySmall?.copyWith(color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
