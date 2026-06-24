import 'dart:async';

import 'package:m3u_tv/playback/playback_capabilities.dart';

abstract class PlayerAdapter {
  PlaybackCapabilities get capabilities;
  Stream<PlaybackState> get onState;
  Stream<PlaybackError> get onError;

  Future<void> load(PlaybackSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
  Future<void> setAudioTrack(String? trackId);
  Future<void> setSubtitleTrack(String? trackId);
  Future<void> setPlaybackSpeed(double speed);
}

abstract class VideoTextureProvider {
  int? get textureId;
}

class FallbackPlayerAdapter implements PlayerAdapter {
  FallbackPlayerAdapter({required this.primary, required this.fallback})
    : _active = primary;

  final PlayerAdapter primary;
  final PlayerAdapter fallback;
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();
  PlayerAdapter _active;
  PlayerAdapter? _boundAdapter;
  StreamSubscription<PlaybackState>? _stateSubscription;
  StreamSubscription<PlaybackError>? _errorSubscription;

  @override
  PlaybackCapabilities get capabilities => _active.capabilities;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    _active = primary;
    await _bind(primary);

    try {
      await primary.load(source);
    } on PlaybackException catch (error) {
      if (!error.isUnsupported) {
        _errorController.add(PlaybackError.fromException(error));
        rethrow;
      }

      _active = fallback;
      await _bind(fallback);
      await fallback.load(source);
    }
  }

  @override
  Future<void> play() => _active.play();

  @override
  Future<void> pause() => _active.pause();

  @override
  Future<void> seek(Duration position) => _active.seek(position);

  @override
  Future<void> stop() => _active.stop();

  @override
  Future<void> setAudioTrack(String? trackId) => _active.setAudioTrack(trackId);

  @override
  Future<void> setSubtitleTrack(String? trackId) =>
      _active.setSubtitleTrack(trackId);

  @override
  Future<void> setPlaybackSpeed(double speed) =>
      _active.setPlaybackSpeed(speed);

  @override
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _errorSubscription?.cancel();
    await primary.dispose();
    if (!identical(primary, fallback)) {
      await fallback.dispose();
    }
    await _stateController.close();
    await _errorController.close();
  }

  Future<void> _bind(PlayerAdapter adapter) async {
    if (identical(_boundAdapter, adapter)) return;

    await _stateSubscription?.cancel();
    await _errorSubscription?.cancel();
    _boundAdapter = adapter;
    _stateSubscription = adapter.onState.listen(_stateController.add);
    _errorSubscription = adapter.onError.listen(_errorController.add);
  }
}

enum PlaybackStatus {
  idle,
  loading,
  ready,
  playing,
  paused,
  buffering,
  stopped,
  completed,
}

class PlaybackSource {
  const PlaybackSource({
    required this.uri,
    this.title,
    this.startPosition = Duration.zero,
    this.isLive = false,
    this.videoCodec,
    this.audioCodec,
    this.userAgent,
    this.headers = const <String, String>{},
    this.metadata = const <String, Object?>{},
  });

  final String uri;
  final String? title;
  final Duration startPosition;
  final bool isLive;
  final String? videoCodec;
  final String? audioCodec;
  final String? userAgent;
  final Map<String, String> headers;
  final Map<String, Object?> metadata;

  double? get videoAspectRatio => playbackAspectRatioFromMetadata(metadata);
}

double? playbackAspectRatioFromMetadata(Map<String, Object?> metadata) {
  return playbackAspectRatioFromValues(
    aspectRatio:
        metadata['videoAspectRatio'] ??
        metadata['displayAspectRatio'] ??
        metadata['aspectRatio'],
    width: metadata['videoWidth'] ?? metadata['width'],
    height: metadata['videoHeight'] ?? metadata['height'],
  );
}

double? playbackAspectRatioFromValues({
  Object? aspectRatio,
  Object? width,
  Object? height,
}) {
  final parsedRatio = _asPositiveDouble(aspectRatio);
  if (parsedRatio != null) return parsedRatio;

  final parsedWidth = _asPositiveDouble(width);
  final parsedHeight = _asPositiveDouble(height);
  if (parsedWidth == null || parsedHeight == null) return null;
  return parsedWidth / parsedHeight;
}

