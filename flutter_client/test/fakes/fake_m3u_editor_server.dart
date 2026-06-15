import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeM3uEditorServer {
  FakeM3uEditorServer({this.apiToken});

  final String? apiToken;

  final Map<String, Map<String, Object?>> _streams =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> _broadcasts =
      <String, Map<String, Object?>>{};

  Map<String, Map<String, Object?>> get activeBroadcasts =>
      Map<String, Map<String, Object?>>.unmodifiable(
        Map<String, Map<String, Object?>>.fromEntries(
          _broadcasts.entries.where(
            (entry) => entry.value['status'] != 'stopped',
          ),
        ),
      );

  HttpServer? _server;
  int _sequence = 0;

  Uri get uri {
    final server = _server;
    if (server == null) {
      throw StateError('FakeM3uEditorServer has not been started');
    }

    return Uri.parse('http://${server.address.host}:${server.port}');
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server!.listen(_handleRequest).asFuture<void>());
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!_isAuthorized(request)) {
      _sendJson(request, HttpStatus.unauthorized, const <String, Object?>{
        'error_code': 'auth_failed',
        'message': 'Missing or invalid X-API-Token',
      });
      return;
    }

    try {
      final segments = request.uri.pathSegments;
      if (request.method == 'GET' &&
          segments.length >= 2 &&
          segments.first == 'fixture') {
        await _serveFixture(request, segments[1]);
        return;
      }
      if (request.method == 'GET' &&
          _matches(segments, const <String>['streams'])) {
        _listStreams(request);
        return;
      }

      if (request.method == 'POST' &&
          _matches(segments, const <String>['streams'])) {
        await _createDirectStream(request);
        return;
      }

      if (request.method == 'POST' &&
          _matches(segments, const <String>['transcode'])) {
        await _createTranscode(request);
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 3 &&
          segments.first == 'transcode' &&
          segments.last == 'cancel') {
        _cancelTranscode(request, segments[1]);
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 3 &&
          segments.first == 'broadcast' &&
          segments.last == 'start') {
        await _startBroadcast(request, segments[1]);
        return;
      }

      if (request.method == 'GET' &&
          segments.length == 3 &&
          segments.first == 'broadcast' &&
          segments.last == 'status') {
        _broadcastStatus(request, segments[1]);
        return;
      }

      if (request.method == 'POST' &&
          segments.length == 3 &&
          segments.first == 'broadcast' &&
          segments.last == 'stop') {
        _stopBroadcast(request, segments[1]);
        return;
      }

      if (request.method == 'DELETE' &&
          segments.length == 2 &&
          segments.first == 'broadcast') {
        _broadcasts.remove(segments[1]);
        _sendJson(request, HttpStatus.ok, <String, Object?>{
          'status': 'deleted',
        });
        return;
      }

      _sendJson(request, HttpStatus.notFound, const <String, Object?>{
        'error_code': 'not_found',
      });
    } on FormatException catch (error) {
      _sendJson(request, HttpStatus.badRequest, <String, Object?>{
        'error_code': 'bad_json',
        'message': error.message,
      });
    }
  }

  bool _isAuthorized(HttpRequest request) {
    if (request.method == 'GET' &&
        request.uri.pathSegments.isNotEmpty &&
        request.uri.pathSegments.first == 'fixture') {
      return true;
    }
    return apiToken == null || request.headers.value('X-API-Token') == apiToken;
  }

  Future<void> _serveFixture(HttpRequest request, String fixtureId) async {
    switch (fixtureId) {
      case 'expired-token':
        _sendJson(request, HttpStatus.forbidden, const <String, Object?>{
          'error_code': 'expired_token',
          'message': 'Fixture token has expired',
        });
        return;
      case 'dead-stream':
        _sendJson(request, HttpStatus.notFound, const <String, Object?>{
          'error_code': 'stream_not_found',
          'message': 'Fixture stream is intentionally unavailable',
        });
        return;
      case 'timeout':
        await Future<void>.delayed(const Duration(milliseconds: 350));
        _sendJson(request, HttpStatus.gatewayTimeout, const <String, Object?>{
          'error_code': 'stream_timeout',
          'message': 'Fixture stream timed out deterministically',
        });
        return;
      default:
        final response = request.response;
        response.statusCode = HttpStatus.ok;
        if (request.uri.path.endsWith('.m3u8')) {
          response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          response.write(
            '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nsegment0.ts\n',
          );
        } else {
          response.headers.contentType = ContentType.binary;
          response.add(<int>[0, 0, 0, 24, 102, 116, 121, 112]);
        }
        unawaited(response.close());
        return;
    }
  }

  Future<void> _createDirectStream(HttpRequest request) async {
    final body = await _readJson(request);
    final streamId = 'direct-${++_sequence}';
    final stream = <String, Object?>{
      'stream_id': streamId,
      'stream_url': '$uri/stream/$streamId',
      'mode': 'direct',
      'status': 'active',
      'metadata': body['metadata'] ?? <String, Object?>{},
    };
    _streams[streamId] = stream;
    _sendJson(request, HttpStatus.ok, stream);
  }

  Future<void> _createTranscode(HttpRequest request) async {
    final body = await _readJson(request);
    final mode = _stringValue(body, 'mode', fallback: 'local');
    final videoCodec = body['video_codec'] as String?;
    final audioCodec = body['audio_codec'] as String?;

    if (mode != 'server' && !_isSupportedCodec(videoCodec, audioCodec)) {
      _sendJson(request, HttpStatus.unprocessableEntity, <String, Object?>{
        'error_code': 'unsupported_codec',
        'message':
            'Supported fake codecs are h264/h265 video and aac/mp3/ac3 audio',
      });
      return;
    }

    final metadata = _mapValue(body['metadata']);
    final status = metadata['scenario'] == 'stalled' ? 'stalled' : 'starting';
    final streamId = '$mode-${++_sequence}';
    final response = <String, Object?>{
      'stream_id': streamId,
      'stream_url': mode == 'server'
          ? '$uri/hls/$streamId/playlist.m3u8'
          : '$uri/stream/$streamId',
      'mode': mode,
      'status': status,
      'session_id':
          body['session_id'] ??
          (mode == 'server' ? 'fake-plex-session-$streamId' : null),
      'metadata': metadata,
    };
    _streams[streamId] = response;
    _sendJson(
      request,
      status == 'stalled' ? HttpStatus.accepted : HttpStatus.ok,
      response,
    );
  }

  void _cancelTranscode(HttpRequest request, String streamId) {
    final stream = _streams[streamId];
    if (stream == null) {
      _sendJson(request, HttpStatus.notFound, const <String, Object?>{
        'error_code': 'stream_not_found',
      });
      return;
    }

    stream['status'] = 'cancelled';
    _sendJson(request, HttpStatus.ok, <String, Object?>{
      'stream_id': streamId,
      'status': 'cancelled',
    });
  }

  void _listStreams(HttpRequest request) {
    final streams = _streams.values.toList(growable: false);
    _sendJson(request, HttpStatus.ok, <String, Object?>{
      'success': true,
      'streams': streams,
      'total': streams.length,
    });
  }

  Future<void> _startBroadcast(HttpRequest request, String networkId) async {
    final body = await _readJson(request);
    final callbackUrl = body['callback_url'] as String?;
    if (callbackUrl != null && callbackUrl.contains('fail-callback')) {
      _sendJson(request, HttpStatus.badGateway, <String, Object?>{
        'network_id': networkId,
        'status': 'failed',
        'error_code': 'callback_failed',
        'message': 'Fake callback target rejected broadcast start notification',
      });
      return;
    }

    final session = <String, Object?>{
      'network_id': networkId,
      'status': 'running',
      'ffmpeg_pid': 12000 + (++_sequence),
      'playlist_url': '$uri/broadcast/$networkId/live.m3u8',
      'segment_start_number': body['segment_start_number'] ?? 0,
      'transcode': body['transcode'] ?? false,
      'transcode_session_id': _extractQueryValue(
        body['stream_url'] as String?,
        'session',
      ),
    };
    _broadcasts[networkId] = session;
    _sendJson(request, HttpStatus.ok, <String, Object?>{
      ...session,
      'status': 'running',
    });
  }

  void _broadcastStatus(HttpRequest request, String networkId) {
    final session = _broadcasts[networkId];
    if (session == null || session['status'] == 'stopped') {
      _sendJson(request, HttpStatus.notFound, <String, Object?>{
        'network_id': networkId,
        'status': 'stopped',
      });
      return;
    }

    _sendJson(request, HttpStatus.ok, session);
  }

  void _stopBroadcast(HttpRequest request, String networkId) {
    final session = _broadcasts[networkId];
    final finalSegment = ((session?['segment_start_number'] as int?) ?? 0) + 3;
    _broadcasts[networkId] = <String, Object?>{
      'network_id': networkId,
      'status': 'stopped',
      'final_segment_number': finalSegment,
    };
    _sendJson(request, HttpStatus.ok, <String, Object?>{
      'network_id': networkId,
      'status': 'stopped',
      'final_segment_number': finalSegment,
    });
  }

  Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    final text = await utf8.decodeStream(request);
    if (text.isEmpty) {
      return <String, Object?>{};
    }

    return jsonDecode(text) as Map<String, Object?>;
  }

  void _sendJson(
    HttpRequest request,
    int statusCode,
    Map<String, Object?> body,
  ) {
    final response = request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    unawaited(response.close());
  }

  bool _matches(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) {
      return false;
    }

    for (var index = 0; index < actual.length; index += 1) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }

    return true;
  }

  bool _isSupportedCodec(String? videoCodec, String? audioCodec) {
    final supportedVideo =
        videoCodec == null ||
        const <String>{'h264', 'h265'}.contains(videoCodec);
    final supportedAudio =
        audioCodec == null ||
        const <String>{'aac', 'mp3', 'ac3'}.contains(audioCodec);
    return supportedVideo && supportedAudio;
  }

  Map<String, Object?> _mapValue(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }

    return <String, Object?>{};
  }

  String _stringValue(
    Map<String, Object?> body,
    String key, {
    required String fallback,
  }) {
    final value = body[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  String? _extractQueryValue(String? url, String key) {
    if (url == null || url.isEmpty) {
      return null;
    }

    return Uri.tryParse(url)?.queryParameters[key];
  }
}
