import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/editor_stream_session_gateway.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  const server = 'https://editor.example';
  late String? serverBase;
  late List<({String type, int streamId, String clientId})> stops;

  EditorStreamSessionGateway gateway() => EditorStreamSessionGateway(
    serverBase: () => serverBase,
    stopPlayerStream:
        ({required type, required streamId, required clientId}) async {
          stops.add((type: type, streamId: streamId, clientId: clientId));
        },
  );

  setUp(() {
    serverBase = server;
    stops = <({String type, int streamId, String clientId})>[];
  });

  test('tags editor stream URLs and stops them by type and id', () async {
    final cases = <String, ({String type, int id})>{
      '$server/live/u/p/101.ts': (type: 'live', id: 101),
      '$server/movie/u/p/202.mkv': (type: 'vod', id: 202),
      '$server/series/u/p/303.mp4': (type: 'series', id: 303),
      '$server/timeshift/u/p/60/2026-10-01:20-00/404.ts': (
        type: 'catchup',
        id: 404,
      ),
    };

    for (final MapEntry(key: url, value: expected) in cases.entries) {
      final tagged = gateway().attachClientId(
        PlaybackSource(uri: url),
        'm3utv-abc',
      );
      await gateway().releaseStream(tagged, 'm3utv-abc');

      expect(tagged.uri, '$url?client_id=m3utv-abc');
      expect(stops.last, (
        type: expected.type,
        streamId: expected.id,
        clientId: 'm3utv-abc',
      ));
    }
  });

  test('appends to an existing query string', () {
    final tagged = gateway().attachClientId(
      const PlaybackSource(uri: '$server/live/u/p/101.ts?proxy=true&profile=3'),
      'm3utv-abc',
    );

    expect(
      tagged.uri,
      '$server/live/u/p/101.ts?proxy=true&profile=3&client_id=m3utv-abc',
    );
  });

  test('leaves URLs that are not editor streams untouched', () async {
    for (final url in <String>[
      'https://provider.example/live/u/p/101.ts',
      '$server/aiostreams-media/abc/movie.mkv',
      '$server/live/u/p/news.m3u8',
    ]) {
      final source = PlaybackSource(uri: url);
      final tagged = gateway().attachClientId(source, 'm3utv-abc');
      await gateway().releaseStream(source, 'm3utv-abc');

      expect(identical(tagged, source), isTrue, reason: url);
    }
    expect(stops, isEmpty);
  });

  test('tracks nothing when signed out', () async {
    serverBase = null;
    const source = PlaybackSource(uri: '$server/live/u/p/101.ts');

    final tagged = gateway().attachClientId(source, 'm3utv-abc');
    await gateway().releaseStream(source, 'm3utv-abc');

    expect(identical(tagged, source), isTrue);
    expect(stops, isEmpty);
  });
}
