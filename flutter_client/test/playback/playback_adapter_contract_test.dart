import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  group('PlayerAdapter contract', () {
    test(
      'fake backend exposes UI-agnostic imperative controls and streams',
      () async {
        final backend = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
        );
        final states = <PlaybackState>[];
        final errors = <PlaybackError>[];
        final stateSubscription = backend.onState.listen(states.add);
        final errorSubscription = backend.onError.listen(errors.add);

        await backend.load(
          const PlaybackSource(
            uri: 'https://streams.example/vod/movie.mkv',
            title: 'Contract Fixture',
            startPosition: Duration(seconds: 42),
            videoCodec: 'hevc',
            audioCodec: 'dts',
            userAgent: 'm3u-tv/flutter-contract-test',
            headers: <String, String>{'Referer': 'https://provider.example'},
          ),
        );
        await backend.play();
        await backend.pause();
        await backend.seek(const Duration(minutes: 2));
        await backend.setAudioTrack('audio-jpn');
        await backend.setSubtitleTrack('sub-eng');
        await backend.setPlaybackSpeed(1.25);
        await backend.stop();

        expect(backend.commands, <String>[
          'load:https://streams.example/vod/movie.mkv',
          'play',
          'pause',
          'seek:120',
          'audio:audio-jpn',
          'subtitle:sub-eng',
          'speed:1.25',
          'stop',
        ]);
        expect(
          states.map((state) => state.status),
          containsAll(<PlaybackStatus>[
            PlaybackStatus.ready,
            PlaybackStatus.playing,
            PlaybackStatus.paused,
            PlaybackStatus.stopped,
          ]),
        );
        expect(states.last.selectedAudioTrackId, 'audio-jpn');
        expect(states.last.selectedSubtitleTrackId, 'sub-eng');
        expect(states.last.playbackSpeed, 1.25);
        expect(errors, isEmpty);

        await stateSubscription.cancel();
        await errorSubscription.cancel();
        await backend.dispose();
      },
    );

    test(
      'unsupported direct backend falls back to server transcode without UI changes',
      () async {
        final directBackend = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          unsupportedVideoCodecs: <String>{'hevc'},
        );
        final serverTranscodeBackend = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final adapter = FallbackPlayerAdapter(
          primary: directBackend,
          fallback: serverTranscodeBackend,
        );
        final ui = _PlaybackUiHarness(adapter);

        await ui.open(
          const PlaybackSource(
            uri: 'https://provider.example/live/news-hevc.ts',
            title: 'News HEVC',
            isLive: true,
            videoCodec: 'hevc',
            audioCodec: 'aac',
          ),
        );
        await ui.play();
        await ui.pause();
        await ui.stop();
        await pumpEventQueue();

        expect(directBackend.commands, <String>[
          'load:https://provider.example/live/news-hevc.ts',
        ]);
        expect(serverTranscodeBackend.commands, <String>[
          'load:https://provider.example/live/news-hevc.ts',
          'play',
          'pause',
          'stop',
        ]);
        expect(ui.backend, PlaybackBackend.serverTranscode);
        expect(ui.status, PlaybackStatus.stopped);

        await ui.dispose();
      },
    );
  });

  group('PlaybackCapabilities matrix', () {
    test('declares explicit backend rows for every planned platform path', () {
      expect(
        PlaybackCapabilities.matrix.map(
          (capabilities) => capabilities.backend,
        ),
        containsAll(<PlaybackBackend>[
          PlaybackBackend.androidExoPlayer,
          PlaybackBackend.androidMpv,
          PlaybackBackend.appleMpvKit,
          PlaybackBackend.appleAvKit,
          PlaybackBackend.desktopLibmpv,
          PlaybackBackend.serverTranscode,
        ]),
      );
      expect(
        PlaybackCapabilities.forPlatform(PlaybackPlatform.android),
        <PlaybackCapabilities>[
          PlaybackCapabilities.androidExoPlayer,
          PlaybackCapabilities.serverTranscode,
        ],
      );
      expect(
        PlaybackCapabilities.forPlatform(PlaybackPlatform.apple),
        <PlaybackCapabilities>[
          PlaybackCapabilities.appleMpvKit,
          PlaybackCapabilities.appleAvKit,
          PlaybackCapabilities.serverTranscode,
        ],
      );
      expect(
        PlaybackCapabilities.forPlatform(PlaybackPlatform.desktop),
        <PlaybackCapabilities>[
          PlaybackCapabilities.desktopLibmpv,
          PlaybackCapabilities.serverTranscode,
        ],
      );
    });

    test('marks unsupported codec and track features explicitly', () {
      expect(
        PlaybackCapabilities.androidExoPlayer.supportsAdvancedCodecs,
        isFalse,
      );
      expect(
        PlaybackCapabilities.androidExoPlayer.supportsExternalSubtitles,
        isFalse,
      );
      expect(
        PlaybackCapabilities.appleAvKit.supportsAdvancedSubtitleFormats,
        isFalse,
      );
      expect(
        PlaybackCapabilities.serverTranscode.supportsDirectStreams,
        isFalse,
      );
      expect(
        PlaybackCapabilities.serverTranscode.supportsAudioTrackSelection,
        isFalse,
      );
      expect(
        PlaybackCapabilities.serverTranscode.unsupportedFeatures,
        containsAll(<String>[
          'direct-streams',
          'audio-track-selection',
          'subtitle-track-selection',
          'external-subtitles',
          'playback-speed',
        ]),
      );
    });
  });
}

