// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/playback/subtitle_controller_provider.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

abstract class PlaybackTranscodeGateway {
  Future<TranscodeResponse> startServerTranscode(StreamRequest request);
  Future<BroadcastSession?> startBroadcast(StreamRequest request);
  Future<void> stopBroadcast(String networkId);
  Future<void> stopServerTranscode({
    required String streamId,
    required String? sessionId,
  });
}

class TranscodeUnavailableException implements Exception {
  const TranscodeUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlaybackOrchestrator {
  PlaybackOrchestrator({
    required PlaybackPlatform platform,
    required Map<PlaybackBackend, PlayerAdapter> adapters,
    required PlaybackTranscodeGateway transcodeGateway,
    Duration bufferingTimeout = const Duration(seconds: 15),
    Duration retryDelay = const Duration(milliseconds: 250),
  }) : _platform = platform,
       _adapters = Map<PlaybackBackend, PlayerAdapter>.unmodifiable(adapters),
       _transcodeGateway = transcodeGateway,
       _bufferingTimeout = bufferingTimeout,
       _retryDelay = retryDelay;

  final PlaybackPlatform _platform;
  final Map<PlaybackBackend, PlayerAdapter> _adapters;
  final PlaybackTranscodeGateway _transcodeGateway;
  final Duration _bufferingTimeout;
  final Duration _retryDelay;
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();
  final List<String> _diagnostics = <String>[];
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  final Set<PlayerAdapter> _boundAdapters = <PlayerAdapter>{};

  PlayerAdapter? _activeAdapter;
  PlaybackBackend? _activeBackend;
  PlaybackSource? _activeSource;
  TranscodeResponse? _activeServerTranscode;
  BroadcastSession? _activeBroadcast;
  Timer? _bufferingTimer;
  int _activeRecoveryAttempts = 0;
  int _playbackGeneration = 0;
  bool _recovering = false;
  bool _disposed = false;

  Stream<PlaybackState> get onState => _stateController.stream;
  Stream<PlaybackError> get onError => _errorController.stream;
  PlaybackBackend? get activeBackend => _activeBackend;
  int? get activeTextureId {
    final adapter = _activeAdapter;
    if (adapter is! VideoTextureProvider) return null;
    return (adapter! as VideoTextureProvider).textureId;
  }

  mkv.VideoController? get activeSubtitleController {
    final adapter = _activeAdapter;
    if (adapter == null || adapter is! SubtitleControllerProvider) return null;
    return (adapter as SubtitleControllerProvider).subtitleController;
  }

  List<String> get diagnostics => List<String>.unmodifiable(_diagnostics);

  Future<void> open(PlaybackSource source) async {
    _ensureNotDisposed();
    _playbackGeneration += 1;
    _cancelBufferingTimer();
    _activeRecoveryAttempts = 0;
    _recovering = false;
    await _stopActiveAdapter();
    await _cleanupSessions();
    _activeAdapter = null;
    _activeBackend = null;
    _activeSource = null;

    PlaybackException? lastRecoverableFailure;
    PlaybackBackend? previousBackend;
    var attempt = 0;
    for (final backend in _nativeBackends()) {
      final failure = await _tryLoadBackend(
        backend: backend,
        source: source,
        successDiagnostic: attempt == 0
            ? 'direct:${backend.name}:ready'
            : 'fallback:${backend.name}:preferred ${previousBackend?.name ?? 'none'} unsupported',
      );
      attempt += 1;
      if (failure == null) return;
      if (_platform == PlaybackPlatform.android &&
          backend == PlaybackBackend.androidExoPlayer) {
        _diagnostics.add('android-mpv:disabled-future-gated:${failure.code}');
      }
      previousBackend = backend;
      if (!failure.recoverable) return;
      lastRecoverableFailure = failure;
    }

    await _openServerTranscode(source, lastFailure: lastRecoverableFailure);
  }

  Future<void> play() => _requireActiveAdapter().play();
  Future<void> pause() => _requireActiveAdapter().pause();
  Future<void> seek(Duration position) =>
      _requireActiveAdapter().seek(position);
  Future<void> setAudioTrack(String? trackId) =>
      _requireActiveAdapter().setAudioTrack(trackId);
  Future<void> setSubtitleTrack(String? trackId) =>
      _requireActiveAdapter().setSubtitleTrack(trackId);
  Future<void> setPlaybackSpeed(double speed) =>
      _requireActiveAdapter().setPlaybackSpeed(speed);

  Future<void> stop() async {
    await _stopActiveAdapter();
    await _cleanupSessions();
  }

  Future<void> cancel() => stop();

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final adapter in _adapters.values.toSet()) {
      await adapter.dispose();
    }
    await _stateController.close();
    await _errorController.close();
  }

  Iterable<PlaybackBackend> _nativeBackends() sync* {
    for (final capabilities in PlaybackCapabilities.forPlatform(_platform)) {
      if (capabilities.backend == PlaybackBackend.serverTranscode) {
        continue;
      }
      if (_platform == PlaybackPlatform.android &&
          capabilities.backend == PlaybackBackend.androidMpv) {
        continue;
      }
      if (_adapters.containsKey(capabilities.backend)) {
        yield capabilities.backend;
      }
    }
  }

  Future<PlaybackException?> _tryLoadBackend({
    required PlaybackBackend backend,
    required PlaybackSource source,
    required String successDiagnostic,
  }) async {
    final adapter = _adapters[backend];
    if (adapter == null) return null;
    _bind(adapter);
    _activeAdapter = adapter;
    _activeBackend = backend;
    _activeSource = source;
    try {
      await adapter.load(source);
      _activeSource = source;
      _diagnostics
        ..add(successDiagnostic)
        ..add('active-backend:${backend.name}:ready');
      return null;
    } on PlaybackException catch (error) {
      if (identical(_activeAdapter, adapter) && _activeBackend == backend) {
        _activeAdapter = null;
        _activeBackend = null;
        _activeSource = null;
      }
      _diagnostics.add(
        'load-failed:${backend.name}:${error.code}:${error.message}',
      );
      if (error.recoverable) {
        _diagnostics.add('fallback-reason:${error.code}:${error.message}');
      }
      if (!error.recoverable) {
        _emitError(PlaybackError.fromException(error));
      }
      return error;
    }
  }

  Future<void> _openServerTranscode(
    PlaybackSource source, {
    required PlaybackException? lastFailure,
  }) async {
    final adapter = _adapters[PlaybackBackend.serverTranscode];
    if (adapter == null) {
      if (_platform == PlaybackPlatform.desktop && lastFailure != null) {
        _emitError(PlaybackError.fromException(lastFailure));
        return;
      }
      _emitError(
        PlaybackError(
          backend: lastFailure?.backend ?? PlaybackBackend.serverTranscode,
          message: 'No server transcode playback backend is registered',
          code: 'server_transcode_unavailable',
          recoverable: true,
        ),
      );
      return;
    }

    TranscodeResponse response;
    try {
      response = await _transcodeGateway.startServerTranscode(
        _serverRequestFromSource(source),
      );
    } on TranscodeUnavailableException catch (error) {
      _emitError(
        PlaybackError(
          backend: PlaybackBackend.serverTranscode,
          message: error.message,
          code: 'server_transcode_unavailable',
          recoverable: true,
        ),
      );
      return;
    } on Object catch (error) {
      _emitError(
        PlaybackError(
          backend: PlaybackBackend.serverTranscode,
          message: error.toString(),
          code: 'server_transcode_unavailable',
          recoverable: true,
        ),
      );
      return;
    }

    _activeServerTranscode = response;
    if (response.status == BroadcastStatus.stalled.value ||
        response.status == BroadcastStatus.failed.value) {
      await _cleanupSessions();
      _emitError(
        PlaybackError(
          backend: PlaybackBackend.serverTranscode,
          message:
              response.message ?? 'Server transcode did not become playable',
          code: response.errorCode ?? 'transcode_stalled',
          recoverable: true,
        ),
      );
      return;
    }

    _diagnostics.add(
      'server-transcode:${response.streamId}:${response.sessionId}',
    );
    BroadcastSession? broadcast;
    try {
      broadcast = await _startBroadcastIfNeeded(source);
    } on Object catch (error) {
      await _cleanupSessions();
      _emitError(
        PlaybackError(
          backend: PlaybackBackend.serverTranscode,
          message: error.toString(),
          code: 'broadcast_start_failed',
          recoverable: true,
        ),
      );
      return;
    }
    if (broadcast != null) {
      _activeBroadcast = broadcast;
      _diagnostics.add(
        'broadcast:${broadcast.networkId}:${broadcast.status.value}',
      );
    }

    final transcodedSource = PlaybackSource(
      uri: broadcast?.playlistUrl ?? response.streamUrl,
      title: source.title,
      startPosition: source.startPosition,
      isLive: source.isLive,
      userAgent: source.userAgent,
      headers: source.headers,
      metadata: <String, Object?>{
        ...source.metadata,
        'transcode_stream_id': response.streamId,
        if (response.sessionId != null)
          'transcode_session_id': response.sessionId,
      },
    );

    _bind(adapter);
    _activeAdapter = adapter;
    _activeBackend = PlaybackBackend.serverTranscode;
    _activeSource = transcodedSource;
    try {
      await adapter.load(transcodedSource);
      _diagnostics.add('active-backend:serverTranscode:ready');
    } on PlaybackException catch (error) {
      if (identical(_activeAdapter, adapter) &&
          _activeBackend == PlaybackBackend.serverTranscode) {
        _activeAdapter = null;
        _activeBackend = null;
        _activeSource = null;
      }
      await _cleanupSessions();
      _emitError(PlaybackError.fromException(error));
    }
  }

  StreamRequest _serverRequestFromSource(PlaybackSource source) {
    return StreamRequest(
      url: source.uri,
      mode: TranscodeMode.server,
      metadata: <String, Object?>{
        ...source.metadata,
        if (source.startPosition > Duration.zero)
          'resume_seconds': source.startPosition.inSeconds,
      },
      userAgent: source.userAgent,
      headers: source.headers,
      videoCodec: source.videoCodec,
      audioCodec: source.audioCodec,
      sessionId: source.metadata['transcode_session_id'] as String?,
    );
  }

  Future<BroadcastSession?> _startBroadcastIfNeeded(PlaybackSource source) {
    if (source.metadata['broadcast_network_id'] is! String) {
      return Future<BroadcastSession?>.value();
    }
    return _transcodeGateway.startBroadcast(_serverRequestFromSource(source));
  }

  Future<void> _stopActiveAdapter() async {
    _playbackGeneration += 1;
    _cancelBufferingTimer();
    final adapter = _activeAdapter;
    if (adapter == null) return;
    _activeAdapter = null;
    _activeBackend = null;
    _activeSource = null;
    await adapter.stop();
  }

  Future<void> _cleanupSessions() async {
    final broadcast = _activeBroadcast;
    _activeBroadcast = null;
    if (broadcast != null) {
      await _transcodeGateway.stopBroadcast(broadcast.networkId);
      _diagnostics.add('cleanup:broadcast:stopped:${broadcast.networkId}');
    }
    final serverTranscode = _activeServerTranscode;
    _activeServerTranscode = null;
    if (serverTranscode != null) {
      await _stopServerTranscode(serverTranscode);
    }
  }

  Future<void> _stopServerTranscode(TranscodeResponse transcode) async {
    await _transcodeGateway.stopServerTranscode(
      streamId: transcode.streamId,
      sessionId: transcode.sessionId,
    );
    _diagnostics.add(
      'cleanup:server-transcode:stopped:${transcode.streamId}:${transcode.sessionId}',
    );
  }

  void _bind(PlayerAdapter adapter) {
    if (!_boundAdapters.add(adapter)) {
      return;
    }
    _subscriptions
      ..add(adapter.onState.listen(_handleAdapterState))
      ..add(
        adapter.onError.listen((error) {
          unawaited(_handleAdapterError(adapter, error));
        }),
      );
  }

  void _handleAdapterState(PlaybackState state) {
    if (_disposed) return;
    _stateController.add(state);
    if (state.status == PlaybackStatus.buffering &&
        state.backend == _activeBackend) {
      _startBufferingTimer(state.backend);
      return;
    }
    if (state.backend == _activeBackend) {
      _cancelBufferingTimer();
    }
  }

  void _startBufferingTimer(PlaybackBackend backend) {
    _cancelBufferingTimer();
    final generation = _playbackGeneration;
    _bufferingTimer = Timer(_bufferingTimeout, () {
      if (_disposed || generation != _playbackGeneration) return;
      unawaited(
        _handleRecoverableActiveFailure(
          PlaybackError(
            backend: backend,
            message:
                'Playback stayed buffering for ${_bufferingTimeout.inSeconds}s',
            code: 'network_unavailable',
            recoverable: true,
          ),
        ),
      );
    });
  }

  Future<void> _handleAdapterError(
    PlayerAdapter adapter,
    PlaybackError error,
  ) async {
    if (_disposed || !identical(adapter, _activeAdapter)) return;
    if (!error.recoverable) {
      _emitError(error);
      return;
    }
    await _handleRecoverableActiveFailure(error);
  }

  Future<void> _handleRecoverableActiveFailure(PlaybackError error) async {
    if (_disposed || _recovering) return;
    _cancelBufferingTimer();
    final adapter = _activeAdapter;
    final backend = _activeBackend;
    final source = _activeSource;
    if (adapter == null || backend == null || source == null) {
      _emitError(error);
      return;
    }
    if (_activeRecoveryAttempts >= 1) {
      await _stopActiveAdapter();
      await _cleanupSessions();
      _emitError(error);
      return;
    }

    _recovering = true;
    _activeRecoveryAttempts += 1;
    final generation = _playbackGeneration;
    _diagnostics.add(
      'active-retry:${error.code}:${backend.name}:$_activeRecoveryAttempts',
    );
    try {
      if (_retryDelay > Duration.zero) {
        await Future<void>.delayed(_retryDelay);
      }
      if (_disposed || generation != _playbackGeneration) return;
      await adapter.stop();
      if (_disposed || generation != _playbackGeneration) return;
      await adapter.load(source);
    } on PlaybackException catch (retryError) {
      if (_disposed || generation != _playbackGeneration) return;
      await _stopActiveAdapter();
      await _cleanupSessions();
      _emitError(PlaybackError.fromException(retryError));
    } on Object catch (retryError) {
      if (_disposed || generation != _playbackGeneration) return;
      await _stopActiveAdapter();
      await _cleanupSessions();
      _emitError(
        PlaybackError(
          backend: backend,
          message: retryError.toString(),
          code: error.code,
          recoverable: error.recoverable,
        ),
      );
    } finally {
      _recovering = false;
    }
  }

  void _cancelBufferingTimer() {
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
  }

  PlayerAdapter _requireActiveAdapter() {
    final adapter = _activeAdapter;
    if (adapter == null) {
      throw StateError('PlaybackOrchestrator has no active backend');
    }
    return adapter;
  }

  void _emitError(PlaybackError error) {
    if (_disposed) return;
    _diagnostics.add('error:${error.code}:${error.message}');
    _errorController.add(error);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PlaybackOrchestrator is disposed');
    }
  }
}
