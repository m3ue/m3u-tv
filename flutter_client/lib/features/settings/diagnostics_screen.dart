import 'package:flutter/material.dart';

import 'package:m3u_tv/features/settings/backend_capabilities.dart';

/// Diagnostics screen showing backend capabilities and transcode server status.
///
/// Does NOT expose secrets (passwords, credentials) in the UI.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key, required this.capabilities});

  /// Backend capabilities to display. Null means not connected.
  final BackendCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (capabilities == null) {
      return Center(
        child: Text('Not connected', style: theme.textTheme.bodyLarge),
      );
    }

    final cap = capabilities!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Backend Capabilities', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          _CapabilityRow(label: 'm3u-editor Version', value: cap.m3uEditorVersion),
          const SizedBox(height: 8),
          Text('Features', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          ...cap.features.map((f) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(f, style: theme.textTheme.bodyMedium),
              ],
            ),
          )),
          const SizedBox(height: 24),
          Text('Transcode Server', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                cap.transcodeAvailable ? Icons.cloud_done : Icons.cloud_off,
                color: cap.transcodeAvailable ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                cap.transcodeAvailable ? 'Available' : 'Unavailable',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cap.transcodeAvailable ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        )),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}