import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../main.dart';
import '../widgets.dart';

/// Host side: share this phone's Bluetooth printers with the Wi-Fi.
class SharePage extends StatelessWidget {
  const SharePage({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    if (!app.canHost) {
      return Scaffold(
        appBar: AppBar(title: const Text('Share printers')),
        body: const EmptyState(
          icon: Icons.phonelink_off,
          title: 'Sharing needs Android',
          message: 'The printer hub runs in an Android background service. '
              'On this device you can still print from the Print tab.',
        ),
      );
    }

    final running = app.hubRunning;
    final hasPrinters = app.printers.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Share printers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPrinter(context),
        icon: const Icon(Icons.add),
        label: const Text('Add printer'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          StatusCard(
            icon: running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
            active: running,
            title: running ? 'Sharing on Wi-Fi' : 'Sharing is off',
            message: running
                ? 'Runs in the background, even with this app closed. '
                    'Every phone on this Wi-Fi can print.'
                : hasPrinters
                    ? 'Turn on to let every phone on this Wi-Fi print on the printers below.'
                    : 'Add a printer first, then turn sharing on.',
            trailing: app.hubBusy
                ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : Switch(
                    value: running,
                    onChanged: running || hasPrinters ? app.setSharing : null,
                  ),
            footer: running && app.hubAddress.isNotEmpty
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.link, size: 18),
                        label: Text('http://${app.hubAddress}'),
                        tooltip: 'Copy address',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: 'http://${app.hubAddress}'));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Address copied')));
                        },
                      ),
                      Chip(
                        avatar: const Icon(Icons.receipt_long, size: 18),
                        label: Text('${app.printed} printed'),
                      ),
                    ],
                  )
                : null,
          ),
          const SectionTitle('Printers', icon: Icons.print_outlined),
          if (!hasPrinters)
            const EmptyState(
              icon: Icons.print_disabled_outlined,
              title: 'No printers yet',
              message: 'Pair the printer in Android Bluetooth settings, then tap "Add printer".',
            )
          else
            CardList(
              children: [
                for (final p in app.printers)
                  ListTile(
                    leading: const DeviceAvatar(['print']),
                    title: Text(p.name),
                    subtitle: Text(
                      !running
                          ? 'Not shared while sharing is off'
                          : app.connectedPrinters.contains(p.id)
                              ? 'Connected'
                              : 'Connects on the first job',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => app.removePrinter(p),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          Text(
            'Keep this phone charging, on Wi-Fi and near the printers.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _addPrinter(BuildContext context) async {
    final List<BtcDevice> paired;
    try {
      paired = await app.pairedDevices();
    } on Exception catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (!context.mounted) return;
    bool spp(BtcDevice d) => d.uuids.any((u) => u.toLowerCase().startsWith('00001101'));
    final picked = await showModalBottomSheet<BtcDevice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                child: Text('Choose a printer', style: Theme.of(ctx).textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  'Pick your printer by name. Only paired devices are listed; '
                  'pair new printers in Android Bluetooth settings.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
              if (paired.isEmpty)
                const EmptyState(
                  icon: Icons.bluetooth_disabled,
                  title: 'No paired devices',
                  message: 'Pair the printer in Android Bluetooth settings first.',
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in paired)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                        // Printers take jobs over the serial port profile; without it a
                        // device (headphones, keyboard...) cannot print.
                        enabled: spp(d),
                        leading: const Icon(Icons.bluetooth),
                        title: Text(d.name ?? d.address),
                        subtitle: Text(spp(d) ? 'Serial port (SPP)' : 'No serial port, cannot print'),
                        onTap: () => Navigator.pop(ctx, d),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) await app.addPrinter(picked);
  }
}
