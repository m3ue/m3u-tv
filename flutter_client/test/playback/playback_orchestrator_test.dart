import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackOrchestrator', () {
    const methodChannel = MethodChannel('m3u_tv/desktop_libmpv');
    const eventChannel = EventChannel('m3u_tv/desktop_libmpv/events');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    test(
      'plays directly when the preferred backend can load the stream',
      () async {
        final direct = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
        );
        final fallback = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidMpv,
        );
        final transcode = _FakeTranscodeGateway();
        final orchestrator = _orchestrator(
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: direct,
            PlaybackBackend.androidMpv: fallback,
          },
          transcodeGateway: transcode,
        );

        await orchestrator.open(_source(videoCodec: 'h264'));
        await orchestrator.play();

        expect(direct.commands, <String>[
          'load:https://provider.example/live/news.ts',
          'play',
        ]);
        expect(fallback.commands, isEmpty);
        expect(transcode.startedServerRequests, isEmpty);
        expect(orchestrator.activeBackend, PlaybackBackend.androidExoPlayer);
        expect(
          orchestrator.diagnostics,
          contains('direct:androidExoPlayer:ready'),
        );

        await orchestrator.dispose();
      },
    );

    test(
      'falls back to the native platform backend before transcoding',
      () async {
        final direct = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.appleMediaKit,
          unsupportedVideoCodecs: <String>{'hevc'},
        );
        final fallback = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.appleAvKit,
        );
        final transcode = _FakeTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.apple,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.appleMediaKit: direct,
            PlaybackBackend.appleAvKit: fallback,
          },
          transcodeGateway: transcode,
        );

        await orchestrator.open(_source(videoCodec: 'hevc'));
        await orchestrator.play();

        expect(direct.commands, <String>[
          'load:https://provider.example/live/news.ts',
        ]);
        expect(fallback.commands, <String>[
          'load:https://provider.example/live/news.ts',
          'play',
        ]);
        expect(transcode.startedServerRequests, isEmpty);
        expect(orchestrator.activeBackend, PlaybackBackend.appleAvKit);
        expect(
          orchestrator.diagnostics,
          contains('fallback:appleAvKit:preferred appleMediaKit unsupported'),
        );

        await orchestrator.dispose();
      },
    );

    test(
      'uses server transcode when direct and native fallback are unsupported',
      () async {
        final direct = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          unsupportedVideoCodecs: <String>{'hevc'},
        );
        final fallback = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidMpv,
          unsupportedVideoCodecs: <String>{'hevc'},
        );
        final serverPlayer = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final transcode = _FakeTranscodeGateway(
          serverResponse: const TranscodeResponse(
            streamId: 'transcode-1',
            streamUrl:
                'https://m3u-editor.example/hls/transcode-1/playlist.m3u8',
            mode: TranscodeMode.server,
            status: 'running',
            sessionId: 'plex-session-1',
          ),
        );
        final orchestrator = _orchestrator(
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: direct,
            PlaybackBackend.androidMpv: fallback,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: transcode,
        );

        await orchestrator.open(_source(videoCodec: 'hevc'));
        await orchestrator.play();

        expect(transcode.startedServerRequests.single.videoCodec, 'hevc');
        expect(
          transcode.startedServerRequests.single.mode,
          TranscodeMode.server,
        );
        expect(serverPlayer.commands, <String>[
          'load:https://m3u-editor.example/hls/transcode-1/playlist.m3u8',
          'play',
        ]);
        expect(
          serverPlayer.loadedSources.single.startPosition,
          const Duration(minutes: 3),
        );
        expect(orchestrator.activeBackend, PlaybackBackend.serverTranscode);
        expect(
          orchestrator.diagnostics,
          contains('server-transcode:transcode-1:plex-session-1'),
        );

        await orchestrator.dispose();
      },
    );

    test(
      'emits one recoverable error when server transcode is unavailable',
      () async {
        final direct = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          unsupportedVideoCodecs: <String>{'hevc'},
        );
        final fallback = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidMpv,
          unsupportedVideoCodecs: <String>{'hevc'},
        );
        final serverPlayer = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final transcode = _FakeTranscodeGateway(
          serverError: const TranscodeUnavailableException(
            'm3u-editor offline',
          ),
        );
        final orchestrator = _orchestrator(
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: direct,
            PlaybackBackend.androidMpv: fallback,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: transcode,
        );
        final errors = <PlaybackError>[];
        final sub = orchestrator.onError.listen(errors.add);

        await orchestrator.open(_source(videoCodec: 'hevc'));
        await pumpEventQueue();

        expect(errors, hasLength(1));
        expect(errors.single.recoverable, isTrue);
        expect(errors.single.code, 'server_transcode_unavailable');
        expect(serverPlayer.commands, isEmpty);
        expect(transcode.stoppedServerTranscodes, isEmpty);
        expect(
          orchestrator.diagnostics,
          contains('error:server_transcode_unavailable:m3u-editor offline'),
        );

        await sub.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'desktop without server adapter emits the native libmpv failure',
      () async {
        final desktop = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: const PlaybackException(
            message: 'libmpv render context failed to initialize',
            backend: PlaybackBackend.desktopLibmpv,
            code: 'desktop-libmpv-render-context-failed',
            recoverable: true,
          ),
        );
        final transcode = _FakeTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: desktop,
          },
          transcodeGateway: transcode,
        );
        final errors = <PlaybackError>[];
        final sub = orchestrator.onError.listen(errors.add);

        await orchestrator.open(_source(videoCodec: 'hevc'));
        await pumpEventQueue();

        expect(errors, hasLength(1));
        expect(errors.single.backend, PlaybackBackend.desktopLibmpv);
        expect(errors.single.code, 'desktop-libmpv-render-context-failed');
        expect(
          errors.single.message,
          'libmpv render context failed to initialize',
        );
        expect(transcode.startedServerRequests, isEmpty);
        expect(
          orchestrator.diagnostics,
          contains(
            'error:desktop-libmpv-render-context-failed:libmpv render context failed to initialize',
          ),
        );

        await sub.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'treats stalled transcode as recoverable and cancels its server session',
      () async {
        final direct = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          unsupportedVideoCodecs: <String>{'hevc'},
        );
        final fallback = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.androidMpv,
          unsupportedVideoCodecs: <String>{'hevc'},
        );
        final serverPlayer = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final transcode = _FakeTranscodeGateway(
          serverResponse: const TranscodeResponse(
            streamId: 'transcode-stalled',
            streamUrl:
                'https://m3u-editor.example/hls/transcode-stalled/playlist.m3u8',
            mode: TranscodeMode.server,
            status: 'stalled',
            sessionId: 'plex-session-stalled',
            errorCode: 'transcode_stalled',
            message: 'No HLS segments arrived',
          ),
        );
        final orchestrator = _orchestrator(
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: direct,
            PlaybackBackend.androidMpv: fallback,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: transcode,
        );
        final errors = <PlaybackError>[];
        final sub = orchestrator.onError.listen(errors.add);

        await orchestrator.open(_source(videoCodec: 'hevc'));
        await pumpEventQueue();

        expect(serverPlayer.commands, isEmpty);
        expect(transcode.stoppedServerTranscodes, <String>[
          'transcode-stalled:plex-session-stalled',
        ]);
        expect(errors.single.code, 'transcode_stalled');
        expect(errors.single.recoverable, isTrue);

        await sub.cancel();
        await orchestrator.dispose();
      },
    );

    test('cancels broadcast and server transcode sessions on stop', () async {
      final direct = _FakePlayerAdapter(
        capabilities: PlaybackCapabilities.androidExoPlayer,
        unsupportedVideoCodecs: <String>{'hevc'},
      );
      final fallback = _FakePlayerAdapter(
        capabilities: PlaybackCapabilities.androidMpv,
        unsupportedVideoCodecs: <String>{'hevc'},
      );
      final serverPlayer = _FakePlayerAdapter(
        capabilities: PlaybackCapabilities.serverTranscode,
      );
      final transcode = _FakeTranscodeGateway(
        serverResponse: const TranscodeResponse(
          streamId: 'transcode-live',
          streamUrl:
              'https://m3u-editor.example/hls/transcode-live/playlist.m3u8',
          mode: TranscodeMode.server,
          status: 'running',
          sessionId: 'plex-live-session',
        ),
        broadcastSession: const BroadcastSession(
          networkId: 'network-1',
          status: BroadcastStatus.running,
          playlistUrl:
              'https://m3u-editor.example/broadcast/network-1/live.m3u8',
          transcodeSessionId: 'plex-live-session',
        ),
      );
      final orchestrator = _orchestrator(
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.androidExoPlayer: direct,
          PlaybackBackend.androidMpv: fallback,
          PlaybackBackend.serverTranscode: serverPlayer,
        },
        transcodeGateway: transcode,
      );

      await orchestrator.open(
        _source(
          videoCodec: 'hevc',
          metadata: const <String, Object?>{
            'broadcast_network_id': 'network-1',
          },
        ),
      );
      await orchestrator.stop();

      expect(serverPlayer.commands.last, 'stop');
      expect(transcode.stoppedBroadcasts, <String>['network-1']);
      expect(transcode.stoppedServerTranscodes, <String>[
        'transcode-live:plex-live-session',
      ]);

      await orchestrator.dispose();
    });

    test('preserves resume seek when loading a server transcode URL', () async {
      final direct = _FakePlayerAdapter(
        capabilities: PlaybackCapabilities.appleAvKit,
        unsupportedVideoCodecs: <String>{'hevc'},
      );
      final fallback = _FakePlayerAdapter(
        capabilities: PlaybackCapabilities.appleMediaKit,
        unsupportedVideoCodecs: <String>{'hevc'},
      );
      final serverPlayer = _FakePlayerAdapter(
        capabilities: PlaybackCapabilities.serverTranscode,
      );
      final transcode = _FakeTranscodeGateway(
        serverResponse: const TranscodeResponse(
          streamId: 'transcode-vod',
          streamUrl:
              'https://m3u-editor.example/hls/transcode-vod/playlist.m3u8',
          mode: TranscodeMode.server,
          status: 'running',
          sessionId: 'plex-vod-session',
        ),
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.apple,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.appleAvKit: direct,
          PlaybackBackend.appleMediaKit: fallback,
          PlaybackBackend.serverTranscode: serverPlayer,
        },
        transcodeGateway: transcode,
      );

      await orchestrator.open(
        _source(
          isLive: false,
          videoCodec: 'hevc',
          startPosition: const Duration(minutes: 12, seconds: 34),
        ),
      );

      expect(
        serverPlayer.loadedSources.single.uri,
        'https://m3u-editor.example/hls/transcode-vod/playlist.m3u8',
      );
      expect(
        serverPlayer.loadedSources.single.startPosition,
        const Duration(minutes: 12, seconds: 34),
      );
      expect(
        transcode.startedServerRequests.single.metadata['resume_seconds'],
        754,
      );

      await orchestrator.dispose();
    });

    test(
      'desktop without server transcode reports the libmpv load failure',
      () async {
        final desktop = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: const PlaybackException(
            message: 'libmpv shared library not found; tried libmpv.so.2',
            backend: PlaybackBackend.desktopLibmpv,
            code: 'backend_unavailable',
            recoverable: true,
          ),
        );
        final transcode = _FakeTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: desktop,
          },
          transcodeGateway: transcode,
        );
        final errors = <PlaybackError>[];
        final sub = orchestrator.onError.listen(errors.add);

        await orchestrator.open(_source(isLive: false));
        await pumpEventQueue();

        expect(desktop.commands, <String>[
          'load:https://provider.example/live/news.ts',
        ]);
        expect(transcode.startedServerRequests, isEmpty);
        expect(errors, hasLength(1));
        expect(errors.single.backend, PlaybackBackend.desktopLibmpv);
        expect(errors.single.code, 'backend_unavailable');
        expect(
          errors.single.message,
          'libmpv shared library not found; tried libmpv.so.2',
        );
        expect(
          errors.single.message,
          isNot(contains('No server transcode playback backend is registered')),
        );
        expect(
          orchestrator.diagnostics,
          contains(
            'error:backend_unavailable:libmpv shared library not found; tried libmpv.so.2',
          ),
        );

        await sub.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'deterministic desktop dead URL emits one final load error',
      () async {
        final events = _setUpDesktopEvents(eventChannel);
        const sourceUri = 'http://127.0.0.1:9/fixture/dead-stream/master.m3u8';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              if (call.method != 'load') return null;
              final arguments = Map<String, Object?>.from(
                call.arguments as Map<Object?, Object?>,
              );
              expect(arguments['uri'], sourceUri);
              return <String, Object?>{
                'ok': false,
                'code': 'stream_not_found',
                'error': 'Fixture stream is intentionally unavailable',
              };
            });

        final desktop = DesktopLibmpvBackend();
        final adapterErrors = <PlaybackError>[];
        final adapterSubscription = desktop.onError.listen(adapterErrors.add);
        final transcode = _FakeTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: desktop,
          },
          transcodeGateway: transcode,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator
            .open(const PlaybackSource(uri: sourceUri, isLive: true))
            .timeout(const Duration(seconds: 1));
        await pumpEventQueue();

        expect(adapterErrors, isEmpty);
        expect(errors, hasLength(1));
        expect(errors.single.code, 'stream_not_found');
        expect(orchestrator.activeBackend, isNull);
        expect(desktop.textureId, isNull);
        expect(transcode.startedServerRequests, isEmpty);

        await adapterSubscription.cancel();
        await subscription.cancel();
        await orchestrator.dispose();
        await events.close();
      },
      timeout: const Timeout(Duration(seconds: 3)),
    );

    test(
      'pre-ready desktop terminal cleanup completes before server fallback',
      () async {
        final events = _setUpDesktopEvents(eventChannel);
        final methodCalls = <MethodCall>[];
        var nativeDisposed = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              methodCalls.add(call);
              if (call.method == 'dispose') {
                await Future<void>.delayed(const Duration(milliseconds: 20));
                nativeDisposed = true;
                return null;
              }
              if (call.method != 'load') return null;
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 61,
                  'sequence': 0,
                  'kind': 'ERROR',
                  'message': 'desktop demuxer rejected fixture',
                  'code': 'mpv-end-file-error',
                  'recoverable': true,
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': 61,
                'textureId': 6100,
              };
            });

        final desktop = DesktopLibmpvBackend();
        final serverPlayer = _FakePlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final transcode = _FakeTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: desktop,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: transcode,
        );

        await orchestrator
            .open(
              const PlaybackSource(
                uri: 'https://provider.example/live/fallback.ts',
                isLive: true,
              ),
            )
            .timeout(const Duration(seconds: 1));

        expect(nativeDisposed, isTrue);
        expect(desktop.textureId, isNull);
        expect(orchestrator.activeBackend, PlaybackBackend.serverTranscode);
        expect(transcode.startedServerRequests, hasLength(1));
        final disposeCalls = methodCalls
            .where((call) => call.method == 'dispose')
            .toList();
        expect(disposeCalls, hasLength(1));
        expect(disposeCalls.single.arguments, <String, Object?>{'handle': 61});

        await orchestrator.dispose();
        await events.close();
      },
      timeout: const Timeout(Duration(seconds: 3)),
    );

    test(
      'post-ready desktop failure retries once then releases final handle',
      () async {
        final events = _setUpDesktopEvents(eventChannel);
        final methodCalls = <MethodCall>[];
        var loadCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              methodCalls.add(call);
              if (call.method != 'load') return null;
              loadCount += 1;
              final handle = 70 + loadCount;
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': handle,
                  'sequence': 0,
                  'kind': 'FILE_LOADED',
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': handle,
                'textureId': handle * 100,
              };
            });

        final desktop = DesktopLibmpvBackend();
        final transcode = _FakeTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: desktop,
          },
          transcodeGateway: transcode,
          retryDelay: Duration.zero,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator
            .open(
              const PlaybackSource(
                uri: 'https://provider.example/live/runtime.ts',
                isLive: true,
              ),
            )
            .timeout(const Duration(seconds: 1));
        events.add(<String, Object?>{
          'schemaVersion': 1,
          'handle': 71,
          'sequence': 1,
          'kind': 'ERROR',
          'message': 'desktop stream failed after ready',
          'code': 'network_unavailable',
          'recoverable': true,
        });
        await pumpEventQueue();

        expect(loadCount, 2);
        expect(desktop.textureId, 7200);

        events.add(<String, Object?>{
          'schemaVersion': 1,
          'handle': 72,
          'sequence': 1,
          'kind': 'ERROR',
          'message': 'desktop stream failed after retry',
          'code': 'network_unavailable',
          'recoverable': true,
        });
        await pumpEventQueue();

        expect(errors, hasLength(1));
        expect(errors.single.code, 'network_unavailable');
        expect(orchestrator.activeBackend, isNull);
        expect(desktop.textureId, isNull);
        final disposeCalls = methodCalls
            .where((call) => call.method == 'dispose')
            .toList();
        expect(disposeCalls, hasLength(2));
        expect(disposeCalls[0].arguments, <String, Object?>{'handle': 71});
        expect(disposeCalls[1].arguments, <String, Object?>{'handle': 72});
        expect(transcode.startedServerRequests, isEmpty);

        await subscription.cancel();
        await orchestrator.dispose();
        await events.close();
      },
      timeout: const Timeout(Duration(seconds: 3)),
    );
  });
}

