import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/domain_models.dart';

// M3 buttons and chips use StadiumBorder. A large radius makes the dpad
// focus border match the pill shape regardless of widget height.
const _kStadiumEffect = [
  DpadBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.authNotifier,
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

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({
    required this.authNotifier,
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

  void _openViewerManagement(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => _ViewerManagementDialog(
          viewers: viewers.isNotEmpty ? viewers : [activeViewer!],
          activeViewer: activeViewer!,
          onSwitch: onSwitchViewer ?? (_) {},
          onCreateViewer: onCreateViewer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = authNotifier.authResponse;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 24),

          // ── Connection ────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Connection',
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
                    label: 'Last error',
                    value: sourceError!,
                    valueColor: theme.colorScheme.error,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Viewer ────────────────────────────────────────────────────────
          if (activeViewer != null) ...[
            _SettingsSection(
              title: 'Active Viewer',
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(
                      activeViewer!.name.isNotEmpty
                          ? activeViewer!.name[0].toUpperCase()
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
                          activeViewer!.name,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (activeViewer!.isAdmin)
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

          // ── Cache ─────────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Content Cache',
            subtitle:
                'Cached content loads instantly. Data refreshes automatically in the background.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (epgRefreshOptions.isNotEmpty &&
                    epgRefreshInterval != null) ...[
                  Text(
                    'EPG refresh interval',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: epgRefreshOptions.map((d) {
                      return _IntervalChip(
                        label: _intervalLabel(d),
                        isSelected: d == epgRefreshInterval,
                        onTap: () => onEpgIntervalChanged?.call(d),
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
                    autofocus: epgRefreshOptions.isEmpty,
                    onSelect: onClearCache,
                    effects: _kStadiumEffect,
                    child: FilledButton.tonalIcon(
                      onPressed: onClearCache,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Clear Cache & Refresh'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Account ───────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Account',
            child: SizedBox(
              width: double.infinity,
              child: DpadFocusable(
                onSelect: onDisconnect,
                effects: _kStadiumEffect,
                child: FilledButton(
                  onPressed: onDisconnect,
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
      ),
    );
  }
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
                  // ── Add viewer form ──────────────────────────────────────
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
                  // ── Active viewer ────────────────────────────────────────
                  Text(
                    'Active Viewer',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ViewerRow(viewer: widget.activeViewer, isActive: true),

                  // ── Switch viewer list ───────────────────────────────────
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

                  // ── Add new viewer ───────────────────────────────────────
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
    DpadBorderEffect(borderRadius: BorderRadius.all(Radius.circular(_radius))),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadFocusable(
      onSelect: onTap,
      effects: _effects,
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_radius),
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
