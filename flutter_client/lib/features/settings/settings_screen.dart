import 'package:flutter/material.dart';

import 'package:m3u_tv/features/settings/connection_form.dart';
import 'package:m3u_tv/features/settings/viewer_selector.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Settings screen mirroring the RN SettingsScreen behavior.
///
/// Shows the connection form when not configured, and connection status,
/// viewer section, cache section, and disconnect button when configured.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.authNotifier,
    this.activeViewer,
    this.sourceLabel,
    this.sourceError,
    this.isConfiguredOverride,
    this.onConnect,
    this.onDisconnect,
  });

  /// Auth state notifier providing connection status.
  final AuthNotifier authNotifier;

  /// Currently active viewer (null if not connected or no viewer).
  final Viewer? activeViewer;

  final String? sourceLabel;
  final String? sourceError;
  final bool? isConfiguredOverride;
  final Future<bool> Function(UserCredentials credentials)? onConnect;

  /// Called when the user taps Disconnect.
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final isConfigured = isConfiguredOverride ?? authNotifier.isConfigured;
    if (!isConfigured) {
      return ConnectionForm(
        onConnect:
            onConnect ?? (credentials) => authNotifier.connect(credentials),
        isLoading: authNotifier.isLoading,
        error: sourceError ?? authNotifier.error,
      );
    }

    return _ConnectedView(
      authNotifier: authNotifier,
      activeViewer: activeViewer,
      sourceLabel: sourceLabel,
      sourceError: sourceError,
      onDisconnect: onDisconnect ?? () => authNotifier.disconnect(),
    );
  }
}

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({
    required this.authNotifier,
    this.activeViewer,
    this.sourceLabel,
    this.sourceError,
    required this.onDisconnect,
  });

  final AuthNotifier authNotifier;
  final Viewer? activeViewer;
  final String? sourceLabel;
  final String? sourceError;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = authNotifier.authResponse;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome section
          Text('Welcome to M3U TV', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Your streaming server is connected',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Connection status card
          Text('Connection Status', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const _StatusRow(
                    label: 'Status',
                    value: 'Connected',
                    valueColor: Colors.green,
                  ),
                  if (sourceLabel != null) ...[
                    const Divider(),
                    _StatusRow(label: 'Source', value: sourceLabel!),
                  ],
                  if (auth != null) ...[
                    const Divider(),
                    _StatusRow(
                      label: 'm3u-editor',
                      value: auth.m3uEditorVersion ?? 'Unknown',
                    ),
                  ],
                  if (sourceError != null && sourceError!.isNotEmpty) ...[
                    const Divider(),
                    _StatusRow(
                      label: 'Last source error',
                      value: sourceError!,
                      valueColor: theme.colorScheme.error,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Viewer section (only when m3u-editor and viewer available)
          if (activeViewer != null) ...[
            ViewerSelector(
              viewers: [activeViewer!],
              activeViewer: activeViewer!,
              onSwitch: (_) {},
            ),
            const SizedBox(height: 24),
          ],

          // Cache section
          Text('Content Cache', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Cached content loads instantly. Data refreshes automatically in the background.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Disconnect button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onDisconnect,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              child: const Text('Disconnect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
