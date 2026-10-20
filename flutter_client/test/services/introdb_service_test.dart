import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/introdb_service.dart';

void main() {
  group('IntroDbSegments.fromJson (v4 bodies)', () {
    test('reads the first intro and credits segments of a MediaResponse', () {
      final segments = IntroDbSegments.fromJson({
        'tvdb_id': 81189,
        'type': 'tv',
        'season': 1,
        'episode': 1,
        'intro': [
          {'start_ms': 228664, 'end_ms': 246143},
          {'start_ms': 300000, 'end_ms': 310000},
        ],
        'recap': [
          {'start_ms': 0, 'end_ms': 20000},
        ],
        'credits': [
          {'start_ms': 3431000, 'end_ms': null},
        ],
      });

      expect(segments.isEmpty, isFalse);
      expect(segments.intro?.startMs, 228664);
      expect(segments.intro?.endMs, 246143);
      expect(segments.credits?.startMs, 3431000);
      expect(segments.credits?.endMs, isNull);
    });

    test('keeps a null intro start (start of media)', () {
      final segments = IntroDbSegments.fromJson({
        'tvdb_id': 169,
        'type': 'movie',
        'intro': [
          {'start_ms': null, 'end_ms': 23000},
        ],
      });

      expect(segments.intro?.startMs, isNull);
      expect(segments.intro?.endMs, 23000);
      expect(segments.credits, isNull);
    });

    test('treats the episode-list fallback as no data', () {
      final segments = IntroDbSegments.fromJson({
        'tvdb_id': 71663,
        'type': 'tv',
        'episodes': [
          {'season': 1, 'episode': 1, 'total_submission_count': 4},
        ],
      });

      expect(segments.isEmpty, isTrue);
    });
  });
  group('IntroDbService User-Agent', () {
    test('identifies the app by name and version', () {
      expect(
        IntroDbService.userAgentFor('1.2.3'),
        'm3u-tv/1.2.3',
      );
    });

    test('drops the version when it cannot be resolved', () {
      expect(
        IntroDbService.userAgentFor(null),
        'm3u-tv',
      );
      expect(
        IntroDbService.userAgentFor(''),
        'm3u-tv',
      );
    });

    test('sends the User-Agent on /media requests', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <HttpRequest>[];
      server.listen((request) {
        requests.add(request);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'tvdb_id': 81189,
              'type': 'tv',
              'season': 1,
              'episode': 1,
              'intro': [
                {'start_ms': 1000, 'end_ms': 2000},
              ],
            }),
          );
        unawaited(request.response.close());
      });

      final service = IntroDbService(
        appVersionResolver: () async => '9.9.9',
        baseUrl: 'http://${server.address.host}:${server.port}/v4',
      );
      final segments = await service.getSegments(
        tmdbId: 1396,
        isSeries: true,
        season: 1,
        episode: 1,
      );

      expect(segments?.intro?.endMs, 2000);
      expect(requests, hasLength(1));
      expect(requests.single.uri.path, '/v4/media');
      expect(
        requests.single.headers.value(HttpHeaders.userAgentHeader),
        'm3u-tv/9.9.9',
      );
    });
  });
}
