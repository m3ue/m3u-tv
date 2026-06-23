import 'dart:async';

import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

/// Dart adapter for the iOS AVKit/AVPlayer playback plugin.
///
/// Communicates with AvKitPlaybackPlugin.swift via MethodChannel +
/// EventChannel, using the same event contract as the Android Media3 adapter.
class AppleAvKitBackend implements PlayerAdapter, VideoTextureProvider {
  AppleAvKitBackend() : _host = const _MethodChannelAvKitHost() {
    _eventSub = _host.events.listen(_handleEvent);
  }

  final _AvKitHost _host;
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();
  StreamSubscription<_AvKitEvent>? _eventSub;

  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.appleAvKit,
  );
  int? _textureId;

  @override
  int? get textureId => _textureId;

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.appleAvKit;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    _emit(
      _state.copyWith(
        backend: PlaybackBackend.appleAvKit,
        status: PlaybackStatus.loading,
        source: source,
        position: source.startPosition,
      ),
    );
    try {
      final result = await _host.load(source);
      _textureId = result['textureId'] as int?;
    } on PlatformException catch (e) {
      throw PlaybackException(
        message: e.message ?? 'AVKit load failed',
        backend: PlaybackBackend.appleAvKit,
        code: e.code,
        recoverable: true,
      );
    }
  }

  @override
  Future<void> play() async {
    await _host.play();
    _emit(_state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    await _host.pause();
    _emit(_state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    await _host.seek(position);
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> stop() async {
    await _host.stop();
    _emit(_state.copyWith(status: PlaybackStatus.stopped));
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {
    await _host.setAudioTrack(trackId);
    _emit(_state.copyWith(selectedAudioTrackId: trackId));
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    await _host.setSubtitleTrack(trackId);
    _emit(_state.copyWith(selectedSubtitleTrackId: trackId));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _emit(_state.copyWith(playbackSpeed: speed));
  }

  @override
  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _host.dispose();
    await _stateController.close();
    await _errorController.close();
  }

  void _handleEvent(_AvKitEvent event) {
    if (event.type == _AvKitEventType.error) {
      _errorController.add(
        PlaybackError(
          backend: PlaybackBackend.appleAvKit,
          message: event.message ?? 'AVKit playback failed',
          code: event.code ?? 'avkit-error',
          recoverable: event.recoverable,
        ),
      );
      return;
    }
    final status = switch (event.type) {
      _AvKitEventType.buffering => PlaybackStatus.buffering,
      _AvKitEventType.ready => PlaybackStatus.ready,
      _AvKitEventType.playing => PlaybackStatus.playing,
      _AvKitEventType.end => PlaybackStatus.completed,
      _AvKitEventType.stopped ||
      _AvKitEventType.disposed => PlaybackStatus.stopped,
      _AvKitEventType.error => _state.status,
    };
    var nextState = _state.copyWith(
      backend: PlaybackBackend.appleAvKit,
      status: status,
      position: event.position ?? _state.position,
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

  void _emit(PlaybackState state) {
    _state = state;
    _stateController.add(state);
  }
}

// --- Host abstraction (private — uses private event types) ---

abstract class _AvKitHost {
  Stream<_AvKitEvent> get events;

  Future<Map<String, dynamic>> load(PlaybackSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setAudioTrack(String? trackId);
  Future<void> setSubtitleTrack(String? trackId);
  Future<void> dispose();
}

class _MethodChannelAvKitHost implements _AvKitHost {
  const _MethodChannelAvKitHost({
    MethodChannel methodChannel = const MethodChannel('m3u_tv/apple_avkit'),
    EventChannel eventChannel = const EventChannel('m3u_tv/apple_avkit/events'),
  }) : _method = methodChannel,
       _event = eventChannel;

  final MethodChannel _method;
  final EventChannel _event;

  @override
  Stream<_AvKitEvent> get events => _event.receiveBroadcastStream().map((raw) {
    final map = Map<String, Object?>.from(raw! as Map<Object?, Object?>);
    return _AvKitEvent.fromMap(map);
  });

  @override
  Future<Map<String, dynamic>> load(PlaybackSource source) async {
    final result = await _method.invokeMethod<Object?>(
      'load',
      <String, Object?>{
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
      },
    );
    if (result is Map) return Map<String, dynamic>.from(result);
    return const <String, dynamic>{};
  }

  @override
  Future<void> play() => _method.invokeMethod<void>('play');

  @override
  Future<void> pause() => _method.invokeMethod<void>('pause');

  @override
  Future<void> seek(Duration position) => _method.invokeMethod<void>(
    'seek',
    <String, Object?>{'positionMs': position.inMilliseconds},
  );

  @override
  Future<void> stop() => _method.invokeMethod<void>('stop');

  @override
  Future<void> setAudioTrack(String? trackId) => _method.invokeMethod<void>(
    'setAudioTrack',
    <String, Object?>{'trackId': trackId},
  );

  @override
  Future<void> setSubtitleTrack(String? trackId) => _method.invokeMethod<void>(
    'setSubtitleTrack',
    <String, Object?>{'trackId': trackId},
  );

  @override
  Future<void> dispose() async {
    try {
      await _method.invokeMethod<void>('dispose');
    } on MissingPluginException {
      return;
    }
  }
}

// --- Event model ---

enum _AvKitEventType {
  buffering,
  ready,
  playing,
  error,
  end,
  stopped,
  disposed,
}

class _AvKitEvent {
  const _AvKitEvent({
    required this.type,
    this.position,
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

  factory _AvKitEvent.fromMap(Map<String, Object?> map) => _AvKitEvent(
    type: _typeFrom(map['type'] as String?),
    position: map['positionMs'] is num
        ? Duration(milliseconds: (map['positionMs']! as num).round())
        : null,
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

  final _AvKitEventType type;
  final Duration? position;
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

  static _AvKitEventType _typeFrom(String? value) => switch (value) {
    'buffering' => _AvKitEventType.buffering,
    'ready' => _AvKitEventType.ready,
    'playing' => _AvKitEventType.playing,
    'error' => _AvKitEventType.error,
    'end' => _AvKitEventType.end,
    'stopped' => _AvKitEventType.stopped,
    'disposed' => _AvKitEventType.disposed,
    _ => _AvKitEventType.error,
  };
}
