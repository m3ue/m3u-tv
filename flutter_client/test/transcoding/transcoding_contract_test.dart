import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

import '../fakes/fake_m3u_editor_server.dart';

void main() {
  group('m3u-editor transcoding contract models', () {
    test('encodes the source-of-truth transcode modes', () {
      expect(
        TranscodeMode.values.map((mode) => mode.value),
        <String>['direct', 'server', 'local'],
      );
    });

    test('serializes stream requests without UI coupling', () {
      const request = StreamRequest(
        url: 'https://provider.example/live/news.ts',
        mode: TranscodeMode.local,
        metadata: {
          'playlist_uuid': 'playlist-1',
          'channel_id': 42,
        },
        userAgent: 'm3u-tv/flutter-contract-test',
        headers: {'Referer': 'https://provider.example'},
        profile: 'h264-aac-720p',
        videoCodec: 'h264',
        audioCodec: 'aac',
        clientCapabilities: ClientPlaybackCapabilities(
          profile: 'android-tv-safe',
          platform: 'android',
          backend: 'androidExoPlayer',
          videoCodecs: <String>['h264'],
          audioCodecs: <String>['aac', 'ac3'],
          containers: <String>['hls', 'mpegts'],
        ),
      );

      expect(request.toJson(), <String, Object?>{
        'url': 'https://provider.example/live/news.ts',
        'mode': 'local',
        'metadata': <String, Object?>{
          'playlist_uuid': 'playlist-1',
          'channel_id': 42,
        },
        'user_agent': 'm3u-tv/flutter-contract-test',
        'headers': <String, String>{'Referer': 'https://provider.example'},
        'profile': 'h264-aac-720p',
        'video_codec': 'h264',
        'audio_codec': 'aac',
        'client_capabilities': <String, Object?>{
          'profile': 'android-tv-safe',
          'platform': 'android',
          'backend': 'androidExoPlayer',
          'video_codecs': <String>['h264'],
          'audio_codecs': <String>['aac', 'ac3'],
          'containers': <String>['hls', 'mpegts'],
        },
      });
    });

    test('parses transcode and broadcast responses', () {
      final transcode = TranscodeResponse.fromJson(const <String, Object?>{
        'stream_id': 'transcode-1',
        'stream_url': 'http://proxy.example/hls/transcode-1/playlist.m3u8',
        'mode': 'server',
        'status': 'starting',
        'session_id': 'plex-session-1',
      });
      final broadcast = BroadcastSession.fromJson(const <String, Object?>{
        'network_id': 'network-1',
        'status': 'running',
        'ffmpeg_pid': 12345,
        'playlist_url': 'http://proxy.example/broadcast/network-1/live.m3u8',
        'transcode_session_id': 'plex-session-1',
      });

      expect(transcode.mode, TranscodeMode.server);
      expect(transcode.sessionId, 'plex-session-1');
      expect(broadcast.status, BroadcastStatus.running);
      expect(broadcast.ffmpegPid, 12345);
    });
  });

  group('FakeM3uEditorServer transcoding endpoints', () {
    late FakeM3uEditorServer server;

    setUp(() async {
      server = FakeM3uEditorServer(apiToken: 'secret-token');
      await server.start();
    });

    tearDown(() async {
      await server.close();
    });

    test('simulates direct stream creation and /streams listing', () async {
      final response = await _jsonPost(
        server.uri.resolve('/streams'),
        const StreamRequest(
          url: 'https://provider.example/live/news.ts',
          mode: TranscodeMode.direct,
          metadata: <String, Object?>{'playlist_uuid': 'playlist-1'},
        ).toJson(),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body['stream_id'], startsWith('direct-'));
      expect(response.body['stream_url'], contains('/stream/'));

      final streams = await _jsonGet(server.uri.resolve('/streams'));
      expect(streams.statusCode, HttpStatus.ok);
      expect(streams.body['total'], 1);
      expect(streams.body['streams'], isA<List<Object?>>());
    });

    test('simulates server and local transcode success', () async {
      final serverTranscode = await _jsonPost(
        server.uri.resolve('/transcode'),
        const StreamRequest(
          url: 'https://plex.example/library/parts/1/file.ts',
          mode: TranscodeMode.server,
          profile: 'plex-hls',
          sessionId: 'plex-session-1',
        ).toJson(),
      );
      final localTranscode = await _jsonPost(
        server.uri.resolve('/transcode'),
        const StreamRequest(
          url: 'https://provider.example/live/sports.ts',
          mode: TranscodeMode.local,
          profile: 'ffmpeg-h264-aac',
          videoCodec: 'h264',
          audioCodec: 'aac',
        ).toJson(),
      );

      expect(serverTranscode.statusCode, HttpStatus.ok);
      expect(serverTranscode.body['mode'], 'server');
      expect(serverTranscode.body['session_id'], 'plex-session-1');
      expect(serverTranscode.body['stream_url'], contains('/hls/'));
      expect(localTranscode.statusCode, HttpStatus.ok);
      expect(localTranscode.body['mode'], 'local');
      expect(localTranscode.body['stream_url'], contains('/stream/'));
    });

    test('simulates unsupported codec and auth failure', () async {
      final unsupportedCodec = await _jsonPost(
        server.uri.resolve('/transcode'),
        const StreamRequest(
          url: 'https://provider.example/live/hevc.ts',
          mode: TranscodeMode.local,
          videoCodec: 'vp9',
          audioCodec: 'aac',
        ).toJson(),
      );
      final authFailure = await _jsonGet(
        server.uri.resolve('/streams'),
        apiToken: 'wrong-token',
      );

      expect(unsupportedCodec.statusCode, HttpStatus.unprocessableEntity);
      expect(unsupportedCodec.body['error_code'], 'unsupported_codec');
      expect(authFailure.statusCode, HttpStatus.unauthorized);
      expect(authFailure.body['error_code'], 'auth_failed');
    });

    test(
      'simulates stalled transcode, callback failure, and cancellation',
      () async {
        final stalled = await _jsonPost(
          server.uri.resolve('/transcode'),
          const StreamRequest(
            url: 'https://provider.example/live/stalled.ts',
            mode: TranscodeMode.local,
            metadata: {'scenario': 'stalled'},
          ).toJson(),
        );
        final callbackFailure = await _jsonPost(
          server.uri.resolve('/broadcast/network-callback-fail/start'),
          _broadcastStartPayload(
            callbackUrl: 'http://client.invalid/fail-callback',
          ),
        );

        expect(stalled.statusCode, HttpStatus.accepted);
        expect(stalled.body['status'], 'stalled');
        expect(callbackFailure.statusCode, HttpStatus.badGateway);
        expect(callbackFailure.body['error_code'], 'callback_failed');

        final cancel = await _jsonPost(
          server.uri.resolve('/transcode/${stalled.body['stream_id']}/cancel'),
          const <String, Object?>{},
        );
        expect(cancel.statusCode, HttpStatus.ok);
        expect(cancel.body['status'], 'cancelled');
      },
    );

    test('simulates broadcast start, status, and stop', () async {
      final start = await _jsonPost(
        server.uri.resolve('/broadcast/network-1/start'),
        _broadcastStartPayload(),
      );
      final status = await _jsonGet(
        server.uri.resolve('/broadcast/network-1/status'),
      );
      final stop = await _jsonPost(
        server.uri.resolve('/broadcast/network-1/stop'),
        const <String, Object?>{},
      );
      final stoppedStatus = await _jsonGet(
        server.uri.resolve('/broadcast/network-1/status'),
      );

      expect(start.statusCode, HttpStatus.ok);
      expect(start.body['status'], 'running');
      expect(start.body['ffmpeg_pid'], isA<int>());
      expect(status.body['status'], 'running');
      expect(stop.body['status'], 'stopped');
      expect(stop.body['final_segment_number'], isA<int>());
      expect(stoppedStatus.statusCode, HttpStatus.notFound);
    });
  });
}

