import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/json_isolate.dart';
import 'package:m3u_tv/services/xtream_http_transport_common.dart';
import 'package:m3u_tv/services/xtream_service.dart';

Uint8List _utf8Json(Object? value) => utf8.encode(jsonEncode(value));

void main() {
  group('decodeJsonBytes', () {
    test('decodes UTF-8 JSON in one pass', () {
      expect(decodeJsonBytes(_utf8Json({'name': 'Café 24/7'})), {
        'name': 'Café 24/7',
      });
    });

    test('replaces malformed UTF-8 instead of failing the body', () {
      // "Caf" + a lone Latin-1 0xE9 byte, as a misencoded provider sends.
      final bytes = Uint8List.fromList([
        ...utf8.encode('{"name":"Caf'),
        0xE9,
        ...utf8.encode('"}'),
      ]);
      expect(decodeJsonBytes(bytes), {'name': 'Caf\uFFFD'});
    });

    test('offloads large bodies and returns the same structure', () async {
      final big = [
        for (var i = 0; i < 5000; i++) {'stream_id': i, 'name': 'Channel $i'},
      ];
      expect(await decodeJsonBytesOffMainIsolate(_utf8Json(big)), big);
    });
  });

  group('BackgroundWorker', () {
    late BackgroundWorker worker;

    setUp(() => worker = BackgroundWorker(debugName: 'test-worker'));
    tearDown(() => worker.shutdown());

    test('runs jobs off the calling isolate and returns results', () async {
      final callerName = Isolate.current.debugName;
      final ranOn = await worker.run(() => Isolate.current.debugName);
      expect(ranOn, isNot(callerName));
      expect(await worker.run(() => 6 * 7), 42);
    });

    test('reuses one isolate across a burst of jobs', () async {
      final names = await Future.wait([
        for (var i = 0; i < 5; i++) worker.run(() => Isolate.current.hashCode),
      ]);
      expect(names.toSet(), hasLength(1));
    });

    test('surfaces a failing job as a RemoteError', () async {
      await expectLater(
        worker.run<int>(() => throw StateError('boom')),
        throwsA(isA<RemoteError>()),
      );
      // The worker survives a failed job.
      expect(await worker.run(() => 1), 1);
    });

    test(
      'a worker that dies fails its job and the next one respawns',
      () async {
        await expectLater(
          worker.run<int>(Isolate.exit),
          throwsA(isA<RemoteError>()),
        );
        expect(await worker.run(() => 2), 2);
      },
    );

    test('starts a fresh isolate after shutdown', () async {
      expect(await worker.run(() => 'first'), 'first');
      worker.shutdown();
      expect(await worker.run(() => 'second'), 'second');
    });
  });

  group('handleXtreamResponse', () {
    const request = XtreamRequest(
      credentials: UserCredentials(
        server: 'http://example.com',
        username: 'u',
        password: 'p',
      ),
      headers: {},
      action: 'get_live_streams',
      wantsRawText: true,
    );
    final uri = Uri.parse('http://example.com/player_api.php');

    test('hands raw bytes through for wantsRawText', () async {
      final response = await handleXtreamResponse(
        request: request,
        uri: uri,
        statusCode: 200,
        reasonPhrase: 'OK',
        bytes: _utf8Json([
          {'stream_id': 1},
        ]),
      );
      expect(response, isA<XtreamRawResponse>());
      expect((response! as XtreamRawResponse).decode(), [
        {'stream_id': 1},
      ]);
    });

    test('reports a plain-text error body as the server message', () async {
      await expectLater(
        handleXtreamResponse(
          request: request,
          uri: uri,
          statusCode: 500,
          reasonPhrase: 'Server Error',
          bytes: utf8.encode('upstream exploded'),
        ),
        throwsA(
          isA<XtreamHttpException>().having(
            (e) => e.serverMessage,
            'serverMessage',
            'upstream exploded',
          ),
        ),
      );
    });
  });
}
