import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// Trakt integration card
// ---------------------------------------------------------------------------

class TraktCard extends StatelessWidget {
  const TraktCard({super.key, required this.traktService});

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
    final userCode = pending?.userCode ?? '------';

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
