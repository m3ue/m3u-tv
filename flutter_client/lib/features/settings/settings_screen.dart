import 'dart:async';
import 'dart:io' show Platform;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType;
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_callout.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.onConnected,
    this.locale,
    this.onLocaleChanged,
    this.proxyPlaybackSettings,
    this.comskipSettings,
    this.viewSettingsService,
    this.deviceType,
  });

  final AuthNotifier authNotifier;
  final TraktService traktService;
  final DevicePairingService? devicePairingService;

  /// Used to decide whether the pairing URL should be a tappable link with an
  /// "open in browser" affordance (every non-TV device) or plain text (TV).
  final DeviceType? deviceType;
  final ProxyPlaybackSettings? proxyPlaybackSettings;
  final ComskipSettings? comskipSettings;
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
  final VoidCallback? onClearCache;
  final void Function(Duration interval)? onEpgIntervalChanged;

  /// Called after a successful connection so the parent can navigate to Home.
  final VoidCallback? onConnected;
  final Locale? locale;
  final void Function(Locale?)? onLocaleChanged;

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
          devicePairingService: widget.devicePairingService,
          deviceType: widget.deviceType,
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
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
        proxyPlaybackSettings: widget.proxyPlaybackSettings,
        comskipSettings: widget.comskipSettings,
        viewSettingsService: widget.viewSettingsService,
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
    this.devicePairingService,
    this.deviceType,
  });

  final Future<void> Function(UserCredentials credentials) onConnect;
  final UserCredentials? initialValues;
  final String? error;
  final DevicePairingService? devicePairingService;
  final DeviceType? deviceType;

  @override
  State<_ConnectionFormBody> createState() => _ConnectionFormBodyState();
}

