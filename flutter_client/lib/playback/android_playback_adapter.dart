import 'dart:async';

import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

enum VideoCodec { h264, h265, av1, mpeg2, unknown }

enum AudioCodec { aac, ac3, eac3, dts, mp3, unknown }

class AndroidPlaybackProbe {
  const AndroidPlaybackProbe({
    required this.hardwareCodecs,
    required this.passthroughAudioCodecs,
    required this.mpvAvailable,
    required this.serverTranscodeAvailable,
  });

  final Set<VideoCodec> hardwareCodecs;
  final Set<AudioCodec> passthroughAudioCodecs;
  final bool mpvAvailable;
  final bool serverTranscodeAvailable;
}

class AndroidBackendCapabilities {
  const AndroidBackendCapabilities({required this.probe});

  final AndroidPlaybackProbe probe;

  bool get supportsSubtitles => true;
  bool get supportsAudioTracks => true;

  List<PlaybackBackend> get fallbackOrder {
    return <PlaybackBackend>[
      PlaybackBackend.androidExoPlayer,
      if (probe.serverTranscodeAvailable) PlaybackBackend.serverTranscode,
    ];
  }

  bool supportsVideo(VideoCodec codec) => probe.hardwareCodecs.contains(codec);

  bool supportsAudio(AudioCodec codec) {
    return switch (codec) {
      AudioCodec.aac || AudioCodec.mp3 => true,
      AudioCodec.ac3 ||
      AudioCodec.eac3 ||
      AudioCodec.dts => probe.passthroughAudioCodecs.contains(codec),
      AudioCodec.unknown => false,
    };
  }
}

class AndroidPlaybackAdapter implements PlayerAdapter, VideoTextureProvider {
  AndroidPlaybackAdapter({
    required AndroidPlaybackProbe probe,
    AndroidMedia3Host? media3Host,
  }) : androidCapabilities = AndroidBackendCapabilities(probe: probe),
       _media3Host = media3Host ?? const MethodChannelAndroidMedia3Host() {
    _eventSubscription = _media3Host.events.listen(_handleNativeEvent);
  }

  final AndroidBackendCapabilities androidCapabilities;
  final AndroidMedia3Host _media3Host;
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();
  final List<String> _decisionLog = <String>[];
  StreamSubscription<AndroidMedia3Event>? _eventSubscription;

  PlaybackBackend _activeBackend = PlaybackBackend.androidExoPlayer;
  int? _textureId;

