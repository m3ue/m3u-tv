import 'dart:async';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// The "go to this URL and enter this code" step of a device login, shared by
/// the watch-history integrations. [qrUrl] is what the QR code and the browser
/// button open, which may already carry the code.
///
/// [onLeave] runs when the view goes away, so leaving the screen mid sign-in
/// can stop polling. It also runs when the sign-in finishes and the view is
/// replaced, so it must only cancel an attempt that is still pending.
class DeviceAuthPendingView extends StatefulWidget {
  const DeviceAuthPendingView({
    super.key,
    required this.url,
    required this.qrUrl,
    required this.userCode,
    required this.onCancel,
    this.onLeave,
  });

  final String url;
  final String qrUrl;
  final String userCode;
  final VoidCallback onCancel;
  final VoidCallback? onLeave;

  @override
  State<DeviceAuthPendingView> createState() => _DeviceAuthPendingViewState();
}

class _DeviceAuthPendingViewState extends State<DeviceAuthPendingView> {
  @override
  void dispose() {
    // Deferred: cancelling notifies listeners, which mustn't happen while the
    // tree is being torn down.
    final onLeave = widget.onLeave;
    if (onLeave != null) scheduleMicrotask(onLeave);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 600
          ? _PendingWide(
              url: widget.url,
              qrUrl: widget.qrUrl,
              userCode: widget.userCode,
              onCancel: widget.onCancel,
            )
          : _PendingNarrow(
              url: widget.url,
              qrUrl: widget.qrUrl,
              userCode: widget.userCode,
              onCancel: widget.onCancel,
            ),
    );
  }
}

class _PendingWide extends StatelessWidget {
  const _PendingWide({
    required this.url,
    required this.qrUrl,
    required this.userCode,
    required this.onCancel,
  });

  final String url;
  final String qrUrl;
  final String userCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PendingInstructions(url: url, userCode: userCode),
        ),
        const SizedBox(width: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: QrImageView(
                data: qrUrl,
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

class _PendingNarrow extends StatelessWidget {
  const _PendingNarrow({
    required this.url,
    required this.qrUrl,
    required this.userCode,
    required this.onCancel,
  });

  final String url;
  final String qrUrl;
  final String userCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PendingInstructions(
          url: url,
          userCode: userCode,
          tapUrl: qrUrl,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            icon: Icons.open_in_new,
            label: AppLocalizations.of(context).traktOpenBrowser,
            onPressed: () => launchUrl(
              Uri.parse(qrUrl),
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

class _PendingInstructions extends StatelessWidget {
  const _PendingInstructions({
    required this.url,
    required this.userCode,
    this.tapUrl,
  });

  final String url;
  final String userCode;

  /// Makes the URL tappable, opening this address.
  final String? tapUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tapUrl = this.tapUrl;
    final urlStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
      decoration: tapUrl != null ? TextDecoration.underline : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).traktPendingGoTo,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        if (tapUrl != null)
          GestureDetector(
            onTap: () => launchUrl(
              Uri.parse(tapUrl),
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
          // Simkl's codes are longer than Trakt's and include a hyphen.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              userCode,
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: AppLoadingIndicator(strokeWidth: 2),
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
