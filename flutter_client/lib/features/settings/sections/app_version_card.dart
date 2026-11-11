import 'dart:async';

import 'package:m3u_tv/features/settings/sections/settings_status_row.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:material_ui/material_ui.dart';
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

/// Opens the latest GitHub release.
class _AppReleaseLink extends StatelessWidget {
  const _AppReleaseLink();

  static const _releaseUrl = 'https://github.com/m3ue/m3u-tv/releases/latest';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppButton(
        icon: Icons.open_in_new,
        label: AppLocalizations.of(context).settingsAppViewRelease,
        onPressed: () => launchUrl(
          Uri.parse(_releaseUrl),
          mode: LaunchMode.externalApplication,
        ),
      ),
    );
  }
}
