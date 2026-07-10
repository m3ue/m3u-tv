import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/stream_resolution_service.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

void main() {
  group('capability-aware playback resolution', () {
    test('PlayerArgs carries resolver identity into PlaybackSource', () {
      const args = PlayerArgs(
        streamUrl: 'https://provider.example/stream.ts',
        title: 'News',
        type: 'live',
        streamId: 42,
      );

      expect(args.toPlaybackSource().metadata['type'], 'live');
      expect(args.toPlaybackSource().metadata['stream_id'], 42);
    });

    test('loads the backend-selected direct play URL', () async {
      final adapter = _FakeAdapter();
      final resolver = _FakeResolver(
        response: const StreamResolveResponse(
          mode: StreamResolveMode.directPlay,
          url: 'https://cdn.example/signed/live.ts?signature=value',
          source: StreamSourceInfo(
            videoCodec: 'h264',
            audioCodec: 'aac',
            container: 'mpegts',
          ),
        ),
      );
      final orchestrator = _orchestrator(adapter, resolver);

      await orchestrator.open(_source(type: 'live', streamId: 42));

      expect(
        adapter.sources.single.uri,
        'https://cdn.example/signed/live.ts?signature=value',
      );
      expect(
        orchestrator.diagnostics,
        contains('resolve:direct_play:video=h264,audio=aac,container=mpegts'),
      );
      await orchestrator.dispose();
    });

    test(
      'uses effective output metadata for a selected transcode URL',
      () async {
        final adapter = _FakeAdapter(rejectedVideoCodec: 'hevc');
        final resolver = _FakeResolver(
          response: const StreamResolveResponse(
            mode: StreamResolveMode.transcode,
            url: 'https://editor.example/hls/42/playlist.m3u8?token=signed',
            reason: 'hevc unsupported at https://provider.example/private',
            source: StreamSourceInfo(
              videoCodec: 'hevc',
              audioCodec: 'eac3',
              container: 'mpegts',
            ),
            output: StreamOutputInfo(
              videoCodec: 'h264',
              audioCodec: 'aac',
              container: 'hls',
            ),
          ),
        );
        final orchestrator = _orchestrator(adapter, resolver);

        await orchestrator.open(_source(type: 'live', streamId: 42));

        final selected = adapter.sources.single;
        expect(selected.videoCodec, 'h264');
        expect(selected.audioCodec, 'aac');
        expect(selected.metadata['resolve_video_codec'], 'hevc');
        expect(selected.metadata['resolve_output_container'], 'hls');
        expect(selected.metadata, isNot(contains('resolve_reason')));
        expect(
          orchestrator.diagnostics.join(' '),
          isNot(contains('provider.example')),
        );
        await orchestrator.dispose();
      },
    );

    test(
      'accepts an older transcode response without output metadata',
      () async {
        final adapter = _FakeAdapter(rejectedVideoCodec: 'hevc');
        final orchestrator = _orchestrator(
          adapter,
          _FakeResolver(
            response: const StreamResolveResponse(
              mode: StreamResolveMode.transcode,
              url: 'https://editor.example/hls/legacy/playlist.m3u8',
              source: StreamSourceInfo(videoCodec: 'hevc'),
            ),
          ),
        );

        await orchestrator.open(
          _source(type: 'live', streamId: 42, videoCodec: 'hevc'),
        );

        expect(adapter.sources.single.videoCodec, isNull);
        expect(orchestrator.activeBackend, PlaybackBackend.androidExoPlayer);
        await orchestrator.dispose();
      },
    );

    for (final entry in [
      (
        response: const StreamResolveResponse(
          mode: StreamResolveMode.unsupported,
          reason: 'private https://provider.example/live/user/pass/42.ts',
        ),
        code: 'stream_unsupported',
      ),
      (
        response: const StreamResolveResponse(
          mode: StreamResolveMode.unsupported,
          reason: 'account user/password rejected',
          failure: StreamResolveFailure.rejected,
        ),
        code: 'stream_resolution_rejected',
      ),
    ]) {
      test(
        '${entry.code} is stable and does not expose server reason',
        () async {
          final adapter = _FakeAdapter();
          final orchestrator = _orchestrator(
            adapter,
            _FakeResolver(response: entry.response),
          );
          final errors = <PlaybackError>[];
          final subscription = orchestrator.onError.listen(errors.add);

          await orchestrator.open(_source(type: 'live', streamId: 42));
          await pumpEventQueue();

          expect(adapter.sources, isEmpty);
          expect(errors.single.code, entry.code);
          expect(errors.single.message, isEmpty);
          expect(
            orchestrator.diagnostics.join(' '),
            isNot(contains('private')),
          );
          expect(
            orchestrator.diagnostics.join(' '),
            isNot(contains('user/pass')),
          );
          await subscription.cancel();
          await orchestrator.dispose();
        },
      );
    }

    test('strips Authorization from resolved playback headers', () async {
      final adapter = _FakeAdapter();
      final orchestrator = _orchestrator(
        adapter,
        _FakeResolver(
          response: const StreamResolveResponse(
            mode: StreamResolveMode.directPlay,
            url: 'https://cdn.example/live.ts',
          ),
        ),
      );

      await orchestrator.open(
        _source(
          type: 'live',
          streamId: 42,
          headers: const {
            'AuThOrIzAtIoN': 'Basic secret',
            'Referer': 'https://safe.example',
          },
        ),
      );

      expect(
        adapter.sources.single.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('authorization')),
      );
      expect(adapter.sources.single.headers['Referer'], 'https://safe.example');
      await orchestrator.dispose();
    });

    for (final uri in [
      '../relative.ts',
      'file:///tmp/stream.ts',
      'data:video/mp2t;base64,AAAA',
      'ftp://provider.example/stream.ts',
      'https:///hostless.ts',
      'https://user:pass@provider.example/stream.ts',
    ]) {
      test(
        'rejects unsafe resolved URL $uri and uses safe legacy URL',
        () async {
          final adapter = _FakeAdapter();
          final orchestrator = _orchestrator(
            adapter,
            _FakeResolver(
              response: StreamResolveResponse(
                mode: StreamResolveMode.directPlay,
                url: uri,
              ),
            ),
          );

          await orchestrator.open(_source(type: 'live', streamId: 42));

          expect(
            adapter.sources.single.uri,
            'https://provider.example/stream.ts',
          );
          expect(
            orchestrator.diagnostics,
            contains('resolve:fallback:direct_play:unsafe-resolved-url'),
          );
          expect(orchestrator.diagnostics.join(' '), isNot(contains(uri)));
          await orchestrator.dispose();
        },
      );
    }

    for (final uri in [
      'https://provider.example/stream.ts?anything=value',
      'https://provider.example/live/user/password/42.ts',
      'https://provider.example/movie/user/password/42.mp4',
      'https://provider.example/series/user/password/42.mkv',
      'https://provider.example/timeshift/user/password/60/start/42.ts',
      'https://provider.example/live%2Fuser%2Fpassword%2F42.ts',
      'https://user:password@provider.example/stream.ts',
    ]) {
      test('resolver failure rejects credential-bearing legacy URL', () async {
        final adapter = _FakeAdapter();
        final orchestrator = _orchestrator(adapter, _FakeResolver());
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator.open(
          _source(type: 'live', streamId: 42, uri: uri),
        );
        await pumpEventQueue();

        expect(adapter.sources, isEmpty);
        expect(errors.single.code, 'stream_resolution_unavailable');
        expect(orchestrator.diagnostics.join(' '), isNot(contains(uri)));
        await subscription.cancel();
        await orchestrator.dispose();
      });
    }

    test(
      'resolver failure keeps a credential-free legacy URL working',
      () async {
        final adapter = _FakeAdapter();
        final orchestrator = _orchestrator(adapter, _FakeResolver());

        await orchestrator.open(_source(type: 'live', streamId: 42));

        expect(
          adapter.sources.single.uri,
          'https://provider.example/stream.ts',
        );
        await orchestrator.dispose();
      },
    );

    test('catchup sends canonical timing and catchup_format', () async {
      final adapter = _FakeAdapter();
      final resolver = _FakeResolver(
        response: const StreamResolveResponse(
          mode: StreamResolveMode.directPlay,
          url: 'https://cdn.example/catchup/42.m3u8',
        ),
      );
      final orchestrator = _orchestrator(adapter, resolver);

      await orchestrator.open(
        _source(
          type: 'catchup',
          streamId: 42,
          metadata: const {
            'program_start': '2026-07-10T08:00:00Z',
            'program_end': '2026-07-10T09:30:00Z',
            'catchup_format': 'm3u8',
          },
        ),
      );

      expect(resolver.request?.catchupStart, DateTime.utc(2026, 7, 10, 8));
      expect(resolver.request?.catchupDurationMinutes, 90);
      expect(resolver.request?.catchupFormat, 'm3u8');
      expect(resolver.request?.toJson(), isNot(contains('extension')));
      await orchestrator.dispose();
    });

    test('invalid catchup format is omitted rather than rewritten', () async {
      final adapter = _FakeAdapter();
      final resolver = _FakeResolver(
        response: const StreamResolveResponse(
          mode: StreamResolveMode.directPlay,
          url: 'https://cdn.example/catchup/42.ts',
        ),
      );
      final orchestrator = _orchestrator(adapter, resolver);

      await orchestrator.open(
        _source(
          type: 'catchup',
          streamId: 42,
          metadata: const {
            'program_start': '2026-07-10T08:00:00Z',
            'program_end': '2026-07-10T09:00:00Z',
            'catchup_format': 'mp4',
          },
        ),
      );

      expect(resolver.request?.catchupFormat, isNull);
      expect(resolver.request?.toJson(), isNot(contains('catchup_format')));
      await orchestrator.dispose();
    });

    for (final metadata in [
      <String, Object?>{},
      <String, Object?>{
        'program_start': 'invalid',
        'program_end': '2026-07-10T09:00:00Z',
      },
      <String, Object?>{
        'program_start': '2026-07-10T09:00:00Z',
        'program_end': '2026-07-10T08:00:00Z',
      },
    ]) {
      test('invalid catchup timing fails closed before resolver', () async {
        final adapter = _FakeAdapter();
        final resolver = _FakeResolver();
        final orchestrator = _orchestrator(adapter, resolver);
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator.open(
          _source(
            type: 'catchup',
            streamId: 42,
            uri: 'https://provider.example/timeshift/user/pass/60/start/42.ts',
            metadata: metadata,
          ),
        );
        await pumpEventQueue();

        expect(resolver.calls, 0);
        expect(adapter.sources, isEmpty);
        expect(errors.single.code, 'stream_resolution_unavailable');
        await subscription.cancel();
        await orchestrator.dispose();
      });
    }

    test('stop invalidates a resolver response already in flight', () async {
      final gate = Completer<StreamResolveResponse?>();
      final adapter = _FakeAdapter();
      final orchestrator = _orchestrator(
        adapter,
        _FakeResolver(delayed: gate.future),
      );

      final opening = orchestrator.open(_source(type: 'live', streamId: 1));
      await pumpEventQueue();
      await orchestrator.stop();
      gate.complete(
        const StreamResolveResponse(
          mode: StreamResolveMode.directPlay,
          url: 'https://stale.example/stream.ts',
        ),
      );
      await opening;

      expect(adapter.sources, isEmpty);
      expect(orchestrator.activeBackend, isNull);
      await orchestrator.dispose();
    });

    test(
      'a second open synchronously invalidates the first preflight',
      () async {
        final first = Completer<StreamResolveResponse?>();
        final second = Completer<StreamResolveResponse?>();
        final adapter = _FakeAdapter();
        final resolver = _QueuedResolver([first.future, second.future]);
        final orchestrator = _orchestrator(adapter, resolver);

        final openingA = orchestrator.open(_source(type: 'live', streamId: 1));
        await pumpEventQueue();
        final openingB = orchestrator.open(_source(type: 'live', streamId: 2));
        first.complete(
          const StreamResolveResponse(
            mode: StreamResolveMode.directPlay,
            url: 'https://stale.example/a.ts',
          ),
        );
        await pumpEventQueue();
        second.complete(
          const StreamResolveResponse(
            mode: StreamResolveMode.directPlay,
            url: 'https://cdn.example/b.ts',
          ),
        );
        await Future.wait([openingA, openingB]);

        expect(adapter.sources.single.uri, 'https://cdn.example/b.ts');
        await orchestrator.dispose();
      },
    );
  });
}

