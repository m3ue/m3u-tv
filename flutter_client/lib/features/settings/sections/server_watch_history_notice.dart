import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:material_ui/material_ui.dart';

/// Tells the viewer that M3U Editor already sends this login's watch
/// progress to a Trakt / SIMKL account, and that signing in on this device
/// takes over for it: the device then sends its playback to its own account
/// and the server skips that provider for this device's saves.
class ServerWatchHistoryNotice extends StatelessWidget {
  const ServerWatchHistoryNotice({
    super.key,
    required this.account,
    required this.serviceName,
    required this.connectedHere,
  });

  final ServerWatchHistoryAccount account;
  final String serviceName;

  /// Whether this device is signed in to the same service.
  final bool connectedHere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final accountName = account.account;
    final status = accountName == null || accountName.isEmpty
        ? l.serverWatchHistoryActive(serviceName)
        : l.serverWatchHistoryActiveAs(serviceName, accountName);
    final hint = connectedHere
        ? l.serverWatchHistoryOverridden
        : l.serverWatchHistoryOverrideHint(serviceName);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cloud_done_outlined, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(status, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
