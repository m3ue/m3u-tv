import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType;
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_callout.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/embedded_origin.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Connection form
// ---------------------------------------------------------------------------

class ConnectionFormBody extends StatefulWidget {
  const ConnectionFormBody({
    super.key,
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
  State<ConnectionFormBody> createState() => _ConnectionFormBodyState();
}

class _ConnectionFormBodyState extends State<ConnectionFormBody>
    with SingleTickerProviderStateMixin {
  /// Non-null when this web build is served by the editor itself at
  /// /m3u-tv/ — the server URL is that editor's own origin, not something
  /// the user should have to type or be able to change.
  final String? _lockedServerUrl = embeddedEditorOrigin;
  late final _serverController = TextEditingController(
    text: _lockedServerUrl ?? widget.initialValues?.server,
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
                      autofocus: _lockedServerUrl == null,
                      readOnly: _lockedServerUrl != null,
                      enableInteractiveSelection: _lockedServerUrl == null,
                      decoration: InputDecoration(
                        labelText: l.settingsServerUrl,
                        hintText: 'example.com:8080',
                        helperText: _lockedServerUrl != null
                            ? l.settingsServerUrlLocked
                            : null,
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
        autofocus: autofocusServer && _lockedServerUrl == null,
        readOnly: _lockedServerUrl != null,
        enableInteractiveSelection: _lockedServerUrl == null,
        decoration: InputDecoration(
          labelText: l.settingsServerUrl,
          hintText: 'example.com:8080',
          helperText: _lockedServerUrl != null
              ? l.settingsServerUrlLocked
              : null,
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
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _CopyPairingCodeButton(userCode: userCode),
                    AppButton(
                      icon: Icons.open_in_new,
                      label: l.pairingOpenBrowser,
                      onPressed: () => launchUrl(
                        Uri.parse(uri),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
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
        if (linksAreTappable && uri.isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            child: _CopyPairingCodeButton(userCode: userCode),
          ),
          const SizedBox(height: 8),
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
        ],
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

/// Copies the pairing code so it can be pasted into the m3u-editor pairing
/// page, then briefly flips to a "Copied" confirmation.
class _CopyPairingCodeButton extends StatefulWidget {
  const _CopyPairingCodeButton({required this.userCode});

  final String userCode;

  @override
  State<_CopyPairingCodeButton> createState() => _CopyPairingCodeButtonState();
}

class _CopyPairingCodeButtonState extends State<_CopyPairingCodeButton> {
  Timer? _resetTimer;
  bool _copied = false;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.userCode));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppButton(
      icon: _copied ? Icons.check : Icons.copy,
      label: _copied ? l.pairingCodeCopied : l.pairingCopyCode,
      onPressed: _copy,
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
