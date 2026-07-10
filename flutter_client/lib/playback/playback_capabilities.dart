enum PlaybackPlatform { android, apple, desktop, server }

enum PlaybackBackend {
  androidExoPlayer,
  androidMpv,
  appleMpvKit,
  appleAvKit,
  desktopLibmpv,
  serverTranscode,
}

class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.platform,
    required this.backend,
    required this.displayName,
    required this.supportsDirectStreams,
    required this.supportsServerTranscodeFallback,
    required this.supportsHls,
    required this.supportsMpegTs,
    required this.supportsMp4,
    required this.supportsAdvancedCodecs,
    required this.supportsAudioTrackSelection,
    required this.supportsSubtitleTrackSelection,
    required this.supportsEmbeddedSubtitles,
    required this.supportsExternalSubtitles,
    required this.supportsAdvancedSubtitleFormats,
    required this.supportsPlaybackSpeed,
    required this.supportsSeek,
    required this.supportsLiveSeek,
    this.requiresNetworkTranscode = false,
  });

  final PlaybackPlatform platform;
  final PlaybackBackend backend;
  final String displayName;
  final bool supportsDirectStreams;
  final bool supportsServerTranscodeFallback;
  final bool supportsHls;
  final bool supportsMpegTs;
  final bool supportsMp4;
  final bool supportsAdvancedCodecs;
  final bool supportsAudioTrackSelection;
  final bool supportsSubtitleTrackSelection;
  final bool supportsEmbeddedSubtitles;
  final bool supportsExternalSubtitles;
  final bool supportsAdvancedSubtitleFormats;
  final bool supportsPlaybackSpeed;
  final bool supportsSeek;
  final bool supportsLiveSeek;
  final bool requiresNetworkTranscode;

  static const PlaybackCapabilities androidExoPlayer = PlaybackCapabilities(
    platform: PlaybackPlatform.android,
    backend: PlaybackBackend.androidExoPlayer,
    displayName: 'Android ExoPlayer',
    supportsDirectStreams: true,
    supportsServerTranscodeFallback: true,
    supportsHls: true,
    supportsMpegTs: true,
    supportsMp4: true,
    supportsAdvancedCodecs: false,
    supportsAudioTrackSelection: true,
    supportsSubtitleTrackSelection: true,
    supportsEmbeddedSubtitles: true,
    supportsExternalSubtitles: false,
    supportsAdvancedSubtitleFormats: false,
    supportsPlaybackSpeed: true,
    supportsSeek: true,
    supportsLiveSeek: false,
  );

  static const PlaybackCapabilities androidMpv = PlaybackCapabilities(
    platform: PlaybackPlatform.android,
    backend: PlaybackBackend.androidMpv,
    displayName: 'Android MPV fallback',
    supportsDirectStreams: true,
    supportsServerTranscodeFallback: true,
    supportsHls: true,
    supportsMpegTs: true,
    supportsMp4: true,
    supportsAdvancedCodecs: true,
    supportsAudioTrackSelection: true,
    supportsSubtitleTrackSelection: true,
    supportsEmbeddedSubtitles: true,
    supportsExternalSubtitles: true,
    supportsAdvancedSubtitleFormats: true,
    supportsPlaybackSpeed: true,
    supportsSeek: true,
    supportsLiveSeek: false,
  );

  static const PlaybackCapabilities appleMpvKit = PlaybackCapabilities(
    platform: PlaybackPlatform.apple,
    backend: PlaybackBackend.appleMpvKit,
    displayName: 'Apple MPVKit',
    supportsDirectStreams: true,
    supportsServerTranscodeFallback: true,
    supportsHls: true,
    supportsMpegTs: true,
    supportsMp4: true,
    supportsAdvancedCodecs: true,
    supportsAudioTrackSelection: true,
    supportsSubtitleTrackSelection: true,
    supportsEmbeddedSubtitles: true,
    supportsExternalSubtitles: true,
    supportsAdvancedSubtitleFormats: true,
    supportsPlaybackSpeed: true,
    supportsSeek: true,
    supportsLiveSeek: false,
  );

  static const PlaybackCapabilities appleAvKit = PlaybackCapabilities(
    platform: PlaybackPlatform.apple,
    backend: PlaybackBackend.appleAvKit,
    displayName: 'Apple AVKit fallback',
    supportsDirectStreams: true,
    supportsServerTranscodeFallback: true,
    supportsHls: true,
    supportsMpegTs: false,
    supportsMp4: true,
    supportsAdvancedCodecs: false,
    supportsAudioTrackSelection: true,
    supportsSubtitleTrackSelection: true,
    supportsEmbeddedSubtitles: true,
    supportsExternalSubtitles: false,
    supportsAdvancedSubtitleFormats: false,
    supportsPlaybackSpeed: true,
    supportsSeek: true,
    supportsLiveSeek: false,
  );

  static const PlaybackCapabilities desktopLibmpv = PlaybackCapabilities(
    platform: PlaybackPlatform.desktop,
    backend: PlaybackBackend.desktopLibmpv,
    displayName: 'Desktop libmpv',
    supportsDirectStreams: true,
    supportsServerTranscodeFallback: true,
    supportsHls: true,
    supportsMpegTs: true,
    supportsMp4: true,
    supportsAdvancedCodecs: true,
    supportsAudioTrackSelection: true,
    supportsSubtitleTrackSelection: true,
    supportsEmbeddedSubtitles: true,
    supportsExternalSubtitles: true,
    supportsAdvancedSubtitleFormats: true,
    supportsPlaybackSpeed: true,
    supportsSeek: true,
    supportsLiveSeek: false,
  );

  static const PlaybackCapabilities serverTranscode = PlaybackCapabilities(
    platform: PlaybackPlatform.server,
    backend: PlaybackBackend.serverTranscode,
    displayName: 'Server transcode fallback',
    supportsDirectStreams: false,
    supportsServerTranscodeFallback: false,
    supportsHls: true,
    supportsMpegTs: false,
    supportsMp4: false,
    supportsAdvancedCodecs: false,
    supportsAudioTrackSelection: false,
    supportsSubtitleTrackSelection: false,
    supportsEmbeddedSubtitles: false,
    supportsExternalSubtitles: false,
    supportsAdvancedSubtitleFormats: false,
    supportsPlaybackSpeed: false,
    supportsSeek: true,
    supportsLiveSeek: false,
    requiresNetworkTranscode: true,
  );

  static const List<PlaybackCapabilities> matrix = <PlaybackCapabilities>[
    androidExoPlayer,
    androidMpv,
    appleMpvKit,
    appleAvKit,
    desktopLibmpv,
    serverTranscode,
  ];

  static List<PlaybackCapabilities> forPlatform(PlaybackPlatform platform) {
    return switch (platform) {
      PlaybackPlatform.android => const <PlaybackCapabilities>[
        androidExoPlayer,
        serverTranscode,
      ],
      PlaybackPlatform.apple => const <PlaybackCapabilities>[
        appleMpvKit,
        appleAvKit,
        serverTranscode,
      ],
      PlaybackPlatform.desktop => const <PlaybackCapabilities>[
        desktopLibmpv,
        serverTranscode,
      ],
      PlaybackPlatform.server => const <PlaybackCapabilities>[serverTranscode],
    };
  }

  static ClientCapabilities clientCapabilities(PlaybackCapabilities caps) {
    return switch (caps.backend) {
      PlaybackBackend.androidMpv ||
      PlaybackBackend.appleMpvKit ||
      PlaybackBackend.desktopLibmpv => ClientCapabilities(
        profile: caps.displayName,
        platform: caps.platform,
        backend: caps.backend.name,
        videoCodecs: const <String>[
          'h264',
          'hevc',
          'av1',
          'vp9',
          'mpeg2video',
        ],
        audioCodecs: const <String>[
          'aac',
          'ac3',
          'eac3',
          'mp2',
          'mp3',
          'opus',
        ],
        containers: const <String>['hls', 'mpegts', 'mp4', 'mkv', 'dash'],
      ),
      PlaybackBackend.androidExoPlayer => ClientCapabilities(
        profile: caps.displayName,
        platform: caps.platform,
        backend: caps.backend.name,
        videoCodecs: const <String>['h264'],
        audioCodecs: const <String>['aac', 'mp3'],
        containers: [
          if (caps.supportsHls) 'hls',
          if (caps.supportsMpegTs) 'mpegts',
          if (caps.supportsMp4) 'mp4',
        ],
        maxHeight: 1080,
        maxBitrateKbps: 20000,
        hdr: false,
      ),
      PlaybackBackend.appleAvKit => ClientCapabilities(
        profile: caps.displayName,
        platform: caps.platform,
        backend: caps.backend.name,
        videoCodecs: const <String>['h264'],
        audioCodecs: const <String>['aac'],
        containers: [
          if (caps.supportsHls) 'hls',
          if (caps.supportsMpegTs) 'mpegts',
          if (caps.supportsMp4) 'mp4',
        ],
        maxHeight: 1080,
        maxBitrateKbps: 20000,
        hdr: false,
      ),
      PlaybackBackend.serverTranscode => ClientCapabilities(
        profile: caps.displayName,
        platform: caps.platform,
        backend: caps.backend.name,
        videoCodecs: const <String>['h264'],
        audioCodecs: const <String>['aac'],
        containers: [
          if (caps.supportsHls) 'hls',
          if (caps.supportsMpegTs) 'mpegts',
          if (caps.supportsMp4) 'mp4',
        ],
        maxHeight: 1080,
        hdr: false,
      ),
    };
  }

  List<String> get unsupportedFeatures {
    final features = <String>[];
    if (!supportsDirectStreams) features.add('direct-streams');
    if (!supportsHls) features.add('hls');
    if (!supportsMpegTs) features.add('mpeg-ts');
    if (!supportsMp4) features.add('mp4');
    if (!supportsAdvancedCodecs) features.add('advanced-codecs');
    if (!supportsAudioTrackSelection) features.add('audio-track-selection');
    if (!supportsSubtitleTrackSelection) {
      features.add('subtitle-track-selection');
    }
    if (!supportsEmbeddedSubtitles) features.add('embedded-subtitles');
    if (!supportsExternalSubtitles) features.add('external-subtitles');
    if (!supportsAdvancedSubtitleFormats) {
      features.add('advanced-subtitle-formats');
    }
    if (!supportsPlaybackSpeed) features.add('playback-speed');
    if (!supportsSeek) features.add('seek');
    if (!supportsLiveSeek) features.add('live-seek');
    return List<String>.unmodifiable(features);
  }
}

class ClientCapabilities {
  const ClientCapabilities({
    required this.profile,
    required this.platform,
    this.backend,
    required this.videoCodecs,
    required this.audioCodecs,
    required this.containers,
    this.maxHeight,
    this.maxBitrateKbps,
    this.hdr,
  });

  final String profile;
  final PlaybackPlatform platform;
  final String? backend;
  final List<String> videoCodecs;
  final List<String> audioCodecs;
  final List<String> containers;
  final int? maxHeight;
  final int? maxBitrateKbps;
  final bool? hdr;

  Map<String, Object?> toJson() => <String, Object?>{
    'profile': profile,
    'platform': platform.name,
    if (backend != null) 'backend': backend,
    'video_codecs': videoCodecs,
    'audio_codecs': audioCodecs,
    'containers': containers,
    if (maxHeight != null) 'max_height': maxHeight,
    if (maxBitrateKbps != null) 'max_bitrate_kbps': maxBitrateKbps,
    if (hdr != null) 'hdr': hdr,
  };
}
