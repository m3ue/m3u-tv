import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

import '../fakes/fake_m3u_editor_server.dart';
import '../fixtures/production_stream_catalog.dart';

void main() {
  group('production playback vertical slice', () {
    late FakeM3uEditorServer server;

    setUp(() async {
      server = FakeM3uEditorServer(apiToken: 'fixture-api-token');
      await server.start();
    });

    tearDown(() async {
      await server.close();
    });

    test(
      'happy_path: source fixture opens playable HLS through orchestrator and cleans up',
      () async {
        final sourceFixture = _ProductionSourceFixture(server.uri);
        final liveItem = sourceFixture.liveChannels.singleWhere(
          (channel) => channel.name == hlsLiveFixture.title,
        );
        final playerArgs = hlsLiveFixture.playerArgs(server.uri);

        expect(sourceFixture.credentials.server, server.uri.toString());
        expect(liveItem.streamUrl, playerArgs.streamUrl);
        expect(playerArgs.videoCodec, 'h264');
        expect(
          playerArgs.headers,
          containsPair('Referer', 'https://fixture.invalid/app'),
        );

        final directPlayer = _FixturePlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
        );
        final serverPlayer = _FixturePlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _HttpPlaybackTranscodeGateway(server: server);
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: directPlayer,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
        );

        await orchestrator.open(playerArgs.toPlaybackSource());
        await orchestrator.play();

        expect(orchestrator.activeBackend, PlaybackBackend.androidExoPlayer);
        expect(
          orchestrator.diagnostics,
          contains('active-backend:androidExoPlayer:ready'),
        );

        await orchestrator.stop();
        expect(orchestrator.activeBackend, isNull);
        await orchestrator.dispose();

        expect(
          directPlayer.loadedSources.single.uri,
          hlsLiveFixture.uriFor(server.uri).toString(),
        );
        expect(
          directPlayer.loadedSources.single.metadata['fixture_id'],
          'hls-live',
        );
        expect(directPlayer.commands, contains('play'));
        expect(directPlayer.commands, contains('stop'));
        expect(serverPlayer.loadedSources, isEmpty);
        expect(server.activeBroadcasts, isEmpty);
        expect(gateway.stoppedBroadcasts, isEmpty);
      },
    );

    test(
      'happy_path: VOD and track fixture metadata survive PlayerArgs to PlaybackSource',
      () async {
        final sourceFixture = _ProductionSourceFixture(server.uri);
        final vodItem = sourceFixture.vodItems.singleWhere(
          (item) => item.name == subtitlesAndAudioFixture.title,
        );
        final playerArgs = subtitlesAndAudioFixture.playerArgs(
          server.uri,
          startPosition: 91,
        );
        final source = playerArgs.toPlaybackSource();

        expect(vodItem.streamUrl, source.uri);
        expect(source.isLive, isFalse);
        expect(source.startPosition, const Duration(seconds: 91));
        expect(source.metadata['audio_tracks'], isA<List<Object?>>());
        expect(source.metadata['subtitle_tracks'], isA<List<Object?>>());
      },
    );

    test(
      'failure_paths: expired token, dead stream, unsupported codec, and stalled transcode are typed',
      () async {
        final expiredGateway = _HttpPlaybackTranscodeGateway(server: server);
        final deadGateway = _HttpPlaybackTranscodeGateway(server: server);
        final unsupportedGateway = _HttpPlaybackTranscodeGateway(
          server: server,
        );
        final stalledGateway = _HttpPlaybackTranscodeGateway(server: server);

        final expiredError = await _openAndCollectFirstError(
          expiredTokenFixture.playerArgs(server.uri),
          expiredGateway,
        );
        final deadError = await _openAndCollectFirstError(
          deadUrlFixture.playerArgs(server.uri),
          deadGateway,
        );
        final unsupportedResult = await _openAndCollectResult(
          unsupportedCodecFixture.playerArgs(server.uri),
          unsupportedGateway,
        );
        final stalledError = await _openAndCollectFirstError(
          stalledTranscodeFixture.playerArgs(server.uri),
          stalledGateway,
        );

        expect(expiredError.code, 'expired_token');
        expect(expiredError.recoverable, isFalse);
        expect(deadError.code, 'stream_not_found');
        expect(deadError.recoverable, isFalse);
        expect(
          unsupportedResult.orchestrator.activeBackend,
          PlaybackBackend.serverTranscode,
        );
        expect(
          unsupportedResult
              .gateway
              .startedServerRequests
              .single
              .metadata['fallback_reason'],
          'unsupported_codec',
        );
        expect(
          unsupportedResult
              .serverPlayer
              .loadedSources
              .single
              .metadata['transcode_stream_id'],
          startsWith('server-'),
        );
        expect(stalledError.code, 'transcode_stalled');
        expect(stalledError.recoverable, isTrue);
        expect(
          stalledGateway.stoppedServerTranscodes.any(
            (item) => item.contains('server-'),
          ),
          isTrue,
        );

        await unsupportedResult.dispose();
      },
    );
  });
}

class _ProductionSourceFixture {
  _ProductionSourceFixture(this.serverUri);

  final Uri serverUri;

  UserCredentials get credentials => UserCredentials(
    server: serverUri.toString(),
    username: 'fixture-user',
    password: 'fixture-password',
  );

  List<Category> get categories => productionFixtureCategories;

  List<Channel> get liveChannels => productionStreamCatalog
      .where((fixture) => fixture.type == 'live')
      .map((fixture) => fixture.channel(serverUri))
      .toList(growable: false);

  List<VodItem> get vodItems => productionStreamCatalog
      .where((fixture) => fixture.type == 'vod')
      .map((fixture) => fixture.vodItem(serverUri))
      .toList(growable: false);
}

