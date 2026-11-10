import 'dart:async';

import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:material_ui/material_ui.dart';

// ---------------------------------------------------------------------------
// Playback settings sub-page (player, proxy, live TV, DVR)
// ---------------------------------------------------------------------------

class PlaybackSettingsPage extends StatelessWidget {
  const PlaybackSettingsPage({
    super.key,
    required this.proxyCapability,
    required this.proxyPlaybackSettings,
    required this.comskipSettings,
    this.viewSettingsService,
    this.onHandleTopLevelBack,
    this.isTv = false,
  });

  final ProxyCapability? proxyCapability;
  final ProxyPlaybackSettings? proxyPlaybackSettings;
  final ComskipSettings? comskipSettings;
  final ViewSettingsService? viewSettingsService;
  final bool Function()? onHandleTopLevelBack;
  final bool isTv;

  // Pre-buffering is an mpv option. Android plays through ExoPlayer, which
  // already buffers before it starts (mpv there is only a fallback), so hide
  // it there, like Deinterlace.
  static final bool _showPrebufferLiveToggle = !HostPlatform.isAndroid;

  // Android is the only platform with two full players to choose between.
  static final bool _showVodPlayer = HostPlatform.isAndroid;

  // The mpv HDR override ships on the Linux and Windows desktop backends
  // only. Refresh-rate matching ships on Windows (DisplayModeManager),
  // Android (FrameRateManager), and tvOS (MpvPlayerCore.swift's
  // AVDisplayManager use, decoupled from its always-on HDR criteria so this
  // toggle actually controls it). Windows/Android default off -- the mode
  // switch briefly blanks/flashes the display; tvOS defaults on, since it
  // shipped unconditionally before this toggle existed (see
  // ViewSettingsService.matchRefreshRate's platform-aware default).
  static final bool _showHdrToggle =
      HostPlatform.isWindows || HostPlatform.isLinux;
  static final bool _showRefreshRateToggle =
      HostPlatform.isWindows || HostPlatform.isAndroid || HostPlatform.isTvOS;

  // Deinterlacing is an mpv filter. Android plays through ExoPlayer, which
  // has no filter chain (mpv there is only a fallback), so hide it there.
  static final bool _showDeinterlaceToggle = !HostPlatform.isAndroid;

  // Phones and tablets only: a TV has nothing to keep playing behind.
  bool get _showBackgroundAudioToggle =>
      HostPlatform.isIOS || (HostPlatform.isAndroid && !isTv);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final viewSettings = viewSettingsService;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (viewSettings != null &&
            (_showVodPlayer ||
                _showHdrToggle ||
                _showRefreshRateToggle ||
                _showDeinterlaceToggle ||
                _showBackgroundAudioToggle)) ...[
          SettingsSectionHeader(l.settingsSectionPlayer),
          ListenableBuilder(
            listenable: viewSettings,
            builder: (context, _) => PlayerSettingsGroup(
              service: viewSettings,
              showVodPlayer: _showVodPlayer,
              showHdr: _showHdrToggle,
              showRefreshRate: _showRefreshRateToggle,
              showDeinterlace: _showDeinterlaceToggle,
              showBackgroundAudio: _showBackgroundAudioToggle,
              onHandleTopLevelBack: onHandleTopLevelBack,
            ),
          ),
        ],

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
                  locked: viewSettings.isEnforced(
                    ViewSettingsService.prebufferLiveKey,
                  ),
                  subtitle: l.settingsPrebufferLiveHint,
                  icon: Icons.hourglass_bottom,
                  value: viewSettings.prebufferLiveSync,
                  onChanged: viewSettings.setPrebufferLive,
                ),
              ],
            ),
          ),
        ],

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
}

/// The player section of [PlaybackSettingsPage]. Reads the cached settings
/// `main()` loads before the first frame, so wrap it in a listener on
/// [service].
class PlayerSettingsGroup extends StatelessWidget {
  const PlayerSettingsGroup({
    super.key,
    required this.service,
    required this.showVodPlayer,
    required this.showHdr,
    required this.showRefreshRate,
    required this.showDeinterlace,
    this.showBackgroundAudio = false,
    this.onHandleTopLevelBack,
  });

  final ViewSettingsService service;
  final bool showVodPlayer;
  final bool showHdr;
  final bool showRefreshRate;
  final bool showDeinterlace;
  final bool showBackgroundAudio;
  final bool Function()? onHandleTopLevelBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SettingsGroup(
      children: [
        if (showVodPlayer)
          SettingsRow(
            title: l.settingsVodPlayer,
            locked: service.isEnforced(ViewSettingsService.vodPlayerKey),
            subtitle: _vodPlayerLabel(l, service.vodPlayerSync),
            icon: Icons.smart_display_outlined,
            trailing: const SettingsChevron(),
            onTap: () => unawaited(
              pushSettingsPicker<VodPlayerPreference>(
                context,
                title: (context) =>
                    AppLocalizations.of(context).settingsVodPlayer,
                onBack: onHandleTopLevelBack,
                selected: service.vodPlayerSync,
                options: [
                  for (final preference in VodPlayerPreference.values)
                    SettingsPickerOption(
                      value: preference,
                      label: _vodPlayerLabel(l, preference),
                    ),
                ],
                onSelected: service.setVodPlayer,
              ),
            ),
          ),
        if (showHdr)
          SettingsSwitchRow(
            title: l.settingsHdrMode,
            locked: service.isEnforced(ViewSettingsService.hdrEnabledKey),
            subtitle: l.settingsHdrModeHint,
            icon: Icons.hdr_on_outlined,
            value: service.hdrEnabledSync,
            onChanged: service.setHdrEnabled,
          ),
        if (showRefreshRate)
          SettingsSwitchRow(
            title: l.settingsMatchRefreshRate,
            locked: service.isEnforced(ViewSettingsService.matchRefreshRateKey),
            subtitle: l.settingsMatchRefreshRateHint,
            icon: Icons.speed_outlined,
            value: service.matchRefreshRateSync,
            onChanged: service.setMatchRefreshRate,
          ),
        if (showDeinterlace)
          SettingsSwitchRow(
            title: l.settingsDeinterlace,
            locked: service.isEnforced(ViewSettingsService.deinterlaceKey),
            subtitle: l.settingsDeinterlaceHint,
            icon: Icons.reorder,
            value: service.deinterlaceSync,
            onChanged: service.setDeinterlace,
          ),
        if (showBackgroundAudio)
          SettingsSwitchRow(
            title: l.settingsBackgroundAudio,
            subtitle: l.settingsBackgroundAudioHint,
            icon: Icons.headphones_outlined,
            value: service.backgroundAudioSync,
            onChanged: service.setBackgroundAudio,
          ),
      ],
    );
  }
}

String _vodPlayerLabel(
  AppLocalizations l,
  VodPlayerPreference preference,
) => switch (preference) {
  VodPlayerPreference.exoPlayerFirst => l.settingsVodPlayerExoPlayerFirst,
  VodPlayerPreference.mpv => l.settingsVodPlayerMpv,
};
