import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/stream_resolution_service.dart';

void main() {
  group('StreamResolveRequest', () {
    test('serializes live capabilities to the accepted backend shape', () {
      const request = StreamResolveRequest(
        type: 'live',
        streamId: 42,
        clientCapabilities: ClientCapabilities(
          profile: 'android-tv-safe',
          platform: PlaybackPlatform.android,
          backend: 'androidExoPlayer',
          videoCodecs: ['h264'],
          audioCodecs: ['aac', 'mp3'],
          containers: ['hls', 'mpegts', 'mp4'],
          maxHeight: 1080,
          maxBitrateKbps: 20000,
          hdr: false,
        ),
      );

      expect(request.toJson(), {
        'type': 'live',
        'stream_id': 42,
        'client_capabilities': {
          'profile': 'android-tv-safe',
          'platform': 'android',
          'backend': 'androidExoPlayer',
          'video_codecs': ['h264'],
          'audio_codecs': ['aac', 'mp3'],
          'containers': ['hls', 'mpegts', 'mp4'],
          'max_height': 1080,
          'max_bitrate_kbps': 20000,
          'hdr': false,
        },
      });
    });

    test('uses catchup_format and never serializes extension', () {
      final request = StreamResolveRequest(
        type: 'catchup',
        streamId: 7,
        clientCapabilities: _testCapabilities,
        catchupStart: DateTime.parse('2026-07-10T08:30:00+02:00'),
        catchupDurationMinutes: 90,
        catchupFormat: 'm3u8',
      );

      expect(request.toJson(), containsPair('catchup_format', 'm3u8'));
      expect(
        request.toJson(),
        containsPair('catchup_start', '2026-07-10T06:30:00.000Z'),
      );
      expect(request.toJson(), containsPair('catchup_duration_minutes', 90));
      expect(request.toJson(), isNot(contains('extension')));
    });

    for (final format in ['ts', 'm3u8']) {
      test('accepts canonical catchup format $format', () {
        final request = StreamResolveRequest(
          type: 'catchup',
          streamId: 7,
          clientCapabilities: _testCapabilities,
          catchupFormat: format,
        );

        expect(request.catchupFormat, format);
        expect(request.toJson()['catchup_format'], format);
      });
    }

    for (final format in ['mp4', '../ts', 'M3U8', '']) {
      test('omits invalid catchup format "$format" at model boundary', () {
        final request = StreamResolveRequest(
          type: 'catchup',
          streamId: 7,
          clientCapabilities: _testCapabilities,
          catchupFormat: format,
        );

        expect(request.catchupFormat, isNull);
        expect(request.toJson(), isNot(contains('catchup_format')));
        expect(request.toJson(), isNot(contains('extension')));
      });
    }
  });

  group('ClientCapabilities', () {
    test('uses conservative Android and AVKit profiles', () {
      final android = PlaybackCapabilities.clientCapabilities(
        PlaybackCapabilities.androidExoPlayer,
      );
      final avKit = PlaybackCapabilities.clientCapabilities(
        PlaybackCapabilities.appleAvKit,
      );

      expect(android.videoCodecs, ['h264']);
      expect(android.audioCodecs, ['aac', 'mp3']);
      expect(android.containers, ['hls', 'mpegts', 'mp4']);
      expect(android.hdr, isFalse);
      expect(avKit.videoCodecs, ['h264']);
      expect(avKit.audioCodecs, ['aac']);
      expect(avKit.containers, ['hls', 'mp4']);
      expect(avKit.hdr, isFalse);
    });

    test('does not advertise artificial MPV dimensions or bitrate caps', () {
      for (final capabilities in [
        PlaybackCapabilities.androidMpv,
        PlaybackCapabilities.appleMpvKit,
        PlaybackCapabilities.desktopLibmpv,
      ]) {
        final client = PlaybackCapabilities.clientCapabilities(capabilities);

        expect(client.videoCodecs, containsAll(['h264', 'hevc', 'av1', 'vp9']));
        expect(client.containers, containsAll(['hls', 'mpegts', 'mp4', 'mkv']));
        expect(client.maxHeight, isNull);
        expect(client.maxBitrateKbps, isNull);
        expect(client.hdr, isNull);
      }
    });
  });

  group('StreamResolveResponse', () {
    test('decodes source and effective transcode output separately', () {
      final response = StreamResolveResponse.fromJson({
        'mode': 'transcode',
        'url': 'https://editor.example/hls/42/playlist.m3u8',
        'reason': 'must not become a diagnostic',
        'source': {
          'video_codec': 'hevc',
          'audio_codec': 'eac3',
          'container': 'mpegts',
          'width': 3840,
          'height': 2160,
          'bitrate_kbps': 18000,
          'hdr': true,
        },
        'output': {
          'video_codec': 'h264',
          'audio_codec': 'aac',
          'container': 'hls',
          'max_height': 1080,
          'max_bitrate_kbps': 6000,
          'hdr': false,
        },
      });

      expect(response.mode, StreamResolveMode.transcode);
      expect(response.source?.videoCodec, 'hevc');
      expect(response.source?.bitrateKbps, 18000);
      expect(response.output?.videoCodec, 'h264');
      expect(response.output?.audioCodec, 'aac');
      expect(response.output?.container, 'hls');
      expect(response.output?.maxHeight, 1080);
      expect(response.output?.maxBitrateKbps, 6000);
      expect(response.output?.hdr, isFalse);
    });

    test('accepts older transcode responses without output', () {
      final response = StreamResolveResponse.fromJson({
        'mode': 'transcode',
        'url': 'https://editor.example/hls/42/playlist.m3u8',
      });

      expect(response.mode, StreamResolveMode.transcode);
      expect(response.output, isNull);
    });
  });

  group('ProductionStreamResolutionService', () {
    test('builds a credential-free resolver URI', () {
      final service = ProductionStreamResolutionService(
        credentials: const UserCredentials(
          server: 'https://editor.example/prefix/player_api.php?old=query',
          username: 'user/name',
          password: 'pass word',
        ),
      );

      final uri = service.buildResolveUri();

      expect(
        uri.toString(),
        'https://editor.example/prefix/api/tv/stream/resolve',
      );
      expect(uri.toString(), isNot(contains('user/name')));
      expect(uri.toString(), isNot(contains('pass word')));
    });

    test(
      'sends credentials only as Basic auth on a non-following POST',
      () async {
        final client = _TestHttpClient(
          responseBody: jsonEncode({'mode': 'direct_play'}),
        );
        final service = ProductionStreamResolutionService(
          credentials: const UserCredentials(
            server: 'https://editor.example/player_api.php',
            username: 'user/name +%',
            password: 'pass/word :%',
          ),
          httpClient: client,
        );

        await service.resolve(_testRequest());

        expect(client.request.followRedirects, isFalse);
        expect(client.uri.toString(), isNot(contains('user/name')));
        expect(client.body, isNot(contains('pass/word')));
        expect(
          utf8.decode(base64Decode(client.authorization!.substring(6))),
          'user/name +%:pass/word :%',
        );
      },
    );

    test('does not request a redirect target or forward Basic auth', () async {
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var targetRequests = 0;
      String? targetAuthorization;
      target.listen((request) async {
        targetRequests += 1;
        targetAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        await request.drain<void>();
        await request.response.close();
      });
      final resolver = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      resolver.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.seeOther
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://${target.address.host}:${target.port}/target',
          );
        await request.response.close();
      });
      final service = ProductionStreamResolutionService(
        credentials: UserCredentials(
          server: 'http://${resolver.address.host}:${resolver.port}',
          username: 'redirect-user',
          password: 'redirect-password',
        ),
      );

      try {
        expect(await service.resolve(_testRequest()), isNull);
        expect(targetRequests, 0);
        expect(targetAuthorization, isNull);
      } finally {
        await resolver.close(force: true);
        await target.close(force: true);
      }
    });

    for (final status in [301, 302, 303, 307, 308, 500]) {
      test(
        'returns unavailable for HTTP $status without a second request',
        () async {
          final client = _TestHttpClient(statusCode: status);
          final service = ProductionStreamResolutionService(
            credentials: _credentials,
            httpClient: client,
          );

          expect(await service.resolve(_testRequest()), isNull);
          expect(client.postCount, 1);
          expect(client.request.followRedirects, isFalse);
        },
      );
    }

    for (final status in [401, 403, 422]) {
      test('maps HTTP $status to a reason-free rejection', () async {
        final service = ProductionStreamResolutionService(
          credentials: _credentials,
          httpClient: _TestHttpClient(
            statusCode: status,
            responseBody: 'https://provider.example/live/user/pass/42.ts',
          ),
        );

        final response = await service.resolve(_testRequest());

        expect(response?.mode, StreamResolveMode.unsupported);
        expect(response?.failure, StreamResolveFailure.rejected);
        expect(response?.reason, isNull);
        expect(response?.url, isNull);
      });
    }

    for (final status in [404, 405]) {
      test('keeps legacy server compatibility for HTTP $status', () async {
        final service = ProductionStreamResolutionService(
          credentials: _credentials,
          httpClient: _TestHttpClient(statusCode: status),
        );

        expect(await service.resolve(_testRequest()), isNull);
      });
    }

    test('times out response body handling as part of the operation', () async {
      final service = ProductionStreamResolutionService(
        credentials: _credentials,
        httpClient: _TestHttpClient(
          responseBody: jsonEncode({'mode': 'direct_play'}),
          bodyDelay: const Duration(seconds: 1),
        ),
        timeout: const Duration(milliseconds: 10),
      );

      expect(await service.resolve(_testRequest()), isNull);
    });

    test('times out while establishing the resolver request', () async {
      final service = ProductionStreamResolutionService(
        credentials: _credentials,
        httpClient: _TestHttpClient(
          connectionDelay: const Duration(seconds: 1),
        ),
        timeout: const Duration(milliseconds: 10),
      );

      expect(await service.resolve(_testRequest()), isNull);
    });
  });
}

