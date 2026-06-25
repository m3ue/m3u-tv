import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/features/series/series_details_screen.dart';
import 'package:m3u_tv/features/vod/vod_details_screen.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/playback/android_playback_adapter.dart';
import 'package:m3u_tv/playback/apple_avkit_backend.dart';
import 'package:m3u_tv/playback/media_kit_desktop_adapter.dart';
import 'package:m3u_tv/playback/media_kit_ios_adapter.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

/// Placeholder screen for routes not yet implemented.
/// Shows the route name so navigation is visually verifiable.
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

/// Player route arguments matching the RN RootStackParamList.Player type.
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

/// Builds the app router using Navigator 2.0 with named routes.
///
/// Route structure mirrors the RN app:
/// - Main stack: Home, Search, LiveTV, VOD, Series, Settings
/// - Modal stack: Player (fullscreen), Details, SeriesDetails, ViewerSelection
RouteFactory buildAppRouter({
  Widget Function(String routeName)? mainRouteBuilder,
  XtreamService? xtreamService,
  EpgService? epgService,
  PlaybackOrchestrator Function()? playbackOrchestratorBuilder,
  Widget Function(PlayerArgs args)? playerRouteBuilder,
  void Function(PlayerArgs)? onOpenPlayer,
  List<Progress> progressList = const [],
  Listenable? progressListenable,
  List<Progress> Function()? progressListProvider,
}) {
  Widget withProgressUpdates(
    Widget Function(List<Progress> progressList) builder,
  ) {
    final listenable = progressListenable;
    if (listenable == null) return builder(progressList);
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, child) => builder(
        progressListProvider?.call() ?? progressList,
      ),
    );
  }

  return (RouteSettings settings) {
    final routeName = settings.name;

    // Main tab routes
    if (routeName == RouteNames.home) {
      return _buildRoute(
        settings,
        mainRouteBuilder?.call(RouteNames.home) ??
            const PlaceholderScreen(title: 'Home'),
      );
    }
    if (routeName == RouteNames.search) {
      return _buildRoute(
        settings,
        mainRouteBuilder?.call(RouteNames.search) ??
            const PlaceholderScreen(title: 'Search'),
      );
    }
    if (routeName == RouteNames.liveTv) {
      return _buildRoute(
        settings,
        mainRouteBuilder?.call(RouteNames.liveTv) ??
            const PlaceholderScreen(title: 'Live TV'),
      );
    }
    if (routeName == RouteNames.vod) {
      return _buildRoute(
        settings,
        mainRouteBuilder?.call(RouteNames.vod) ??
            const PlaceholderScreen(title: 'Movies'),
      );
    }
    if (routeName == RouteNames.series) {
      return _buildRoute(
        settings,
        mainRouteBuilder?.call(RouteNames.series) ??
            const PlaceholderScreen(title: 'Series'),
      );
    }
    if (routeName == RouteNames.settings) {
      return _buildRoute(
        settings,
        mainRouteBuilder?.call(RouteNames.settings) ??
            const PlaceholderScreen(title: 'Settings'),
      );
    }

    // Modal routes
    if (routeName == RouteNames.player) {
      final args = settings.arguments;
      if (args is PlayerArgs) {
        return _buildModalRoute(
          settings,
          playerRouteBuilder?.call(args) ??
              PlayerScreen(
                args: args,
                orchestrator:
                    playbackOrchestratorBuilder?.call() ??
                    buildPlaybackOrchestrator(),
                epgService: epgService ?? EpgService(),
                xtreamService: xtreamService,
              ),
        );
      }
      return _buildModalRoute(
        settings,
        const PlaceholderScreen(title: 'Player unavailable'),
      );
    }
    if (routeName == RouteNames.details) {
      final args = settings.arguments;
      if (args is DetailsArgs && args.item != null) {
        return _buildSlideRoute(
          settings,
          withProgressUpdates(
            (progressList) => VodDetailsScreen(
              item: args.item!,
              xtreamService: xtreamService,
              onPlay: onOpenPlayer,
              progressList: progressList,
            ),
          ),
        );
      }
      final detailTitle = args is DetailsArgs ? args.vodName : 'Details';
      return _buildSlideRoute(settings, PlaceholderScreen(title: detailTitle));
    }
    if (routeName == RouteNames.seriesDetails) {
      final args = settings.arguments;
      if (args is SeriesDetailsArgs && xtreamService != null) {
        return _buildSlideRoute(
          settings,
          withProgressUpdates(
            (progressList) => SeriesDetailsScreen(
              seriesId: args.seriesId,
              seriesName: args.seriesName,
              xtreamService: xtreamService,
              onPlay: onOpenPlayer,
              progressList: progressList,
            ),
          ),
        );
      }
      final detailTitle = args is SeriesDetailsArgs
          ? args.seriesName
          : 'Series Details';
      return _buildSlideRoute(settings, PlaceholderScreen(title: detailTitle));
    }
    if (routeName == RouteNames.viewerSelection) {
      return _buildModalRoute(
        settings,
        const PlaceholderScreen(title: 'Viewer Selection'),
      );
    }

    // Unknown route → Home
    return _buildRoute(
      const RouteSettings(name: RouteNames.home),
      const PlaceholderScreen(title: 'Home'),
    );
  };
}

const BoxDecoration _kGradientBg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1a1528), // dark purple tint
      Color(0xFF09090b), // background
      Color(0xFF09090b), // slightly deeper
    ],
    stops: [0.0, 0.45, 1.0],
  ),
);

Widget _withGradient(Widget screen) =>
    DecoratedBox(decoration: _kGradientBg, child: screen);

MaterialPageRoute<void> _buildRoute(RouteSettings settings, Widget screen) {
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => _withGradient(screen),
  );
}

PageRoute<void> _buildModalRoute(RouteSettings settings, Widget screen) {
  return PageRouteBuilder<void>(
    settings: settings,
    opaque: false,
    pageBuilder: (_, _, _) => screen,
    transitionsBuilder: (_, animation, _, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

PageRoute<void> _buildSlideRoute(RouteSettings settings, Widget screen) {
  return PageRouteBuilder<void>(
    settings: settings,
    pageBuilder: (context, _, _) => ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: screen,
    ),
    transitionsBuilder: (_, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      );
    },
  );
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
    // media_kit doesn't support tvOS; only register it on standard iOS/macOS.
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
