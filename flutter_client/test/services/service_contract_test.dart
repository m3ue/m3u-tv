import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/m3u_parser.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('XtreamService contract', () {
    test('default transport authenticates against player_api.php over HTTP', () async {
      final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      final requests = <Uri>[];
      unawaited(server.listen((io.HttpRequest request) {
        requests.add(request.uri);
        request.response.headers.contentType = io.ContentType.json;
        final action = request.uri.queryParameters['action'];
        final body = switch (action) {
          null => xtreamAuth(auth: 1),
          'get_live_categories' => [category('10', 'Live News')],
          _ => <String, Object?>{'error': 'unexpected action $action'},
        };
        request.response.write(jsonEncode(body));
        unawaited(request.response.close());
      }).asFuture<void>());
      addTearDown(() => server.close(force: true));

      final service = XtreamService();
      final response = await service.authenticate(UserCredentials(
        server: 'http://${server.address.host}:${server.port}',
        username: 'demo',
        password: 'secret',
      ));

      expect(response.isAuthenticated, isTrue);
      expect(await service.getLiveCategories(), [const Category(id: '10', name: 'Live News')]);
      expect(requests.map((Uri uri) => uri.path).toSet(), {'/player_api.php'});
      expect(requests.first.queryParameters['username'], 'demo');
      expect(requests.first.queryParameters['password'], 'secret');
      expect(requests.last.queryParameters['action'], 'get_live_categories');
    });

    test('default transport reports unauthorized HTTP failures without credentials', () async {
      final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
      unawaited(server.listen((io.HttpRequest request) {
        request.response.statusCode = io.HttpStatus.unauthorized;
        request.response.reasonPhrase = 'Unauthorized';
        request.response.headers.contentType = io.ContentType.json;
        request.response.write(jsonEncode(<String, Object?>{'error': 'Unauthorized'}));
        unawaited(request.response.close());
      }).asFuture<void>());
      addTearDown(() => server.close(force: true));

      final service = XtreamService();

      await expectLater(
        service.authenticate(UserCredentials(
          server: 'http://${server.address.host}:${server.port}',
          username: 'demo-user',
          password: 'playlist-secret',
        )),
        throwsA(
          isA<XtreamHttpException>()
              .having((XtreamHttpException error) => error.statusCode, 'statusCode', 401)
              .having((XtreamHttpException error) => '$error', 'message', contains('player_api.php'))
              .having((XtreamHttpException error) => '$error', 'message', isNot(contains('demo-user')))
              .having((XtreamHttpException error) => '$error', 'message', isNot(contains('playlist-secret'))),
        ),
      );
    });

    test('auth success loads categories and typed content', () async {
      final transport = FakeXtreamTransport({
        'auth': xtreamAuth(auth: 1),
        'get_live_categories': [category('10', 'Live News')],
        'get_vod_categories': [category('20', 'Movies')],
        'get_series_categories': [category('30', 'Series')],
        'get_live_streams': [liveStream(101, 'BBC One', '10', 'bbc.one')],
        'get_vod_streams': [vodItem(201, 'Big Buck Bunny', '20')],
        'get_series': [seriesItem(301, 'Fixture Show', '30')],
      });
      final service = XtreamService(transport: transport.call);

      final response = await service.authenticate(
        const UserCredentials(
          server: 'https://xtream.example/',
          username: 'demo',
          password: 'secret',
        ),
      );

      expect(response.isAuthenticated, isTrue);
      expect(await service.getLiveCategories(), [const Category(id: '10', name: 'Live News')]);
      expect((await service.getVodCategories()).single.name, 'Movies');
      expect((await service.getSeriesCategories()).single.name, 'Series');
      expect((await service.getLiveStreams()).single.epgChannelId, 'bbc.one');
      expect((await service.getVodStreams()).single.containerExtension, 'mp4');
      expect((await service.getSeries()).single.id, 301);
      expect(transport.lastHeaders['X-M3UE-Client'], 'm3u-tv');
    });

    test('expired credentials return typed auth error without cache corruption', () async {
      final cache = CacheService(memory: <String, Object?>{});
      await cache.set('categories', {'sentinel': true});
      final service = XtreamService(
        cache: cache,
        transport: FakeXtreamTransport({'auth': xtreamAuth(auth: 0, status: 'Expired')}).call,
      );

      await expectLater(
        service.authenticate(
          const UserCredentials(server: 'https://xtream.example', username: 'expired', password: 'bad'),
        ),
        throwsA(isA<XtreamAuthException>().having((e) => e.code, 'code', AuthErrorCode.expired)),
      );

      expect((await cache.get<Map<String, Object?>>('categories'))?.data, {'sentinel': true});
      expect(service.isConfigured, isFalse);
    });

    test('series seasons and episodes are typed from Xtream response', () async {
      final service = XtreamService(
        transport: FakeXtreamTransport({
          'auth': xtreamAuth(auth: 1),
          'get_series_info': {
            'seasons': [
              {'season_number': 1, 'name': 'Season 1', 'episode_count': 1},
            ],
            'info': seriesItem(301, 'Fixture Show', '30'),
            'episodes': {
              '1': [episode(9001, 1, 'Pilot')],
            },
          },
        }).call,
      );
      await service.authenticate(const UserCredentials(server: 'https://xtream.example', username: 'demo', password: 'secret'));

      final info = await service.getSeriesInfo(301);

      expect(info.seasons.single.number, 1);
      expect(info.episodesBySeason[1]!.single.title, 'Pilot');
      expect(info.episodesBySeason[1]!.single.containerExtension, 'mp4');
    });
  });

  group('M3UParser contract', () {
    test('parses valid direct M3U with metadata, headers, and groups', () async {
      final text = await io.File('test/fixtures/direct_playlist.m3u').readAsString();

      final result = M3UParser().parse(text);

      expect(result.channels, hasLength(3));
      expect(result.channels.first, isA<Channel>());
      expect(result.channels.first.epgChannelId, 'bbc.one');
      expect(result.channels.first.name, 'BBC One HD');
      expect(result.channels.first.logoUrl, 'https://img.example/bbc.png');
      expect(result.channels.first.groupTitle, 'News');
      expect(result.channels.first.streamUrl, 'https://streams.example/live/bbc-one.m3u8');
      expect(result.channels.first.headers, containsPair('User-Agent', 'FixtureAgent/1.0'));
      expect(result.channels.first.headers, containsPair('Authorization', 'Bearer fixture-token'));
      expect(result.categories.map((c) => c.name), containsAll(['News', 'Movies', 'Ungrouped']));
    });

    test('malformed playlist reports a typed parse error', () async {
      final text = await io.File('test/fixtures/malformed_playlist.m3u').readAsString();

      expect(() => M3UParser().parse(text), throwsA(isA<M3UParseException>()));
    });

    test('maps tvg-id to EPG current/next programmes', () async {
      final playlist = M3UParser().parse(await io.File('test/fixtures/direct_playlist.m3u').readAsString());
      final now = DateTime.utc(2026, 1, 1, 12);
      final epg = EpgService(clock: () => now)..loadPrograms([
        EpgProgram(
          channelId: 'bbc.one',
          title: 'Midday News',
          description: 'Fixture bulletin',
          start: now.subtract(const Duration(minutes: 10)),
          end: now.add(const Duration(minutes: 20)),
        ),
        EpgProgram(
          channelId: 'bbc.one',
          title: 'Afternoon News',
          description: 'Next fixture',
          start: now.add(const Duration(minutes: 20)),
          end: now.add(const Duration(minutes: 50)),
        ),
      ]);

      final currentNext = epg.lookupForChannel(playlist.channels.first);

      expect(currentNext?.current.title, 'Midday News');
      expect(currentNext?.next?.title, 'Afternoon News');
    });

    test('huge playlist and EPG fixtures complete under timeout', () async {
      final buffer = StringBuffer('#EXTM3U\n');
      final now = DateTime.utc(2026, 1, 1, 12);
      final programs = <EpgProgram>[];
      for (var i = 0; i < 5000; i++) {
        buffer.writeln('#EXTINF:-1 tvg-id="ch.$i" group-title="Bulk",Channel $i');
        buffer.writeln('https://streams.example/live/$i.m3u8');
        programs.add(EpgProgram(
          channelId: 'ch.$i',
          title: 'Current $i',
          description: 'Bulk fixture',
          start: now.subtract(const Duration(minutes: 1)),
          end: now.add(const Duration(minutes: 59)),
        ));
      }

      final parser = M3UParser();
      final stopwatch = Stopwatch()..start();
      final playlist = parser.parse(buffer.toString());
      final epg = EpgService(clock: () => now)..loadPrograms(programs);

      expect(playlist.channels, hasLength(5000));
      expect(epg.lookupForChannel(playlist.channels[4999])?.current.title, 'Current 4999');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    }, timeout: const Timeout(Duration(seconds: 3)));
  });

  group('Local state services', () {
    test('favorites add and remove channel ids', () async {
      final service = FavoritesService(memory: <String, Object?>{});

      expect(await service.add(101), isTrue);
      expect(await service.isFavorite(101), isTrue);
      expect(await service.remove(101), isFalse);
      expect(await service.all(), isEmpty);
    });

    test('viewer service selects saved viewer or admin fallback', () async {
      final memory = <String, Object?>{};
      final service = ViewerService(memory: memory);
      final viewers = [
        const Viewer(id: 1, ulid: 'viewer-user', name: 'User', isAdmin: false),
        const Viewer(id: 2, ulid: 'viewer-admin', name: 'Admin', isAdmin: true),
      ];

      expect(await service.resolveActiveViewer(viewers), viewers[1]);
      await service.setActiveViewer(viewers[0]);
      expect(await service.resolveActiveViewer(viewers), viewers[0]);
    });

    test('resume progress saves and loads viewer-scoped position', () async {
      final service = ResumeService(memory: <String, Object?>{});
      const progress = Progress(
        viewerId: 'viewer-admin',
        contentType: ContentType.vod,
        streamId: 201,
        positionSeconds: 125,
        durationSeconds: 600,
      );

      await service.save(progress);

      expect(await service.load('viewer-admin', ContentType.vod, 201), progress);
      expect(await service.shouldPromptResume('viewer-admin', ContentType.vod, 201), isTrue);
    });
  });
}

