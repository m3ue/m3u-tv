import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/host_platform.dart';

// ---------------------------------------------------------------------------
// Playback settings sub-page (proxy, content cache, DVR)
// ---------------------------------------------------------------------------

class PlaybackSettingsPage extends StatelessWidget {
  const PlaybackSettingsPage({
    super.key,
    required this.proxyCapability,
    required this.proxyPlaybackSettings,
    required this.comskipSettings,
    required this.epgRefreshInterval,
    required this.epgRefreshOptions,
    required this.onEpgIntervalChanged,
    required this.onClearCache,
    this.viewSettingsService,
    this.onHandleTopLevelBack,
  });

  final ProxyCapability? proxyCapability;
  final ProxyPlaybackSettings? proxyPlaybackSettings;
  final ComskipSettings? comskipSettings;
  final ViewSettingsService? viewSettingsService;
  final Duration? epgRefreshInterval;
  final List<Duration> epgRefreshOptions;
  final void Function(Duration interval)? onEpgIntervalChanged;
  final VoidCallback onClearCache;
  final bool Function()? onHandleTopLevelBack;

  // Pre-buffering is an mpv option. Android plays through ExoPlayer, which
  // already buffers before it starts (mpv there is only a fallback), so hide
  // it there, like Deinterlace.
  static final bool _showPrebufferLiveToggle = !HostPlatform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final viewSettings = viewSettingsService;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Web always routes through the editor's in-app-player transcoding
        // path (WebVideoBackend appends proxy=true&player=true to every
        // stream URL -- see its doc comment), the same way the editor's own
        // floating player does, with no user-facing profile picker. A
        // client-selected profile here would be silently ignored (the
        // in-app-player route only ever honors the channel/playlist-level
        // default -- see M3uProxyApiController::channelPlayer), so showing
        // it would just be misleading.
        if (!HostPlatform.isWeb &&
            proxyCapability != null &&
            proxyPlaybackSettings != null) ...[
          SettingsSectionHeader(l.settingsSectionStreaming),
          ListenableBuilder(
            listenable: proxyPlaybackSettings!,
            builder: (context, _) => _buildProxyGroup(context, l),
          ),
        ],

        if (viewSettings != null && _showPrebufferLiveToggle) ...[
          SettingsSectionHeader(l.settingsSectionLiveTv),
          ListenableBuilder(
            listenable: viewSettings,
            builder: (context, _) => SettingsGroup(
              children: [
                SettingsSwitchRow(
                  title: l.settingsPrebufferLive,
                  subtitle: l.settingsPrebufferLiveHint,
                  icon: Icons.hourglass_bottom,
                  value: viewSettings.prebufferLiveSync,
                  onChanged: viewSettings.setPrebufferLive,
                ),
              ],
            ),
          ),
        ],

        SettingsSectionHeader(l.settingsContentCache),
        _buildCacheGroup(context, l),