  @override
  int? get textureId => _textureId;
  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.androidExoPlayer,
  );

  PlaybackBackend get activeBackend => _activeBackend;

  List<String> get decisionLog => List<String>.unmodifiable(_decisionLog);

  @override
  PlaybackCapabilities get capabilities {
    return switch (_activeBackend) {
      PlaybackBackend.androidExoPlayer => PlaybackCapabilities.androidExoPlayer,
      PlaybackBackend.androidMpv => PlaybackCapabilities.androidMpv,
      PlaybackBackend.serverTranscode => PlaybackCapabilities.serverTranscode,
      PlaybackBackend.appleMpvKit ||
      PlaybackBackend.appleAvKit ||
      PlaybackBackend.desktopLibmpv => PlaybackCapabilities.androidExoPlayer,
    };
  }

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    final fallbackReason = _fallbackReason(source);
    if (fallbackReason == null) {
      _activeBackend = PlaybackBackend.androidExoPlayer;
      _decisionLog.add('direct:exo-player');
      _emit(
        PlaybackState(
          backend: _activeBackend,
          status: PlaybackStatus.loading,
          source: source,
          position: source.startPosition,
        ),
      );
      try {
        await _media3Host.load(source);
      } on PlatformException catch (error) {
        final exception = PlaybackException(
          message: error.message ?? 'Android Media3 load failed',
          backend: PlaybackBackend.androidExoPlayer,
          code: error.code,
          recoverable: true,
        );
        _errorController.add(PlaybackError.fromException(exception));
        throw exception;
      }
      return;
    } else {
      _recordMpvFutureGate(fallbackReason);
    }

    if (androidCapabilities.probe.serverTranscodeAvailable) {
      _activeBackend = PlaybackBackend.serverTranscode;
      _decisionLog.add('fallback:server-transcode:$fallbackReason');
    } else {
      final error = PlaybackException.unsupported(
        'Android Media3 cannot handle ${source.uri} and server transcode is unavailable',
        backend: PlaybackBackend.androidExoPlayer,
      );
      _decisionLog.add('error:unsupported:$fallbackReason');
      _errorController.add(PlaybackError.fromException(error));
      throw error;
    }

    _emit(
      PlaybackState(
        backend: _activeBackend,
        status: PlaybackStatus.ready,
        source: source,
        position: source.startPosition,
        audioTracks: const <PlaybackTrack>[
          PlaybackTrack(id: 'primary', label: 'Primary audio'),
        ],
        subtitleTracks: const <PlaybackTrack>[
          PlaybackTrack(id: 'embedded', label: 'Embedded subtitles'),
        ],
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_activeBackend == PlaybackBackend.androidExoPlayer) {
      await _media3Host.play();
    }
    _emit(_state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    if (_activeBackend == PlaybackBackend.androidExoPlayer) {
      await _media3Host.pause();
    }
    _emit(_state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    if (_activeBackend == PlaybackBackend.androidExoPlayer) {
      await _media3Host.seek(position);
    }
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> stop() async {
    if (_activeBackend == PlaybackBackend.androidExoPlayer) {
      await _media3Host.stop();
    }
    _textureId = null;
    _emit(_state.copyWith(status: PlaybackStatus.stopped));
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {
    if (_activeBackend == PlaybackBackend.androidExoPlayer) {
      await _media3Host.setAudioTrack(trackId);
    }
    _emit(_state.copyWith(selectedAudioTrackId: trackId));
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    if (_activeBackend == PlaybackBackend.androidExoPlayer) {
      await _media3Host.setSubtitleTrack(trackId);
    }
    _emit(_state.copyWith(selectedSubtitleTrackId: trackId));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _emit(_state.copyWith(playbackSpeed: speed));
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _media3Host.dispose();
    await _stateController.close();
    await _errorController.close();
  }

  String? _fallbackReason(PlaybackSource source) {
    final decoderFailure = source.metadata['decoderFailure'];
    if (decoderFailure == 'black-screen') return 'black-screen';
    if (decoderFailure == 'decoder-failure') return 'decoder-failure';

    final videoCodecName = source.videoCodec;
    if (videoCodecName != null) {
      final videoCodec = _videoCodecFromSource(videoCodecName);
      if (videoCodec == VideoCodec.unknown ||
          !androidCapabilities.supportsVideo(videoCodec)) {
        return 'unsupported-codec';
      }
    }

    final audioCodecName = source.audioCodec;
    if (audioCodecName != null) {
      final audioCodec = _audioCodecFromSource(audioCodecName);
      if (audioCodec == AudioCodec.unknown ||
          !androidCapabilities.supportsAudio(audioCodec)) {
        return 'unsupported-codec';
      }
    }

    return null;
  }

  VideoCodec _videoCodecFromSource(String? value) {
    return switch (value?.toLowerCase()) {
      'h264' || 'avc' => VideoCodec.h264,
      'h265' || 'hevc' => VideoCodec.h265,
      'av1' => VideoCodec.av1,
      'mpeg2' || 'mpeg-2' => VideoCodec.mpeg2,
      _ => VideoCodec.unknown,
    };
  }

  AudioCodec _audioCodecFromSource(String? value) {
    return switch (value?.toLowerCase()) {
      'aac' => AudioCodec.aac,
      'ac3' || 'ac-3' => AudioCodec.ac3,
      'eac3' || 'e-ac-3' => AudioCodec.eac3,
      'dts' => AudioCodec.dts,
      'mp3' => AudioCodec.mp3,
      _ => AudioCodec.unknown,
    };
  }

  void _emit(PlaybackState state) {
    _state = state;
    _stateController.add(state);
  }

  void _recordMpvFutureGate(String fallbackReason) {
    if (!androidCapabilities.probe.mpvAvailable) return;
    _decisionLog.add('android-mpv:disabled-future-gated:$fallbackReason');
  }

  void _handleNativeEvent(AndroidMedia3Event event) {
    if (_state.source == null && event.uri == null) return;
    if (event.type == AndroidMedia3EventType.error) {
      _errorController.add(
        PlaybackError(
          backend: PlaybackBackend.androidExoPlayer,
          message: event.message ?? 'Android Media3 playback failed',
          code: event.code ?? 'android-media3-error',
          recoverable: event.recoverable,
        ),
      );
      return;
    }

    // Capture the Flutter texture ID sent by the native plugin on first load.
    if (event.textureId != null) {
      _textureId = event.textureId;
    }

    final status = switch (event.type) {
      AndroidMedia3EventType.buffering => PlaybackStatus.buffering,
      AndroidMedia3EventType.ready => PlaybackStatus.ready,
      AndroidMedia3EventType.playing => PlaybackStatus.playing,
      AndroidMedia3EventType.end => PlaybackStatus.completed,
      AndroidMedia3EventType.stopped => PlaybackStatus.stopped,
      AndroidMedia3EventType.disposed => PlaybackStatus.stopped,
      AndroidMedia3EventType.error => _state.status,
    };
    var nextState = _state.copyWith(
      backend: PlaybackBackend.androidExoPlayer,
      status: status,
      position: event.position ?? _state.position,
      duration: event.duration,
      audioTracks: event.audioTracks,
      subtitleTracks: event.subtitleTracks,
    );
    if (event.hasSelectedAudioTrackId) {
      nextState = nextState.copyWith(
        selectedAudioTrackId: event.selectedAudioTrackId,
      );
    }
    if (event.hasSelectedSubtitleTrackId) {
      nextState = nextState.copyWith(
        selectedSubtitleTrackId: event.selectedSubtitleTrackId,
      );
    }
    _emit(nextState);
  }
}

abstract class AndroidMedia3Host {
  Stream<AndroidMedia3Event> get events;

  Future<void> load(PlaybackSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setAudioTrack(String? trackId);
  Future<void> setSubtitleTrack(String? trackId);
  Future<void> dispose();
}

class MethodChannelAndroidMedia3Host implements AndroidMedia3Host {
  const MethodChannelAndroidMedia3Host({
    MethodChannel methodChannel = const MethodChannel(_methodChannelName),
    EventChannel eventChannel = const EventChannel(_eventChannelName),
  }) : this._(methodChannel: methodChannel, eventChannel: eventChannel);

  const MethodChannelAndroidMedia3Host._({
    required this._methodChannel,
    required this._eventChannel,
  });

  static const String _methodChannelName = 'm3u_tv/android_media3';
  static const String _eventChannelName = 'm3u_tv/android_media3/events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Stream<AndroidMedia3Event> get events =>
      _eventChannel.receiveBroadcastStream().map(
        (event) => AndroidMedia3Event.fromMap(
          Map<String, Object?>.from(event! as Map<Object?, Object?>),
        ),
      );

  @override
  Future<void> load(PlaybackSource source) async {
    await _methodChannel.invokeMethod<Object?>('load', <String, Object?>{
      'source': <String, Object?>{
        'uri': source.uri,
        'title': source.title,
        'startPositionMs': source.startPosition.inMilliseconds,
        'isLive': source.isLive,
        'videoCodec': source.videoCodec,
        'audioCodec': source.audioCodec,
        'userAgent': source.userAgent,
        'headers': source.headers,
        'metadata': source.metadata,
      },
    });
  }

  @override
  Future<void> play() => _methodChannel.invokeMethod<void>('play');

  @override
  Future<void> pause() => _methodChannel.invokeMethod<void>('pause');

  @override
  Future<void> seek(Duration position) => _methodChannel.invokeMethod<void>(
    'seek',
    <String, Object?>{'positionMs': position.inMilliseconds},
  );

  @override
  Future<void> stop() => _methodChannel.invokeMethod<void>('stop');

  @override
  Future<void> setAudioTrack(String? trackId) =>
      _methodChannel.invokeMethod<void>(
        'setAudioTrack',
        <String, Object?>{'trackId': trackId},
      );

  @override
  Future<void> setSubtitleTrack(String? trackId) =>
      _methodChannel.invokeMethod<void>(
        'setSubtitleTrack',
        <String, Object?>{'trackId': trackId},
      );

  @override
  Future<void> dispose() async {
    try {
      await _methodChannel.invokeMethod<void>('dispose');
    } on MissingPluginException {
      return;
    }
  }
}

enum AndroidMedia3EventType {
  buffering,
  ready,
  playing,
  error,
  end,
  stopped,
  disposed,
}

class AndroidMedia3Event {
  const AndroidMedia3Event({
    required this.type,
    this.uri,
    this.position,
    this.duration,
    this.textureId,
    this.audioTracks,
    this.subtitleTracks,
    this.selectedAudioTrackId,
    this.selectedSubtitleTrackId,
    bool? hasSelectedAudioTrackId,
    bool? hasSelectedSubtitleTrackId,
    this.code,
    this.message,
    this.recoverable = false,
  }) : hasSelectedAudioTrackId =
           hasSelectedAudioTrackId ?? selectedAudioTrackId != null,
       hasSelectedSubtitleTrackId =
           hasSelectedSubtitleTrackId ?? selectedSubtitleTrackId != null;

  factory AndroidMedia3Event.fromMap(Map<String, Object?> map) {
    return AndroidMedia3Event(
      type: _typeFromString(map['type'] as String?),
      uri: map['uri'] as String?,
      position: map['positionMs'] is num
          ? Duration(milliseconds: (map['positionMs']! as num).round())
          : null,
      duration: map['durationMs'] is num
          ? Duration(milliseconds: (map['durationMs']! as num).round())
          : null,
      textureId: (map['textureId'] as num?)?.toInt(),
      audioTracks: _tracksFromMap(map['audioTracks']),
      subtitleTracks: _tracksFromMap(map['subtitleTracks']),
      selectedAudioTrackId: map['selectedAudioTrackId'] as String?,
      selectedSubtitleTrackId: map['selectedSubtitleTrackId'] as String?,
      hasSelectedAudioTrackId: map.containsKey('selectedAudioTrackId'),
      hasSelectedSubtitleTrackId: map.containsKey('selectedSubtitleTrackId'),
      code: map['code'] as String?,
      message: map['message'] as String?,
      recoverable: map['recoverable'] == true,
    );
  }

  final AndroidMedia3EventType type;
  final String? uri;
  final Duration? position;
  final Duration? duration;
  final int? textureId;
  final List<PlaybackTrack>? audioTracks;
  final List<PlaybackTrack>? subtitleTracks;
  final String? selectedAudioTrackId;
  final String? selectedSubtitleTrackId;
  final bool hasSelectedAudioTrackId;
  final bool hasSelectedSubtitleTrackId;
  final String? code;
  final String? message;
  final bool recoverable;

  static List<PlaybackTrack>? _tracksFromMap(Object? raw) {
    if (raw == null) return null;
    return (raw as List<Object?>)
        .map(
          (item) => Map<String, Object?>.from(item! as Map<Object?, Object?>),
        )
        .map(
          (track) => PlaybackTrack(
            id: track['id']! as String,
            label: track['label']! as String,
            language: track['language'] as String?,
          ),
        )
        .toList(growable: false);
  }

  static AndroidMedia3EventType _typeFromString(String? value) {
    return switch (value) {
      'buffering' => AndroidMedia3EventType.buffering,
      'ready' => AndroidMedia3EventType.ready,
      'playing' => AndroidMedia3EventType.playing,
      'error' => AndroidMedia3EventType.error,
      'end' => AndroidMedia3EventType.end,
      'stopped' => AndroidMedia3EventType.stopped,
      'disposed' => AndroidMedia3EventType.disposed,
      _ => AndroidMedia3EventType.error,
    };
  }
}
