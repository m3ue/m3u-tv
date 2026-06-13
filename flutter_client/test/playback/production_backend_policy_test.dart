import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/m3u_parser.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

void main() {
  group('production backend policy', () {
    testWidgets(
      'unsupported_codec: Android uses Media3 then server transcode and renders diagnostics',
      (WidgetTester tester) async {
        final media3 = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          loadFailure: const PlaybackException.unsupported(
            'Unsupported codec hevc/aac on Android Media3',
            backend: PlaybackBackend.androidExoPlayer,
          ),
        );
        final androidMpv = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.androidMpv,
        );
        final serverPlayer = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _PolicyTranscodeGateway(
          serverResponse: const TranscodeResponse(
            streamId: 'unsupported-stream',
            streamUrl:
                'https://m3u-editor.example/hls/unsupported-stream/index.m3u8',
            mode: TranscodeMode.server,
            status: 'running',
            sessionId: 'unsupported-session',
          ),
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: media3,
            PlaybackBackend.androidMpv: androidMpv,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
        );
        addTearDown(orchestrator.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: PlayerScreen(
              args: const PlayerArgs(
                streamUrl: 'https://provider.example/live/unsupported.ts',
                title: 'Unsupported Codec Fixture',
                type: 'live',
                videoCodec: 'hevc',
                audioCodec: 'aac',
              ),
              orchestrator: orchestrator,
              epgService: EpgService(clock: () => DateTime(2026)),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(media3.commands, <String>[
          'load:https://provider.example/live/unsupported.ts',
        ]);
        expect(androidMpv.commands, isEmpty);
        expect(gateway.startedServerRequests, hasLength(1));
        expect(gateway.startedServerRequests.single.videoCodec, 'hevc');
        expect(serverPlayer.loadedSources.single.uri, contains('unsupported'));
        expect(orchestrator.activeBackend, PlaybackBackend.serverTranscode);
        expect(
          orchestrator.diagnostics,
          contains('android-mpv:disabled-future-gated:unsupported'),
        );
        expect(
          orchestrator.diagnostics,
          contains('active-backend:serverTranscode:ready'),
        );

        expect(find.text('Backend'), findsOneWidget);
        expect(find.text('Server transcode fallback'), findsWidgets);
        expect(find.text('Fallback'), findsOneWidget);
        expect(
          find.textContaining('Unsupported codec hevc/aac'),
          findsOneWidget,
        );
        expect(find.text('Transcode'), findsOneWidget);
        expect(find.textContaining('unsupported-session'), findsOneWidget);
        expect(find.text('Android mpv/libmpv'), findsOneWidget);
        expect(find.textContaining('disabled'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    test(
      'desktop policy reports libmpv failure when no server transcode player is registered',
      () async {
        final desktopLibmpv = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: BackendUnavailableException(
            'libmpv shared library not found; tried libmpv.so.2',
          ),
        );
        final gateway = _PolicyTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: desktopLibmpv,
          },
          transcodeGateway: gateway,
        );
        addTearDown(orchestrator.dispose);
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);
        addTearDown(subscription.cancel);

        await orchestrator.open(
          const PlaybackSource(
            uri: 'https://provider.example/vod/movie.mkv',
            videoCodec: 'hevc',
            audioCodec: 'dts',
          ),
        );

        expect(desktopLibmpv.commands, <String>[
          'load:https://provider.example/vod/movie.mkv',
        ]);
        expect(gateway.startedServerRequests, isEmpty);
        expect(orchestrator.activeBackend, isNull);
        expect(errors, hasLength(1));
        expect(errors.single.backend, PlaybackBackend.desktopLibmpv);
        expect(errors.single.code, BackendUnavailableException.unavailableCode);
        expect(
          errors.single.message,
          'libmpv shared library not found; tried libmpv.so.2',
        );
        expect(
          orchestrator.diagnostics,
          contains(
            'load-failed:desktopLibmpv:backend_unavailable:libmpv shared library not found; tried libmpv.so.2',
          ),
        );
        expect(
          orchestrator.diagnostics,
          contains(
            'error:backend_unavailable:libmpv shared library not found; tried libmpv.so.2',
          ),
        );
      },
    );

    test(
      'desktop software texture render paths use Flutter RGBA pixel buffers',
      () {
        final linuxBackend = File(
          'linux/desktop_libmpv_backend.cc',
        ).readAsStringSync();
        final windowsBackend = File(
          'windows/runner/desktop_libmpv_backend.cpp',
        ).readAsStringSync();

        expect(linuxBackend, contains('char format[] = "rgba";'));
        expect(windowsBackend, contains('char format[] = "rgba";'));
        expect(linuxBackend, isNot(contains('char format[] = "bgra";')));
        expect(windowsBackend, isNot(contains('char format[] = "bgra";')));
      },
    );

    test('Android Media3 retries mislabeled HLS streams as MPEG-TS', () {
      final media3Plugin = File(
        'android/app/src/main/kotlin/com/m3ue/m3utv/Media3PlaybackPlugin.kt',
      ).readAsStringSync();

      expect(media3Plugin, contains('retryHlsAsProgressive'));
      expect(media3Plugin, contains('MimeTypes.VIDEO_MP2T'));
      expect(
        media3Plugin,
        contains('Input does not start with the #EXTM3U header'),
      );
    });

    test(
      'failure diagnostics cover decoder failure, dead stream, and stalled transcode',
      () async {
        final decoderFailure = await _openWithFailure(
          PlaybackPlatform.android,
          PlaybackCapabilities.androidExoPlayer,
          const PlaybackException(
            message: 'Media3 decoder failed during init',
            backend: PlaybackBackend.androidExoPlayer,
            code: 'decoder_failure',
            recoverable: true,
          ),
        );
        expect(decoderFailure.errors, isEmpty);
        expect(
          decoderFailure.orchestrator.diagnostics,
          contains(
            'fallback-reason:decoder_failure:Media3 decoder failed during init',
          ),
        );
        await decoderFailure.dispose();

        final deadStream = await _openWithFailure(
          PlaybackPlatform.android,
          PlaybackCapabilities.androidExoPlayer,
          const PlaybackException(
            message: 'Fixture stream not found',
            backend: PlaybackBackend.androidExoPlayer,
            code: 'stream_not_found',
          ),
        );
        expect(deadStream.errors.single.code, 'stream_not_found');
        expect(deadStream.gateway.startedServerRequests, isEmpty);
        expect(
          deadStream.orchestrator.diagnostics,
          contains(
            'load-failed:androidExoPlayer:stream_not_found:Fixture stream not found',
          ),
        );
        await deadStream.dispose();

        final stalledGateway = _PolicyTranscodeGateway(
          serverResponse: const TranscodeResponse(
            streamId: 'stalled-stream',
            streamUrl:
                'https://m3u-editor.example/hls/stalled-stream/index.m3u8',
            mode: TranscodeMode.server,
            status: 'stalled',
            sessionId: 'stalled-session',
            errorCode: 'transcode_stalled',
            message: 'No HLS segments arrived',
          ),
        );
        final stalled = await _openWithFailure(
          PlaybackPlatform.android,
          PlaybackCapabilities.androidExoPlayer,
          const PlaybackException.unsupported(
            'Unsupported codec vp9/opus',
            backend: PlaybackBackend.androidExoPlayer,
          ),
          gateway: stalledGateway,
        );
        expect(stalled.errors.single.code, 'transcode_stalled');
        expect(stalled.gateway.stoppedServerTranscodes, <String>[
          'stalled-stream:stalled-session',
        ]);
        expect(
          stalled.orchestrator.diagnostics,
          contains(
            'cleanup:server-transcode:stopped:stalled-stream:stalled-session',
          ),
        );
        await stalled.dispose();
      },
    );

    test(
      'cleanup_idempotent: stop and dispose clean backend and transcode session once',
      () async {
        final direct = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: BackendUnavailableException('mpv-2.dll not found'),
        );
        final serverPlayer = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _PolicyTranscodeGateway(
          serverResponse: const TranscodeResponse(
            streamId: 'cleanup-stream',
            streamUrl:
                'https://m3u-editor.example/hls/cleanup-stream/index.m3u8',
            mode: TranscodeMode.server,
            status: 'running',
            sessionId: 'cleanup-session',
          ),
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: direct,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
        );

        await orchestrator.open(
          const PlaybackSource(uri: 'https://provider.example/live/news.ts'),
        );
        await orchestrator.stop();
        await orchestrator.stop();
        await orchestrator.dispose();
        await orchestrator.dispose();

        expect(
          serverPlayer.commands.where((String command) => command == 'stop'),
          hasLength(1),
        );
        expect(gateway.stoppedServerTranscodes, <String>[
          'cleanup-stream:cleanup-session',
        ]);
        expect(
          orchestrator.diagnostics.where(
            (String item) =>
                item ==
                'cleanup:server-transcode:stopped:cleanup-stream:cleanup-session',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'network_loss: buffering timeout retries once then cleans up',
      () async {
        final media3 = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          loadStatus: PlaybackStatus.buffering,
        );
        final gateway = _PolicyTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: media3,
          },
          transcodeGateway: gateway,
          bufferingTimeout: const Duration(milliseconds: 20),
          retryDelay: Duration.zero,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator.open(
          const PlaybackSource(uri: 'https://provider.example/live/offline.ts'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(
          media3.commands.where(
            (String command) =>
                command == 'load:https://provider.example/live/offline.ts',
          ),
          hasLength(2),
        );
        expect(errors, hasLength(1));
        expect(errors.single.code, 'network_unavailable');
        expect(errors.single.recoverable, isTrue);
        expect(orchestrator.activeBackend, isNull);
        expect(media3.commands, contains('stop'));

        await subscription.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'token_expiry: mid-playback expiry reloads once then errors',
      () async {
        final media3 = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
        );
        final gateway = _PolicyTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: media3,
          },
          transcodeGateway: gateway,
          retryDelay: Duration.zero,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator.open(
          const PlaybackSource(
            uri: 'https://provider.example/live/expiring.ts',
          ),
        );
        media3.emitError(
          const PlaybackError(
            backend: PlaybackBackend.androidExoPlayer,
            message: 'Provider token expired during playback',
            code: 'expired_token',
            recoverable: true,
          ),
        );
        await pumpEventQueue();
        media3.emitError(
          const PlaybackError(
            backend: PlaybackBackend.androidExoPlayer,
            message: 'Provider token expired during playback',
            code: 'expired_token',
            recoverable: true,
          ),
        );
        await pumpEventQueue();

        expect(
          media3.commands.where(
            (String command) =>
                command == 'load:https://provider.example/live/expiring.ts',
          ),
          hasLength(2),
        );
        expect(errors, hasLength(1));
        expect(errors.single.code, 'expired_token');
        expect(errors.single.recoverable, isTrue);
        expect(
          orchestrator.diagnostics,
          contains('active-retry:expired_token:androidExoPlayer:1'),
        );

        await subscription.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'rapid_channel_switch: twenty server sessions leave no active backend',
      () async {
        final direct = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: BackendUnavailableException('libmpv unavailable'),
        );
        final serverPlayer = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _PolicyTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: direct,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
        );

        for (var index = 0; index < 20; index += 1) {
          await orchestrator.open(
            PlaybackSource(
              uri: 'https://provider.example/live/channel-$index.ts',
              metadata: <String, Object?>{
                'broadcast_network_id': 'network-$index',
              },
            ),
          );
        }
        await orchestrator.dispose();

        expect(orchestrator.activeBackend, isNull);
        expect(gateway.startedServerRequests, hasLength(20));
        expect(gateway.stoppedBroadcasts, hasLength(20));
        expect(gateway.stoppedServerTranscodes, hasLength(20));
        expect(
          serverPlayer.commands.where((String command) => command == 'stop'),
          hasLength(20),
        );
      },
    );

    test(
      'large_m3u_epg_perf: fixture stays under documented thresholds',
      () {
        final buffer = StringBuffer('#EXTM3U\n');
        final now = DateTime.utc(2026, 1, 1, 12);
        final programs = <EpgProgram>[];
        for (var index = 0; index < 10000; index += 1) {
          buffer.writeln(
            '#EXTINF:-1 tvg-id="bulk.$index" group-title="Bulk",Bulk $index',
          );
          buffer.writeln('https://streams.example/live/$index.m3u8');
          programs.add(
            EpgProgram(
              channelId: 'bulk.$index',
              title: 'Current $index',
              description: 'Task 9 bulk EPG fixture',
              start: now.subtract(const Duration(minutes: 5)),
              end: now.add(const Duration(minutes: 55)),
            ),
          );
        }

        final rssBefore = ProcessInfo.currentRss;
        final stopwatch = Stopwatch()..start();
        final playlist = M3UParser().parse(buffer.toString());
        final epg = EpgService(clock: () => now)..loadPrograms(programs);
        final elapsed = stopwatch.elapsed;
        final rssDelta = ProcessInfo.currentRss - rssBefore;

        expect(playlist.channels, hasLength(10000));
        expect(
          epg.lookupForChannel(playlist.channels.last)?.current.title,
          'Current 9999',
        );
        expect(elapsed, lessThan(const Duration(seconds: 2)));
        expect(rssDelta, lessThan(64 * 1024 * 1024));
      },
      timeout: const Timeout(Duration(seconds: 3)),
    );
  });
}

