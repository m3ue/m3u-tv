import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/features/settings/sections/device_auth_pending.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

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
    return DeviceAuthPendingView(
      url: url,
      qrUrl: url,
      userCode: pending?.userCode ?? '------',
      onCancel: traktService.cancelAuth,
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
