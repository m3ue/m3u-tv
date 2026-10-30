import 'dart:async';

import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/host_platform.dart';

/// Applies the persisted playback settings to [source]. Shared by the
/// full-screen player and the EPG preview: the preview's player is handed
/// to the full-screen player as-is, so both must open a stream the same way.
PlaybackSource applyPlayerSourceSettings(
  PlaybackSource source,
  ViewSettingsService? settings, {
  bool? hdrEnabled,
}) {
  return source.copyWith(
    hdrEnabled: hdrEnabled ?? settings?.hdrEnabledSync ?? true,
    matchDisplayRefreshRate: settings?.matchRefreshRateSync ?? false,
    deinterlace: settings?.deinterlaceSync ?? false,
    prebufferLive: settings?.prebufferLiveSync ?? false,
  );
}

/// The settings pushed to [orchestrator] once a stream has opened.
void applyPlayerOpenedSettings(
  PlaybackOrchestrator orchestrator, {
  required bool hdrEnabled,
  required double volume,
}) {
  // Native backends default to HDR on; only push an explicit call when
  // the persisted setting disagrees, so backends without the capability
  // (and the common case of it already being on) skip the round trip.
  if (!hdrEnabled) {
    unawaited(orchestrator.activeHdrToggleProvider?.setHdrEnabled(false));
  }
  // App-level volume only applies on desktop (see player_screen.dart's
  // `_isDesktop`).
  if (HostPlatform.isMacOS || HostPlatform.isWindows || HostPlatform.isLinux) {
    unawaited(orchestrator.activeVolumeProvider?.setVolume(volume));
  }
}
