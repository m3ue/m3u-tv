import 'dart:async';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

/// A fake PlayerAdapter for widget tests that records calls and emits
/// configurable state/error streams.
class FakePlayerAdapter
    implements PlayerAdapter, VideoTextureProvider, NativePlaneProvider {
  FakePlayerAdapter({
    PlaybackCapabilities? capabilities,
    this.textureId,
    this.usesNativePlane = false,
  }) : capabilities = capabilities ?? PlaybackCapabilities.androidExoPlayer;

  @override
  final PlaybackCapabilities capabilities;

  @override
  final int? textureId;

  @override
  final bool usesNativePlane;

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  // Call records
  final List<PlaybackSource> loadCalls = [];
  final List<Duration> seekCalls = [];
  final List<String?> setAudioTrackCalls = [];
  final List<String?> setSubtitleTrackCalls = [];
  final List<double> setPlaybackSpeedCalls = [];
  int playCallCount = 0;
  int pauseCallCount = 0;
  int stopCallCount = 0;
  int disposeCallCount = 0;

  @override
  Future<void> load(PlaybackSource source) async {
    loadCalls.add(source);
  }

  @override
  Future<void> play() async {
    playCallCount++;
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    await _stateController.close();
    await _errorController.close();
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {
    setAudioTrackCalls.add(trackId);
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    setSubtitleTrackCalls.add(trackId);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    setPlaybackSpeedCalls.add(speed);
  }

  /// Emit a state update for testing.
  void emitState(PlaybackState state) => _stateController.add(state);

  /// Emit an error for testing.
  void emitError(PlaybackError error) => _errorController.add(error);

  @override
  void reportVideoRect(
    double x,
    double y,
    double width,
    double height,
    double devicePixelRatio,
  ) {}
}
