import 'dart:async';

import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/playback/subtitle_controller_provider.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

class MediaKitDesktopAdapter
    implements PlayerAdapter, VideoTextureProvider, SubtitleControllerProvider {
  MediaKitDesktopAdapter() {
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
    backend: PlaybackBackend.desktopLibmpv,
  );

  @override
  int? get textureId => _controller.id.value;

  @override
  mkv.VideoController get subtitleController => _controller;

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.desktopLibmpv;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  void _onTextureIdChanged() {
    // Re-emit current state so PlayerScreen rebuilds and reads the new textureId.
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
              selectedSubtitleTrackId: _selectedTrackId(track.subtitle.id),
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
          if (error.isNotEmpty) {
            _errorController.add(
              PlaybackError(
                backend: PlaybackBackend.desktopLibmpv,
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
            (track) => track.id == trackId,
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
            (track) => track.id == trackId,
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

  void _emit(PlaybackState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }
}

List<PlaybackTrack> mediaKitAudioTracksToPlaybackTracks(
  List<mk.AudioTrack> tracks,
) {
  return tracks
      .where((track) => !_isMediaKitSentinelTrack(track.id))
      .map(
        (track) => PlaybackTrack(
          id: track.id,
          label: _mediaKitTrackLabel(
            id: track.id,
            title: track.title,
            language: track.language,
          ),
          language: track.language,
        ),
      )
      .toList(growable: false);
}

List<PlaybackTrack> mediaKitSubtitleTracksToPlaybackTracks(
  List<mk.SubtitleTrack> tracks,
) {
  return tracks
      .where((track) => !_isMediaKitSentinelTrack(track.id))
      .map(
        (track) => PlaybackTrack(
          id: track.id,
          label: _mediaKitTrackLabel(
            id: track.id,
            title: track.title,
            language: track.language,
          ),
          language: track.language,
        ),
      )
      .toList(growable: false);
}

String _mediaKitTrackLabel({
  required String id,
  required String? title,
  required String? language,
}) {
  final cleanTitle = title?.trim();
  if (cleanTitle != null && cleanTitle.isNotEmpty) return cleanTitle;
  final cleanLanguage = language?.trim();
  if (cleanLanguage != null && cleanLanguage.isNotEmpty) return cleanLanguage;
  return 'Track $id';
}

String? selectedMediaKitAudioTrackId(
  mk.AudioTrack selectedTrack,
  List<mk.AudioTrack> availableTracks,
) {
  if (selectedTrack.id == 'no') return null;
  if (selectedTrack.id != 'auto') return selectedTrack.id;

  return availableTracks
      .where((track) => !_isMediaKitSentinelTrack(track.id))
      .firstOrNull
      ?.id;
}

String? _selectedTrackId(String id) => id == 'no' || id == 'auto' ? null : id;

bool _isMediaKitSentinelTrack(String id) => id == 'auto' || id == 'no';