Map<String, Object?> _broadcastStartPayload({String? callbackUrl}) {
  return <String, Object?>{
    'stream_url': 'https://provider.example/live/news.ts',
    'seek_seconds': 300,
    'duration_seconds': 1800,
    'segment_start_number': 7,
    'add_discontinuity': true,
    'segment_duration': 6,
    'hls_list_size': 20,
    'transcode': false,
    'video_bitrate': '2500',
    'audio_bitrate': 192,
    'video_resolution': '1280x720',
    'video_codec': 'h264',
    'audio_codec': 'aac',
    'preset': 'veryfast',
    'hwaccel': null,
    'callback_url':
        callbackUrl ?? 'http://client.example/api/m3u-proxy/broadcast/callback',
    'output_dir': '/dev/shm',
  };
}

Future<_JsonResponse> _jsonGet(
  Uri uri, {
  String apiToken = 'secret-token',
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set('X-API-Token', apiToken);
    final response = await request.close();
    return _decode(response);
  } finally {
    client.close(force: true);
  }
}

Future<_JsonResponse> _jsonPost(
  Uri uri,
  Map<String, Object?> body, {
  String apiToken = 'secret-token',
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set('X-API-Token', apiToken);
    request.write(jsonEncode(body));
    final response = await request.close();
    return _decode(response);
  } finally {
    client.close(force: true);
  }
}

Future<_JsonResponse> _decode(HttpClientResponse response) async {
  final text = await response.transform(utf8.decoder).join();
  return _JsonResponse(
    response.statusCode,
    jsonDecode(text) as Map<String, Object?>,
  );
}

class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}
