import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/playback/android_mpv_backend.dart';
import 'package:m3u_tv/playback/android_playback_adapter.dart';
import 'package:m3u_tv/playback/apple_avkit_backend.dart';
import 'package:m3u_tv/playback/apple_mpv_native_backend.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/mac_mpv_native_backend.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

/// Placeholder screen used when a route target cannot be resolved.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
    );
  }
}

/// Player route arguments.
class PlayerArgs {
  const PlayerArgs({
    required this.streamUrl,
    required this.title,
    required this.type,
    this.streamId,
    this.seriesId,
    this.seasonNumber,
    this.startPosition,
    this.epgChannelId,
    this.videoCodec,
    this.audioCodec,
    this.userAgent,
    this.headers = const <String, String>{},
    this.metadata = const <String, Object?>{},
  });

  final String streamUrl;
  final String title;
  final String type; // 'live' | 'vod' | 'series' | 'catchup'
  final int? streamId;
  final int? seriesId;
  final int? seasonNumber;
  final double? startPosition;
  final String? epgChannelId;
  final String? videoCodec;
  final String? audioCodec;
  final String? userAgent;
  final Map<String, String> headers;
  final Map<String, Object?> metadata;

  PlayerArgs copyWith({String? streamUrl, double? startPosition}) {
    return PlayerArgs(
      streamUrl: streamUrl ?? this.streamUrl,
      title: title,
      type: type,
      streamId: streamId,
      seriesId: seriesId,
      seasonNumber: seasonNumber,
      startPosition: startPosition ?? this.startPosition,
      epgChannelId: epgChannelId,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      userAgent: userAgent,
      headers: headers,
      metadata: metadata,
    );
  }

  PlaybackSource toPlaybackSource({bool includeStartPosition = true}) {
    return PlaybackSource(
      uri: streamUrl,
      title: title,
      startPosition: includeStartPosition && startPosition != null
          ? Duration(seconds: startPosition!.round())
          : Duration.zero,
      isLive: type == 'live',
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      userAgent: userAgent,
      headers: headers,
      metadata: <String, Object?>{
        ...metadata,
        if (epgChannelId != null) 'epg_channel_id': epgChannelId,
      },
    );
  }
}

/// Details route arguments for VOD items.
class DetailsArgs {
  const DetailsArgs({required this.vodId, required this.vodName, this.item});

  final int vodId;
  final String vodName;
  final VodItem? item;
}

/// Series details route arguments.
class SeriesDetailsArgs {
  const SeriesDetailsArgs({required this.seriesId, required this.seriesName});

  final int seriesId;
  final String seriesName;
}