class _PlaybackUiHarness {
  _PlaybackUiHarness(this.adapter) {
    _stateSubscription = adapter.onState.listen((state) {
      backend = state.backend;
      status = state.status;
    });
    _errorSubscription = adapter.onError.listen((error) {
      lastError = error;
    });
  }

  final PlayerAdapter adapter;
  late final StreamSubscription<PlaybackState> _stateSubscription;
  late final StreamSubscription<PlaybackError> _errorSubscription;
  PlaybackBackend? backend;
  PlaybackStatus? status;
  PlaybackError? lastError;

  Future<void> open(PlaybackSource source) => adapter.load(source);
  Future<void> play() => adapter.play();
  Future<void> pause() => adapter.pause();
  Future<void> stop() => adapter.stop();

  Future<void> dispose() async {
    await _stateSubscription.cancel();
    await _errorSubscription.cancel();
    await adapter.dispose();
  }
}

class _FakePlayerAdapter implements PlayerAdapter {
  _FakePlayerAdapter({
    required this.capabilities,
    this.unsupportedVideoCodecs = const <String>{},
  });

  @override
  final PlaybackCapabilities capabilities;
  final Set<String> unsupportedVideoCodecs;
  final List<String> commands = <String>[];
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.serverTranscode,
  );

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    commands.add('load:${source.uri}');
    if (source.videoCodec != null &&
        unsupportedVideoCodecs.contains(source.videoCodec)) {
      throw PlaybackException.unsupported(
        'Unsupported video codec: ${source.videoCodec}',
        backend: capabilities.backend,
      );
    }
    _emit(
      PlaybackState(
        backend: capabilities.backend,
        status: PlaybackStatus.ready,
        source: source,
        position: source.startPosition,
        duration: const Duration(minutes: 30),
        audioTracks: const <PlaybackTrack>[
          PlaybackTrack(id: 'audio-eng', label: 'English', language: 'eng'),
          PlaybackTrack(id: 'audio-jpn', label: 'Japanese', language: 'jpn'),
        ],
        subtitleTracks: const <PlaybackTrack>[
          PlaybackTrack(id: 'sub-eng', label: 'English CC', language: 'eng'),
        ],
      ),
    );
  }

  @override
  Future<void> play() async {
    commands.add('play');
    _emit(_state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    _emit(_state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inSeconds}');
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> stop() async {
    commands.add('stop');
    _emit(_state.copyWith(status: PlaybackStatus.stopped));
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {
    commands.add('audio:$trackId');
    _emit(_state.copyWith(selectedAudioTrackId: trackId));
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    commands.add('subtitle:$trackId');
    _emit(_state.copyWith(selectedSubtitleTrackId: trackId));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    commands.add('speed:$speed');
    _emit(_state.copyWith(playbackSpeed: speed));
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _errorController.close();
  }

  void _emit(PlaybackState state) {
    _state = state;
    _stateController.add(state);
  }
}
