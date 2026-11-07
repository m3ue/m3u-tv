import 'package:m3u_tv/features/settings/sections/device_auth_pending.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/simkl_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

class SimklCard extends StatelessWidget {
  const SimklCard({super.key, required this.simklService});

  final SimklService simklService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final logoSize = 40 * scale;
    final pending = simklService.pending;
    final body = !simklService.isConfigured
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.simklNotConfigured, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                l.simklNotConfiguredHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          )
        : switch (simklService.status) {
            SimklAuthStatus.disconnected => _SimklDisconnected(
              simklService: simklService,
            ),
            SimklAuthStatus.pending => DeviceAuthPendingView(
              url: pending?.verificationUrl ?? 'https://simkl.com/pin',
              qrUrl: pending?.completeUrl ?? 'https://simkl.com/pin',
              userCode: pending?.userCode ?? '------',
              onCancel: simklService.cancelAuth,
            ),
            SimklAuthStatus.connected => _SimklConnected(
              simklService: simklService,
            ),
          };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntegrationCardHeader(
          logo: ClipRRect(
            borderRadius: BorderRadius.circular(8 * scale),
            child: Image.asset(
              'assets/icons/simkl-logo.png',
              key: const ValueKey('simkl-logo'),
              width: logoSize,
              height: logoSize,
              excludeFromSemantics: true,
            ),
          ),
          title: l.simklName,
        ),
        const SizedBox(height: 16),
        body,
      ],
    );
  }
}

class _SimklDisconnected extends StatelessWidget {
  const _SimklDisconnected({required this.simklService});

  final SimklService simklService;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.simklConnectPrompt,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            autofocus: true,
            variant: AppButtonVariant.primary,
            icon: Icons.link,
            label: l.simklConnectButton,
            onPressed: simklService.startDeviceAuth,
          ),
        ),
      ],
    );
  }
}

class _SimklConnected extends StatelessWidget {
  const _SimklConnected({required this.simklService});

  final SimklService simklService;

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
            l.simklConnected,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        AppButton(
          autofocus: true,
          label: l.simklDisconnectButton,
          onPressed: simklService.disconnect,
        ),
      ],
    );
  }
}