Future<_PolicyOpenResult> _openWithFailure(
  PlaybackPlatform platform,
  PlaybackCapabilities capabilities,
  PlaybackException failure, {
  _PolicyTranscodeGateway? gateway,
}) async {
  final direct = _PolicyPlayerAdapter(
    capabilities: capabilities,
    loadFailure: failure,
  );
  final serverPlayer = _PolicyPlayerAdapter(
    capabilities: PlaybackCapabilities.serverTranscode,
  );
  final transcodeGateway = gateway ?? _PolicyTranscodeGateway();
  final orchestrator = PlaybackOrchestrator(
    platform: platform,
    adapters: <PlaybackBackend, PlayerAdapter>{
      capabilities.backend: direct,
      PlaybackBackend.serverTranscode: serverPlayer,
    },
    transcodeGateway: transcodeGateway,
  );
  final errors = <PlaybackError>[];
  final subscription = orchestrator.onError.listen(errors.add);

  await orchestrator.open(
    const PlaybackSource(
      uri: 'https://provider.example/live/news.ts',
      videoCodec: 'vp9',
      audioCodec: 'opus',
    ),
  );
  await pumpEventQueue();

  return _PolicyOpenResult(
    orchestrator: orchestrator,
    gateway: transcodeGateway,
    errors: errors,
    subscription: subscription,
  );
}