Map<String, Object?> xtreamAuth({required int auth, String status = 'Active'}) => {
      'user_info': {
        'username': 'demo',
        'password': 'secret',
        'auth': auth,
        'status': status,
        'message': status,
      },
      'server_info': {'url': 'xtream.example', 'port': '443', 'server_protocol': 'https'},
      'm3u_editor': {'version': '0.10.0', 'features': <String>['progress']},
    };

Map<String, Object?> category(String id, String name) => {'category_id': id, 'category_name': name, 'parent_id': 0};

Map<String, Object?> liveStream(int id, String name, String categoryId, String epgId) => {
      'stream_id': id,
      'name': name,
      'stream_icon': 'https://img.example/$id.png',
      'category_id': categoryId,
      'epg_channel_id': epgId,
      'stream_type': 'live',
    };

Map<String, Object?> vodItem(int id, String name, String categoryId) => {
      'stream_id': id,
      'name': name,
      'stream_icon': 'https://img.example/$id.png',
      'category_id': categoryId,
      'container_extension': 'mp4',
      'rating_5based': 4.5,
    };

Map<String, Object?> seriesItem(int id, String name, String categoryId) => {
      'series_id': id,
      'name': name,
      'cover': 'https://img.example/$id.png',
      'category_id': categoryId,
      'plot': 'Fixture plot',
      'rating_5based': 4.0,
    };

Map<String, Object?> episode(int id, int episodeNum, String title) => {
      'id': '$id',
      'episode_num': episodeNum,
      'title': title,
      'container_extension': 'mp4',
      'season': 1,
      'info': {'plot': 'Fixture episode'},
    };

class FakeXtreamTransport {
  FakeXtreamTransport(this.responses);

  final Map<String, Object?> responses;
  Map<String, String> lastHeaders = const {};

  Future<Object?> call(XtreamRequest request) async {
    lastHeaders = request.headers;
    final action = request.action ?? 'auth';
    final response = responses[action];
    if (response == null) {
      throw StateError('No fixture for ${jsonEncode(request.toDebugMap())}');
    }
    return response;
  }
}
