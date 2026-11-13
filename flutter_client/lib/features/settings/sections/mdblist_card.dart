import 'package:m3u_tv/features/settings/sections/device_auth_pending.dart';
import 'package:m3u_tv/features/settings/sections/server_watch_history_notice.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/mdblist_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

class MdblistCard extends StatelessWidget {
  const MdblistCard({
    super.key,
    required this.mdblistService,
    this.serverAccount,
  });

  final MdblistService mdblistService;

  /// M3U Editor's own MDBList account for this login, when one is set up.
  final ServerWatchHistoryAccount? serverAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final logoSize = 40 * scale;
    final pending = mdblistService.pending;
    final body = !mdblistService.isConfigured
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.mdblistNotConfigured, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                l.mdblistNotConfiguredHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          )
        : switch (mdblistService.status) {
            MdblistAuthStatus.disconnected => _MdblistDisconnected(
              mdblistService: mdblistService,
            ),
            MdblistAuthStatus.pending => DeviceAuthPendingView(
              url:
                  pending?.verificationUrl ??
                  'https://mdblist.com/oauth/device/',
              qrUrl:
                  pending?.completeUrl ?? 'https://mdblist.com/oauth/device/',
              userCode: pending?.userCode ?? '------',
              onCancel: mdblistService.cancelAuth,
              onLeave: () {
                if (mdblistService.status == MdblistAuthStatus.pending) {
                  mdblistService.cancelAuth();
                }
              },
            ),
            MdblistAuthStatus.connected => _MdblistConnected(
              mdblistService: mdblistService,
            ),
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntegrationCardHeader(
          logo: ClipRRect(
            borderRadius: BorderRadius.circular(8 * scale),
            child: Image.asset(
              'assets/icons/mdblist-logo.png',
              key: const ValueKey('mdblist-logo'),
              width: logoSize,
              height: logoSize,
              excludeFromSemantics: true,
            ),
          ),
          title: l.mdblistName,
        ),
        const SizedBox(height: 16),
        if (serverAccount case final account?) ...[
          ServerWatchHistoryNotice(
            account: account,
            serviceName: l.mdblistName,
            connectedHere: mdblistService.isConnected,
          ),
          const SizedBox(height: 16),
        ],
        body,
      ],
    );
  }
}

class _MdblistDisconnected extends StatelessWidget {
  const _MdblistDisconnected({required this.mdblistService});

  final MdblistService mdblistService;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.mdblistConnectPrompt,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            autofocus: true,
            variant: AppButtonVariant.primary,
            icon: Icons.link,
            label: l.mdblistConnectButton,
            onPressed: mdblistService.startDeviceAuth,
          ),
        ),
      ],
    );
  }
}

class _MdblistConnected extends StatelessWidget {
  const _MdblistConnected({required this.mdblistService});

  final MdblistService mdblistService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Icon(Icons.check_circle, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            switch (mdblistService.accountName) {
              final name? => l.mdblistConnectedAs(name),
              null => l.mdblistConnected,
            },
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        AppButton(
          autofocus: true,
          label: l.mdblistDisconnectButton,
          onPressed: mdblistService.disconnect,
        ),
      ],
    );
  }
}
