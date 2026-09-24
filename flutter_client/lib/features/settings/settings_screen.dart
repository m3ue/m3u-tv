import 'dart:async';
import 'dart:io' show Platform;

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType;
import 'package:m3u_tv/features/settings/release_notes_view.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
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
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
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
    this.onSidebarActivate,
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

  /// Activates the shell sidebar (left-edge press from tab content).
  final VoidCallback? onSidebarActivate;

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
        onSidebarActivate: widget.onSidebarActivate,
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
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12 * FontSizeScope.scaleOf(context),
                          vertical: 16 * FontSizeScope.scaleOf(context),
                        ),
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
    final scale = FontSizeScope.scaleOf(context);
    // Material's default content padding is fixed and unscaled - as the
    // field's (already-scaling) text grows with the display-size setting,
    // a static padding makes the box look proportionally smaller.
    final contentPadding = EdgeInsets.symmetric(
      horizontal: 12 * scale,
      vertical: 16 * scale,
    );
    return [
      TextFormField(
        controller: _serverController,
        autofocus: autofocusServer,
        decoration: InputDecoration(
          labelText: l.settingsServerUrl,
          hintText: 'example.com:8080',
          contentPadding: contentPadding,
        ),
        autocorrect: false,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _usernameController,
        decoration: InputDecoration(
          labelText: l.settingsUsername,
          contentPadding: contentPadding,
        ),
        autocorrect: false,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        decoration: InputDecoration(
          labelText: l.settingsPassword,
          contentPadding: contentPadding,
        ),
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final logo = SvgPicture.asset(
      'assets/icons/editor-logo.svg',
      height: 40 * FontSizeScope.scaleOf(context),
    );

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
          children: [logo, const SizedBox(height: 16), body],
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
                size: 140 * FontSizeScope.scaleOf(context),
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
    this.onSidebarActivate,
    this.deviceType,
    this.onHandleTopLevelBack,
  });

  final AuthNotifier authNotifier;
  final TraktService traktService;
  final VoidCallback? onSidebarActivate;
  final ProxyPlaybackSettings? proxyPlaybackSettings;
  final ComskipSettings? comskipSettings;
  final ViewSettingsService? viewSettingsService;
  final DeviceType? deviceType;
  final bool Function()? onHandleTopLevelBack;
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