StreamController<Map<String, Object?>> _setUpDesktopEvents(
  EventChannel eventChannel,
) {
  final events = StreamController<Map<String, Object?>>.broadcast();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, eventSink) {
            events.stream.listen(eventSink.success);
          },
        ),
      );
  return events;
}

PlaybackOrchestrator _orchestrator({
  required Map<PlaybackBackend, PlayerAdapter> adapters,
  required PlaybackTranscodeGateway transcodeGateway,
}) {
  return PlaybackOrchestrator(
    platform: PlaybackPlatform.android,
    adapters: adapters,
    transcodeGateway: transcodeGateway,
  );
}

PlaybackSource _source({
  bool isLive = true,
  String? videoCodec,
  Duration startPosition = const Duration(minutes: 3),
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return PlaybackSource(
    uri: 'https://provider.example/live/news.ts',
    title: 'News',
    isLive: isLive,
    startPosition: startPosition,
    videoCodec: videoCodec,
    audioCodec: 'aac',
    userAgent: 'm3u-tv/flutter-test',
    headers: const <String, String>{'Referer': 'https://provider.example'},
    metadata: metadata,
  );
}

class _FakeTranscodeGateway implements PlaybackTranscodeGateway {
  _FakeTranscodeGateway({
    this.serverResponse,
    this.serverError,
    this.broadcastSession,
  });

  final TranscodeResponse? serverResponse;
  final Exception? serverError;
  final BroadcastSession? broadcastSession;
  final List<StreamRequest> startedServerRequests = <StreamRequest>[];
  final List<StreamRequest> startedBroadcastRequests = <StreamRequest>[];
  final List<String> stoppedServerTranscodes = <String>[];
  final List<String> stoppedBroadcasts = <String>[];

  @override
  Future<TranscodeResponse> startServerTranscode(StreamRequest request) async {
    startedServerRequests.add(request);
    final error = serverError;
    if (error != null) throw error;
    return serverResponse ??
        const TranscodeResponse(
          streamId: 'transcode-default',
          streamUrl: 'https://m3u-editor.example/hls/default/playlist.m3u8',
          mode: TranscodeMode.server,
          status: 'running',
          sessionId: 'plex-default-session',
        );
  }

  @override
  Future<BroadcastSession?> startBroadcast(StreamRequest request) async {
    startedBroadcastRequests.add(request);
    return broadcastSession;
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

class _FakePlayerAdapter implements PlayerAdapter {
  _FakePlayerAdapter({
    required this.capabilities,
    this.loadFailure,
    this.unsupportedVideoCodecs = const <String>{},
  });

  @override
  final PlaybackCapabilities capabilities;
  final PlaybackException? loadFailure;
  final Set<String> unsupportedVideoCodecs;
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
    loadedSources.add(source);
    final failure = loadFailure;
    if (failure != null) {
      throw failure;
    }
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
        duration: source.isLive ? null : const Duration(hours: 2),
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
