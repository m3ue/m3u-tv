import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// M3 buttons and chips use StadiumBorder. A large radius makes the dpad
// focus border match the pill shape regardless of widget height.
const _kStadiumEffect = [
  GradientBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.authNotifier,
    required this.traktService,
    this.activeViewer,
    this.viewers = const [],
    this.sourceLabel,
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
    this.onConnected,
  });

  final AuthNotifier authNotifier;
  final TraktService traktService;
  final Viewer? activeViewer;
  final List<Viewer> viewers;
  final String? sourceLabel;
  final String? sourceError;
  final bool? isConfiguredOverride;
  final Future<bool> Function(UserCredentials credentials)? onConnect;
  final VoidCallback? onDisconnect;
  final void Function(Viewer viewer)? onSwitchViewer;
  final Future<Viewer?> Function(String name)? onCreateViewer;
  final Duration? epgRefreshInterval;
  final List<Duration> epgRefreshOptions;
  final VoidCallback? onClearCache;
  final void Function(Duration interval)? onEpgIntervalChanged;

  /// Called after a successful connection so the parent can navigate to Home.
  final VoidCallback? onConnected;

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
            'Connection failed. Please check your credentials.';
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
        body: _ConnectionFormBody(
          onConnect: _handleConnect,
          initialValues: _lastCredentials,
          error:
              _connectionError ??
              widget.sourceError ??
              widget.authNotifier.error,
        ),
      );
    }

    return Scaffold(
      body: _ConnectedView(
        authNotifier: widget.authNotifier,
        traktService: widget.traktService,
        activeViewer: widget.activeViewer,
        viewers: widget.viewers,
        sourceLabel: widget.sourceLabel,
        sourceError: widget.sourceError,
        epgRefreshInterval: widget.epgRefreshInterval,
        epgRefreshOptions: widget.epgRefreshOptions,
        onDisconnect:
            widget.onDisconnect ?? () => widget.authNotifier.disconnect(),
        onSwitchViewer: widget.onSwitchViewer,
        onCreateViewer: widget.onCreateViewer,
        onClearCache: widget.onClearCache,
        onEpgIntervalChanged: widget.onEpgIntervalChanged,
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
            Text('Connecting...', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Please wait while we connect to your service',
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

// ---------------------------------------------------------------------------
// Connection form
// ---------------------------------------------------------------------------

class _ConnectionFormBody extends StatefulWidget {
  const _ConnectionFormBody({
    required this.onConnect,
    this.initialValues,
    this.error,
  });

  final Future<void> Function(UserCredentials credentials) onConnect;
  final UserCredentials? initialValues;
  final String? error;

  @override
  State<_ConnectionFormBody> createState() => _ConnectionFormBodyState();
}

class _ConnectionFormBodyState extends State<_ConnectionFormBody> {
  late final _serverController = TextEditingController(
    text: widget.initialValues?.server,
  );
  late final _usernameController = TextEditingController(
    text: widget.initialValues?.username,
  );
  late final _passwordController = TextEditingController(
    text: widget.initialValues?.password,
  );
  String? _validationError;

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleConnect() {
    final server = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _validationError = 'Please fill in all fields');
      return;
    }
    setState(() => _validationError = null);
    unawaited(
      widget.onConnect(
        UserCredentials(server: server, username: username, password: password),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayError = _validationError ?? widget.error;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connection Settings', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Enter your Xtream codes details',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (displayError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                displayError,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          TextFormField(
            controller: _serverController,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://example.com:8080',
            ),
            autocorrect: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
            autocorrect: false,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleConnect(),
          ),
          const SizedBox(height: 24),
          DpadFocusable(
            autofocus: true,
            onSelect: _handleConnect,
            effects: _kStadiumEffect,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _handleConnect,
                child: const Text('Connect'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connected settings view
// ---------------------------------------------------------------------------

class _ConnectedView extends StatefulWidget {
  const _ConnectedView({
    required this.authNotifier,
    required this.traktService,
    this.activeViewer,
    this.viewers = const [],
    this.sourceLabel,
    this.sourceError,
    this.epgRefreshInterval,
    this.epgRefreshOptions = const [],
    required this.onDisconnect,
    this.onSwitchViewer,
    this.onCreateViewer,
    this.onClearCache,
    this.onEpgIntervalChanged,
  });

  final AuthNotifier authNotifier;
  final TraktService traktService;
  final Viewer? activeViewer;
  final List<Viewer> viewers;
  final String? sourceLabel;
  final String? sourceError;
  final Duration? epgRefreshInterval;
  final List<Duration> epgRefreshOptions;
  final VoidCallback onDisconnect;
  final void Function(Viewer viewer)? onSwitchViewer;
  final Future<Viewer?> Function(String name)? onCreateViewer;
  final VoidCallback? onClearCache;
  final void Function(Duration interval)? onEpgIntervalChanged;

  @override
  State<_ConnectedView> createState() => _ConnectedViewState();
}

class _ConnectedViewState extends State<_ConnectedView>
    with SingleTickerProviderStateMixin {
  late final _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openViewerManagement(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => _ViewerManagementDialog(
          viewers: widget.viewers.isNotEmpty
              ? widget.viewers
              : [widget.activeViewer!],
          activeViewer: widget.activeViewer!,
          onSwitch: widget.onSwitchViewer ?? (_) {},
          onCreateViewer: widget.onCreateViewer,
        ),
      ),
    );
  }

  Future<void> _handleClearCache() async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Clear Cache & Refresh?',
      message:
          'All cached content will be cleared and reloaded from your source.',
      confirmLabel: 'Clear & Refresh',
    );
    if (!confirmed || !mounted) return;
    widget.onClearCache?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Cache cleared — content is refreshing in the background.',
        ),
      ),
    );
  }

  Future<void> _handleDisconnect() async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Disconnect?',
      message:
          'You will be signed out and will need to re-enter your credentials to reconnect.',
      confirmLabel: 'Disconnect',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    widget.onDisconnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Text('Settings', style: theme.textTheme.headlineMedium),
        ),
        DpadTabBar(
          controller: _tabController,
          tabs: const ['General', 'Integrations'],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildGeneralTab(context),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildIntegrationsTab(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralTab(BuildContext context) {
    final theme = Theme.of(context);
    final auth = widget.authNotifier.authResponse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Connection ──────────────────────────────────────────────────────
        _SettingsSection(
          title: 'Connection',
          child: Column(
            children: [
              _StatusRow(
                label: 'Status',
                value:
                    widget.sourceError != null && widget.sourceError!.isNotEmpty
                    ? 'Unavailable'
                    : 'Connected',
                valueColor:
                    widget.sourceError != null && widget.sourceError!.isNotEmpty
                    ? Colors.orange
                    : Colors.green,
              ),
              if (widget.sourceLabel != null) ...[
                const Divider(),
                _StatusRow(label: 'Source', value: widget.sourceLabel!),
              ],
              if (auth != null) ...[
                const Divider(),
                _StatusRow(
                  label: 'm3u-editor',
                  value: auth.m3uEditorVersion ?? 'Unknown',
                ),
              ],
              if (widget.sourceError != null &&
                  widget.sourceError!.isNotEmpty) ...[
                const Divider(),
                _StatusRow(
                  label: 'Last error',
                  value: widget.sourceError!,
                  valueColor: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: DpadFocusable(
                    autofocus: true,
                    onSelect: widget.onClearCache,
                    effects: _kStadiumEffect,
                    child: FilledButton.tonalIcon(
                      onPressed: widget.onClearCache,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry connection'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: DpadFocusable(
                    onSelect: _handleDisconnect,
                    effects: _kStadiumEffect,
                    child: FilledButton.tonalIcon(
                      onPressed: _handleDisconnect,
                      icon: const Icon(Icons.settings),
                      label: const Text('Edit server settings'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Viewer ──────────────────────────────────────────────────────────
        if (widget.activeViewer != null) ...[
          _SettingsSection(
            title: 'Active Viewer',
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    widget.activeViewer!.name.isNotEmpty
                        ? widget.activeViewer!.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(color: theme.colorScheme.onPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.activeViewer!.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (widget.activeViewer!.isAdmin)
                        Text(
                          'Admin',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                DpadFocusable(
                  onSelect: () => _openViewerManagement(context),
                  effects: _kStadiumEffect,
                  child: FilledButton.tonal(
                    onPressed: () => _openViewerManagement(context),
                    child: const Text('Manage Viewers'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Cache ────────────────────────────────────────────────────────────
        _SettingsSection(
          title: 'Content Cache',
          subtitle:
              'Cached content loads instantly. Data refreshes automatically in the background.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.epgRefreshOptions.isNotEmpty &&
                  widget.epgRefreshInterval != null) ...[
                Text(
                  'EPG refresh interval',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: widget.epgRefreshOptions.map((d) {
                    return _IntervalChip(
                      label: _intervalLabel(d),
                      isSelected: d == widget.epgRefreshInterval,
                      onTap: () => widget.onEpgIntervalChanged?.call(d),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: DpadFocusable(
                  autofocus: widget.epgRefreshOptions.isEmpty,
                  onSelect: _handleClearCache,
                  effects: _kStadiumEffect,
                  child: FilledButton.tonalIcon(
                    onPressed: _handleClearCache,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Clear Cache & Refresh'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Account ──────────────────────────────────────────────────────────
        _SettingsSection(
          title: 'Account',
          child: SizedBox(
            width: double.infinity,
            child: DpadFocusable(
              onSelect: _handleDisconnect,
              effects: _kStadiumEffect,
              child: FilledButton(
                onPressed: _handleDisconnect,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                child: const Text('Disconnect'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrationsTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSection(
          title: 'Watch History',
          subtitle:
              'Sync your watch history with Trakt to track progress across apps and services.',
          child: ListenableBuilder(
            listenable: widget.traktService,
            builder: (context, _) =>
                _TraktCard(traktService: widget.traktService),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Trakt integration card
// ---------------------------------------------------------------------------

class _TraktCard extends StatelessWidget {
  const _TraktCard({required this.traktService});

  final TraktService traktService;

  static Widget get _logo => SvgPicture.asset(
    'assets/icons/trakt-logo.svg',
    height: 40,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = !traktService.isConfigured
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trakt client credentials are not configured.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Register an app at trakt.tv/oauth/applications and set the '
                'client ID and secret via --dart-define at build time.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          )
        : switch (traktService.status) {
            TraktAuthStatus.disconnected => _TraktDisconnected(
              traktService: traktService,
            ),
            TraktAuthStatus.pending => _TraktPending(
              traktService: traktService,
            ),
            TraktAuthStatus.connected => _TraktConnected(
              traktService: traktService,
            ),
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _logo,
        const SizedBox(height: 16),
        body,
      ],
    );
  }
}

class _TraktDisconnected extends StatelessWidget {
  const _TraktDisconnected({required this.traktService});

  final TraktService traktService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect your Trakt account to automatically track what you watch.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: DpadFocusable(
            autofocus: true,
            onSelect: traktService.startDeviceAuth,
            effects: _kStadiumEffect,
            child: FilledButton.icon(
              onPressed: traktService.startDeviceAuth,
              icon: const Icon(Icons.link),
              label: const Text('Connect with Trakt'),
            ),
          ),
        ),
      ],
    );
  }
}

class _TraktPending extends StatelessWidget {
  const _TraktPending({required this.traktService});

  final TraktService traktService;

  @override
  Widget build(BuildContext context) {
    final pending = traktService.pending;
    final url = pending?.verificationUrl ?? 'https://trakt.tv/activate';
    final userCode = pending?.userCode ?? '––––––';

    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 600
          ? _TraktPendingWide(
              url: url,
              userCode: userCode,
              onCancel: traktService.cancelAuth,
            )
          : _TraktPendingNarrow(
              url: url,
              userCode: userCode,
              onCancel: traktService.cancelAuth,
            ),
    );
  }
}

class _TraktPendingWide extends StatelessWidget {
  const _TraktPendingWide({
    required this.url,
    required this.userCode,
    required this.onCancel,
  });

  final String url;
  final String userCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _TraktPendingInstructions(url: url, userCode: userCode),
        ),
        const SizedBox(width: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: QrImageView(
                data: url,
                size: 140,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scan to open on your phone',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            DpadFocusable(
              autofocus: true,
              onSelect: onCancel,
              effects: _kStadiumEffect,
              child: FilledButton.tonal(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TraktPendingNarrow extends StatelessWidget {
  const _TraktPendingNarrow({
    required this.url,
    required this.userCode,
    required this.onCancel,
  });

  final String url;
  final String userCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TraktPendingInstructions(
          url: url,
          userCode: userCode,
          urlTappable: true,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () => launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open in browser'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

class _TraktPendingInstructions extends StatelessWidget {
  const _TraktPendingInstructions({
    required this.url,
    required this.userCode,
    this.urlTappable = false,
  });

  final String url;
  final String userCode;
  final bool urlTappable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urlStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
      decoration: urlTappable ? TextDecoration.underline : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'On your phone or computer, go to:',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        if (urlTappable)
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(url, style: urlStyle),
          )
        else
          Text(url, style: urlStyle),
        const SizedBox(height: 16),
        Text('Then enter this code:', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            userCode,
            style: theme.textTheme.displaySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Waiting for authorization…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TraktConnected extends StatelessWidget {
  const _TraktConnected({required this.traktService});

  final TraktService traktService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.check_circle, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Connected to Trakt',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        DpadFocusable(
          autofocus: true,
          onSelect: traktService.disconnect,
          effects: _kStadiumEffect,
          child: FilledButton.tonal(
            onPressed: traktService.disconnect,
            child: const Text('Disconnect Trakt'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Confirm dialog helper
// ---------------------------------------------------------------------------

Future<bool> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool isDestructive = false,
}) async {
  final theme = Theme.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 480,
        child: DpadRegion(
          memoryKey: 'confirm-dialog',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(message, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    DpadFocusable(
                      onSelect: () => Navigator.pop(ctx, false),
                      effects: _kStadiumEffect,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DpadFocusable(
                      autofocus: true,
                      onSelect: () => Navigator.pop(ctx, true),
                      effects: _kStadiumEffect,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: isDestructive
                            ? FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                                foregroundColor: theme.colorScheme.onError,
                              )
                            : null,
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Viewer management dialog
// ---------------------------------------------------------------------------

class _ViewerManagementDialog extends StatefulWidget {
  const _ViewerManagementDialog({
    required this.viewers,
    required this.activeViewer,
    required this.onSwitch,
    this.onCreateViewer,
  });

  final List<Viewer> viewers;
  final Viewer activeViewer;
  final void Function(Viewer viewer) onSwitch;
  final Future<Viewer?> Function(String name)? onCreateViewer;

  @override
  State<_ViewerManagementDialog> createState() =>
      _ViewerManagementDialogState();
}

class _ViewerManagementDialogState extends State<_ViewerManagementDialog> {
  bool _showAddForm = false;
  final _nameController = TextEditingController();
  bool _isCreating = false;
  String? _createError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || widget.onCreateViewer == null) return;
    setState(() {
      _isCreating = true;
      _createError = null;
    });
    final viewer = await widget.onCreateViewer!(name);
    if (!mounted) return;
    if (viewer != null) {
      widget.onSwitch(viewer);
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isCreating = false;
        _createError = 'Failed to create viewer. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = widget.viewers
        .where((v) => v.ulid != widget.activeViewer.ulid)
        .toList();

    return Dialog(
      child: SizedBox(
        width: 520,
        child: DpadRegion(
          memoryKey: 'viewer-management',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header row
                Row(
                  children: [
                    Text(
                      _showAddForm ? 'Add New Viewer' : 'Manage Viewers',
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    DpadFocusable(
                      onSelect: () => Navigator.of(context).pop(),
                      effects: _kStadiumEffect,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_showAddForm) ...[
                  // ── Add viewer form ────────────────────────────────────────
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Viewer name',
                      errorText: _createError,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleCreate(),
                    enabled: !_isCreating,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      DpadFocusable(
                        onSelect: () => setState(() {
                          _showAddForm = false;
                          _nameController.clear();
                          _createError = null;
                        }),
                        effects: _kStadiumEffect,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _showAddForm = false;
                            _nameController.clear();
                            _createError = null;
                          }),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DpadFocusable(
                        onSelect: _isCreating ? null : _handleCreate,
                        effects: _kStadiumEffect,
                        child: FilledButton(
                          onPressed: _isCreating ? null : _handleCreate,
                          child: _isCreating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Create'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // ── Active viewer ──────────────────────────────────────────
                  Text(
                    'Active Viewer',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ViewerRow(viewer: widget.activeViewer, isActive: true),

                  // ── Switch viewer list ─────────────────────────────────────
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Switch Viewer',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: others.length,
                        itemBuilder: (context, index) {
                          final viewer = others[index];
                          return DpadFocusable(
                            autofocus: index == 0,
                            onSelect: () {
                              widget.onSwitch(viewer);
                              Navigator.of(context).pop();
                            },
                            child: _ViewerRow(
                              viewer: viewer,
                              onTap: () {
                                widget.onSwitch(viewer);
                                Navigator.of(context).pop();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // ── Add new viewer ─────────────────────────────────────────
                  if (widget.onCreateViewer != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    DpadFocusable(
                      autofocus: others.isEmpty,
                      onSelect: () => setState(() => _showAddForm = true),
                      effects: _kStadiumEffect,
                      child: FilledButton.icon(
                        onPressed: () => setState(() => _showAddForm = true),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Add New Viewer'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({required this.viewer, this.isActive = false, this.onTap});

  final Viewer viewer;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: isActive ? theme.colorScheme.primary : null,
        child: Text(
          viewer.name.isNotEmpty ? viewer.name[0].toUpperCase() : '?',
          style: isActive
              ? TextStyle(color: theme.colorScheme.onPrimary)
              : null,
        ),
      ),
      title: Text(viewer.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (viewer.isAdmin)
            Text(
              'Admin',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          if (isActive) ...[
            if (viewer.isAdmin) const SizedBox(width: 8),
            Icon(
              Icons.check_circle,
              size: 16,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared section layout
// ---------------------------------------------------------------------------

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Card(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ],
    );
  }
}

class _IntervalChip extends StatelessWidget {
  const _IntervalChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  static const double _radius = 20;
  static const _effects = [
    GradientBorderEffect(
      borderRadius: BorderRadius.all(Radius.circular(_radius)),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(_radius));
    return DpadInkWell(
      onTap: onTap,
      effects: _effects,
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: radius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(
                Icons.check,
                size: 16,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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

String _intervalLabel(Duration d) {
  if (d.inHours >= 1) {
    final h = d.inHours;
    return h == 1 ? '1 hour' : '$h hours';
  }
  return '${d.inMinutes} min';
}