class _PolicyOpenResult {
  const _PolicyOpenResult({
    required this.orchestrator,
    required this.gateway,
    required this.errors,
    required this.subscription,
  });

  final PlaybackOrchestrator orchestrator;
  final _PolicyTranscodeGateway gateway;
  final List<PlaybackError> errors;
  final StreamSubscription<PlaybackError> subscription;

  Future<void> dispose() async {
    await subscription.cancel();
    await orchestrator.dispose();
  }
}

class _PolicyTranscodeGateway implements PlaybackTranscodeGateway {
  _PolicyTranscodeGateway({this.serverResponse});

  final TranscodeResponse? serverResponse;
  final List<StreamRequest> startedServerRequests = <StreamRequest>[];
  final List<String> stoppedBroadcasts = <String>[];
  final List<String> stoppedServerTranscodes = <String>[];

  @override
  Future<TranscodeResponse> startServerTranscode(StreamRequest request) async {
    startedServerRequests.add(request);
    return serverResponse ??
        TranscodeResponse(
          streamId: 'default-stream-${startedServerRequests.length}',
          streamUrl:
              'https://m3u-editor.example/hls/default-${startedServerRequests.length}/index.m3u8',
          mode: TranscodeMode.server,
          status: 'running',
          sessionId: 'default-session-${startedServerRequests.length}',
        );
  }