        if (comskipSettings != null) ...[
          SettingsSectionHeader(l.settingsDvr),
          ListenableBuilder(
            listenable: comskipSettings!,
            builder: (context, _) => SettingsGroup(
              children: [
                SettingsSwitchRow(
                  title: l.settingsComskipAutoSkip,
                  subtitle: l.settingsComskipSubtitle,
                  icon: Icons.fast_forward,
                  value: comskipSettings!.autoSkipEnabled,
                  onChanged: (enabled) => unawaited(
                    comskipSettings!.setAutoSkipEnabled(enabled: enabled),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProxyGroup(BuildContext context, AppLocalizations l) {
    final settings = proxyPlaybackSettings!;
    final capability = proxyCapability!;
    final isActive = settings.enabled || capability.forced;

    final rows = <Widget>[
      if (capability.forced)
        SettingsRow(
          title: l.settingsProxyPlayback,
          subtitle: l.settingsProxyForced,
          icon: Icons.dns_outlined,
        )
      else
        SettingsSwitchRow(
          title: l.settingsProxyPlayback,
          subtitle: l.settingsProxyPlaybackSubtitle,
          icon: Icons.dns_outlined,
          value: settings.enabled,
          onChanged: (enabled) =>
              unawaited(settings.setEnabled(enabled: enabled)),
        ),
      if (isActive && capability.profiles.isEmpty)
        SettingsRow(
          title: l.settingsProxyLiveProfile,
          subtitle: l.settingsProxyNoProfiles,
          icon: Icons.tune,
        ),
      if (isActive && capability.profiles.isNotEmpty) ...[
        _proxyProfileRow(
          context,
          l: l,
          title: l.settingsProxyLiveProfile,
          titleBuilder: (context) =>
              AppLocalizations.of(context).settingsProxyLiveProfile,
          profiles: capability.profiles,
          selectedId: settings.liveProfileId,
          onChanged: (id) => unawaited(settings.setLiveProfileId(id)),
        ),
        _proxyProfileRow(
          context,
          l: l,
          title: l.settingsProxyVodProfile,
          titleBuilder: (context) =>
              AppLocalizations.of(context).settingsProxyVodProfile,
          profiles: capability.profiles,
          selectedId: settings.vodProfileId,
          onChanged: (id) => unawaited(settings.setVodProfileId(id)),
        ),
      ],
    ];

    return SettingsGroup(children: rows);
  }

  Widget _proxyProfileRow(
    BuildContext context, {
    required AppLocalizations l,
    required String title,
    required String Function(BuildContext) titleBuilder,
    required List<ProxyStreamProfile> profiles,
    required int? selectedId,
    required void Function(int? id) onChanged,
  }) {
    final options = <SettingsPickerOption<int?>>[
      SettingsPickerOption(value: null, label: l.settingsProxyProfileDefault),
      SettingsPickerOption(
        value: ProxyPlaybackSettings.directProfileId,
        label: l.settingsProxyProfileDirect,
      ),
      for (final profile in profiles)
        SettingsPickerOption(value: profile.id, label: profile.name),
    ];
    final selectedLabel = options
        .firstWhere(
          (option) => option.value == selectedId,
          orElse: () => options.first,
        )
        .label;
    return SettingsRow(
      title: title,
      subtitle: selectedLabel,
      icon: Icons.high_quality_outlined,
      trailing: const SettingsChevron(),
      onTap: () => unawaited(
        pushSettingsPicker<int?>(
          context,
          title: titleBuilder,
          onBack: onHandleTopLevelBack,
          options: options,
          selected: selectedId,
          onSelected: onChanged,
        ),
      ),
    );
  }

  Widget _buildCacheGroup(BuildContext context, AppLocalizations l) {
    final rows = <Widget>[];
    if (epgRefreshOptions.isNotEmpty && epgRefreshInterval != null) {
      final options = [
        for (final d in epgRefreshOptions)
          SettingsPickerOption(value: d, label: _intervalLabel(l, d)),
      ];
      rows.add(
        SettingsRow(
          title: l.settingsEpgRefreshInterval,
          subtitle: _intervalLabel(l, epgRefreshInterval!),
          icon: Icons.schedule,
          trailing: const SettingsChevron(),
          onTap: () => unawaited(
            pushSettingsPicker<Duration>(
              context,
              title: (context) =>
                  AppLocalizations.of(context).settingsEpgRefreshInterval,
              onBack: onHandleTopLevelBack,
              options: options,
              selected: epgRefreshInterval!,
              onSelected: (d) => onEpgIntervalChanged?.call(d),
            ),
          ),
        ),
      );
    }
    rows.add(
      SettingsRow(
        title: l.settingsClearCacheConfirm,
        subtitle: l.settingsCacheSubtitle,
        icon: Icons.refresh,
        onTap: onClearCache,
      ),
    );
    return SettingsGroup(children: rows);
  }
}

String _intervalLabel(AppLocalizations l, Duration d) {
  if (d.inHours >= 1) {
    final h = d.inHours;
    return h == 1 ? l.settingsEpgDurationHour : l.settingsEpgDurationHours(h);
  }
  return l.settingsEpgDurationMinutes(d.inMinutes);
}
