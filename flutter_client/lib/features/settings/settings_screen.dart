import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType;
import 'package:m3u_tv/features/settings/sections/connected_view.dart';
import 'package:m3u_tv/features/settings/sections/connection_section.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/introdb_settings.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.authNotifier,
    required this.traktService,
    this.devicePairingService,
    this.activeViewer,
    this.viewers = const [],
    this.sourceLabel,
    this.serverTimezone,
    this.sourceError,
    this.isConfiguredOverride,
    this.epgRefreshInterval,
    this.epgRefreshOptions = const [],
    this.onConnect,
    this.onDisconnect,
    this.onSwitchViewer,
    this.onCreateViewer,
    this.onClearCache,
    this.onEpgIntervalChanged,
    this.loadDiagnosticsHeader,
    this.onUploadLogs,
    this.onConnected,
    this.locale,
    this.onLocaleChanged,
    this.proxyPlaybackSettings,
    this.comskipSettings,
    this.introDbSettings,
    this.viewSettingsService,
    this.deviceType,
    this.onHandleTopLevelBack,
  });

  final AuthNotifier authNotifier;
  final TraktService traktService;
  final DevicePairingService? devicePairingService;

  /// Used to decide whether the pairing URL should be a tappable link with an
  /// "open in browser" affordance (every non-TV device) or plain text (TV).
  final DeviceType? deviceType;
  final ProxyPlaybackSettings? proxyPlaybackSettings;
  final ComskipSettings? comskipSettings;
  final IntroDbSettings? introDbSettings;
  final ViewSettingsService? viewSettingsService;
  final Viewer? activeViewer;
  final List<Viewer> viewers;
  final String? sourceLabel;
  final String? serverTimezone;
  final String? sourceError;
  final bool? isConfiguredOverride;
  final Future<bool> Function(UserCredentials credentials)? onConnect;
  final VoidCallback? onDisconnect;
  final void Function(Viewer viewer)? onSwitchViewer;
  final Future<Viewer?> Function(String name)? onCreateViewer;
  final Duration? epgRefreshInterval;
  final List<Duration> epgRefreshOptions;
  final ValueChanged<CacheClearScope>? onClearCache;
  final void Function(Duration interval)? onEpgIntervalChanged;

  /// Logs & Diagnostics (Settings > General > App): builds the device header,
  /// and uploads a report to the editor returning the stored upload's id.
  /// The row is hidden when [loadDiagnosticsHeader] is null.
  final Future<String> Function()? loadDiagnosticsHeader;
  final Future<int> Function(String report)? onUploadLogs;

  /// Called after a successful connection so the parent can navigate to Home.
  final VoidCallback? onConnected;
  final Locale? locale;
  final void Function(Locale?)? onLocaleChanged;

  /// Pops the topmost immersive settings sub-page pushed on the root
  /// Navigator, deduping Android TV's two hardware-Back delivery paths (see
  /// `AppShellState.handleBackFromTopLevelRoute` and `settings_ui.dart`'s
  /// `_withTopLevelBackHandling`).
  final bool Function()? onHandleTopLevelBack;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isConnecting = false;
  String? _connectionError;
  UserCredentials? _lastCredentials;

  Future<void> _handleConnect(UserCredentials credentials) async {
    _lastCredentials = credentials;
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    bool success;
    final onConnect = widget.onConnect;
    if (onConnect != null) {
      success = await onConnect(credentials);
    } else {
      success = await widget.authNotifier.connect(credentials);
    }

    if (!mounted) return;

    if (success) {
      setState(() => _isConnecting = false);
      widget.onConnected?.call();
    } else {
      setState(() {
        _isConnecting = false;
        _connectionError =
            widget.sourceError ??
            widget.authNotifier.error ??
            AppLocalizations.of(context).settingsConnectionFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return const _ConnectingScreen();
    }

    final isConfigured =
        widget.isConfiguredOverride ?? widget.authNotifier.isConfigured;

    if (!isConfigured) {
      return Scaffold(
        body: ConnectionFormBody(
          onConnect: _handleConnect,
          initialValues: _lastCredentials,
          error:
              _connectionError ??
              widget.sourceError ??
              widget.authNotifier.error,
          devicePairingService: widget.devicePairingService,
          deviceType: widget.deviceType,
        ),
      );
    }

    return Scaffold(
      body: ConnectedView(
        authNotifier: widget.authNotifier,
        traktService: widget.traktService,
        activeViewer: widget.activeViewer,
        viewers: widget.viewers,
        sourceLabel: widget.sourceLabel,
        serverTimezone: widget.serverTimezone,
        sourceError: widget.sourceError,
        epgRefreshInterval: widget.epgRefreshInterval,
        epgRefreshOptions: widget.epgRefreshOptions,
        onDisconnect:
            widget.onDisconnect ?? () => widget.authNotifier.disconnect(),
        onSwitchViewer: widget.onSwitchViewer,
        onCreateViewer: widget.onCreateViewer,
        onClearCache: widget.onClearCache,
        onEpgIntervalChanged: widget.onEpgIntervalChanged,
        loadDiagnosticsHeader: widget.loadDiagnosticsHeader,
        onUploadLogs: widget.onUploadLogs,
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
        proxyPlaybackSettings: widget.proxyPlaybackSettings,
        comskipSettings: widget.comskipSettings,
        introDbSettings: widget.introDbSettings,
        viewSettingsService: widget.viewSettingsService,
        deviceType: widget.deviceType,
        onHandleTopLevelBack: widget.onHandleTopLevelBack,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connecting interstitial
// ---------------------------------------------------------------------------

class _ConnectingScreen extends StatelessWidget {
  const _ConnectingScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).settingsConnecting,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).settingsConnectingSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
