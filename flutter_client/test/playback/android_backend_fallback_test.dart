import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/android_playback_adapter.dart';
import 'package:m3u_tv/playback/android_tv_player_overlay.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  group('AndroidPlaybackAdapter', () {
    test('reports codec, track, and subtitle backend capabilities', () {
      final adapter = AndroidPlaybackAdapter(
        probe: const AndroidPlaybackProbe(
          hardwareCodecs: <VideoCodec>{
            VideoCodec.h264,
            VideoCodec.h265,
            VideoCodec.av1,
          },
          passthroughAudioCodecs: <AudioCodec>{AudioCodec.ac3},
          mpvAvailable: true,
          serverTranscodeAvailable: true,
        ),
      );

      expect(adapter.capabilities.backend, PlaybackBackend.androidExoPlayer);
      expect(
        adapter.androidCapabilities.supportsVideo(VideoCodec.h264),
        isTrue,
      );
      expect(
        adapter.androidCapabilities.supportsVideo(VideoCodec.h265),
        isTrue,
      );
      expect(adapter.androidCapabilities.supportsVideo(VideoCodec.av1), isTrue);
      expect(adapter.androidCapabilities.supportsAudio(AudioCodec.ac3), isTrue);
      expect(
        adapter.androidCapabilities.supportsAudio(AudioCodec.dts),
        isFalse,
      );
      expect(adapter.androidCapabilities.supportsSubtitles, isTrue);
      expect(adapter.androidCapabilities.supportsAudioTracks, isTrue);
      expect(adapter.androidCapabilities.fallbackOrder, <PlaybackBackend>[
        PlaybackBackend.androidExoPlayer,
        PlaybackBackend.serverTranscode,
      ]);
    });

    test('loads streams without codec metadata through Media3 first', () async {
      final host = _FakeAndroidMedia3Host();
      final adapter = AndroidPlaybackAdapter(
        probe: const AndroidPlaybackProbe(
          hardwareCodecs: <VideoCodec>{VideoCodec.h264},
          passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac, AudioCodec.mp3},
          mpvAvailable: false,
          serverTranscodeAvailable: false,
        ),
        media3Host: host,
      );

      await adapter.load(
        const PlaybackSource(
          uri: 'https://provider.example/live/channel.ts',
          title: 'Provider Channel',
          isLive: true,
        ),
      );

      expect(adapter.activeBackend, PlaybackBackend.androidExoPlayer);
      expect(host.commands, <String>[
        'load:https://provider.example/live/channel.ts',
      ]);
      expect(adapter.decisionLog, contains('direct:exo-player'));

      await adapter.dispose();
    });

    test(
      'uses server transcode for unsupported codec fixtures while Android MPV is future-gated',
      () async {
        final adapter = AndroidPlaybackAdapter(
          probe: const AndroidPlaybackProbe(
            hardwareCodecs: <VideoCodec>{VideoCodec.h264},
            passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac},
            mpvAvailable: true,
            serverTranscodeAvailable: true,
          ),
        );
        final states = <PlaybackState>[];
        final subscription = adapter.onState.listen(states.add);

        await adapter.load(
          const PlaybackSource(
            uri: 'https://fixtures.example/unsupported-hevc-dts.mkv',
            title: 'Unsupported HEVC + DTS fixture',
            videoCodec: 'hevc',
            audioCodec: 'dts',
          ),
        );
        await adapter.play();

        expect(adapter.activeBackend, PlaybackBackend.serverTranscode);
        expect(
          states.map((state) => state.backend),
          contains(PlaybackBackend.serverTranscode),
        );
        expect(
          adapter.decisionLog,
          contains('android-mpv:disabled-future-gated:unsupported-codec'),
        );
        expect(
          adapter.decisionLog,
          contains('fallback:server-transcode:unsupported-codec'),
        );

        await subscription.cancel();
        await adapter.dispose();
      },
    );

    test(
      'uses server transcode for decoder failures even when Android MPV probe is available',
      () async {
        final adapter = AndroidPlaybackAdapter(
          probe: const AndroidPlaybackProbe(
            hardwareCodecs: <VideoCodec>{VideoCodec.h264},
            passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac},
            mpvAvailable: true,
            serverTranscodeAvailable: true,
          ),
        );

        await adapter.load(
          const PlaybackSource(
            uri: 'https://fixtures.example/black-screen-h264.ts',
            videoCodec: 'h264',
            audioCodec: 'aac',
            metadata: <String, Object?>{'decoderFailure': 'black-screen'},
          ),
        );

        expect(adapter.activeBackend, PlaybackBackend.serverTranscode);
        expect(
          adapter.decisionLog,
          contains('android-mpv:disabled-future-gated:black-screen'),
        );
        expect(
          adapter.decisionLog,
          contains('fallback:server-transcode:black-screen'),
        );

        await adapter.dispose();
      },
    );

    test(
      'uses server transcode for audio codec mismatch and typed unsupported error when unavailable',
      () async {
        final serverAdapter = AndroidPlaybackAdapter(
          probe: const AndroidPlaybackProbe(
            hardwareCodecs: <VideoCodec>{VideoCodec.h264},
            passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac},
            mpvAvailable: true,
            serverTranscodeAvailable: true,
          ),
        );

        await serverAdapter.load(
          const PlaybackSource(
            uri: 'https://fixtures.example/unsupported-dts.mkv',
            videoCodec: 'h264',
            audioCodec: 'dts',
          ),
        );

        expect(serverAdapter.activeBackend, PlaybackBackend.serverTranscode);
        expect(
          serverAdapter.decisionLog,
          contains('android-mpv:disabled-future-gated:unsupported-codec'),
        );
        expect(
          serverAdapter.decisionLog,
          contains('fallback:server-transcode:unsupported-codec'),
        );

        final unsupportedAdapter = AndroidPlaybackAdapter(
          probe: const AndroidPlaybackProbe(
            hardwareCodecs: <VideoCodec>{VideoCodec.h264},
            passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac},
            mpvAvailable: true,
            serverTranscodeAvailable: false,
          ),
        );
        final errors = <PlaybackError>[];
        final subscription = unsupportedAdapter.onError.listen(errors.add);

        await expectLater(
          unsupportedAdapter.load(
            const PlaybackSource(
              uri: 'https://fixtures.example/unsupported-dts.mkv',
              videoCodec: 'h264',
              audioCodec: 'dts',
            ),
          ),
          throwsA(
            isA<PlaybackException>()
                .having(
                  (error) => error.code,
                  'code',
                  'unsupported',
                )
                .having(
                  (error) => error.recoverable,
                  'recoverable',
                  isTrue,
                ),
          ),
        );
        await pumpEventQueue();
        expect(
          unsupportedAdapter.activeBackend,
          PlaybackBackend.androidExoPlayer,
        );
        expect(errors.single.code, 'unsupported');
        expect(errors.single.recoverable, isTrue);
        expect(
          unsupportedAdapter.decisionLog,
          contains('android-mpv:disabled-future-gated:unsupported-codec'),
        );
        expect(
          unsupportedAdapter.decisionLog,
          contains('error:unsupported:unsupported-codec'),
        );

        await subscription.cancel();
        await serverAdapter.dispose();
        await unsupportedAdapter.dispose();
      },
    );

    test(
      'maps native Media3 track events and forwards track selection',
      () async {
        final host = _FakeAndroidMedia3Host();
        final adapter = AndroidPlaybackAdapter(
          probe: const AndroidPlaybackProbe(
            hardwareCodecs: <VideoCodec>{VideoCodec.h264},
            passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac},
            mpvAvailable: false,
            serverTranscodeAvailable: false,
          ),
          media3Host: host,
        );
        final states = <PlaybackState>[];
        final subscription = adapter.onState.listen(states.add);

        await adapter.load(
          const PlaybackSource(uri: 'https://fixtures.example/movie.m3u8'),
        );
        host.emit(
          const AndroidMedia3Event(
            type: AndroidMedia3EventType.ready,
            audioTracks: <PlaybackTrack>[
              PlaybackTrack(id: 'audio:0:0', label: 'English', language: 'en'),
              PlaybackTrack(id: 'audio:0:1', label: 'Deutsch', language: 'de'),
            ],
            subtitleTracks: <PlaybackTrack>[
              PlaybackTrack(
                id: 'subtitle:1:0',
                label: 'English CC',
                language: 'en',
              ),
            ],
            selectedAudioTrackId: 'audio:0:0',
          ),
        );
        await pumpEventQueue();

        expect(states.last.audioTracks.map((track) => track.label), <String>[
          'English',
          'Deutsch',
        ]);
        expect(states.last.subtitleTracks.single.label, 'English CC');
        expect(states.last.selectedAudioTrackId, 'audio:0:0');

        await adapter.setAudioTrack('audio:0:1');
        await adapter.setSubtitleTrack('subtitle:1:0');
        await adapter.setSubtitleTrack(null);
        await pumpEventQueue();

        expect(
          host.commands,
          containsAll(<String>[
            'setAudioTrack:audio:0:1',
            'setSubtitleTrack:subtitle:1:0',
            'setSubtitleTrack:null',
          ]),
        );
        expect(states.last.selectedAudioTrackId, 'audio:0:1');
        expect(states.last.selectedSubtitleTrackId, isNull);

        await subscription.cancel();
        await adapter.dispose();
      },
    );

    test(
      'maps ExoPlayer commands and typed native events through Media3 host',
      () async {
        final host = _FakeAndroidMedia3Host();
        final adapter = AndroidPlaybackAdapter(
          probe: const AndroidPlaybackProbe(
            hardwareCodecs: <VideoCodec>{VideoCodec.h264},
            passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac},
            mpvAvailable: false,
            serverTranscodeAvailable: true,
          ),
          media3Host: host,
        );
        final states = <PlaybackState>[];
        final errors = <PlaybackError>[];
        final stateSubscription = adapter.onState.listen(states.add);
        final errorSubscription = adapter.onError.listen(errors.add);

        const source = PlaybackSource(
          uri: 'http://127.0.0.1:8080/fixture/hls-live/master.m3u8',
          title: 'Fixture HLS Live',
          isLive: true,
          videoCodec: 'h264',
          audioCodec: 'aac',
          userAgent: 'm3u-tv-production-fixture/1.0',
          headers: <String, String>{'Referer': 'https://fixture.invalid/app'},
        );
        await adapter.load(source);
        host.emit(
          const AndroidMedia3Event(
            type: AndroidMedia3EventType.ready,
            position: Duration.zero,
          ),
        );
        await pumpEventQueue();
        await adapter.play();
        host.emit(
          const AndroidMedia3Event(
            type: AndroidMedia3EventType.playing,
            position: Duration(seconds: 1),
          ),
        );
        await pumpEventQueue();
        await adapter.pause();
        await adapter.seek(const Duration(seconds: 42));
        await adapter.stop();
        host.emit(
          const AndroidMedia3Event(
            type: AndroidMedia3EventType.error,
            code: 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
            message: 'Fixture stream not found',
            recoverable: true,
          ),
        );
        await pumpEventQueue();

        expect(adapter.activeBackend, PlaybackBackend.androidExoPlayer);
        expect(host.commands, <String>[
          'load:http://127.0.0.1:8080/fixture/hls-live/master.m3u8',
          'play',
          'pause',
          'seek:42000',
          'stop',
        ]);
        expect(
          host.loadedSources.single.headers,
          containsPair('Referer', 'https://fixture.invalid/app'),
        );
        expect(
          states.map((state) => state.status),
          containsAll(<PlaybackStatus>[
            PlaybackStatus.loading,
            PlaybackStatus.ready,
            PlaybackStatus.playing,
            PlaybackStatus.paused,
            PlaybackStatus.stopped,
          ]),
        );
        expect(errors.single.code, 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED');
        expect(errors.single.recoverable, isTrue);

        await stateSubscription.cancel();
        await errorSubscription.cancel();
        await adapter.dispose();
        expect(host.commands.last, 'dispose');
      },
    );
  });

  group('AndroidTvPlayerOverlay', () {
    testWidgets('handles D-pad select/play/pause/back focus flow', (
      tester,
    ) async {
      final controller = AndroidTvPlaybackOverlayController(
        initialStatus: PlaybackStatus.playing,
      );
      final actions = <PlaybackOverlayAction>[];

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: AndroidTvPlayerOverlay(
            controller: controller,
            onAction: actions.add,
          ),
        ),
      );

      await tester.pump();
      expect(controller.isVisible, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(controller.isVisible, isTrue);
      expect(controller.focusedControl, PlaybackOverlayControl.pause);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(actions, contains(PlaybackOverlayAction.pause));
      expect(controller.status, PlaybackStatus.paused);
      expect(controller.focusedControl, PlaybackOverlayControl.play);

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(actions, contains(PlaybackOverlayAction.play));
      expect(controller.status, PlaybackStatus.playing);
      expect(controller.focusedControl, PlaybackOverlayControl.pause);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.focusedControl, PlaybackOverlayControl.audioTracks);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(actions, contains(PlaybackOverlayAction.dismiss));
      expect(controller.isVisible, isFalse);
    });
  });
}

class _FakeAndroidMedia3Host implements AndroidMedia3Host {
  final StreamController<AndroidMedia3Event> _events =
      StreamController<AndroidMedia3Event>.broadcast();
  final List<String> commands = <String>[];
  final List<PlaybackSource> loadedSources = <PlaybackSource>[];

  @override
  Stream<AndroidMedia3Event> get events => _events.stream;

  void emit(AndroidMedia3Event event) => _events.add(event);

  @override
  Future<void> load(PlaybackSource source) async {
    commands.add('load:${source.uri}');
    loadedSources.add(source);
  }

  @override
  Future<void> play() async => commands.add('play');

  @override
  Future<void> pause() async => commands.add('pause');

  @override
  Future<void> seek(Duration position) async =>
      commands.add('seek:${position.inMilliseconds}');

  @override
  Future<void> stop() async => commands.add('stop');

  @override
  Future<void> setAudioTrack(String? trackId) async =>
      commands.add('setAudioTrack:$trackId');

  @override
  Future<void> setSubtitleTrack(String? trackId) async =>
      commands.add('setSubtitleTrack:$trackId');

  @override
  Future<void> dispose() async {
    commands.add('dispose');
    await _events.close();
  }
}
