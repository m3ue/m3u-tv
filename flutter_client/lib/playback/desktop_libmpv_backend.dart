import 'dart:async';

import 'package:flutter/services.dart';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

class DesktopLibmpvBackend implements PlayerAdapter, VideoTextureProvider {
  DesktopLibmpvBackend({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'm3u_tv/desktop_libmpv';

  final MethodChannel _channel;
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.desktopLibmpv,
  );
  int? _handle;
  int? _textureId;

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
    _emit(_state.copyWith(status: PlaybackStatus.loading, source: source));
    final response = await _channel.invokeMapMethod<String, Object?>('load', {
      'uri': source.uri,
      'title': source.title,
      'startPositionMs': source.startPosition.inMilliseconds,
      'isLive': source.isLive,
      'userAgent': source.userAgent,
      'headers': source.headers,
    });
    _handle = response?['handle'] as int?;
    _textureId = response?['textureId'] as int?;
    final ok = response?['ok'] == true;
    if (!ok || _handle == null || _textureId == null) {
      final message = response?['error'] as String? ?? 'libmpv load failed';
      final code = response?['code'] as String? ?? 'desktop-libmpv-load-failed';
      final error = code == BackendUnavailableException.unavailableCode
          ? BackendUnavailableException(message)
          : PlaybackException(
              message: message,
              backend: capabilities.backend,
              code: code,
              recoverable: true,
            );
      _errorController.add(PlaybackError.fromException(error));
      throw error;
    }
    final initialAspectRatio = playbackAspectRatioFromValues(
      aspectRatio:
          response?['videoAspectRatio'] ??
          response?['displayAspectRatio'] ??
          response?['aspectRatio'],
      width: response?['videoWidth'] ?? response?['width'],
      height: response?['videoHeight'] ?? response?['height'],
    );
    _emit(
      _state.copyWith(
        status: PlaybackStatus.ready,
        source: source,
        videoAspectRatio: initialAspectRatio,
      ),
    );
    if (initialAspectRatio == null) {
      unawaited(_refreshVideoAspectRatio());
    }
  }

  @override
  Future<void> play() async {
    await _invokeControl('play');
    _emit(_state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    await _invokeControl('pause');
    _emit(_state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    await _invokeControl('seek', <String, Object?>{
      'positionMs': position.inMilliseconds,
    });
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> stop() async {
    await _invokeControl('stop');
    _emit(_state.copyWith(status: PlaybackStatus.stopped));
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {
    await _invokeControl('setAudioTrack', <String, Object?>{
      'trackId': trackId,
    });
    _emit(_state.copyWith(selectedAudioTrackId: trackId));
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    await _invokeControl('setSubtitleTrack', <String, Object?>{
      'trackId': trackId,
    });
    _emit(_state.copyWith(selectedSubtitleTrackId: trackId));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    await _invokeControl('setPlaybackSpeed', <String, Object?>{'speed': speed});
    _emit(_state.copyWith(playbackSpeed: speed));
  }

  @override
  Future<void> dispose() async {
    if (_handle != null) {
      await _invokeControl('dispose');
      _handle = null;
      _textureId = null;
    }
    await _stateController.close();
    await _errorController.close();
  }

  Future<void> _refreshVideoAspectRatio() async {
    final handle = _handle;
    if (handle == null) return;

    for (final delay in <Duration>[
      Duration.zero,
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 250),
      const Duration(milliseconds: 500),
      const Duration(seconds: 1),
    ]) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (_handle != handle) return;

      final response = await _channel.invokeMapMethod<String, Object?>(
        'getVideoAspectRatio',
        <String, Object?>{'handle': handle},
      );
      final aspectRatio = playbackAspectRatioFromValues(
        aspectRatio:
            response?['videoAspectRatio'] ??
            response?['displayAspectRatio'] ??
            response?['aspectRatio'],
        width: response?['videoWidth'] ?? response?['width'],
        height: response?['videoHeight'] ?? response?['height'],
      );
      if (aspectRatio != null) {
        _emit(_state.copyWith(videoAspectRatio: aspectRatio));
        return;
      }
    }
  }

  Future<void> _invokeControl(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final handle = _handle;
    await _channel.invokeMethod<void>(method, <String, Object?>{
      'handle': ?handle,
      ...arguments,
    });
  }

  void _emit(PlaybackState state) {
    _state = state;
    _stateController.add(state);
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
