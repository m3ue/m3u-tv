import 'dart:async';

import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

// Shared broadcast event stream, same rationale as desktop_libmpv_backend.dart:
// receiveBroadcastStream() must be listened to exactly once and shared across
// instances (each [MacMpvNativeBackend] filters it down to its own [_viewId]
// in [_applyEvent]). Do not wrap in .asBroadcastStream() -- its pause/resume
// semantics break resubscription across sequential loads/disposes.
Stream<MacMpvEvent>? _sharedMpvEvents;
Stream<MacMpvEvent> _mpvEvents(EventChannel channel) {
  return _sharedMpvEvents ??= channel.receiveBroadcastStream().map((raw) {
    final map = Map<String, Object?>.from(raw! as Map<Object?, Object?>);
    return MacMpvEvent.fromMap(map);
  });
}

int _nextViewId = 0;

/// Native macOS mpv backend rendered through a `FlutterPlatformView`
/// (`AppKitView`) driving `vo=gpu-next`/`gpu-context=moltenvk`/
/// `hwdec=videotoolbox` directly, bypassing the Flutter texture bridge that
/// `MediaKitDesktopAdapter` goes through. Modeled on
/// `macos/Runner/MpvPlayer/MpvPlayerCore.swift`, itself adapted from the
/// open-source Plezy player (github.com/edde746/plezy, GPL-3.0).
///
/// Unlike `DesktopLibmpvBackend`, the native player instance is addressed by
/// a `_viewId` the Dart side generates up front (so the `AppKitView` can be
/// created and the native player instance attached to it before `load()` is
/// ever called), not a handle returned from a `load` response.
///
/// Subtitles are rendered natively (mpv's own libass compositing, baked into
/// the `gpu-next`/libplacebo output), so this adapter does not implement
/// `SubtitleControllerProvider` -- same as `DesktopLibmpvBackend`.
class MacMpvNativeBackend
    implements PlayerAdapter, PlatformViewProvider, MultiviewBackend {
  MacMpvNativeBackend({MethodChannel? channel, EventChannel? eventChannel})
    : _viewId = _nextViewId++,
      _channel = channel ?? const MethodChannel(_methodChannelName),
      _eventChannel = eventChannel ?? const EventChannel(_eventChannelName) {
    _eventSubscription = _mpvEvents(_eventChannel).listen(
      _handleEvent,
      onError: _handleEventStreamError,
    );
  }

  static const String _methodChannelName = 'm3u_tv/mac_mpv';
  static const String _eventChannelName = 'm3u_tv/mac_mpv/events';
  static const String platformViewTypeId = 'm3u_tv/mac_mpv_view';

  final int _viewId;
  final MethodChannel _channel;
  final EventChannel _eventChannel;
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.macMpvNative,
  );
  int _lastSequence = -1;
  int _loadGeneration = 0;
  bool _errorEmitted = false;
  bool _disposed = false;
  Completer<void>? _readyCompleter;
  PlaybackException? _readyFailure;
  PlaybackSource? _pendingSource;
  StreamSubscription<Object?>? _eventSubscription;
  final List<MacMpvEvent> _pendingEvents = <MacMpvEvent>[];

  @override
  String get platformViewType => platformViewTypeId;

  @override
  Map<String, dynamic>? get platformViewCreationParams => <String, dynamic>{
    'viewId': _viewId,
  };

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.macMpvNative;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    _ensureNotDisposed();
    final generation = ++_loadGeneration;

    final ready = Completer<void>();
    _pendingSource = source;
    _readyCompleter = ready;
    _readyFailure = null;
    _lastSequence = -1;
    _errorEmitted = false;
    _pendingEvents.clear();

    try {
      final response = await _channel.invokeMapMethod<String, Object?>('load', {
        'viewId': _viewId,
        'uri': source.uri,
        'title': source.title,
        'startPositionMs': source.startPosition.inMilliseconds,
        'isLive': source.isLive,
        'userAgent': source.userAgent,
        'headers': source.headers,
      });

      if (!_isActiveLoad(generation)) return;
      final preResponseFailure = _readyFailure;
      if (preResponseFailure != null) {
        if (!_isActiveLoad(generation)) return;
        _clearLoading(ready);
        throw preResponseFailure;
      }
      final ok = response?['ok'] == true;
      if (!ok) {
        final message = response?['error'] as String? ?? 'mpv load failed';
        final code = response?['code'] as String? ?? 'mac-mpv-load-failed';
        final error = code == MacMpvUnavailableException.unavailableCode
            ? MacMpvUnavailableException(message)
            : PlaybackException(
                message: message,
                backend: capabilities.backend,
                code: code,
                recoverable: true,
              );
        _clearLoading(ready);
        throw error;
      }

      // Drain buffered events that arrived before the load response.
      final pendingEvents = List<MacMpvEvent>.of(_pendingEvents);
      _pendingEvents.clear();
      for (final event in pendingEvents) {
        if (event.viewId == _viewId) _applyEvent(event);
      }

      await ready.future;
      if (!_isActiveLoad(generation)) return;
      final failure = _readyFailure;
      _clearLoading(ready);
      if (failure != null) throw failure;
    } on PlaybackException {
      _clearLoading(ready);
      rethrow;
    } on Object catch (e) {
      if (!_isActiveLoad(generation)) return;
      _clearLoading(ready);
      throw PlaybackException(
        message: e.toString(),
        backend: capabilities.backend,
        code: 'mac-mpv-load-failed',
        recoverable: true,
      );
    }
  }

  @override
  Future<void> play() async {
    await _invokeControl('play');
  }

  @override
  Future<void> pause() async {
    await _invokeControl('pause');
  }

  @override
  Future<void> seek(Duration position) async {
    await _invokeControl('seek', <String, Object?>{
      'positionMs': position.inMilliseconds,
    });
  }

  @override
  Future<void> stop() async {
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ++_loadGeneration;
      ready.complete();
      if (identical(_readyCompleter, ready)) {
        _readyCompleter = null;
        _readyFailure = null;
        _pendingSource = null;
        _pendingEvents.clear();
      }
    }

    try {
      await _channel.invokeMethod<void>('stop', <String, Object?>{
        'viewId': _viewId,
      });
    } finally {
      if (_state.status != PlaybackStatus.stopped) {
        _emit(_state.copyWith(status: PlaybackStatus.stopped));
      }
    }
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {
    await _invokeControl('setAudioTrack', <String, Object?>{
      'trackId': trackId,
    });
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    await _invokeControl('setSubtitleTrack', <String, Object?>{
      'trackId': trackId,
    });
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    await _invokeControl('setPlaybackSpeed', <String, Object?>{'speed': speed});
  }

  @override
  Future<void> setVolume(double volume) async {
    // mpv's `volume` property (like media_kit's) is 0-100, not the 0-1 scale
    // [MultiviewBackend.setVolume] uses to match AVPlayer/ExoPlayer.
    await _invokeControl('setVolume', <String, Object?>{
      'volume': volume * 100,
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_loadGeneration;

    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) {
      ready.complete();
    }
    _readyCompleter = null;
    _readyFailure = null;
    _pendingSource = null;
    _pendingEvents.clear();

    await _eventSubscription?.cancel();

    await _channel.invokeMethod<void>('dispose', <String, Object?>{
      'viewId': _viewId,
    });

    await _stateController.close();
    await _errorController.close();
  }

  Future<void> _invokeControl(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    await _channel.invokeMethod<void>(method, <String, Object?>{
      'viewId': _viewId,
      ...arguments,
    });
  }

  void _handleEvent(MacMpvEvent event) {
    if (_disposed) return;
    if (event.kind == MacMpvEventKind.unknown) return;

    if (event.viewId != _viewId) return;

    // Buffer events that arrive before the load() response resolves; drained
    // in load() once it knows this event stream is active for this instance.
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted && _pendingSource != null) {
      _applyEvent(event);
      return;
    }

    _applyEvent(event);
  }

  void _applyEvent(MacMpvEvent event) {
    if (event.viewId != _viewId) return;
    if (event.sequence <= _lastSequence) return;
    _lastSequence = event.sequence;

    if (_errorEmitted) return;

    if (event.kind == MacMpvEventKind.error) {
      _errorEmitted = true;
      final error = PlaybackException(
        message: event.message ?? 'mac mpv error',
        backend: capabilities.backend,
        code: event.code ?? 'mac-mpv-error',
        recoverable: event.recoverable,
      );
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _failReady(error);
      } else {
        _errorController.add(PlaybackError.fromException(error));
      }
      return;
    }

    if (event.kind == MacMpvEventKind.endFile &&
        _readyCompleter != null &&
        !_readyCompleter!.isCompleted) {
      _errorEmitted = true;
      final error = PlaybackException(
        message: 'mac mpv ended before FILE_LOADED',
        backend: capabilities.backend,
        code: 'mac-mpv-ended-before-ready',
        recoverable: true,
      );
      _failReady(error);
      return;
    }

    final effectiveSource = _state.source ?? _pendingSource;
    if (effectiveSource == null && event.kind != MacMpvEventKind.shutdown) {
      return;
    }

    final nextState = MacMpvEventReducer.reduce(
      _state,
      event,
      effectiveSource ?? const PlaybackSource(uri: ''),
    );

    if (_readyCompleter != null &&
        !_readyCompleter!.isCompleted &&
        event.kind == MacMpvEventKind.fileLoaded) {
      _readyCompleter!.complete();
      _readyCompleter = null;
      _pendingSource = null;
    }

    _emit(nextState);
  }

  void _handleEventStreamError(Object error) {
    if (_disposed) return;
    final playbackError = PlaybackError(
      backend: capabilities.backend,
      message: error.toString(),
      code: 'event-stream-error',
      recoverable: true,
    );
    final failure = PlaybackException(
      message: playbackError.message,
      backend: playbackError.backend,
      code: playbackError.code,
      recoverable: playbackError.recoverable,
    );
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _failReady(failure);
    } else {
      _errorController.add(playbackError);
    }
  }

  void _emit(PlaybackState state) {
    if (_disposed || _stateController.isClosed) return;
    _state = state;
    _stateController.add(state);
  }

  void _failReady(PlaybackException error) {
    final ready = _readyCompleter;
    if (ready == null || ready.isCompleted) return;
    _readyFailure = error;
    ready.complete();
    _readyCompleter = null;
    _pendingSource = null;
  }

  void _clearLoading(Completer<void> ready) {
    if (_readyCompleter == ready) _readyCompleter = null;
    _pendingSource = null;
    _readyFailure = null;
  }

  bool _isActiveLoad(int generation) =>
      !_disposed && generation == _loadGeneration;

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MacMpvNativeBackend is disposed');
    }
  }
}