double? _asPositiveDouble(Object? value) {
  if (value is num && value > 0) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

class PlaybackTrack {
  const PlaybackTrack({required this.id, required this.label, this.language});

  final String id;
  final String label;
  final String? language;
}

class PlaybackState {
  const PlaybackState({
    required this.backend,
    required this.status,
    this.source,
    this.position = Duration.zero,
    this.duration,
    this.audioTracks = const <PlaybackTrack>[],
    this.subtitleTracks = const <PlaybackTrack>[],
    this.selectedAudioTrackId,
    this.selectedSubtitleTrackId,
    this.playbackSpeed = 1,
    this.videoAspectRatio,
  });

  const PlaybackState.idle({required this.backend})
    : status = PlaybackStatus.idle,
      source = null,
      position = Duration.zero,
      duration = null,
      audioTracks = const <PlaybackTrack>[],
      subtitleTracks = const <PlaybackTrack>[],
      selectedAudioTrackId = null,
      selectedSubtitleTrackId = null,
      playbackSpeed = 1,
      videoAspectRatio = null;

  final PlaybackBackend backend;
  final PlaybackStatus status;
  final PlaybackSource? source;
  final Duration position;
  final Duration? duration;
  final List<PlaybackTrack> audioTracks;
  final List<PlaybackTrack> subtitleTracks;
  final String? selectedAudioTrackId;
  final String? selectedSubtitleTrackId;
  final double playbackSpeed;
  final double? videoAspectRatio;

  PlaybackState copyWith({
    PlaybackBackend? backend,
    PlaybackStatus? status,
    PlaybackSource? source,
    Duration? position,
    Duration? duration,
    List<PlaybackTrack>? audioTracks,
    List<PlaybackTrack>? subtitleTracks,
    Object? selectedAudioTrackId = _unchanged,
    Object? selectedSubtitleTrackId = _unchanged,
    double? playbackSpeed,
    double? videoAspectRatio,
  }) {
    return PlaybackState(
      backend: backend ?? this.backend,
      status: status ?? this.status,
      source: source ?? this.source,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      audioTracks: audioTracks ?? this.audioTracks,
      subtitleTracks: subtitleTracks ?? this.subtitleTracks,
      selectedAudioTrackId: identical(selectedAudioTrackId, _unchanged)
          ? this.selectedAudioTrackId
          : selectedAudioTrackId as String?,
      selectedSubtitleTrackId: identical(selectedSubtitleTrackId, _unchanged)
          ? this.selectedSubtitleTrackId
          : selectedSubtitleTrackId as String?,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      videoAspectRatio: videoAspectRatio ?? this.videoAspectRatio,
    );
  }
}

class PlaybackError {
  const PlaybackError({
    required this.backend,
    required this.message,
    required this.code,
    this.recoverable = false,
  });

  factory PlaybackError.fromException(PlaybackException exception) {
    return PlaybackError(
      backend: exception.backend,
      message: exception.message,
      code: exception.code,
      recoverable: exception.recoverable,
    );
  }

  final PlaybackBackend backend;
  final String message;
  final String code;
  final bool recoverable;
}

class PlaybackException implements Exception {
  const PlaybackException({
    required this.message,
    required this.backend,
    required this.code,
    this.recoverable = false,
  });

  const PlaybackException.unsupported(
    String message, {
    required PlaybackBackend backend,
  }) : this(
         message: message,
         backend: backend,
         code: 'unsupported',
         recoverable: true,
       );

  final String message;
  final PlaybackBackend backend;
  final String code;
  final bool recoverable;

  bool get isUnsupported => code == 'unsupported';

  @override
  String toString() => 'PlaybackException($backend, $code): $message';
}

class _Unchanged {
  const _Unchanged();
}

const _Unchanged _unchanged = _Unchanged();