class _ConnectionFormBodyState extends State<_ConnectionFormBody>
    with SingleTickerProviderStateMixin {
  late final _serverController = TextEditingController(
    text: widget.initialValues?.server,
  );
  late final _usernameController = TextEditingController(
    text: widget.initialValues?.username,
  );
  late final _passwordController = TextEditingController(
    text: widget.initialValues?.password,
  );
  late final TabController _tabController;
  String? _validationError;
  bool _pairing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.devicePairingService?.addListener(_onPairingChanged);
  }

  @override
  void dispose() {
    widget.devicePairingService?.removeListener(_onPairingChanged);
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onPairingChanged() {
    final service = widget.devicePairingService;
    if (service == null) return;
    if (service.status == DevicePairingStatus.approved) {
      final result = service.result;
      if (result != null) unawaited(widget.onConnect(result));
      return;
    }
    setState(() {});
  }

  void _handleConnect() {
    final server = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      setState(
        () => _validationError = AppLocalizations.of(
          context,
        ).settingsFillAllFields,
      );
      return;
    }
    setState(() => _validationError = null);
    unawaited(
      widget.onConnect(
        UserCredentials(server: server, username: username, password: password),
      ),
    );
  }

  void _handlePairWithCode() {
    final server = _serverController.text.trim();
    if (server.isEmpty) {
      setState(
        () => _validationError = AppLocalizations.of(
          context,
        ).pairingEnterServerFirst,
      );
      return;
    }
    setState(() {
      _validationError = null;
      _pairing = true;
    });
    unawaited(widget.devicePairingService!.start(server));
  }

  void _cancelPairing() {
    widget.devicePairingService?.cancel();
    setState(() => _pairing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final service = widget.devicePairingService;
    if (_pairing &&
        service != null &&
        service.status != DevicePairingStatus.idle) {
      return DpadRegion(
        memoryKey: 'device-pairing',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: _DevicePairingBody(
            service: service,
            onCancel: _cancelPairing,
            linksAreTappable: widget.deviceType != DeviceType.tv,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final displayError = _validationError ?? widget.error;

    if (service == null) {
      // No pairing service available — a single manual sign-in form, same
      // as before device pairing existed.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.settingsConnectionSettings,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l.settingsConnectionSettingsSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _buildError(theme, displayError),
            _buildCredentialHelp(theme, l),
            ..._buildSignInFields(l, autofocusServer: true),
          ],
        ),
      );
    }

    return Column(
      children: [
        DpadTabBar(
          controller: _tabController,
          tabs: [l.settingsTabPair, l.settingsTabSignIn],
        ),
        Expanded(
          child: DpadTabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.settingsConnectionSettings,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.settingsPairTabSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildError(theme, displayError),
                    TextFormField(
                      controller: _serverController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: l.settingsServerUrl,
                        hintText: 'example.com:8080',
                      ),
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handlePairWithCode(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        variant: AppButtonVariant.primaryInverted,
                        icon: Icons.qr_code,
                        label: l.settingsPairWithCode,
                        onPressed: _handlePairWithCode,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.settingsConnectionSettings,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.settingsConnectionSettingsSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildError(theme, displayError),
                    _buildCredentialHelp(theme, l),
                    ..._buildSignInFields(l, autofocusServer: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme, String? displayError) {
    if (displayError == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        displayError,
        style: TextStyle(color: theme.colorScheme.error),
      ),
    );
  }

  Widget _buildCredentialHelp(ThemeData theme, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCallout(message: l.settingsConnectionSettingsHelp),
    );
  }

  List<Widget> _buildSignInFields(
    AppLocalizations l, {
    required bool autofocusServer,
  }) {
    return [
      TextFormField(
        controller: _serverController,
        autofocus: autofocusServer,
        decoration: InputDecoration(
          labelText: l.settingsServerUrl,
          hintText: 'example.com:8080',
        ),
        autocorrect: false,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _usernameController,
        decoration: InputDecoration(labelText: l.settingsUsername),
        autocorrect: false,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        decoration: InputDecoration(labelText: l.settingsPassword),
        obscureText: true,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _handleConnect(),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: AppButton(
          variant: AppButtonVariant.primaryInverted,
          label: l.settingsConnect,
          onPressed: _handleConnect,
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Device pairing (Trakt-style device code flow against the user's own server)
// ---------------------------------------------------------------------------

class _DevicePairingBody extends StatelessWidget {
  const _DevicePairingBody({
    required this.service,
    required this.onCancel,
    this.linksAreTappable = true,
  });

  final DevicePairingService service;
  final VoidCallback onCancel;

  /// True on every non-TV device: the pairing URL becomes a real link with an
  /// "open in browser" button, so a server admin setting up the device doesn't
  /// have to retype it. On a TV there's no browser and no pointer, so it stays
  /// plain text next to the QR code.
  final bool linksAreTappable;

  static Widget get _logo =>
      SvgPicture.asset('assets/icons/editor-logo.svg', height: 40);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final Widget body;
    if (service.status == DevicePairingStatus.error) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.pairingErrorGeneric, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          AppButton(autofocus: true, label: l.cancel, onPressed: onCancel),
        ],
      );
    } else {
      final pending = service.pending;
      final uri = pending?.verificationUri ?? '';
      final userCode = pending?.userCode ?? '––––––';

      body = LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 600
            ? _DevicePairingWide(
                uri: uri,
                userCode: userCode,
                onCancel: onCancel,
                linksAreTappable: linksAreTappable,
              )
            : _DevicePairingNarrow(
                uri: uri,
                userCode: userCode,
                onCancel: onCancel,
                linksAreTappable: linksAreTappable,
              ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_logo, const SizedBox(height: 16), body],
        ),
      ),
    );
  }
}

class _DevicePairingWide extends StatelessWidget {
  const _DevicePairingWide({
    required this.uri,
    required this.userCode,
    required this.onCancel,
    this.linksAreTappable = true,
  });

  final String uri;
  final String userCode;
  final VoidCallback onCancel;
  final bool linksAreTappable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DevicePairingInstructions(
                uri: uri,
                userCode: userCode,
                uriTappable: linksAreTappable,
              ),
              if (linksAreTappable && uri.isNotEmpty) ...[
                const SizedBox(height: 16),
                AppButton(
                  icon: Icons.open_in_new,
                  label: l.pairingOpenBrowser,
                  onPressed: () => launchUrl(
                    Uri.parse(uri),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: QrImageView(
                data: uri.isEmpty ? ' ' : uri,
                size: 140,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l.pairingScanQr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            AppButton(
              autofocus: true,
              label: l.cancel,
              onPressed: onCancel,
            ),
          ],
        ),
      ],
    );
  }
}

class _DevicePairingNarrow extends StatelessWidget {
  const _DevicePairingNarrow({
    required this.uri,
    required this.userCode,
    required this.onCancel,
    this.linksAreTappable = true,
  });

  final String uri;
  final String userCode;
  final VoidCallback onCancel;
  final bool linksAreTappable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DevicePairingInstructions(
          uri: uri,
          userCode: userCode,
          uriTappable: linksAreTappable,
        ),
        const SizedBox(height: 20),
        if (linksAreTappable && uri.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: AppButton(
              icon: Icons.open_in_new,
              label: AppLocalizations.of(context).pairingOpenBrowser,
              onPressed: () => launchUrl(
                Uri.parse(uri),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: AppLocalizations.of(context).cancel,
            onPressed: onCancel,
          ),
        ),
      ],
    );
  }
}

