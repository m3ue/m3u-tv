import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/mpv_native_event.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

/// Shared load/play/pause/stop/dispose/event-reduction state machine for a
/// native mpv `PlatformViewProvider` backend addressed by a Dart-generated
/// `viewId` -- one per platform-view instance, created up front so the
/// platform view can be attached and `load()` called before the native side
/// necessarily exists yet (see `waitForCore` in each `MpvPlayerPlugin.swift`).
///
/// `MacMpvNativeBackend` and `AppleMpvNativeBackend` are near-identical
/// consumers of this FSM, differing only in their method/event channel
/// names, [PlaybackCapabilities], error codes, and (macOS only) `setVolume`.
abstract class MpvNativeBackendBase implements PlayerAdapter {
  MpvNativeBackendBase({
    required this.viewId,
    required this._channel,
    required Stream<MpvNativeEvent> events,
  }) {
    _eventSubscription = events.listen(
      _handleEvent,
      onError: _handleEventStreamError,
    );
  }

  final int viewId;
  final MethodChannel _channel;

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  late PlaybackState _state = PlaybackState.idle(backend: capabilities.backend);
  int _lastSequence = -1;
  int _loadGeneration = 0;
  bool _errorEmitted = false;
  bool _disposed = false;
  Completer<void>? _readyCompleter;
  PlaybackException? _readyFailure;
  PlaybackSource? _pendingSource;
  StreamSubscription<Object?>? _eventSubscription;
  final List<MpvNativeEvent> _pendingEvents = <MpvNativeEvent>[];

  /// The load-failure code to attach to a generic (non-`backend_unavailable`)
  /// load error, e.g. `'mac-mpv-load-failed'`/`'apple-mpv-load-failed'`.
  String get loadFailedCode;

  /// The error code to attach when the native side reports one without its
  /// own code, e.g. `'mac-mpv-error'`/`'apple-mpv-error'`.
  String get defaultErrorCode;

  /// The error code for an mpv `END_FILE` arriving before `FILE_LOADED`.
  String get endedBeforeReadyCode;

  bool get disposed => _disposed;

  @override
  PlaybackCapabilities get capabilities;

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
        'viewId': viewId,
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
        final code = response?['code'] as String? ?? loadFailedCode;
        final error = code == NativeMpvUnavailableException.unavailableCode
            ? NativeMpvUnavailableException(
                message,
                backend: capabilities.backend,
              )
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
      final pendingEvents = List<MpvNativeEvent>.of(_pendingEvents);
      _pendingEvents.clear();
      for (final event in pendingEvents) {
        if (event.viewId == viewId) _applyEvent(event);
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
        code: loadFailedCode,
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
        'viewId': viewId,
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

  /// Tears down the native mpv core without closing [onState]/[onError], so
  /// this adapter is still safe to [load] again later. See
  /// `PlatformViewProvider.releaseNativeView`.
  Future<void> releaseNativeView() async {
    if (_disposed) return;
    await _channel.invokeMethod<void>('dispose', <String, Object?>{
      'viewId': viewId,
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
      'viewId': viewId,
    });

    await _stateController.close();
    await _errorController.close();
  }

  Future<void> _invokeControl(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) => invokeControl(method, arguments);

  /// Invokes a native control method on this backend's own `viewId`, merging
  /// [arguments] into the call. Exposed (rather than `_channel` itself) for
  /// subclasses that need a control method this base class doesn't already
  /// cover, e.g. `MacMpvNativeBackend.setVolume`.
  @protected
  Future<void> invokeControl(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    await _channel.invokeMethod<void>(method, <String, Object?>{
      'viewId': viewId,
      ...arguments,
    });
  }

  void _handleEvent(MpvNativeEvent event) {
    if (_disposed) return;
    if (event.kind == MpvNativeEventKind.unknown) return;
    if (event.viewId != viewId) return;

    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted && _pendingSource != null) {
      _applyEvent(event);
      return;
    }

    _applyEvent(event);
  }

  void _applyEvent(MpvNativeEvent event) {
    if (event.viewId != viewId) return;
    if (event.sequence <= _lastSequence) return;
    _lastSequence = event.sequence;

    if (_errorEmitted) return;

    if (event.kind == MpvNativeEventKind.error) {
      _errorEmitted = true;
      final error = PlaybackException(
        message: event.message ?? 'native mpv error',
        backend: capabilities.backend,
        code: event.code ?? defaultErrorCode,
        recoverable: event.recoverable,
      );
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        _failReady(error);
      } else {
        _errorController.add(PlaybackError.fromException(error));
      }
      return;
    }

    if (event.kind == MpvNativeEventKind.endFile &&
        _readyCompleter != null &&
        !_readyCompleter!.isCompleted) {
      _errorEmitted = true;
      final error = PlaybackException(
        message: 'native mpv ended before FILE_LOADED',
        backend: capabilities.backend,
        code: endedBeforeReadyCode,
        recoverable: true,
      );
      _failReady(error);
      return;
    }

    final effectiveSource = _state.source ?? _pendingSource;
    if (effectiveSource == null && event.kind != MpvNativeEventKind.shutdown) {
      return;
    }

    final nextState = MpvNativeEventReducer.reduce(
      _state,
      event,
      effectiveSource ?? const PlaybackSource(uri: ''),
      backend: capabilities.backend,
    );

    if (_readyCompleter != null &&
        !_readyCompleter!.isCompleted &&
        event.kind == MpvNativeEventKind.fileLoaded) {
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
      throw StateError('$runtimeType is disposed');
    }
  }
}