PlaybackOrchestrator buildPlaybackOrchestrator() {
  final platform = _playbackPlatformForCurrentTarget();
  final adapters = <PlaybackBackend, PlayerAdapter>{};

  if (platform == PlaybackPlatform.android) {
    // Native mpv via a Flutter PlatformView (`AndroidView` hosting a
    // `SurfaceView`, `vo=gpu-next` + `gpu-context=android` +
    // `hwdec=mediacodec`), registered as primary -- same architecture as
    // `MacMpvNativeBackend`/`AppleMpvNativeBackend` above, modeled on the
    // open-source Plezy player. `AndroidPlaybackAdapter` (ExoPlayer) stays
    // registered as an automatic fallback via `PlaybackOrchestrator`'s own
    // native multi-backend fallback -- do not wrap it in
    // `FallbackPlayerAdapter`, see the desktop branch below for why.
    adapters[PlaybackBackend.androidMpv] = AndroidMpvBackend();
    adapters[PlaybackBackend.androidExoPlayer] = AndroidPlaybackAdapter(
      probe: const AndroidPlaybackProbe(
        hardwareCodecs: <VideoCodec>{VideoCodec.h264},
        passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac, AudioCodec.mp3},
        serverTranscodeAvailable: false,
      ),
    );
  } else if (platform == PlaybackPlatform.apple) {
    // Native mpv via a Flutter PlatformView (`vo=avfoundation` +
    // `hwdec=videotoolbox`, rendering straight to an
    // `AVSampleBufferDisplayLayer`), registered as primary on both iOS and
    // tvOS -- same architecture as the macOS `MacMpvNativeBackend` above,
    // modeled on the open-source Plezy player. `AppleAvKitBackend` (iOS +
    // tvOS) stays registered as an automatic fallback via
    // `PlaybackOrchestrator`'s own native multi-backend fallback -- do not
    // wrap it in `FallbackPlayerAdapter`, see the desktop branch below for
    // why. `AppleAvKitBackend` is the sole automatic fallback; `media_kit`
    // is not a dependency of this project at all (see the desktop branch
    // below for why).
    adapters[PlaybackBackend.appleMpvNative] = AppleMpvNativeBackend();
    adapters[PlaybackBackend.appleAvKit] = AppleAvKitBackend();
  } else if (platform == PlaybackPlatform.desktop) {
    // `media_kit`/`media_kit_video`/`media_kit_libs_*` are not a dependency
    // of this project at all -- removed entirely (not just left
    // unregistered) after it turned out to be dead weight on every
    // platform: each vendored its own independently-versioned ffmpeg/libmpv
    // build, which collided with this project's own native mpv builds
    // (MPVKit on Apple, the fetched gpu-next/D3D11 build on Windows) at
    // link time or, on Windows, by silently overwriting the fetched DLL at
    // build time since both builds used the same output filename (see
    // windows/runner/desktop_libmpv_backend.cpp's `kMpvDllNames` comment).
    // No adapter anywhere ever actually registered a MediaKit backend as an
    // automatic fallback in the shipped orchestrator wiring, so nothing
    // here changed behavior -- it only removed a build-time hazard.
    // `PlaybackOrchestrator._nativeBackends()` walks
    // `PlaybackCapabilities.forPlatform` in order and falls through to the
    // next registered backend on a recoverable `PlaybackException`, so no
    // wrapper adapter is needed for any backend registered here -- and none
    // should be added: wrapping these in `FallbackPlayerAdapter` would break
    // rendering, since it does not forward
    // `PlatformViewProvider`/`VideoTextureProvider`, so
    // `PlaybackOrchestrator`'s `is` checks against `_activeAdapter` need the
    // literal registered instance.
    //
    // macOS registers `MacMpvNativeBackend` (native mpv via a Flutter
    // PlatformView, `vo=gpu-next` + `gpu-context=moltenvk` +
    // `hwdec=videotoolbox`, bypassing the texture bridge entirely --
    // modeled on the open-source Plezy player) with no automatic fallback:
    // a recoverable load failure surfaces directly to the user via
    // `_openServerTranscode`'s `lastFailure` path in
    // playback_orchestrator.dart, since no server-transcode adapter is
    // registered either.
    //
    // Linux/Windows use the in-process C++ libmpv backend
    // (`linux/desktop_libmpv_backend.cc`,
    // `windows/runner/desktop_libmpv_backend.cpp`) instead of `media_kit`'s
    // H/W render path, which requires a current EGL context on the
    // platform thread; starting with Flutter 3.38 the EGL context lives
    // exclusively on the raster thread, so `eglGetCurrentDisplay()` returns
    // `EGL_NO_DISPLAY` and playback would fall back to software texture
    // upload (media-kit/media-kit#1404) even if it were still a dependency.
    // The in-process libmpv backend uses `MPV_RENDER_API_TYPE_SW` with
    // `FlPixelBufferTexture` and `hwdec=auto-safe` on the software path (and
    // a native GPU window on Windows), sidestepping the EGL dependency
    // entirely while keeping hardware video decode. macOS never hits #1404
    // (it renders through Metal, not EGL), so that specific bug never
    // applied there.
    if (Platform.isMacOS) {
      adapters[PlaybackBackend.macMpvNative] = MacMpvNativeBackend();
    } else {
      adapters[PlaybackBackend.desktopLibmpv] = DesktopLibmpvBackend();
    }
  }

  return PlaybackOrchestrator(
    platform: platform,
    adapters: adapters,
    transcodeGateway: const _UnavailableTranscodeGateway(),
    retryDelay: Duration.zero,
  );
}