PlaybackOrchestrator _orchestrator(
  _FakeAdapter adapter,
  StreamResolutionService resolver,
) {
  return PlaybackOrchestrator(
    platform: PlaybackPlatform.android,
    adapters: {PlaybackBackend.androidExoPlayer: adapter},
    transcodeGateway: _FakeTranscodeGateway(),
    resolutionService: resolver,
  );
}

PlaybackSource _source({
  required String type,
  int? streamId,
  String uri = 'https://provider.example/stream.ts',
  String? videoCodec,
  Map<String, String> headers = const {},
  Map<String, Object?> metadata = const {},
}) {
  return PlaybackSource(
    uri: uri,
    isLive: type == 'live' || type == 'catchup',
    videoCodec: videoCodec,
    headers: headers,
    metadata: {
      ...metadata,
      'type': type,
      'stream_id': ?streamId,
    },
  );
}

class _FakeResolver implements StreamResolutionService {
  _FakeResolver({this.response, this.delayed});

  final StreamResolveResponse? response;
  final Future<StreamResolveResponse?>? delayed;
  StreamResolveRequest? request;
  int calls = 0;

  @override
  Future<StreamResolveResponse?> resolve(StreamResolveRequest request) async {
    calls += 1;
    this.request = request;
    return delayed ?? response;
  }
}

