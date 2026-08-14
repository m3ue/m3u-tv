import 'dart:async';

import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

// One handle per loaded stream is already multiplexed over the single
// method+event channel pair (see `linux/desktop_libmpv_backend.cc`'s
// `g_players` map), but the broadcast event stream itself must be listened
// to exactly once here and shared -- a second receiveBroadcastStream()
// listener would silently steal events from the first instead of adding a
// second subscriber. Every [DesktopLibmpvBackend] instance already filters
// this shared stream down to its own handle in [_applyEvent].
// `receiveBroadcastStream()` already returns a broadcast stream, and `.map`
// preserves that -- no extra `.asBroadcastStream()` wrapping is needed (and
// actively breaks resubscription across sequential loads/disposes: its
// default pause/resume semantics leave the upstream subscription paused
// rather than fully cancelled between listeners, so a later listener never
// re-triggers the platform channel's "listen" handshake).
Stream<DesktopLibmpvEvent>? _sharedLibmpvEvents;
Stream<DesktopLibmpvEvent> _libmpvEvents(EventChannel channel) {
  return _sharedLibmpvEvents ??= channel.receiveBroadcastStream().map((raw) {
    final map = Map<String, Object?>.from(raw! as Map<Object?, Object?>);
    return DesktopLibmpvEvent.fromMap(map);
  });
}

