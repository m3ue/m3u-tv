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