class _QueuedResolver implements StreamResolutionService {
  _QueuedResolver(this.responses);

  final List<Future<StreamResolveResponse?>> responses;
  int calls = 0;

  @override
  Future<StreamResolveResponse?> resolve(StreamResolveRequest request) {
    return responses[calls++];
  }
}

class _FakeAdapter implements PlayerAdapter {
  _FakeAdapter({this.rejectedVideoCodec});

  final String? rejectedVideoCodec;
  final List<PlaybackSource> sources = [];
  final StreamController<PlaybackState> _states = StreamController.broadcast();
  final StreamController<PlaybackError> _errors = StreamController.broadcast();

  @override
  PlaybackCapabilities get capabilities =>
      PlaybackCapabilities.androidExoPlayer;

  @override
  Stream<PlaybackState> get onState => _states.stream;

  @override
  Stream<PlaybackError> get onError => _errors.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    sources.add(source);
    if (source.videoCodec == rejectedVideoCodec) {
      throw const PlaybackException.unsupported(
        'codec unsupported',
        backend: PlaybackBackend.androidExoPlayer,
      );
    }
    _states.add(
      PlaybackState(
        backend: PlaybackBackend.androidExoPlayer,
        status: PlaybackStatus.ready,
        source: source,
      ),
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _errors.close();
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setAudioTrack(String? trackId) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> setSubtitleTrack(String? trackId) async {}
}

class _FakeTranscodeGateway implements PlaybackTranscodeGateway {
  @override
  Future<BroadcastSession?> startBroadcast(StreamRequest request) async => null;

  @override
  Future<TranscodeResponse> startServerTranscode(StreamRequest request) {
    throw const TranscodeUnavailableException('unavailable');
  }

  @override
  Future<void> stopBroadcast(String networkId) async {}

  @override
  Future<void> stopServerTranscode({
    required String streamId,
    required String? sessionId,
  }) async {}
}
