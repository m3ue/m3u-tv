import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/features/settings/sections/settings_status_row.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// App version card
// ---------------------------------------------------------------------------

class AppVersionCard extends StatefulWidget {
  const AppVersionCard({super.key});

  @override
  State<AppVersionCard> createState() => _AppVersionCardState();
}

class _AppVersionCardState extends State<AppVersionCard> {
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
        SettingsStatusRow(
          label: l.settingsAppVersion,
          value: (check?.currentVersion.isNotEmpty ?? false)
              ? check!.currentVersion
              : l.unknown,
        ),
        const Divider(),
        SettingsStatusRow(
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
