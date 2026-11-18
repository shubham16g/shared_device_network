import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets.dart';

/// Everything this phone sent and received, newest first.
class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          if (app.activity.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: app.clearActivity,
            ),
        ],
      ),
      body: app.activity.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Nothing yet',
              message: 'Jobs this phone sends and receives show up here.',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: app.activity.length,
              itemBuilder: (context, i) {
                final a = app.activity[i];
                final (icon, color) = switch (a.kind) {
                  ActivityKind.info => (Icons.info_outline, scheme.onSurfaceVariant),
                  ActivityKind.sent => (Icons.north_east, scheme.secondary),
                  ActivityKind.received => (Icons.south_west, scheme.tertiary),
                  ActivityKind.success => (Icons.check_circle_outline, scheme.primary),
                  ActivityKind.error => (Icons.error_outline, scheme.error),
                };
                return ListTile(
                  leading: Icon(icon, color: color),
                  title: Text(a.message),
                  trailing: Text(
                    _clock(a.time),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                );
              },
            ),
    );
  }

  static String _clock(DateTime t) =>
      [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');
}
