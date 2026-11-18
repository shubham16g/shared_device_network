import 'package:flutter/material.dart';

/// Large rounded card that says, in one sentence, what state something is in.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.active = false,
    this.trailing,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool active;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final fg = active ? scheme.onPrimaryContainer : scheme.onSurface;
    return Card(
      color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: active ? scheme.primary : scheme.surfaceContainerHighest,
                  foregroundColor: active ? scheme.onPrimary : scheme.onSurfaceVariant,
                  child: Icon(icon),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: text.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            Text(message, style: text.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.8))),
            if (footer != null) ...[const SizedBox(height: 16), footer!],
          ],
        ),
      ),
    );
  }
}

/// Friendly placeholder for an empty list: what is missing and what to do.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 56, color: scheme.outline),
          const SizedBox(height: 16),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            message,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 10),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 8)],
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// A card holding list tiles separated by thin dividers.
class CardList extends StatelessWidget {
  const CardList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 72),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Icon for a device, picked from the capabilities it advertises.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar(this.capabilities, {super.key});

  final List<String> capabilities;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Icon(
        capabilities.contains('print')
            ? Icons.print_outlined
            : capabilities.contains('scan')
                ? Icons.qr_code_scanner
                : Icons.developer_board_outlined,
      ),
    );
  }
}