/// Builds one Multiview grid tile's player: an isolated [MultiviewBackend]
/// instance wrapped in its own orchestrator, so each tile gets independent
/// retry/error handling for free. Only offered on platforms whose native
/// backend can host several concurrent players (see `_multiviewSupported`
/// in `live_tv_screen.dart`): tvOS, iOS, and Android key native player state
/// by [playerId] to multiplex over their one channel pair; macOS
/// (`MacMpvNativeBackend`, keyed by its own internally-generated `_viewId`)
/// and Linux/Windows (the in-process libmpv backend) are multi-instance by
/// design already, so `playerId` is unused there.
({PlaybackOrchestrator orchestrator, MultiviewBackend backend})
buildMultiviewTilePlayer(String playerId) {
  final platform = _playbackPlatformForCurrentTarget();
  final MultiviewBackend backend;
  final PlaybackBackend backendKind;
  switch (platform) {
    case PlaybackPlatform.apple:
      backend = AppleAvKitBackend(playerId: playerId);
      backendKind = PlaybackBackend.appleAvKit;
    case PlaybackPlatform.android:
      backend = AndroidPlaybackAdapter(
        playerId: playerId,
        // Multiview runs several concurrent ExoPlayer instances and manages
        // per-tile audio itself via setVolume; Media3's default audio-focus
        // handling would otherwise auto-pause every tile except whichever one
        // most recently called play() and won system audio focus.
        handleAudioFocus: false,
        probe: const AndroidPlaybackProbe(
          hardwareCodecs: <VideoCodec>{VideoCodec.h264},
          passthroughAudioCodecs: <AudioCodec>{
            AudioCodec.aac,
            AudioCodec.mp3,
          },
          serverTranscodeAvailable: false,
        ),
      );
      backendKind = PlaybackBackend.androidExoPlayer;
    case PlaybackPlatform.desktop:
      if (Platform.isMacOS) {
        backend = MacMpvNativeBackend();
        backendKind = PlaybackBackend.macMpvNative;
      } else {
        backend = DesktopLibmpvBackend();
        backendKind = PlaybackBackend.desktopLibmpv;
      }
    case PlaybackPlatform.server:
      throw UnsupportedError('Multiview is not supported on this platform');
  }
  final orchestrator = PlaybackOrchestrator(
    platform: platform,
    adapters: <PlaybackBackend, PlayerAdapter>{backendKind: backend},
    transcodeGateway: const _UnavailableTranscodeGateway(),
    retryDelay: Duration.zero,
  );
  return (orchestrator: orchestrator, backend: backend);
}

PlaybackPlatform _playbackPlatformForCurrentTarget() {
  if (kIsWeb) return PlaybackPlatform.server;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => PlaybackPlatform.android,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => PlaybackPlatform.desktop,
    TargetPlatform.iOS => PlaybackPlatform.apple,
    TargetPlatform.fuchsia => PlaybackPlatform.server,
  };
}

class _UnavailableTranscodeGateway implements PlaybackTranscodeGateway {
  const _UnavailableTranscodeGateway();

  @override
  Future<TranscodeResponse> startServerTranscode(StreamRequest request) {
    throw const TranscodeUnavailableException(
      'Server transcode is not configured for this client session.',
    );
  }

  @override
  Future<BroadcastSession?> startBroadcast(StreamRequest request) {
    throw const TranscodeUnavailableException(
      'Broadcast relay is not configured for this client session.',
    );
  }

  @override
  Future<void> stopBroadcast(String networkId) async {}

  @override
  Future<void> stopServerTranscode({
    required String streamId,
    required String? sessionId,
  }) async {}
}