const _testCapabilities = ClientCapabilities(
  profile: 'test',
  platform: PlaybackPlatform.android,
  videoCodecs: ['h264'],
  audioCodecs: ['aac'],
  containers: ['hls'],
);

const _credentials = UserCredentials(
  server: 'https://editor.example',
  username: 'user',
  password: 'pass',
);

StreamResolveRequest _testRequest() => const StreamResolveRequest(
  type: 'vod',
  streamId: 1,
  clientCapabilities: _testCapabilities,
);

class _TestHttpClient implements HttpClient {
  _TestHttpClient({
    this.statusCode = 200,
    this.responseBody = '{}',
    this.bodyDelay = Duration.zero,
    this.connectionDelay = Duration.zero,
  });

  final int statusCode;
  final String responseBody;
  final Duration bodyDelay;
  final Duration connectionDelay;
  late final _TestRequest request;
  Uri uri = Uri();
  String body = '';
  String? authorization;
  int postCount = 0;

  @override
  Future<HttpClientRequest> postUrl(Uri uri) async {
    postCount += 1;
    if (connectionDelay > Duration.zero) {
      await Future<void>.delayed(connectionDelay);
    }
    this.uri = uri;
    return request = _TestRequest(
      statusCode: statusCode,
      responseBody: responseBody,
      bodyDelay: bodyDelay,
      onBody: (value) => body = value,
      onHeader: (name, value) {
        if (name.toLowerCase() == HttpHeaders.authorizationHeader) {
          authorization = value.toString();
        }
      },
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestRequest implements HttpClientRequest {
  _TestRequest({
    required this.statusCode,
    required this.responseBody,
    required this.bodyDelay,
    required this.onBody,
    required this.onHeader,
  });

  final int statusCode;
  final String responseBody;
  final Duration bodyDelay;
  final void Function(String) onBody;
  final void Function(String, Object) onHeader;
  final List<int> _bytes = [];

  @override
  int contentLength = 0;

  @override
  bool followRedirects = true;

  @override
  late final HttpHeaders headers = _TestHeaders(onHeader);

  @override
  void add(List<int> data) => _bytes.addAll(data);

  @override
  Future<HttpClientResponse> close() async {
    onBody(utf8.decode(_bytes));
    return _TestResponse(statusCode, responseBody, bodyDelay);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestResponse extends Stream<List<int>> implements HttpClientResponse {
  _TestResponse(this.statusCode, this.body, this.delay);

  @override
  final int statusCode;
  final String body;
  final Duration delay;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromFuture(
      Future<List<int>>.delayed(delay, () => utf8.encode(body)),
    ).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHeaders implements HttpHeaders {
  _TestHeaders(this.onSet);

  final void Function(String, Object) onSet;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    onSet(name, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