class _DevicePairingInstructions extends StatelessWidget {
  const _DevicePairingInstructions({
    required this.uri,
    required this.userCode,
    this.uriTappable = false,
  });

  final String uri;
  final String userCode;
  final bool uriTappable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final uriStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
      decoration: uriTappable ? TextDecoration.underline : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (uri.isNotEmpty) ...[
          Text(l.pairingPendingGoTo, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          if (uriTappable)
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse(uri),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(uri, style: uriStyle),
            )
          else
            Text(uri, style: uriStyle),
          const SizedBox(height: 16),
        ],
        Text(l.pairingPendingEnterCode, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
        const SizedBox(height: 24),
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                l.pairingPendingWaiting,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
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
    this.serverTimezone,
    this.sourceError,
    this.epgRefreshInterval,
    this.epgRefreshOptions = const [],
    required this.onDisconnect,
    this.onSwitchViewer,
    this.onCreateViewer,
    this.onClearCache,
    this.onEpgIntervalChanged,
    this.locale,
    this.onLocaleChanged,
    this.proxyPlaybackSettings,
    this.comskipSettings,
    this.viewSettingsService,
  });

  final AuthNotifier authNotifier;
  final TraktService traktService;
  final ProxyPlaybackSettings? proxyPlaybackSettings;
  final ComskipSettings? comskipSettings;
  final ViewSettingsService? viewSettingsService;
  final Viewer? activeViewer;
  final List<Viewer> viewers;
  final String? sourceLabel;
  final String? serverTimezone;
  final String? sourceError;
  final Duration? epgRefreshInterval;
  final List<Duration> epgRefreshOptions;
  final VoidCallback onDisconnect;
  final void Function(Viewer viewer)? onSwitchViewer;
  final Future<Viewer?> Function(String name)? onCreateViewer;
  final VoidCallback? onClearCache;
  final void Function(Duration interval)? onEpgIntervalChanged;
  final Locale? locale;
  final void Function(Locale?)? onLocaleChanged;

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
    final l = AppLocalizations.of(context);
    final confirmed = await _showConfirmDialog(
      context,
      title: l.settingsClearCacheTitle,
      message: l.settingsClearCacheBody,
      confirmLabel: l.settingsClearCacheConfirm,
    );
    if (!confirmed || !mounted) return;
    widget.onClearCache?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).settingsCacheCleared),
      ),
    );
  }

  Future<void> _handleDisconnect() async {
    final l = AppLocalizations.of(context);
    final confirmed = await _showConfirmDialog(
      context,
      title: l.settingsDisconnectTitle,
      message: l.settingsDisconnectBody,
      confirmLabel: l.settingsDisconnectConfirm,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    widget.onDisconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DpadTabBar(
          controller: _tabController,
          tabs: [
            AppLocalizations.of(context).settingsGeneral,
            AppLocalizations.of(context).settingsIntegrations,
          ],
        ),
        Expanded(
          child: DpadTabBarView(
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
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Language ────────────────────────────────────────────────────────
        _SettingsSection(
          title: l.settingsLanguage,
          child: Wrap(
            spacing: 8,
            children: [
              _LocaleChip(
                label: l.settingsLanguageSystem,
                isSelected: widget.locale == null,
                onTap: () => widget.onLocaleChanged?.call(null),
              ),
              _LocaleChip(
                label: 'English',
                isSelected: widget.locale?.languageCode == 'en',
                onTap: () => widget.onLocaleChanged?.call(const Locale('en')),
              ),
              _LocaleChip(
                label: 'Deutsch',
                isSelected: widget.locale?.languageCode == 'de',
                onTap: () => widget.onLocaleChanged?.call(const Locale('de')),
              ),
              _LocaleChip(
                label: 'Español',
                isSelected: widget.locale?.languageCode == 'es',
                onTap: () => widget.onLocaleChanged?.call(const Locale('es')),
              ),
              _LocaleChip(
                label: 'Français',
                isSelected: widget.locale?.languageCode == 'fr',
                onTap: () => widget.onLocaleChanged?.call(const Locale('fr')),
              ),
              _LocaleChip(
                label: '简体中文',
                isSelected: widget.locale?.languageCode == 'zh',
                onTap: () => widget.onLocaleChanged?.call(const Locale('zh')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _SettingsSection(
          title: l.settingsApp,
          child: const _AppVersionCard(),
        ),
        const SizedBox(height: 20),

        // ── Connection ──────────────────────────────────────────────────────
        _SettingsSection(
          title: l.settingsConnection,
          child: Column(
            children: [
              _StatusRow(
                label: l.settingsStatusLabel,
                value:
                    widget.sourceError != null && widget.sourceError!.isNotEmpty
                    ? l.settingsStatusUnavailable
                    : l.settingsStatusConnected,
                valueColor:
                    widget.sourceError != null && widget.sourceError!.isNotEmpty
                    ? Colors.orange
                    : Colors.green,
              ),
              if (widget.sourceLabel != null) ...[
                const Divider(),
                _StatusRow(
                  label: l.settingsSourceLabel,
                  value: widget.sourceLabel!,
                ),
              ],
              if (widget.serverTimezone != null) ...[
                const Divider(),
                _StatusRow(
                  label: l.settingsServerTimezone,
                  value: widget.serverTimezone!,
                ),
              ],
              if (auth != null) ...[
                const Divider(),
                _StatusRow(
                  label: 'm3u-editor',
                  value: auth.m3uEditorVersion ?? l.unknown,
                ),
              ],
              if (widget.sourceError != null &&
                  widget.sourceError!.isNotEmpty) ...[
                const Divider(),
                _StatusRow(
                  label: l.settingsLastError,
                  value: widget.sourceError!,
                  valueColor: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    autofocus: true,
                    icon: Icons.refresh,
                    label: l.settingsRetryConnection,
                    onPressed: widget.onClearCache,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    icon: Icons.settings,
                    label: l.settingsEditServer,
                    onPressed: _handleDisconnect,
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
            title: l.settingsActiveViewer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                              l.admin,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: AppLocalizations.of(context).settingsManageViewers,
                    onPressed: () => _openViewerManagement(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (widget.viewSettingsService != null) ...[
          _ViewSettingsSection(service: widget.viewSettingsService!),
          const SizedBox(height: 20),
        ],

        // ── Cache ────────────────────────────────────────────────────────────
        _SettingsSection(
          title: l.settingsContentCache,
          subtitle: l.settingsCacheSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.epgRefreshOptions.isNotEmpty &&
                  widget.epgRefreshInterval != null) ...[
                Text(
                  l.settingsEpgRefreshInterval,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: widget.epgRefreshOptions.map((d) {
                    return _IntervalChip(
                      label: _intervalLabel(l, d),
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
                child: AppButton(
                  autofocus: widget.epgRefreshOptions.isEmpty,
                  icon: Icons.refresh,
                  label: l.settingsClearCacheConfirm,
                  onPressed: _handleClearCache,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Proxy playback ───────────────────────────────────────────────────
        if (auth?.proxy != null && widget.proxyPlaybackSettings != null) ...[
          _SettingsSection(
            title: l.settingsProxyPlayback,
            subtitle: l.settingsProxyPlaybackSubtitle,
            child: ListenableBuilder(
              listenable: widget.proxyPlaybackSettings!,
              builder: (context, _) => _ProxyPlaybackControls(
                capability: auth!.proxy!,
                settings: widget.proxyPlaybackSettings!,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── DVR ──────────────────────────────────────────────────────────────
        if (widget.comskipSettings != null) ...[
          _SettingsSection(
            title: l.settingsDvr,
            subtitle: l.settingsDvrSubtitle,
            child: ListenableBuilder(
              listenable: widget.comskipSettings!,
              builder: (context, _) => SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.settingsComskip, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      l.settingsComskipSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _IntervalChip(
                          label: l.settingsComskipAutoSkip,
                          isSelected: widget.comskipSettings!.autoSkipEnabled,
                          onTap: () => unawaited(
                            widget.comskipSettings!.setAutoSkipEnabled(
                              enabled: !widget.comskipSettings!.autoSkipEnabled,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Account ──────────────────────────────────────────────────────────
        _SettingsSection(
          title: l.settingsAccount,
          child: SizedBox(
            width: double.infinity,
            child: AppButton(
              variant: AppButtonVariant.destructive,
              label: l.disconnect,
              onPressed: _handleDisconnect,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIntegrationsTab(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsSection(
          title: l.traktWatchHistory,
          subtitle: l.traktWatchHistorySubtitle,
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
// App version card
// ---------------------------------------------------------------------------

class _AppVersionCard extends StatefulWidget {
  const _AppVersionCard();

  @override
  State<_AppVersionCard> createState() => _AppVersionCardState();
}

class _AppVersionCardState extends State<_AppVersionCard> {
  final _service = AppVersionService();
  AppVersionCheck? _check;

  @override
  void initState() {
    super.initState();
    unawaited(_runCheck());
  }

  Future<void> _runCheck() async {
    final check = await _service.check();
    if (!mounted) return;
    setState(() => _check = check);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final check = _check;

    final String statusValue;
    Color? statusColor;
    if (check == null) {
      statusValue = l.settingsAppVersionChecking;
    } else if (check.latestVersion == null || !check.updateAvailable) {
      statusValue = l.settingsAppUpToDate;
      statusColor = Colors.green;
    } else {
      statusValue = l.settingsAppUpdateAvailable(check.latestVersion!);
      statusColor = Colors.orange;
    }

    return Column(
      children: [
        _StatusRow(
          label: l.settingsAppVersion,
          value: (check?.currentVersion.isNotEmpty ?? false)
              ? check!.currentVersion
              : l.unknown,
        ),
        const Divider(),
        _StatusRow(
          label: l.settingsAppUpdateStatus,
          value: statusValue,
          valueColor: statusColor,
        ),
        if (check != null &&
            check.latestVersion != null &&
            check.updateAvailable) ...[
          const SizedBox(height: 12),
          const _AppReleaseLink(),
        ],
      ],
    );
  }
}

/// TV screens can't scan a QR code shown on themselves, and tvOS has no
/// in-app browser for url_launcher to hand off to — so this shows a QR
/// code (scan on your phone) on wide/TV layouts, and an "Open" button
/// (which works via url_launcher) only on narrow/mobile layouts. Mirrors
/// the same wide/narrow split _TraktPending already uses.
class _AppReleaseLink extends StatelessWidget {
  const _AppReleaseLink();

  static const _releaseUrl = 'https://github.com/m3ue/m3u-tv/releases/latest';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: QrImageView(
                  data: _releaseUrl,
                  size: 140,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l.settingsAppScanQr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        }
        return SizedBox(
          width: double.infinity,
          child: AppButton(
            icon: Icons.open_in_new,
            label: l.settingsAppViewRelease,
            onPressed: () => launchUrl(
              Uri.parse(_releaseUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        );
      },
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

    final l = AppLocalizations.of(context);
    final body = !traktService.isConfigured
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.traktNotConfigured,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l.traktNotConfiguredHint,
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
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.traktConnectPrompt,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            autofocus: true,
            variant: AppButtonVariant.primary,
            icon: Icons.link,
            label: l.traktConnectButton,
            onPressed: traktService.startDeviceAuth,
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
              AppLocalizations.of(context).traktScanQr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            AppButton(
              autofocus: true,
              label: AppLocalizations.of(context).cancel,
              onPressed: onCancel,
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
          child: AppButton(
            icon: Icons.open_in_new,
            label: AppLocalizations.of(context).traktOpenBrowser,
            onPressed: () => launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            label: AppLocalizations.of(context).cancel,
            onPressed: onCancel,
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
          AppLocalizations.of(context).traktPendingGoTo,
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
        Text(
          AppLocalizations.of(context).traktPendingEnterCode,
          style: theme.textTheme.bodyMedium,
        ),
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
              AppLocalizations.of(context).traktPendingWaiting,
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
            AppLocalizations.of(context).traktConnected,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        AppButton(
          autofocus: true,
          label: AppLocalizations.of(context).traktDisconnectButton,
          onPressed: traktService.disconnect,
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
                    AppButton(
                      label: AppLocalizations.of(ctx).cancel,
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      autofocus: true,
                      variant: isDestructive
                          ? AppButtonVariant.destructive
                          : AppButtonVariant.primary,
                      label: confirmLabel,
                      onPressed: () => Navigator.pop(ctx, true),
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
                      _showAddForm
                          ? AppLocalizations.of(context).settingsAddViewer
                          : AppLocalizations.of(context).settingsManageViewers,
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    DpadFocusable(
                      onSelect: () => Navigator.of(context).pop(),
                      effects: kStadiumFocusEffects,
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
                      labelText: AppLocalizations.of(
                        context,
                      ).settingsViewerNameLabel,
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
                      AppButton(
                        label: AppLocalizations.of(context).cancel,
                        onPressed: () => setState(() {
                          _showAddForm = false;
                          _nameController.clear();
                          _createError = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        variant: AppButtonVariant.primary,
                        label: AppLocalizations.of(context).settingsCreate,
                        loading: _isCreating,
                        onPressed: _handleCreate,
                      ),
                    ],
                  ),
                ] else ...[
                  // ── Active viewer ──────────────────────────────────────────
                  Text(
                    AppLocalizations.of(context).settingsActiveViewer,
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
                      AppLocalizations.of(context).settingsSwitchViewer,
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
                    AppButton(
                      autofocus: others.isEmpty,
                      variant: AppButtonVariant.primary,
                      icon: Icons.person_add,
                      label: AppLocalizations.of(context).settingsAddViewer,
                      onPressed: () => setState(() => _showAddForm = true),
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
              AppLocalizations.of(context).admin,
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

class _ProxyPlaybackControls extends StatelessWidget {
  const _ProxyPlaybackControls({
    required this.capability,
    required this.settings,
  });

  final ProxyCapability capability;
  final ProxyPlaybackSettings settings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isActive = settings.enabled || capability.forced;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (capability.forced)
          Text(l.settingsProxyForced, style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            children: [
              _IntervalChip(
                label: l.settingsProxyUse,
                isSelected: settings.enabled,
                onTap: () =>
                    unawaited(settings.setEnabled(enabled: !settings.enabled)),
              ),
            ],
          ),
        if (isActive && capability.profiles.isEmpty) ...[
          const SizedBox(height: 12),
          Text(l.settingsProxyNoProfiles, style: theme.textTheme.bodySmall),
        ],
        if (isActive && capability.profiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          _ProxyProfilePicker(
            label: l.settingsProxyLiveProfile,
            profiles: capability.profiles,
            selectedId: settings.liveProfileId,
            onChanged: (id) => unawaited(settings.setLiveProfileId(id)),
          ),
          const SizedBox(height: 12),
          _ProxyProfilePicker(
            label: l.settingsProxyVodProfile,
            profiles: capability.profiles,
            selectedId: settings.vodProfileId,
            onChanged: (id) => unawaited(settings.setVodProfileId(id)),
          ),
        ],
      ],
    );
  }
}

class _ProxyProfilePicker extends StatelessWidget {
  const _ProxyProfilePicker({
    required this.label,
    required this.profiles,
    required this.selectedId,
    required this.onChanged,
  });

  final String label;
  final List<ProxyStreamProfile> profiles;
  final int? selectedId;
  final void Function(int? id) onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _IntervalChip(
              label: l.settingsProxyProfileDefault,
              isSelected: selectedId == null,
              onTap: () => onChanged(null),
            ),
            _IntervalChip(
              label: l.settingsProxyProfileDirect,
              isSelected: selectedId == ProxyPlaybackSettings.directProfileId,
              onTap: () => onChanged(ProxyPlaybackSettings.directProfileId),
            ),
            ...profiles.map(
              (profile) => _IntervalChip(
                label: profile.name,
                isSelected: selectedId == profile.id,
                onTap: () => onChanged(profile.id),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ViewSettingsSection extends StatefulWidget {
  const _ViewSettingsSection({required this.service});

  final ViewSettingsService service;

  @override
  State<_ViewSettingsSection> createState() => _ViewSettingsSectionState();
}

class _ViewSettingsSectionState extends State<_ViewSettingsSection> {
  LiveTvLayout _liveTvLayout = LiveTvLayout.list;
  EpgStartView _epgStartView = EpgStartView.currentTime;
  ChannelColumnLayout _channelColumnLayout = ChannelColumnLayout.logoOnly;
  DefaultStartPage _defaultStartPage = DefaultStartPage.home;
  bool _hdrEnabled = true;
  bool _matchRefreshRate = false;

  // The mpv HDR override ships on the Linux and Windows desktop backends
  // only; refresh-rate matching is Windows-only (see DisplayModeManager).
  static final bool _showHdrToggle = Platform.isWindows || Platform.isLinux;
  static final bool _showRefreshRateToggle = Platform.isWindows;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_refresh);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    widget.service.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final layout = await widget.service.liveTvLayout();
    final startView = await widget.service.epgStartView();
    final channelColumnLayout = await widget.service.channelColumnLayout();
    final defaultStartPage = await widget.service.defaultStartPage();
    final hdrEnabled = await widget.service.hdrEnabled();
    final matchRefreshRate = await widget.service.matchRefreshRate();
    if (!mounted) return;
    setState(() {
      _liveTvLayout = layout;
      _epgStartView = startView;
      _channelColumnLayout = channelColumnLayout;
      _defaultStartPage = defaultStartPage;
      _hdrEnabled = hdrEnabled;
      _matchRefreshRate = matchRefreshRate;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _SettingsSection(
      title: l.settingsView,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.settingsDefaultStartPage,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final page in DefaultStartPage.values)
                  _IntervalChip(
                    label: _startPageLabel(l, page),
                    isSelected: _defaultStartPage == page,
                    onTap: () => widget.service.setDefaultStartPage(page),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l.settingsLiveTvLayout,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _IntervalChip(
                  label: l.settingsLiveTvLayoutList,
                  isSelected: _liveTvLayout == LiveTvLayout.list,
                  onTap: () =>
                      widget.service.setLiveTvLayout(LiveTvLayout.list),
                ),
                _IntervalChip(
                  label: l.settingsLiveTvLayoutGrid,
                  isSelected: _liveTvLayout == LiveTvLayout.grid,
                  onTap: () =>
                      widget.service.setLiveTvLayout(LiveTvLayout.grid),
                ),
                _IntervalChip(
                  label: l.settingsLiveTvLayoutTimeline,
                  isSelected: _liveTvLayout == LiveTvLayout.timeline,
                  onTap: () =>
                      widget.service.setLiveTvLayout(LiveTvLayout.timeline),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l.settingsLiveTvChannelColumn,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _IntervalChip(
                  label: l.settingsLiveTvChannelColumnLogoTitle,
                  isSelected:
                      _channelColumnLayout == ChannelColumnLayout.logoAndTitle,
                  onTap: () => widget.service.setChannelColumnLayout(
                    ChannelColumnLayout.logoAndTitle,
                  ),
                ),
                _IntervalChip(
                  label: l.settingsLiveTvChannelColumnLogoOnly,
                  isSelected:
                      _channelColumnLayout == ChannelColumnLayout.logoOnly,
                  onTap: () => widget.service.setChannelColumnLayout(
                    ChannelColumnLayout.logoOnly,
                  ),
                ),
                _IntervalChip(
                  label: l.settingsLiveTvChannelColumnTitleOnly,
                  isSelected:
                      _channelColumnLayout == ChannelColumnLayout.titleOnly,
                  onTap: () => widget.service.setChannelColumnLayout(
                    ChannelColumnLayout.titleOnly,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l.settingsEpgStartView,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _IntervalChip(
                  label: l.settingsEpgStartViewCurrentTime,
                  isSelected: _epgStartView == EpgStartView.currentTime,
                  onTap: () =>
                      widget.service.setEpgStartView(EpgStartView.currentTime),
                ),
                _IntervalChip(
                  label: l.settingsEpgStartViewPrimeTime,
                  isSelected: _epgStartView == EpgStartView.primeTime,
                  onTap: () =>
                      widget.service.setEpgStartView(EpgStartView.primeTime),
                ),
              ],
            ),
            if (_showHdrToggle) ...[
              const SizedBox(height: 16),
              _BooleanSetting(
                label: l.settingsHdrMode,
                hint: l.settingsHdrModeHint,
                value: _hdrEnabled,
                onChanged: widget.service.setHdrEnabled,
              ),
            ],
            if (_showRefreshRateToggle) ...[
              const SizedBox(height: 16),
              _BooleanSetting(
                label: l.settingsMatchRefreshRate,
                hint: l.settingsMatchRefreshRateHint,
                value: _matchRefreshRate,
                onChanged: widget.service.setMatchRefreshRate,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An on/off pair of [_IntervalChip]s with a label and explanatory hint,
/// matching the rest of the View settings section's chip styling.
class _BooleanSetting extends StatelessWidget {
  const _BooleanSetting({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(
          hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _IntervalChip(
              label: l.settingsToggleOn,
              isSelected: value,
              onTap: () => onChanged(true),
            ),
            _IntervalChip(
              label: l.settingsToggleOff,
              isSelected: !value,
              onTap: () => onChanged(false),
            ),
          ],
        ),
      ],
    );
  }
}

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

typedef _LocaleChip = _IntervalChip;

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

String _startPageLabel(AppLocalizations l, DefaultStartPage page) =>
    switch (page) {
      DefaultStartPage.home => l.navHome,
      DefaultStartPage.search => l.navSearch,
      DefaultStartPage.liveTv => l.navLiveTv,
      DefaultStartPage.movies => l.navVod,
      DefaultStartPage.series => l.navSeries,
    };

String _intervalLabel(AppLocalizations l, Duration d) {
  if (d.inHours >= 1) {
    final h = d.inHours;
    return h == 1 ? l.settingsEpgDurationHour : l.settingsEpgDurationHours(h);
  }
  return l.settingsEpgDurationMinutes(d.inMinutes);
}