Future<PlaybackError> _openAndCollectFirstError(
  PlayerArgs args,
  _HttpPlaybackTranscodeGateway gateway,
) async {
  final result = await _openAndCollectResult(args, gateway);
  addTearDown(result.dispose);
  expect(result.errors, isNotEmpty);
  return result.errors.first;
}

Future<_PlaybackResult> _openAndCollectResult(
  PlayerArgs args,
  _HttpPlaybackTranscodeGateway gateway,
) async {
  final direct = _FixturePlayerAdapter(
    capabilities: PlaybackCapabilities.androidExoPlayer,
    probeUrls: true,
    unsupportedVideoCodecs: const <String>{'vp9'},
    unsupportedAudioCodecs: const <String>{'opus'},
  );
  final serverPlayer = _FixturePlayerAdapter(
    capabilities: PlaybackCapabilities.serverTranscode,
  );
  final orchestrator = PlaybackOrchestrator(
    platform: PlaybackPlatform.android,
    adapters: <PlaybackBackend, PlayerAdapter>{
      PlaybackBackend.androidExoPlayer: direct,
      PlaybackBackend.serverTranscode: serverPlayer,
    },
    transcodeGateway: gateway,
  );
  final errors = <PlaybackError>[];
  // ignore: cancel_subscriptions
  final subscription = orchestrator.onError.listen(errors.add);

  await orchestrator.open(args.toPlaybackSource());
  await pumpEventQueue();

  return _PlaybackResult(
    orchestrator: orchestrator,
    directPlayer: direct,
    serverPlayer: serverPlayer,
    gateway: gateway,
    errors: errors,
    subscription: subscription,
  );
}

class _PlaybackResult {
  const _PlaybackResult({
    required this.orchestrator,
    required this.directPlayer,
    required this.serverPlayer,
    required this.gateway,
    required this.errors,
    required this.subscription,
  });

  final PlaybackOrchestrator orchestrator;
  final _FixturePlayerAdapter directPlayer;
  final _FixturePlayerAdapter serverPlayer;
  final _HttpPlaybackTranscodeGateway gateway;
  final List<PlaybackError> errors;
  final StreamSubscription<PlaybackError> subscription;

  Future<void> dispose() async {
    await subscription.cancel();
    await orchestrator.dispose();
  }
}

class _FixturePlayerAdapter implements PlayerAdapter {
  _FixturePlayerAdapter({
    required this.capabilities,
    this.probeUrls = false,
    this.unsupportedVideoCodecs = const <String>{},
    this.unsupportedAudioCodecs = const <String>{},
  });

  @override
  final PlaybackCapabilities capabilities;
  final bool probeUrls;
  final Set<String> unsupportedVideoCodecs;
  final Set<String> unsupportedAudioCodecs;
  final List<String> commands = <String>[];
  final List<PlaybackSource> loadedSources = <PlaybackSource>[];
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    commands.add('load:${source.uri}');
    if (unsupportedVideoCodecs.contains(source.videoCodec) ||
        unsupportedAudioCodecs.contains(source.audioCodec)) {
      throw PlaybackException.unsupported(
        'Unsupported fixture codec ${source.videoCodec}/${source.audioCodec}',
        backend: capabilities.backend,
      );
    }
    if (probeUrls) {
      await _probe(source);
    }
    loadedSources.add(source);
    _stateController.add(
      PlaybackState(
        backend: capabilities.backend,
        status: PlaybackStatus.ready,
        source: source,
      ),
    );
  }

  Future<void> _probe(PlaybackSource source) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 150);
    try {
      final request = await client.getUrl(Uri.parse(source.uri));
      final response = await request.close().timeout(
        const Duration(milliseconds: 300),
      );
      await response.drain<void>();
      if (response.statusCode == HttpStatus.forbidden) {
        throw PlaybackException(
          message: 'Fixture token expired',
          backend: capabilities.backend,
          code: 'expired_token',
        );
      }
      if (response.statusCode == HttpStatus.notFound) {
        throw PlaybackException(
          message: 'Fixture stream not found',
          backend: capabilities.backend,
          code: 'stream_not_found',
        );
      }
      if (response.statusCode >= 400) {
        throw PlaybackException(
          message: 'Fixture stream failed with HTTP ${response.statusCode}',
          backend: capabilities.backend,
          code: 'stream_http_${response.statusCode}',
        );
      }
    } on TimeoutException {
      throw PlaybackException(
        message: 'Fixture stream timed out',
        backend: capabilities.backend,
        code: 'stream_timeout',
        recoverable: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> play() async => commands.add('play');

  @override
  Future<void> pause() async => commands.add('pause');

  @override
  Future<void> seek(Duration position) async =>
      commands.add('seek:${position.inSeconds}');

  @override
  Future<void> stop() async => commands.add('stop');

  @override
  Future<void> dispose() async {
    commands.add('dispose');
    await _stateController.close();
    await _errorController.close();
  }

  @override
  Future<void> setAudioTrack(String? trackId) async =>
      commands.add('audio:$trackId');

  @override
  Future<void> setSubtitleTrack(String? trackId) async =>
      commands.add('subtitle:$trackId');

  @override
  Future<void> setPlaybackSpeed(double speed) async =>
      commands.add('speed:$speed');
}

class _HttpPlaybackTranscodeGateway implements PlaybackTranscodeGateway {
  _HttpPlaybackTranscodeGateway({required this.server});

  final FakeM3uEditorServer server;
  final List<StreamRequest> startedServerRequests = <StreamRequest>[];
  final List<String> stoppedServerTranscodes = <String>[];
  final List<String> stoppedBroadcasts = <String>[];

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
