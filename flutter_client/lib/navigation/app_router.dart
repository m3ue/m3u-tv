import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/playback/android_playback_adapter.dart';
import 'package:m3u_tv/playback/apple_avkit_backend.dart';
import 'package:m3u_tv/playback/media_kit_desktop_adapter.dart';
import 'package:m3u_tv/playback/media_kit_ios_adapter.dart';
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

  PlayerArgs copyWith({double? startPosition}) {
    return PlayerArgs(
      streamUrl: streamUrl,
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
    adapters[PlaybackBackend.androidExoPlayer] = AndroidPlaybackAdapter(
      probe: const AndroidPlaybackProbe(
        hardwareCodecs: <VideoCodec>{VideoCodec.h264},
        passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac, AudioCodec.mp3},
        mpvAvailable: false,
        serverTranscodeAvailable: false,
      ),
    );
  } else if (platform == PlaybackPlatform.apple) {
    if (!kIsWeb && Platform.operatingSystem != 'tvos') {
      adapters[PlaybackBackend.appleMpvKit] = MediaKitIosAdapter();
    }
    adapters[PlaybackBackend.appleAvKit] = AppleAvKitBackend();
  } else if (platform == PlaybackPlatform.desktop) {
    adapters[PlaybackBackend.desktopLibmpv] = MediaKitDesktopAdapter();
  }

  return PlaybackOrchestrator(
    platform: platform,
    adapters: adapters,
    transcodeGateway: const _UnavailableTranscodeGateway(),
    retryDelay: Duration.zero,
  );
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