class MacMpvUnavailableException extends PlaybackException {
  MacMpvUnavailableException(String message)
    : super(
        message: message,
        backend: PlaybackBackend.macMpvNative,
        code: unavailableCode,
        recoverable: true,
      );

  static const String unavailableCode = 'backend_unavailable';
}

enum MacMpvEventKind {
  startFile,
  fileLoaded,
  playbackRestart,
  videoReconfig,
  endFile,
  stop,
  quit,
  error,
  shutdown,
  unknown,
}

class MacMpvEvent {
  const MacMpvEvent({
    required this.viewId,
    required this.sequence,
    required this.kind,
    this.position,
    this.duration,
    this.paused = false,
    this.buffering = false,
    this.eof = false,
    this.videoAspectRatio,
    this.speed,
    this.aid,
    this.sid,
    this.hasAid = false,
    this.hasSid = false,
    this.audioTracks,
    this.subtitleTracks,
    this.message,
    this.code,
    this.recoverable = false,
  });

  factory MacMpvEvent.fromMap(Map<String, Object?> map) {
    return MacMpvEvent(
      viewId: (map['viewId'] as num?)?.toInt() ?? 0,
      sequence: (map['sequence'] as num?)?.toInt() ?? 0,
      kind: _kindFromString(map['kind'] as String?),
      position: map['positionMs'] is num
          ? Duration(milliseconds: (map['positionMs']! as num).round())
          : Duration.zero,
      duration: _asPositiveDuration(map['durationMs']),
      paused: map['paused'] == true,
      buffering: map['buffering'] == true,
      eof: map['eof'] == true,
      videoAspectRatio: playbackAspectRatioFromValues(
        aspectRatio:
            map['videoAspectRatio'] ??
            map['displayAspectRatio'] ??
            map['aspectRatio'],
        width: map['videoWidth'] ?? map['width'],
        height: map['videoHeight'] ?? map['height'],
      ),
      speed: _asPositiveDouble(map['speed']),
      aid: _selectedTrackId(map['aid']),
      sid: _selectedTrackId(map['sid']),
      hasAid: map.containsKey('aid'),
      hasSid: map.containsKey('sid'),
      audioTracks: _tracksFromValue(map['audioTracks']),
      subtitleTracks: _tracksFromValue(map['subtitleTracks']),
      message: map['message'] as String?,
      code: map['code'] as String?,
      recoverable: map['recoverable'] == true,
    );
  }

