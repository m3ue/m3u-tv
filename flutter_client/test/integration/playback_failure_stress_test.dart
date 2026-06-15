import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

import '../fakes/fake_m3u_editor_server.dart';

void main() {
  group('playback failure and stress integration', () {
    late FakeM3uEditorServer server;

    setUp(() async {
      server = FakeM3uEditorServer(apiToken: 'fixture-api-token');
      await server.start();
    });

    tearDown(() async {
      await server.close();
    });

    test(
      'network_loss_integration: buffering timeout with real server retries once then emits typed error and cleans up',
      () async {
        final direct = _StressPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          loadStatus: PlaybackStatus.buffering,
        );
        final serverPlayer = _StressPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _StressTranscodeGateway(server: server);
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: direct,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
          bufferingTimeout: const Duration(milliseconds: 20),
          retryDelay: Duration.zero,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        final sourceUri = '${server.uri}/fixture/hls-live/master.m3u8';
        await orchestrator.open(
          PlaybackSource(
            uri: sourceUri,
            title: 'Network Loss Fixture',
            isLive: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(
          direct.commands.where((c) => c == 'load:$sourceUri'),
          hasLength(2),
        );
        expect(errors, hasLength(1));
        expect(errors.single.code, 'network_unavailable');
        expect(errors.single.recoverable, isTrue);
        expect(orchestrator.activeBackend, isNull);
        expect(direct.commands, contains('stop'));
        expect(gateway.startedServerRequests, isEmpty);
        expect(gateway.stoppedServerTranscodes, isEmpty);
        expect(gateway.stoppedBroadcasts, isEmpty);

        await subscription.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'token_expiry_mid_playback_integration: reloads once then errors deterministically with real gateway',
      () async {
        final direct = _StressPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
        );
        final gateway = _StressTranscodeGateway(server: server);
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: direct,
          },
          transcodeGateway: gateway,
          retryDelay: Duration.zero,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        final sourceUri = '${server.uri}/fixture/hls-live/master.m3u8';
        await orchestrator.open(
          PlaybackSource(
            uri: sourceUri,
            title: 'Token Expiry Fixture',
            isLive: true,
          ),
        );
        direct.emitError(
          const PlaybackError(
            backend: PlaybackBackend.androidExoPlayer,
            message: 'Provider token expired during playback',
            code: 'expired_token',
            recoverable: true,
          ),
        );
        await pumpEventQueue();
        direct.emitError(
          const PlaybackError(
            backend: PlaybackBackend.androidExoPlayer,
            message: 'Provider token expired during playback',
            code: 'expired_token',
            recoverable: true,
          ),
        );
        await pumpEventQueue();

        expect(
          direct.commands.where((c) => c == 'load:$sourceUri'),
          hasLength(2),
        );
        expect(errors, hasLength(1));
        expect(errors.single.code, 'expired_token');
        expect(errors.single.recoverable, isTrue);
        expect(
          orchestrator.diagnostics,
          contains('active-retry:expired_token:androidExoPlayer:1'),
        );
        expect(gateway.startedServerRequests, isEmpty);

        await subscription.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'rapid_channel_switch_integration: 20 switches with real server leaves no active broadcasts and all sessions stopped',
      () async {
        final direct = _StressPlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: BackendUnavailableException('libmpv unavailable'),
        );
        final serverPlayer = _StressPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _StressTranscodeGateway(server: server);
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
              uri: '${server.uri}/fixture/hls-live/master.m3u8',
              title: 'Channel $index',
              isLive: true,
              metadata: <String, Object?>{
                'broadcast_network_id': 'network-$index',
              },
            ),
          );
        }
        await orchestrator.dispose();
        await pumpEventQueue();

        expect(orchestrator.activeBackend, isNull);
        expect(gateway.startedServerRequests, hasLength(20));
        expect(
          gateway.stoppedBroadcasts,
          hasLength(20),
          reason: 'all broadcast stop requests must be issued',
        );
        expect(
          gateway.stoppedServerTranscodes,
          hasLength(20),
          reason: 'all server transcode stop requests must be issued',
        );
        expect(
          serverPlayer.commands.where((c) => c == 'stop'),
          hasLength(20),
        );
        expect(
          serverPlayer.commands.where((c) => c == 'dispose'),
          hasLength(1),
        );
        expect(
          server.activeBroadcasts,
          isEmpty,
          reason:
              'fake server must report zero active broadcasts after cleanup',
        );
      },
    );

    test(
      'memory_leak_probe: create and dispose many orchestrators leaves no active adapters or sessions',
      () async {
        final gateway = _StressTranscodeGateway(server: server);
        var totalDisposeCount = 0;

        for (var index = 0; index < 50; index += 1) {
          final direct = _StressPlayerAdapter(
            capabilities: PlaybackCapabilities.androidExoPlayer,
            loadStatus: PlaybackStatus.buffering,
          );
          final orchestrator = PlaybackOrchestrator(
            platform: PlaybackPlatform.android,
            adapters: <PlaybackBackend, PlayerAdapter>{
              PlaybackBackend.androidExoPlayer: direct,
            },
            transcodeGateway: gateway,
            bufferingTimeout: const Duration(milliseconds: 5),
            retryDelay: Duration.zero,
          );
          await orchestrator.open(
            PlaybackSource(
              uri: '${server.uri}/fixture/hls-live/master.m3u8',
              title: 'Leak Probe $index',
              isLive: true,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await orchestrator.dispose();
          totalDisposeCount += direct.disposeCount;
        }

        expect(totalDisposeCount, 50);
        expect(gateway.startedServerRequests, isEmpty);
        expect(gateway.stoppedServerTranscodes, isEmpty);
        expect(gateway.stoppedBroadcasts, isEmpty);
        expect(server.activeBroadcasts, isEmpty);
      },
    );

    test(
      'stalled_transcode_integration: real server stalled response produces typed recoverable error and cleans up session',
      () async {
        final direct = _StressPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          loadFailure: const PlaybackException.unsupported(
            'Unsupported codec vp9/opus',
            backend: PlaybackBackend.androidExoPlayer,
          ),
        );
        final serverPlayer = _StressPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _StressTranscodeGateway(server: server);
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: direct,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator.open(
          PlaybackSource(
            uri: '${server.uri}/fixture/stalled-transcode/source.ts',
            title: 'Stalled Transcode Fixture',
            videoCodec: 'vp9',
            audioCodec: 'opus',
            metadata: <String, Object?>{
              'scenario': 'stalled',
            },
          ),
        );
        await pumpEventQueue();

        expect(errors, hasLength(1));
        expect(errors.single.code, 'transcode_stalled');
        expect(errors.single.recoverable, isTrue);
        expect(
          orchestrator.diagnostics,
          anyElement(contains('cleanup:server-transcode:stopped')),
        );
        expect(gateway.stoppedServerTranscodes, hasLength(1));
        expect(serverPlayer.loadedSources, isEmpty);

        await subscription.cancel();
        await orchestrator.dispose();
      },
    );
  });
}

