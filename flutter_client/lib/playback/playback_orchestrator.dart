// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/playback/subtitle_controller_provider.dart';
import 'package:m3u_tv/services/stream_resolution_service.dart';
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
    StreamResolutionService? resolutionService,
  }) : _platform = platform,
       _adapters = Map<PlaybackBackend, PlayerAdapter>.unmodifiable(adapters),
       _transcodeGateway = transcodeGateway,
       _bufferingTimeout = bufferingTimeout,
       _retryDelay = retryDelay,
       _resolutionService = resolutionService;

  final PlaybackPlatform _platform;
  final Map<PlaybackBackend, PlayerAdapter> _adapters;
  final PlaybackTranscodeGateway _transcodeGateway;
  final Duration _bufferingTimeout;
  final Duration _retryDelay;
  final StreamResolutionService? _resolutionService;
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
  int _openGeneration = 0;
  int? _activeAdapterGeneration;
  Future<void> _openPipeline = Future<void>.value();
  int _openOperations = 0;
  Completer<void>? _openIdle;
  bool _recovering = false;
  bool _disposing = false;
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

  Future<void> open(PlaybackSource source) {
    _openGeneration += 1;
    final openGeneration = _openGeneration;
    _ensureNotDisposed();
    _playbackGeneration += 1;
    _activeRecoveryAttempts = 0;
    _recovering = false;
    _cancelBufferingTimer();
    _openOperations += 1;

    final operation = _openPipeline.then(
      (_) => _openInternal(source, openGeneration),
    );
    _openPipeline = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    unawaited(
      operation.then<void>(
        (_) => _finishOpenOperation(),
        onError: (Object _, StackTrace _) => _finishOpenOperation(),
      ),
    );
    return operation;
  }

  void _finishOpenOperation() {
    _openOperations -= 1;
    if (_openOperations == 0) {
      _openIdle?.complete();
      _openIdle = null;
    }
  }

  Future<void> _openInternal(
    PlaybackSource source,
    int openGeneration,
  ) async {
    if (_isOpenStale(openGeneration)) return;
    await _stopActiveAdapter();
    if (_isOpenStale(openGeneration)) return;
    await _cleanupSessions();
    if (_isOpenStale(openGeneration)) return;

    final resolver = _resolutionService;
    if (resolver != null) {
      final resolved = await _resolvePreflight(
        source,
        resolver,
        openGeneration,
      );
      if (resolved == null || _isOpenStale(openGeneration)) return;
      source = resolved; // ignore: parameter_assignments
    }

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
        openGeneration: openGeneration,
      );
      if (_isOpenStale(openGeneration)) return;
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

    await _openServerTranscode(
      source,
      lastFailure: lastRecoverableFailure,
      openGeneration: openGeneration,
    );
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
    _openGeneration += 1;
    await _stopActiveAdapter();
    await _cleanupSessions();
  }

  Future<void> cancel() => stop();

  Future<void> dispose() async {
    if (_disposed || _disposing) return;
    _disposing = true;
    await stop();
    if (_openOperations > 0) {
      _openIdle ??= Completer<void>();
      await _openIdle!.future;
    }
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
    required int openGeneration,
  }) async {
    final adapter = _adapters[backend];
    if (adapter == null) return null;
    _bind(adapter);
    _activeAdapter = adapter;
    _activeBackend = backend;
    _activeSource = source;
    _activeAdapterGeneration = openGeneration;
    try {
      await adapter.load(source);
      if (_isOpenStale(openGeneration)) {
        if (identical(_activeAdapter, adapter) &&
            _activeAdapterGeneration == openGeneration) {
          _clearActiveAdapter();
          await adapter.stop();
        }
        return null;
      }
      _activeSource = source;
      _diagnostics
        ..add(successDiagnostic)
        ..add('active-backend:${backend.name}:ready');
      return null;
    } on PlaybackException catch (error) {
      if (_isOpenStale(openGeneration)) return error;
      if (identical(_activeAdapter, adapter) &&
          _activeBackend == backend &&
          _activeAdapterGeneration == openGeneration) {
        _clearActiveAdapter();
      }
      _diagnostics.add('load-failed:${backend.name}:${error.code}');
      if (error.recoverable) {
        _diagnostics.add('fallback-reason:${error.code}');
      }
      if (!error.recoverable) {
        _emitError(PlaybackError.fromException(error));
      }
      return error;
    } on Object {
      if (_isOpenStale(openGeneration)) return null;
      if (identical(_activeAdapter, adapter) &&
          _activeAdapterGeneration == openGeneration) {
        _clearActiveAdapter();
      }
      final error = PlaybackException(
        message: '',
        backend: backend,
        code: 'backend_load_failed',
      );
      _diagnostics.add('load-failed:${backend.name}:${error.code}');
      _emitError(PlaybackError.fromException(error));
      return error;
    }
  }

  Future<PlaybackSource?> _resolvePreflight(
    PlaybackSource source,
    StreamResolutionService resolver,
    int openGeneration,
  ) async {
    final type = source.metadata['type'] as String?;
    final streamId = source.metadata['stream_id'] as int?;
    if (type == null || streamId == null) return source;
    if (!const {'live', 'vod', 'series', 'catchup'}.contains(type)) {
      return source;
    }

    final nativeBackends = _nativeBackends().toList(growable: false);
    if (nativeBackends.isEmpty) return source;
    final capabilities = _adapters[nativeBackends.first]!.capabilities;

    DateTime? catchupStart;
    int? catchupDurationMinutes;
    if (type == 'catchup') {
      final startValue = source.metadata['program_start'];
      final endValue = source.metadata['program_end'];
      catchupStart = startValue is String
          ? DateTime.tryParse(startValue)
          : null;
      final catchupEnd = endValue is String
          ? DateTime.tryParse(endValue)
          : null;
      catchupDurationMinutes = catchupStart != null && catchupEnd != null
          ? catchupEnd.difference(catchupStart).inMinutes
          : null;
      if (catchupStart == null ||
          catchupEnd == null ||
          catchupDurationMinutes == null ||
          catchupDurationMinutes <= 0) {
        _emitResolutionUnavailable();
        return null;
      }
    }

    final response = await _resolveSafely(
      resolver,
      StreamResolveRequest(
        type: type,
        streamId: streamId,
        clientCapabilities: PlaybackCapabilities.clientCapabilities(
          capabilities,
        ),
        catchupStart: catchupStart,
        catchupDurationMinutes: catchupDurationMinutes,
        catchupFormat: type == 'catchup'
            ? source.metadata['catchup_format'] as String?
            : null,
      ),
    );
    if (_isOpenStale(openGeneration)) return null;

    if (response == null) {
      _diagnostics.add('resolve:fallback:direct_play:backend-unavailable');
      return _safeResolverFallback(source);
    }
    if (response.failure == StreamResolveFailure.rejected) {
      _diagnostics.add('resolve:rejected');
      _emitError(
        const PlaybackError(
          backend: PlaybackBackend.serverTranscode,
          message: '',
          code: 'stream_resolution_rejected',
        ),
      );
      return null;
    }

    switch (response.mode) {
      case StreamResolveMode.directPlay:
        final url = response.url;
        if (url == null) {
          _diagnostics.add('resolve:fallback:direct_play:no-direct-url');
          return _safeResolverFallback(source);
        }
        if (!_isSafeResolvedPlaybackUrl(url)) {
          _diagnostics.add('resolve:fallback:direct_play:unsafe-resolved-url');
          return _safeResolverFallback(source);
        }
        _diagnostics.add(_resolutionDiagnostic('direct_play', response.source));
        return _resolvedSource(
          source,
          uri: url,
          videoCodec: response.source?.videoCodec ?? source.videoCodec,
          audioCodec: response.source?.audioCodec ?? source.audioCodec,
        );
      case StreamResolveMode.transcode:
        final url = response.url;
        if (url == null) {
          _diagnostics.add('resolve:fallback:direct_play:no-transcode-url');
          return _safeResolverFallback(source);
        }
        if (!_isSafeResolvedPlaybackUrl(url)) {
          _diagnostics.add('resolve:fallback:direct_play:unsafe-resolved-url');
          return _safeResolverFallback(source);
        }
        _diagnostics.add(_resolutionDiagnostic('transcode', response.source));
        return _resolvedSource(
          source,
          uri: url,
          videoCodec: response.output?.videoCodec,
          audioCodec: response.output?.audioCodec,
          metadata: <String, Object?>{
            ...source.metadata,
            'resolve_mode': 'transcode',
            if (response.source?.videoCodec != null)
              'resolve_video_codec': response.source!.videoCodec,
            if (response.source?.audioCodec != null)
              'resolve_audio_codec': response.source!.audioCodec,
            if (response.source?.container != null)
              'resolve_container': response.source!.container,
            if (response.output?.videoCodec != null)
              'resolve_output_video_codec': response.output!.videoCodec,
            if (response.output?.audioCodec != null)
              'resolve_output_audio_codec': response.output!.audioCodec,
            if (response.output?.container != null)
              'resolve_output_container': response.output!.container,
          },
        );
      case StreamResolveMode.unsupported:
        _diagnostics.add(_resolutionDiagnostic('unsupported', response.source));
        _emitError(
          const PlaybackError(
            backend: PlaybackBackend.serverTranscode,
            message: '',
            code: 'stream_unsupported',
          ),
        );
        return null;
    }
  }

  Future<StreamResolveResponse?> _resolveSafely(
    StreamResolutionService resolver,
    StreamResolveRequest request,
  ) async {
    try {
      return await resolver.resolve(request);
    } on Object {
      return null;
    }
  }

  PlaybackSource _resolvedSource(
    PlaybackSource source, {
    required String uri,
    required String? videoCodec,
    required String? audioCodec,
    Map<String, Object?>? metadata,
  }) {
    return PlaybackSource(
      uri: uri,
      title: source.title,
      startPosition: source.startPosition,
      isLive: source.isLive,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      userAgent: source.userAgent,
      headers: _withoutAuthorization(source.headers),
      metadata: metadata ?? source.metadata,
    );
  }

  PlaybackSource? _safeResolverFallback(PlaybackSource source) {
    if (!_isSafeLegacyFallbackUrl(source.uri)) {
      _emitResolutionUnavailable();
      return null;
    }
    return _resolvedSource(
      source,
      uri: source.uri,
      videoCodec: source.videoCodec,
      audioCodec: source.audioCodec,
    );
  }

  bool _isSafeResolvedPlaybackUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  bool _isSafeLegacyFallbackUrl(String value) {
    if (!_isSafeResolvedPlaybackUrl(value)) return false;
    final uri = Uri.parse(value);
    if (uri.hasQuery) return false;
    final segments = uri.pathSegments
        .expand((segment) => segment.split('/'))
        .map((segment) => segment.toLowerCase())
        .toList(growable: false);
    for (var index = 0; index < segments.length; index += 1) {
      if (const {'live', 'movie', 'series', 'timeshift'}.contains(
            segments[index],
          ) &&
          index + 2 < segments.length) {
        return false;
      }
    }
    return true;
  }

  Map<String, String> _withoutAuthorization(Map<String, String> headers) {
    return Map<String, String>.unmodifiable({
      for (final entry in headers.entries)
        if (entry.key.toLowerCase() != 'authorization') entry.key: entry.value,
    });
  }

  void _emitResolutionUnavailable() {
    _emitError(
      const PlaybackError(
        backend: PlaybackBackend.serverTranscode,
        message: '',
        code: 'stream_resolution_unavailable',
        recoverable: true,
      ),
    );
  }

  String _resolutionDiagnostic(String mode, StreamSourceInfo? source) {
    final parts = <String>[
      if (source?.videoCodec != null) 'video=${source!.videoCodec}',
      if (source?.audioCodec != null) 'audio=${source!.audioCodec}',
      if (source?.container != null) 'container=${source!.container}',
    ];
    return parts.isEmpty ? 'resolve:$mode' : 'resolve:$mode:${parts.join(',')}';
  }

  Future<void> _openServerTranscode(
    PlaybackSource source, {
    required PlaybackException? lastFailure,
    required int openGeneration,
  }) async {
    if (_isOpenStale(openGeneration)) return;
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
      if (_isOpenStale(openGeneration)) return;
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
      if (_isOpenStale(openGeneration)) return;
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

    if (_isOpenStale(openGeneration)) {
      await _stopServerTranscode(response);
      return;
    }
    _activeServerTranscode = response;
    if (response.status == BroadcastStatus.stalled.value ||
        response.status == BroadcastStatus.failed.value) {
      await _cleanupSessions();
      if (_isOpenStale(openGeneration)) return;
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
      if (_isOpenStale(openGeneration)) return;
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
    if (_isOpenStale(openGeneration)) {
      if (broadcast != null) {
        await _transcodeGateway.stopBroadcast(broadcast.networkId);
      }
      if (identical(_activeServerTranscode, response)) {
        _activeServerTranscode = null;
        await _stopServerTranscode(response);
      }
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
    _activeAdapterGeneration = openGeneration;
    try {
      await adapter.load(transcodedSource);
      if (_isOpenStale(openGeneration)) {
        if (identical(_activeAdapter, adapter) &&
            _activeAdapterGeneration == openGeneration) {
          _clearActiveAdapter();
          await adapter.stop();
        }
        await _cleanupSessions();
        return;
      }
      _diagnostics.add('active-backend:serverTranscode:ready');
    } on PlaybackException catch (error) {
      if (_isOpenStale(openGeneration)) return;
      if (identical(_activeAdapter, adapter) &&
          _activeBackend == PlaybackBackend.serverTranscode &&
          _activeAdapterGeneration == openGeneration) {
        _clearActiveAdapter();
      }
      await _cleanupSessions();
      if (!_isOpenStale(openGeneration)) {
        _emitError(PlaybackError.fromException(error));
      }
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
    _clearActiveAdapter();
    await adapter.stop();
  }

  void _clearActiveAdapter() {
    _activeAdapter = null;
    _activeBackend = null;
    _activeSource = null;
    _activeAdapterGeneration = null;
  }

  Future<void> _cleanupSessions() async {
    final broadcast = _activeBroadcast;
    _activeBroadcast = null;
    final serverTranscode = _activeServerTranscode;
    _activeServerTranscode = null;
    if (broadcast != null) {
      await _transcodeGateway.stopBroadcast(broadcast.networkId);
      _diagnostics.add('cleanup:broadcast:stopped:${broadcast.networkId}');
    }
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
      ..add(
        adapter.onState.listen((state) {
          _handleAdapterState(adapter, state);
        }),
      )
      ..add(
        adapter.onError.listen((error) {
          unawaited(_handleAdapterError(adapter, error));
        }),
      );
  }

  void _handleAdapterState(PlayerAdapter adapter, PlaybackState state) {
    if (_disposed ||
        _disposing ||
        !identical(adapter, _activeAdapter) ||
        _activeAdapterGeneration != _openGeneration) {
      return;
    }
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
    if (_disposed ||
        _disposing ||
        !identical(adapter, _activeAdapter) ||
        _activeAdapterGeneration != _openGeneration) {
      return;
    }
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
    if (_disposed || _disposing) return;
    final sanitized = PlaybackError(
      backend: error.backend,
      message: _sanitizeErrorText(error.message),
      code: error.code,
      recoverable: error.recoverable,
    );
    _diagnostics.add('error:${sanitized.code}');
    _errorController.add(sanitized);
  }

  String _sanitizeErrorText(String message) {
    return message
        .replaceAll(
          RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'authorization\s*:\s*(?:basic\s+)?\S+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'basic\s+[a-z0-9+/=]+', caseSensitive: false), '')
        .replaceAll(
          RegExp(
            r'/(?:live|movie|series|timeshift)/[^/\s]+/[^/\s]+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isOpenStale(int openGeneration) {
    return _disposed || _disposing || openGeneration != _openGeneration;
  }

  void _ensureNotDisposed() {
    if (_disposed || _disposing) {
      throw StateError('PlaybackOrchestrator is disposed');
    }
  }
}