class _ConnectedViewState extends State<_ConnectedView> {
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
    final l = AppLocalizations.of(context);
    final auth = widget.authNotifier.authResponse;
    final hasViewSettings = widget.viewSettingsService != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                title: l.settingsGeneral,
                subtitle: l.settingsGeneralSubtitle,
                icon: Icons.settings_outlined,
                trailing: const SettingsChevron(),
                autofocus: true,
                onTap: () => unawaited(
                  pushSettingsSubpage<void>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsGeneral,
                    onBack: widget.onHandleTopLevelBack,
                    builder: _buildGeneralPageBody,
                  ),
                ),
              ),
              if (hasViewSettings)
                SettingsRow(
                  title: l.settingsAppearance,
                  subtitle: l.settingsAppearanceSubtitle,
                  icon: Icons.palette_outlined,
                  trailing: const SettingsChevron(),
                  onTap: () => unawaited(
                    pushSettingsSubpage<void>(
                      context,
                      title: (context) =>
                          AppLocalizations.of(context).settingsAppearance,
                      onBack: widget.onHandleTopLevelBack,
                      builder: (_) => _ViewSettingsSection(
                        service: widget.viewSettingsService!,
                        deviceType: widget.deviceType,
                        onHandleTopLevelBack: widget.onHandleTopLevelBack,
                      ),
                    ),
                  ),
                ),
              SettingsRow(
                title: l.settingsPlayback,
                subtitle: l.settingsPlaybackSubtitle,
                icon: Icons.play_circle_outline,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsSubpage<void>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsPlayback,
                    onBack: widget.onHandleTopLevelBack,
                    builder: (_) => _PlaybackSettingsPage(
                      proxyCapability: auth?.proxy,
                      proxyPlaybackSettings: widget.proxyPlaybackSettings,
                      comskipSettings: widget.comskipSettings,
                      epgRefreshInterval: widget.epgRefreshInterval,
                      epgRefreshOptions: widget.epgRefreshOptions,
                      onEpgIntervalChanged: widget.onEpgIntervalChanged,
                      onClearCache: _handleClearCache,
                      onHandleTopLevelBack: widget.onHandleTopLevelBack,
                    ),
                  ),
                ),
              ),
              SettingsRow(
                title: l.settingsIntegrations,
                subtitle: l.settingsIntegrationsSubtitle,
                icon: Icons.sync_alt,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsSubpage<void>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsIntegrations,
                    onBack: widget.onHandleTopLevelBack,
                    builder: (_) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SettingsSectionHeader(l.settingsSectionServices),
                        ListenableBuilder(
                          listenable: widget.traktService,
                          builder: (context, _) => SettingsCard(
                            child: _TraktCard(
                              traktService: widget.traktService,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SettingsRow(
                title: l.settingsReleaseNotesTab,
                subtitle: l.settingsReleaseNotesSubtitle,
                icon: Icons.new_releases_outlined,
                trailing: const SettingsChevron(),
                onTap: () => unawaited(
                  pushSettingsSubpageFullHeight<void>(
                    context,
                    title: (context) =>
                        AppLocalizations.of(context).settingsReleaseNotesTab,
                    onBack: widget.onHandleTopLevelBack,
                    builder: (_) => ReleaseNotesView(
                      onSidebarActivate: widget.onSidebarActivate,
                    ),
                  ),
                ),
              ),
            ],
          ),

          SettingsSectionHeader(l.settingsAccount),
          SettingsGroup(
            children: [
              if (widget.activeViewer != null)
                SettingsRow(
                  title: l.settingsActiveViewer,
                  subtitle: widget.activeViewer!.name,
                  icon: Icons.person_outline,
                  trailing: const SettingsChevron(),
                  onTap: () => _openViewerManagement(context),
                ),
              SettingsRow(
                title: l.disconnect,
                icon: Icons.logout,
                destructive: true,
                onTap: _handleDisconnect,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGeneralPageBody(BuildContext context) {
    final theme = Theme.of(context);
    final auth = widget.authNotifier.authResponse;
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.settingsSectionLanguageRegion),
        SettingsGroup(
          children: [
            SettingsRow(
              title: l.settingsLanguage,
              subtitle: _localeLabel(context, widget.locale),
              icon: Icons.language,
              trailing: const SettingsChevron(),
              onTap: () => _openLanguagePicker(context, l),
            ),
          ],
        ),

        SettingsSectionHeader(l.settingsApp),
        const SettingsCard(child: _AppVersionCard()),

        SettingsSectionHeader(l.settingsConnection),
        SettingsCard(
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
      ],
    );
  }

  void _openLanguagePicker(BuildContext context, AppLocalizations l) {
    unawaited(
      pushSettingsPicker<Locale?>(
        context,
        title: (context) => AppLocalizations.of(context).settingsLanguage,
        onBack: widget.onHandleTopLevelBack,
        selected: widget.locale,
        options: [
          SettingsPickerOption(value: null, label: l.settingsLanguageSystem),
          const SettingsPickerOption(value: Locale('en'), label: 'English'),
          const SettingsPickerOption(value: Locale('de'), label: 'Deutsch'),
          const SettingsPickerOption(value: Locale('es'), label: 'Español'),
          const SettingsPickerOption(value: Locale('fr'), label: 'Français'),
          const SettingsPickerOption(value: Locale('zh'), label: '简体中文'),
        ],
        onSelected: (locale) => widget.onLocaleChanged?.call(locale),
      ),
    );
  }

  String _localeLabel(BuildContext context, Locale? locale) {
    switch (locale?.languageCode) {
      case 'en':
        return 'English';
      case 'de':
        return 'Deutsch';
      case 'es':
        return 'Español';
      case 'fr':
        return 'Français';
      case 'zh':
        return '简体中文';
      default:
        return AppLocalizations.of(context).settingsLanguageSystem;
    }
  }
}

// ---------------------------------------------------------------------------
// Playback settings sub-page (proxy, content cache, DVR)
// ---------------------------------------------------------------------------

class _PlaybackSettingsPage extends StatelessWidget {
  const _PlaybackSettingsPage({
    required this.proxyCapability,
    required this.proxyPlaybackSettings,
    required this.comskipSettings,
    required this.epgRefreshInterval,
    required this.epgRefreshOptions,
    required this.onEpgIntervalChanged,
    required this.onClearCache,
    this.onHandleTopLevelBack,
  });

  final ProxyCapability? proxyCapability;
  final ProxyPlaybackSettings? proxyPlaybackSettings;
  final ComskipSettings? comskipSettings;
  final Duration? epgRefreshInterval;
  final List<Duration> epgRefreshOptions;
  final void Function(Duration interval)? onEpgIntervalChanged;
  final VoidCallback onClearCache;
  final bool Function()? onHandleTopLevelBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (proxyCapability != null && proxyPlaybackSettings != null) ...[
          SettingsSectionHeader(l.settingsSectionStreaming),
          ListenableBuilder(
            listenable: proxyPlaybackSettings!,
            builder: (context, _) => _buildProxyGroup(context, l),
          ),
        ],

        SettingsSectionHeader(l.settingsContentCache),
        _buildCacheGroup(context, l),

        if (comskipSettings != null) ...[
          SettingsSectionHeader(l.settingsDvr),
          ListenableBuilder(
            listenable: comskipSettings!,
            builder: (context, _) => SettingsGroup(
              children: [
                SettingsSwitchRow(
                  title: l.settingsComskipAutoSkip,
                  subtitle: l.settingsComskipSubtitle,
                  icon: Icons.fast_forward,
                  value: comskipSettings!.autoSkipEnabled,
                  onChanged: (enabled) => unawaited(
                    comskipSettings!.setAutoSkipEnabled(enabled: enabled),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProxyGroup(BuildContext context, AppLocalizations l) {
    final settings = proxyPlaybackSettings!;
    final capability = proxyCapability!;
    final isActive = settings.enabled || capability.forced;

    final rows = <Widget>[
      if (capability.forced)
        SettingsRow(
          title: l.settingsProxyPlayback,
          subtitle: l.settingsProxyForced,
          icon: Icons.dns_outlined,
        )
      else
        SettingsSwitchRow(
          title: l.settingsProxyPlayback,
          subtitle: l.settingsProxyPlaybackSubtitle,
          icon: Icons.dns_outlined,
          value: settings.enabled,
          onChanged: (enabled) =>
              unawaited(settings.setEnabled(enabled: enabled)),
        ),
      if (isActive && capability.profiles.isEmpty)
        SettingsRow(
          title: l.settingsProxyLiveProfile,
          subtitle: l.settingsProxyNoProfiles,
          icon: Icons.tune,
        ),
      if (isActive && capability.profiles.isNotEmpty) ...[
        _proxyProfileRow(
          context,
          l: l,
          title: l.settingsProxyLiveProfile,
          titleBuilder: (context) =>
              AppLocalizations.of(context).settingsProxyLiveProfile,
          profiles: capability.profiles,
          selectedId: settings.liveProfileId,
          onChanged: (id) => unawaited(settings.setLiveProfileId(id)),
        ),
        _proxyProfileRow(
          context,
          l: l,
          title: l.settingsProxyVodProfile,
          titleBuilder: (context) =>
              AppLocalizations.of(context).settingsProxyVodProfile,
          profiles: capability.profiles,
          selectedId: settings.vodProfileId,
          onChanged: (id) => unawaited(settings.setVodProfileId(id)),
        ),
      ],
    ];

    return SettingsGroup(children: rows);
  }

  Widget _proxyProfileRow(
    BuildContext context, {
    required AppLocalizations l,
    required String title,
    required String Function(BuildContext) titleBuilder,
    required List<ProxyStreamProfile> profiles,
    required int? selectedId,
    required void Function(int? id) onChanged,
  }) {
    final options = <SettingsPickerOption<int?>>[
      SettingsPickerOption(value: null, label: l.settingsProxyProfileDefault),
      SettingsPickerOption(
        value: ProxyPlaybackSettings.directProfileId,
        label: l.settingsProxyProfileDirect,
      ),
      for (final profile in profiles)
        SettingsPickerOption(value: profile.id, label: profile.name),
    ];
    final selectedLabel = options
        .firstWhere(
          (option) => option.value == selectedId,
          orElse: () => options.first,
        )
        .label;
    return SettingsRow(
      title: title,
      subtitle: selectedLabel,
      icon: Icons.high_quality_outlined,
      trailing: const SettingsChevron(),
      onTap: () => unawaited(
        pushSettingsPicker<int?>(
          context,
          title: titleBuilder,
          onBack: onHandleTopLevelBack,
          options: options,
          selected: selectedId,
          onSelected: onChanged,
        ),
      ),
    );
  }

  Widget _buildCacheGroup(BuildContext context, AppLocalizations l) {
    final rows = <Widget>[];
    if (epgRefreshOptions.isNotEmpty && epgRefreshInterval != null) {
      final options = [
        for (final d in epgRefreshOptions)
          SettingsPickerOption(value: d, label: _intervalLabel(l, d)),
      ];
      rows.add(
        SettingsRow(
          title: l.settingsEpgRefreshInterval,
          subtitle: _intervalLabel(l, epgRefreshInterval!),
          icon: Icons.schedule,
          trailing: const SettingsChevron(),
          onTap: () => unawaited(
            pushSettingsPicker<Duration>(
              context,
              title: (context) =>
                  AppLocalizations.of(context).settingsEpgRefreshInterval,
              onBack: onHandleTopLevelBack,
              options: options,
              selected: epgRefreshInterval!,
              onSelected: (d) => onEpgIntervalChanged?.call(d),
            ),
          ),
        ),
      );
    }
    rows.add(
      SettingsRow(
        title: l.settingsClearCacheConfirm,
        subtitle: l.settingsCacheSubtitle,
        icon: Icons.refresh,
        onTap: onClearCache,
      ),
    );
    return SettingsGroup(children: rows);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = SvgPicture.asset(
      'assets/icons/trakt-logo.svg',
      height: 40 * FontSizeScope.scaleOf(context),
    );

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
        logo,
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
        width: 480 * FontSizeScope.scaleOf(ctx),
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

    final scale = FontSizeScope.scaleOf(context);

    return Dialog(
      child: SizedBox(
        width: 520 * scale,
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
                        icon: Icon(Icons.close, size: 24 * scale),
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12 * scale,
                        vertical: 16 * scale,
                      ),
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
                      constraints: BoxConstraints(maxHeight: 280 * scale),
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
    final scale = FontSizeScope.scaleOf(context);
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
            if (viewer.isAdmin) SizedBox(width: 8 * scale),
            Icon(
              Icons.check_circle,
              size: 16 * scale,
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
// Appearance settings sub-page (layout, display, filters)
// ---------------------------------------------------------------------------

class _ViewSettingsSection extends StatefulWidget {
  const _ViewSettingsSection({
    required this.service,
    this.deviceType,
    this.onHandleTopLevelBack,
  });

  final ViewSettingsService service;
  final DeviceType? deviceType;
  final bool Function()? onHandleTopLevelBack;

  @override
  State<_ViewSettingsSection> createState() => _ViewSettingsSectionState();
}

class _ViewSettingsSectionState extends State<_ViewSettingsSection> {
  LiveTvLayout _liveTvLayout = LiveTvLayout.list;
  EpgStartView _epgStartView = EpgStartView.currentTime;
  ChannelColumnLayout _channelColumnLayout = ChannelColumnLayout.logoOnly;
  bool _rememberMediaSort = false;
  DefaultStartPage _defaultStartPage = DefaultStartPage.home;
  bool _hdrEnabled = true;
  bool _matchRefreshRate = false;
  bool _navigationSoundEnabled = true;
  OptimizeFor _optimizeFor = OptimizeFor.quality;
  AppFontSize _fontSize = AppFontSize.normal;

  // The mpv HDR override ships on the Linux and Windows desktop backends
  // only. Refresh-rate matching ships on Windows (DisplayModeManager),
  // Android (FrameRateManager), and tvOS (MpvPlayerCore.swift's
  // AVDisplayManager use, decoupled from its always-on HDR criteria so this
  // toggle actually controls it). Windows/Android default off -- the mode
  // switch briefly blanks/flashes the display; tvOS defaults on, since it
  // shipped unconditionally before this toggle existed (see
  // ViewSettingsService.matchRefreshRate's platform-aware default).
  static final bool _showHdrToggle = Platform.isWindows || Platform.isLinux;
  static final bool _showRefreshRateToggle =
      Platform.isWindows || Platform.isAndroid || _isTvOS;

  // Mirrors the tvOS/Android-TV detection duplicated in go_router_config.dart
  // and dvr_series_rule_options_screen.dart -- no shared helper exists yet.
  static bool get _isTvOS => !kIsWeb && Platform.operatingSystem == 'tvos';

  // The navigation click sound only ever plays on TV/desktop (see main.dart);
  // hide the toggle where it would have no effect.
  bool get _showNavigationSoundToggle =>
      widget.deviceType == DeviceType.tv ||
      widget.deviceType == DeviceType.desktop;

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
    final rememberMediaSort = await widget.service.rememberMediaSort();
    final defaultStartPage = await widget.service.defaultStartPage();
    final hdrEnabled = await widget.service.hdrEnabled();
    final matchRefreshRate = await widget.service.matchRefreshRate();
    final navigationSoundEnabled = await widget.service
        .navigationSoundEnabled();
    final optimizeFor = await widget.service.optimizeFor();
    final storedFontSize = await widget.service.fontSizeOrNull();
    final fontSize = AppFontSize.resolveDefault(
      stored: storedFontSize,
      isTv: widget.deviceType == DeviceType.tv,
    );
    if (!mounted) return;
    setState(() {
      _liveTvLayout = layout;
      _epgStartView = startView;
      _channelColumnLayout = channelColumnLayout;
      _rememberMediaSort = rememberMediaSort;
      _defaultStartPage = defaultStartPage;
      _hdrEnabled = hdrEnabled;
      _matchRefreshRate = matchRefreshRate;
      _navigationSoundEnabled = navigationSoundEnabled;
      _optimizeFor = optimizeFor;
      _fontSize = fontSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(l.settingsSectionLayout),
        SettingsGroup(
          children: [
            SettingsRow(
              title: l.settingsDefaultStartPage,
              subtitle: _startPageLabel(l, _defaultStartPage),
              icon: Icons.home_outlined,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<DefaultStartPage>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsDefaultStartPage,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _defaultStartPage,
                  options: [
                    for (final page in DefaultStartPage.values)
                      SettingsPickerOption(
                        value: page,
                        label: _startPageLabel(l, page),
                      ),
                  ],
                  onSelected: widget.service.setDefaultStartPage,
                ),
              ),
            ),
            SettingsRow(
              title: l.settingsLiveTvLayout,
              subtitle: _liveTvLayoutLabel(l, _liveTvLayout),
              icon: Icons.view_list_outlined,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<LiveTvLayout>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsLiveTvLayout,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _liveTvLayout,
                  options: [
                    SettingsPickerOption(
                      value: LiveTvLayout.list,
                      label: l.settingsLiveTvLayoutList,
                    ),
                    SettingsPickerOption(
                      value: LiveTvLayout.grid,
                      label: l.settingsLiveTvLayoutGrid,
                    ),
                    SettingsPickerOption(
                      value: LiveTvLayout.timeline,
                      label: l.settingsLiveTvLayoutTimeline,
                    ),
                  ],
                  onSelected: widget.service.setLiveTvLayout,
                ),
              ),
            ),
            SettingsRow(
              title: l.settingsLiveTvChannelColumn,
              subtitle: _channelColumnLabel(l, _channelColumnLayout),
              icon: Icons.view_column_outlined,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<ChannelColumnLayout>(
                  context,
                  title: (context) => AppLocalizations.of(
                    context,
                  ).settingsLiveTvChannelColumn,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _channelColumnLayout,
                  options: [
                    SettingsPickerOption(
                      value: ChannelColumnLayout.logoAndTitle,
                      label: l.settingsLiveTvChannelColumnLogoTitle,
                    ),
                    SettingsPickerOption(
                      value: ChannelColumnLayout.logoOnly,
                      label: l.settingsLiveTvChannelColumnLogoOnly,
                    ),
                    SettingsPickerOption(
                      value: ChannelColumnLayout.titleOnly,
                      label: l.settingsLiveTvChannelColumnTitleOnly,
                    ),
                  ],
                  onSelected: widget.service.setChannelColumnLayout,
                ),
              ),
            ),
            SettingsRow(
              title: l.settingsEpgStartView,
              subtitle: _epgStartViewLabel(l, _epgStartView),
              icon: Icons.calendar_view_day_outlined,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<EpgStartView>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsEpgStartView,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _epgStartView,
                  options: [
                    SettingsPickerOption(
                      value: EpgStartView.currentTime,
                      label: l.settingsEpgStartViewCurrentTime,
                    ),
                    SettingsPickerOption(
                      value: EpgStartView.primeTime,
                      label: l.settingsEpgStartViewPrimeTime,
                    ),
                  ],
                  onSelected: widget.service.setEpgStartView,
                ),
              ),
            ),
          ],
        ),

        SettingsSectionHeader(l.settingsSectionDisplay),
        SettingsGroup(
          children: [
            if (_showHdrToggle)
              SettingsSwitchRow(
                title: l.settingsHdrMode,
                subtitle: l.settingsHdrModeHint,
                icon: Icons.hdr_on_outlined,
                value: _hdrEnabled,
                onChanged: widget.service.setHdrEnabled,
              ),
            if (_showRefreshRateToggle)
              SettingsSwitchRow(
                title: l.settingsMatchRefreshRate,
                subtitle: l.settingsMatchRefreshRateHint,
                icon: Icons.speed_outlined,
                value: _matchRefreshRate,
                onChanged: widget.service.setMatchRefreshRate,
              ),
            if (_showNavigationSoundToggle)
              SettingsSwitchRow(
                title: l.settingsNavigationSound,
                subtitle: l.settingsNavigationSoundHint,
                icon: Icons.volume_up_outlined,
                value: _navigationSoundEnabled,
                onChanged: widget.service.setNavigationSoundEnabled,
              ),
            SettingsRow(
              title: l.settingsOptimizeFor,
              subtitle: _optimizeForLabel(l, _optimizeFor),
              icon: Icons.tune,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<OptimizeFor>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsOptimizeFor,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _optimizeFor,
                  options: [
                    SettingsPickerOption(
                      value: OptimizeFor.quality,
                      label: l.settingsOptimizeForQuality,
                    ),
                    SettingsPickerOption(
                      value: OptimizeFor.speed,
                      label: l.settingsOptimizeForSpeed,
                    ),
                  ],
                  onSelected: widget.service.setOptimizeFor,
                ),
              ),
            ),
            SettingsRow(
              title: l.settingsFontSize,
              subtitle: _fontSizeLabel(l, _fontSize),
              icon: Icons.format_size,
              trailing: const SettingsChevron(),
              onTap: () => unawaited(
                pushSettingsPicker<AppFontSize>(
                  context,
                  title: (context) =>
                      AppLocalizations.of(context).settingsFontSize,
                  onBack: widget.onHandleTopLevelBack,
                  selected: _fontSize,
                  options: [
                    SettingsPickerOption(
                      value: AppFontSize.normal,
                      label: l.settingsFontSizeNormal,
                      icon: Icons.smartphone,
                    ),
                    SettingsPickerOption(
                      value: AppFontSize.large,
                      label: l.settingsFontSizeLarge,
                    ),
                    SettingsPickerOption(
                      value: AppFontSize.veryLarge,
                      label: l.settingsFontSizeVeryLarge,
                      icon: Icons.tv,
                    ),
                  ],
                  onSelected: widget.service.setFontSize,
                ),
              ),
            ),
          ],
        ),

        SettingsSectionHeader(l.settingsSectionFilters),
        SettingsGroup(
          children: [
            SettingsSwitchRow(
              title: l.settingsFilterPersistence,
              subtitle: _rememberMediaSort
                  ? l.settingsFilterPersistenceRemember
                  : l.settingsFilterPersistenceReset,
              icon: Icons.filter_alt_outlined,
              value: _rememberMediaSort,
              onChanged: widget.service.setRememberMediaSort,
            ),
          ],
        ),
      ],
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

String _liveTvLayoutLabel(AppLocalizations l, LiveTvLayout layout) =>
    switch (layout) {
      LiveTvLayout.list => l.settingsLiveTvLayoutList,
      LiveTvLayout.grid => l.settingsLiveTvLayoutGrid,
      LiveTvLayout.timeline => l.settingsLiveTvLayoutTimeline,
    };

String _channelColumnLabel(AppLocalizations l, ChannelColumnLayout layout) =>
    switch (layout) {
      ChannelColumnLayout.logoAndTitle =>
        l.settingsLiveTvChannelColumnLogoTitle,
      ChannelColumnLayout.logoOnly => l.settingsLiveTvChannelColumnLogoOnly,
      ChannelColumnLayout.titleOnly => l.settingsLiveTvChannelColumnTitleOnly,
    };

String _epgStartViewLabel(AppLocalizations l, EpgStartView view) =>
    switch (view) {
      EpgStartView.currentTime => l.settingsEpgStartViewCurrentTime,
      EpgStartView.primeTime => l.settingsEpgStartViewPrimeTime,
    };

String _optimizeForLabel(AppLocalizations l, OptimizeFor optimizeFor) =>
    switch (optimizeFor) {
      OptimizeFor.quality => l.settingsOptimizeForQuality,
      OptimizeFor.speed => l.settingsOptimizeForSpeed,
    };

String _fontSizeLabel(AppLocalizations l, AppFontSize fontSize) =>
    switch (fontSize) {
      AppFontSize.normal => l.settingsFontSizeNormal,
      AppFontSize.large => l.settingsFontSizeLarge,
      AppFontSize.veryLarge => l.settingsFontSizeVeryLarge,
    };