class _StressPlayerAdapter implements PlayerAdapter {
  _StressPlayerAdapter({
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
  int disposeCount = 0;

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
    disposeCount += 1;
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

class _StressTranscodeGateway implements PlaybackTranscodeGateway {
  _StressTranscodeGateway({required this.server});

  final FakeM3uEditorServer server;
  final List<StreamRequest> startedServerRequests = <StreamRequest>[];
  final List<String> stoppedBroadcasts = <String>[];
  final List<String> stoppedServerTranscodes = <String>[];

  @override
  Future<TranscodeResponse> startServerTranscode(StreamRequest request) async {
    startedServerRequests.add(request);
    final response = await _jsonPost(
      server.uri.resolve('/transcode'),
      request.toJson(),
    );
    if (response.statusCode == HttpStatus.accepted ||
        response.statusCode == HttpStatus.ok) {
      return TranscodeResponse.fromJson(response.body);
    }
    throw TranscodeUnavailableException(
      '${response.body['error_code'] ?? 'transcode_failed'}',
    );
  }

  @override
  Future<BroadcastSession?> startBroadcast(StreamRequest request) async {
    final networkId = request.metadata['broadcast_network_id'];
    if (networkId is! String) return null;
    final response = await _jsonPost(
      server.uri.resolve('/broadcast/$networkId/start'),
      <String, Object?>{
        'stream_url': request.url,
        'transcode': request.mode == TranscodeMode.server,
        'segment_start_number': 0,
      },
    );
    return BroadcastSession.fromJson(response.body);
  }

  @override
  Future<void> stopBroadcast(String networkId) async {
    stoppedBroadcasts.add(networkId);
    await _jsonPost(
      server.uri.resolve('/broadcast/$networkId/stop'),
      const <String, Object?>{},
    );
  }

  @override
  Future<void> stopServerTranscode({
    required String streamId,
    required String? sessionId,
  }) async {
    stoppedServerTranscodes.add('$streamId:$sessionId');
    await _jsonPost(
      server.uri.resolve('/transcode/$streamId/cancel'),
      const <String, Object?>{},
    );
  }

  Future<_JsonResponse> _jsonPost(Uri uri, Map<String, Object?> body) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set('X-API-Token', 'fixture-api-token');
      request.write(jsonEncode(body));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      return _JsonResponse(
        response.statusCode,
        jsonDecode(text) as Map<String, Object?>,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
