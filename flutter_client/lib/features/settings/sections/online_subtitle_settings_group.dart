import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/online_subtitle_settings.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

/// The Integrations rows for the player's online subtitle search.
class OnlineSubtitleSettingsGroup extends StatelessWidget {
  const OnlineSubtitleSettingsGroup({super.key, required this.settings});

  final OnlineSubtitleSettings settings;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SettingsGroup(
        children: [
          SettingsSwitchRow(
            title: l.settingsOnlineSubtitles,
            subtitle: l.settingsOnlineSubtitlesSubtitle,
            icon: Icons.closed_caption,
            value: settings.enabled,
            onChanged: (enabled) =>
                unawaited(settings.setEnabled(enabled: enabled)),
          ),
          if (settings.enabled)
            SettingsRow(
              title: l.settingsOnlineSubtitlesAddress,
              subtitle: Uri.parse(settings.addonUrl).host,
              icon: Icons.link,
              trailing: const SettingsChevron(),
              onTap: () => showAppDialog<void>(
                context: context,
                builder: (_) => _AddonAddressDialog(settings: settings),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddonAddressDialog extends StatefulWidget {
  const _AddonAddressDialog({required this.settings});

  final OnlineSubtitleSettings settings;

  @override
  State<_AddonAddressDialog> createState() => _AddonAddressDialogState();
}

class _AddonAddressDialogState extends State<_AddonAddressDialog> {
  late final _controller = TextEditingController(
    text: widget.settings.addonUrl,
  );
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await widget.settings.setAddonUrl(_controller.text);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _invalid = true);
    }
  }

  Future<void> _useDefault() async {
    await widget.settings.setAddonUrl(null);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return Dialog(
      child: SizedBox(
        width: 480 * scale,
        child: DpadRegion(
          memoryKey: 'online-subtitle-addon-address',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.settingsOnlineSubtitlesAddress,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l.settingsOnlineSubtitlesAddressHint,
                    errorText: _invalid
                        ? l.settingsOnlineSubtitlesAddressInvalid
                        : null,
                    border: const OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12 * scale,
                      vertical: 16 * scale,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_save()),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!widget.settings.usesDefaultAddon)
                      AppButton(
                        label: l.settingsOnlineSubtitlesUseDefault,
                        onPressed: () => unawaited(_useDefault()),
                      ),
                    AppButton(
                      label: l.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    AppButton(
                      variant: AppButtonVariant.primary,
                      label: l.settingsSave,
                      onPressed: () => unawaited(_save()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
