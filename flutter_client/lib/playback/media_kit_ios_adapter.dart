import 'dart:async';

import 'package:m3u_tv/playback/media_kit_desktop_adapter.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/playback/subtitle_controller_provider.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

class MediaKitIosAdapter
    implements PlayerAdapter, VideoTextureProvider, SubtitleControllerProvider {
  MediaKitIosAdapter() {
    _player = mk.Player();
    _controller = mkv.VideoController(_player);
    _controller.id.addListener(_onTextureIdChanged);
    _bindStreams();
  }

  late final mk.Player _player;
  late final mkv.VideoController _controller;
  final List<StreamSubscription<Object?>> _subs = [];

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.appleMpvKit,
  );

  @override
  int? get textureId => _controller.id.value;

  @override
  mkv.VideoController get subtitleController => _controller;

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.appleMpvKit;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  void _onTextureIdChanged() {
    _emit(_state);
  }

  void _bindStreams() {
    _subs
      ..add(
        _player.stream.playing.listen((playing) {
          _emit(
            _state.copyWith(
              status: playing ? PlaybackStatus.playing : PlaybackStatus.paused,
            ),
          );
        }),
      )
      ..add(
        _player.stream.buffering.listen((buffering) {
          if (buffering) {
            _emit(_state.copyWith(status: PlaybackStatus.buffering));
          }
        }),
      )
      ..add(
        _player.stream.position.listen((pos) {
          _emit(_state.copyWith(position: pos));
        }),
      )
      ..add(
        _player.stream.duration.listen((dur) {
          _emit(_state.copyWith(duration: dur));
        }),
      )
      ..add(
        _player.stream.tracks.listen((tracks) {
          _emit(
            _state.copyWith(
              audioTracks: mediaKitAudioTracksToPlaybackTracks(tracks.audio),
              subtitleTracks: mediaKitSubtitleTracksToPlaybackTracks(
                tracks.subtitle,
              ),
              selectedAudioTrackId: selectedMediaKitAudioTrackId(
                _player.state.track.audio,
                tracks.audio,
              ),
            ),
          );
        }),
      )
      ..add(
        _player.stream.track.listen((track) {
          _emit(
            _state.copyWith(
              selectedAudioTrackId: selectedMediaKitAudioTrackId(
                track.audio,
                _player.state.tracks.audio,
              ),
              selectedSubtitleTrackId:
                  track.subtitle.id == 'no' || track.subtitle.id == 'auto'
                  ? null
                  : track.subtitle.id,
            ),
          );
        }),
      )
      ..add(
        _player.stream.completed.listen((completed) {
          if (completed) {
            _emit(_state.copyWith(status: PlaybackStatus.completed));
          }
        }),
      )
      ..add(
        _player.stream.error.listen((error) {
          if (error.isNotEmpty && !_isNonFatalMpvWarning(error)) {
            _errorController.add(
              PlaybackError(
                backend: PlaybackBackend.appleMpvKit,
                message: error,
                code: 'media_kit_error',
              ),
            );
          }
        }),
      );
  }

  @override
  Future<void> load(PlaybackSource source) async {
    _emit(_state.copyWith(status: PlaybackStatus.loading, source: source));
    await _player.open(
      mk.Media(
        source.uri,
        httpHeaders: source.headers.isEmpty ? null : source.headers,
      ),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    _emit(_state.copyWith(status: PlaybackStatus.stopped));
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {
    final track = trackId == null
        ? mk.AudioTrack.no()
        : _player.state.tracks.audio.firstWhere(
            (t) => t.id == trackId,
            orElse: () => mk.AudioTrack(trackId, null, null),
          );
    await _player.setAudioTrack(track);
    _emit(_state.copyWith(selectedAudioTrackId: trackId));
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    final track = trackId == null
        ? mk.SubtitleTrack.no()
        : _player.state.tracks.subtitle.firstWhere(
            (t) => t.id == trackId,
            orElse: () => mk.SubtitleTrack(trackId, null, null),
          );
    await _player.setSubtitleTrack(track);
    _emit(_state.copyWith(selectedSubtitleTrackId: trackId));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) => _player.setRate(speed);

  @override
  Future<void> dispose() async {
    _controller.id.removeListener(_onTextureIdChanged);
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _stateController.close();
    await _errorController.close();
    await _player.dispose();
  }

  bool _isNonFatalMpvWarning(String error) {
    return error.contains('audio device') ||
        error.contains('no sound') ||
        error.contains('AO:');
  }

  void _emit(PlaybackState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }
}