class DesktopLibmpvBackend
    implements PlayerAdapter, VideoTextureProvider, MultiviewBackend {
  DesktopLibmpvBackend({MethodChannel? channel, EventChannel? eventChannel})
    : _channel = channel ?? const MethodChannel(_methodChannelName),
      _eventChannel = eventChannel ?? const EventChannel(_eventChannelName) {
    _eventSubscription = _libmpvEvents(_eventChannel).listen(
      _handleEvent,
      onError: _handleEventStreamError,
    );
  }

  static const String _methodChannelName = 'm3u_tv/desktop_libmpv';
  static const String _eventChannelName = 'm3u_tv/desktop_libmpv/events';

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.desktopLibmpv,
  );
  int? _handle;
  int? _textureId;
  int _lastSequence = -1;
  int _loadGeneration = 0;
  bool _errorEmitted = false;
  bool _disposed = false;
  Completer<void>? _readyCompleter;
  PlaybackException? _readyFailure;
  Future<void>? _terminalCleanup;
  PlaybackSource? _pendingSource;
  StreamSubscription<Object?>? _eventSubscription;
  final List<DesktopLibmpvEvent> _pendingEvents = <DesktopLibmpvEvent>[];

  @override
  int? get textureId => _textureId;

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.desktopLibmpv;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  Future<DesktopLibmpvProbe> probe() async {
    final response = await _channel.invokeMapMethod<String, Object?>('probe');
    return DesktopLibmpvProbe.fromMap(response ?? const <String, Object?>{});
  }

  @override
  Future<void> load(PlaybackSource source) async {
    _ensureNotDisposed();
    final generation = ++_loadGeneration;
    final previousReady = _readyCompleter;
    if (previousReady != null && !previousReady.isCompleted) {
      previousReady.complete();
    }

    // Dispose previous handle before creating a new one.
    if (_handle != null) {
      final oldHandle = _handle;
      _resetHandleState();
      await _channel.invokeMethod<void>('dispose', <String, Object?>{
        'handle': oldHandle,
      });
    }
    if (!_isActiveLoad(generation)) return;

    final ready = Completer<void>();
    _pendingSource = source;
    _readyCompleter = ready;
    _readyFailure = null;
    _pendingEvents.clear();

    try {
      final response = await _channel.invokeMapMethod<String, Object?>('load', {
        'uri': source.uri,
        'title': source.title,
        'startPositionMs': source.startPosition.inMilliseconds,
        'isLive': source.isLive,
        'userAgent': source.userAgent,
        'headers': source.headers,
      });

      final handle = response?['handle'] as int?;
      final textureId = response?['textureId'] as int?;
      final ok = response?['ok'] == true;
      if (!_isActiveLoad(generation)) {
        if (handle != null) await _disposeNativeHandle(handle);
        return;
      }
      final preResponseFailure = _readyFailure;
      if (preResponseFailure != null) {
        if (handle != null) await _disposeNativeHandle(handle);
        if (!_isActiveLoad(generation)) return;
        _clearLoading(ready);
        throw preResponseFailure;
      }
      if (!ok || handle == null || textureId == null) {
        final message = response?['error'] as String? ?? 'libmpv load failed';
        final code =
            response?['code'] as String? ?? 'desktop-libmpv-load-failed';
        final error = code == BackendUnavailableException.unavailableCode
            ? BackendUnavailableException(message)
            : PlaybackException(
                message: message,
                backend: capabilities.backend,
                code: code,
                recoverable: true,
              );
        _clearLoading(ready);
        throw error;
      }

      _handle = handle;
      _textureId = textureId;
      _lastSequence = -1;
      _errorEmitted = false;

      // Drain buffered events that belong to this handle.
      final pendingEvents = List<DesktopLibmpvEvent>.of(_pendingEvents);
      _pendingEvents.clear();
      for (final event in pendingEvents) {
        if (event.handle == _handle) {
          _applyEvent(event);
        }
      }

      await ready.future;
      if (!_isActiveLoad(generation)) return;
      final failure = _readyFailure;
      final terminalCleanup = _terminalCleanup;
      if (terminalCleanup != null) {
        await terminalCleanup;
        if (identical(_terminalCleanup, terminalCleanup)) {
          _terminalCleanup = null;
        }
      }
      if (!_isActiveLoad(generation)) return;
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
        code: 'desktop-libmpv-load-failed',
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

    final handle = _handle;
    if (handle == null) return;
    try {
      await _channel.invokeMethod<void>('stop', <String, Object?>{
        'handle': handle,
      });
    } finally {
      if (_handle == handle) {
        _resetHandleState();
        if (_state.status != PlaybackStatus.stopped) {
          _emit(_state.copyWith(status: PlaybackStatus.stopped));
        }
        await _disposeNativeHandle(handle);
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

    final terminalCleanup = _terminalCleanup;
    _terminalCleanup = null;
    if (terminalCleanup != null) await terminalCleanup;

    final handle = _handle;
    if (handle != null) {
      await _channel.invokeMethod<void>('dispose', <String, Object?>{
        'handle': handle,
      });
    }
    _resetHandleState();

    await _stateController.close();
    await _errorController.close();
  }

  Future<void> _invokeControl(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final handle = _handle;
    await _channel.invokeMethod<void>(method, <String, Object?>{
      'handle': handle,
      ...arguments,
    });
  }

  void _handleEvent(DesktopLibmpvEvent event) {
    if (_disposed) return;

    if (event.kind == DesktopLibmpvEventKind.unknown) {
      return;
    }

    // Buffer events while we do not yet know the active handle.
    if (_handle == null) {
      final ready = _readyCompleter;
      if (ready != null && !ready.isCompleted) {
        _pendingEvents.add(event);
      }
      return;
    }

    _applyEvent(event);
  }

  void _applyEvent(DesktopLibmpvEvent event) {
    // Ignore stale handles and out-of-order sequences.
    if (event.handle != _handle) return;
    if (event.sequence <= _lastSequence) return;
    _lastSequence = event.sequence;

    if (_errorEmitted) return;

    if (event.kind == DesktopLibmpvEventKind.error) {
      _errorEmitted = true;
      final error = PlaybackException(
        message: event.message ?? 'desktop libmpv error',
        backend: capabilities.backend,
        code: event.code ?? 'desktop-libmpv-error',
        recoverable: event.recoverable,
      );
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _failReady(error);
      } else {
        _errorController.add(PlaybackError.fromException(error));
      }
      return;
    }

    if (event.kind == DesktopLibmpvEventKind.endFile &&
        _readyCompleter != null &&
        !_readyCompleter!.isCompleted) {
      _errorEmitted = true;
      final error = PlaybackException(
        message: 'desktop libmpv ended before FILE_LOADED',
        backend: capabilities.backend,
        code: 'desktop-libmpv-ended-before-ready',
        recoverable: true,
      );
      _failReady(error);
      return;
    }

    final effectiveSource = _state.source ?? _pendingSource;
    if (effectiveSource == null &&
        event.kind != DesktopLibmpvEventKind.shutdown) {
      return;
    }

    final nextState = DesktopLibmpvEventReducer.reduce(
      _state,
      event,
      effectiveSource ?? const PlaybackSource(uri: ''),
    );

    if (_readyCompleter != null &&
        !_readyCompleter!.isCompleted &&
        event.kind == DesktopLibmpvEventKind.fileLoaded) {
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
    final handle = _handle;
    if (handle != null) {
      _resetHandleState();
      _terminalCleanup = _disposeNativeHandle(handle);
    }
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

  Future<void> _disposeNativeHandle(int handle) async {
    try {
      await _channel.invokeMethod<void>('dispose', <String, Object?>{
        'handle': handle,
      });
    } on Object {
      // A stale native handle must not turn cancellation into an unhandled load error.
    }
  }

  void _resetHandleState() {
    _handle = null;
    _textureId = null;
    _lastSequence = -1;
    _errorEmitted = false;
    _pendingEvents.clear();
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DesktopLibmpvBackend is disposed');
    }
  }
}

class BackendUnavailableException extends PlaybackException {
  BackendUnavailableException(String message)
    : super(
        message: message,
        backend: PlaybackBackend.desktopLibmpv,
        code: unavailableCode,
        recoverable: true,
      );

  static const String unavailableCode = 'backend_unavailable';
}

class DesktopLibmpvProbe {
  const DesktopLibmpvProbe({
    required this.platform,
    required this.windowSystem,
    required this.videoApi,
    required this.ownedSurface,
    required this.libmpvAvailable,
    required this.renderApiAvailable,
    required this.canPlayFixture,
    required this.fallbackDecision,
    required this.details,
  });

  final String platform;
  final String windowSystem;
  final String videoApi;
  final bool ownedSurface;
  final bool libmpvAvailable;
  final bool renderApiAvailable;
  final bool canPlayFixture;
  final String fallbackDecision;
  final String details;

  bool get passed =>
      ownedSurface && libmpvAvailable && renderApiAvailable && canPlayFixture;

  static DesktopLibmpvProbe fromMap(Map<String, Object?> map) {
    return DesktopLibmpvProbe(
      platform: map['platform'] as String? ?? 'unknown',
      windowSystem: map['windowSystem'] as String? ?? 'unknown',
      videoApi: map['videoApi'] as String? ?? 'unknown',
      ownedSurface: map['ownedSurface'] == true,
      libmpvAvailable: map['libmpvAvailable'] == true,
      renderApiAvailable: map['renderApiAvailable'] == true,
      canPlayFixture: map['canPlayFixture'] == true,
      fallbackDecision: map['fallbackDecision'] as String? ?? 'unreported',
      details: map['details'] as String? ?? '',
    );
  }
}

enum DesktopLibmpvEventKind {
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

class DesktopLibmpvEvent {
  const DesktopLibmpvEvent({
    required this.schemaVersion,
    required this.handle,
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

  factory DesktopLibmpvEvent.fromMap(Map<String, Object?> map) {
    final schemaVersion = (map['schemaVersion'] as num?)?.toInt() ?? 0;
    return DesktopLibmpvEvent(
      schemaVersion: schemaVersion,
      handle: (map['handle'] as num?)?.toInt() ?? 0,
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
      audioTracks: schemaVersion >= 2
          ? _tracksFromValue(map['audioTracks'])
          : null,
      subtitleTracks: schemaVersion >= 2
          ? _tracksFromValue(map['subtitleTracks'])
          : null,
      message: map['message'] as String?,
      code: map['code'] as String?,
      recoverable: map['recoverable'] == true,
    );
  }

  final int schemaVersion;
  final int handle;
  final int sequence;
  final DesktopLibmpvEventKind kind;
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

  static DesktopLibmpvEventKind _kindFromString(String? value) {
    return switch (value) {
      'START_FILE' => DesktopLibmpvEventKind.startFile,
      'FILE_LOADED' => DesktopLibmpvEventKind.fileLoaded,
      'PLAYBACK_RESTART' => DesktopLibmpvEventKind.playbackRestart,
      'VIDEO_RECONFIG' => DesktopLibmpvEventKind.videoReconfig,
      'END_FILE' => DesktopLibmpvEventKind.endFile,
      'STOP' => DesktopLibmpvEventKind.stop,
      'QUIT' => DesktopLibmpvEventKind.quit,
      'ERROR' => DesktopLibmpvEventKind.error,
      'SHUTDOWN' => DesktopLibmpvEventKind.shutdown,
      _ => DesktopLibmpvEventKind.unknown,
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

class DesktopLibmpvEventReducer {
  const DesktopLibmpvEventReducer._();

  static PlaybackState reduce(
    PlaybackState current,
    DesktopLibmpvEvent event,
    PlaybackSource source,
  ) {
    const backend = PlaybackBackend.desktopLibmpv;

    switch (event.kind) {
      case DesktopLibmpvEventKind.startFile:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.loading,
          source: source,
          position: source.startPosition,
        );
      case DesktopLibmpvEventKind.fileLoaded:
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
      case DesktopLibmpvEventKind.playbackRestart:
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
      case DesktopLibmpvEventKind.videoReconfig:
        return current.copyWith(
          backend: backend,
          videoAspectRatio: event.videoAspectRatio ?? current.videoAspectRatio,
        );
      case DesktopLibmpvEventKind.endFile:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.completed,
        );
      case DesktopLibmpvEventKind.stop:
      case DesktopLibmpvEventKind.quit:
      case DesktopLibmpvEventKind.shutdown:
        return current.copyWith(
          backend: backend,
          status: PlaybackStatus.stopped,
        );
      case DesktopLibmpvEventKind.error:
        // Errors are emitted as PlaybackError; state is left unchanged.
        return current;
      case DesktopLibmpvEventKind.unknown:
        return current;
    }
  }
}