  @override
  Future<BroadcastSession?> startBroadcast(StreamRequest request) async {
    final networkId = request.metadata['broadcast_network_id'];
    if (networkId is! String) return null;
    return BroadcastSession(
      networkId: networkId,
      status: BroadcastStatus.running,
      playlistUrl: 'https://m3u-editor.example/broadcast/$networkId/live.m3u8',
      transcodeSessionId: request.sessionId,
    );
  }

  @override
  Future<void> stopBroadcast(String networkId) async {
    stoppedBroadcasts.add(networkId);
  }

  @override
  Future<void> stopServerTranscode({
    required String streamId,
    required String? sessionId,
  }) async {
    stoppedServerTranscodes.add('$streamId:$sessionId');
  }
}

class _PolicyPlayerAdapter implements PlayerAdapter {
  _PolicyPlayerAdapter({
    required this.capabilities,
    this.loadFailure,
    this.loadStatus = PlaybackStatus.ready,
  });

  @override
  final PlaybackCapabilities capabilities;
  final PlaybackException? loadFailure;
  final PlaybackStatus loadStatus;
  final List<String> commands = <String>[];
  final List<PlaybackSource> loadedSources = <PlaybackSource>[];
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
    final failure = loadFailure;
    if (failure != null) {
      throw failure;
    }
    loadedSources.add(source);
    _emit(
      PlaybackState(
        backend: capabilities.backend,
        status: loadStatus,
        source: source,
        position: source.startPosition,
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
  Future<void> dispose() async {
    commands.add('dispose');
    await _stateController.close();
    await _errorController.close();
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

  void _emit(PlaybackState state) {
    _state = state;
    _stateController.add(state);
  }

  void emitError(PlaybackError error) {
    _errorController.add(error);
  }
}