  final int viewId;
  final int sequence;
  final MacMpvEventKind kind;
  final Duration? position;
  final Duration? duration;
  final bool paused;
  final bool buffering;
  final bool eof;
  final double? videoAspectRatio;
  final double? speed;
  final String? aid;
  final String? sid;
  final bool hasAid;
  final bool hasSid;
  final List<PlaybackTrack>? audioTracks;
  final List<PlaybackTrack>? subtitleTracks;
  final String? message;
  final String? code;
  final bool recoverable;

  static MacMpvEventKind _kindFromString(String? value) {
    return switch (value) {
      'START_FILE' => MacMpvEventKind.startFile,
      'FILE_LOADED' => MacMpvEventKind.fileLoaded,
      'PLAYBACK_RESTART' => MacMpvEventKind.playbackRestart,
      'VIDEO_RECONFIG' => MacMpvEventKind.videoReconfig,
      'END_FILE' => MacMpvEventKind.endFile,
      'STOP' => MacMpvEventKind.stop,
      'QUIT' => MacMpvEventKind.quit,
      'ERROR' => MacMpvEventKind.error,
      'SHUTDOWN' => MacMpvEventKind.shutdown,
      _ => MacMpvEventKind.unknown,
    };
  }

  static double? _asPositiveDouble(Object? value) {
    if (value is num && value > 0) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  static Duration? _asPositiveDuration(Object? value) {
    if (value is! num || value <= 0) return null;
    return Duration(milliseconds: value.round());
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String? _selectedTrackId(Object? value) {
    final id = _nonEmptyString(value);
    return id == null || id.toLowerCase() == 'no' ? null : id;
  }

  static List<PlaybackTrack>? _tracksFromValue(Object? value) {
    if (value is! List<Object?>) return null;
    final tracks = <PlaybackTrack>[];
    for (final item in value) {
      if (item is! Map<Object?, Object?>) continue;
      final id = _nonEmptyString(item['id']);
      if (id == null) continue;
      final language = _nonEmptyString(item['language']);
      final label = _nonEmptyString(item['label']) ?? language ?? id;
      tracks.add(PlaybackTrack(id: id, label: label, language: language));
    }
    return tracks;
  }
}

class MacMpvEventReducer {
  const MacMpvEventReducer._();

  static PlaybackState reduce(
    PlaybackState current,
    MacMpvEvent event,
    PlaybackSource source,
  ) {
    const backend = PlaybackBackend.macMpvNative;

    switch (event.kind) {
      case MacMpvEventKind.startFile:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.loading,
          source: source,
          position: source.startPosition,
        );
      case MacMpvEventKind.fileLoaded:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.ready,
          source: source,
          position: event.position ?? source.startPosition,
          duration: event.duration,
          videoAspectRatio: event.videoAspectRatio,
          playbackSpeed: event.speed,
          audioTracks: event.audioTracks ?? const <PlaybackTrack>[],
          subtitleTracks: event.subtitleTracks ?? const <PlaybackTrack>[],
          selectedAudioTrackId: event.hasAid ? event.aid : null,
          selectedSubtitleTrackId: event.hasSid ? event.sid : null,
          isAudioTrackSelectionKnown: event.hasAid,
          isSubtitleTrackSelectionKnown: event.hasSid,
        );
      case MacMpvEventKind.playbackRestart:
        final status = event.paused
            ? PlaybackStatus.paused
            : event.buffering
            ? PlaybackStatus.buffering
            : PlaybackStatus.playing;
        return current.copyWith(
          backend: backend,
          status: status,
          position: event.position ?? current.position,
          duration: event.duration ?? current.duration,
          videoAspectRatio: event.videoAspectRatio ?? current.videoAspectRatio,
          playbackSpeed: event.speed ?? current.playbackSpeed,
          audioTracks: event.audioTracks ?? current.audioTracks,
          subtitleTracks: event.subtitleTracks ?? current.subtitleTracks,
          selectedAudioTrackId: event.hasAid
              ? event.aid
              : current.selectedAudioTrackId,
          selectedSubtitleTrackId: event.hasSid
              ? event.sid
              : current.selectedSubtitleTrackId,
          isAudioTrackSelectionKnown:
              event.hasAid || current.isAudioTrackSelectionKnown,
          isSubtitleTrackSelectionKnown:
              event.hasSid || current.isSubtitleTrackSelectionKnown,
        );
      case MacMpvEventKind.videoReconfig:
        return current.copyWith(
          backend: backend,
          videoAspectRatio: event.videoAspectRatio ?? current.videoAspectRatio,
        );
      case MacMpvEventKind.endFile:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.completed,
        );
      case MacMpvEventKind.stop:
      case MacMpvEventKind.quit:
      case MacMpvEventKind.shutdown:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.stopped,
        );
      case MacMpvEventKind.error:
        // Errors are emitted as PlaybackError; state is left unchanged.
        return current;
      case MacMpvEventKind.unknown:
        return current;
    }
  }
}
