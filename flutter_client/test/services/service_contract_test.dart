import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/m3u_parser.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('XtreamService contract', () {
    test(
      'default transport authenticates against player_api.php over HTTP',
      () async {
        final server = await io.HttpServer.bind(
          io.InternetAddress.loopbackIPv4,
          0,
        );
        final requests = <Uri>[];
        unawaited(
          server.listen((request) {
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
          }).asFuture<void>(),
        );
        addTearDown(() => server.close(force: true));

        final service = XtreamService();
        final response = await service.authenticate(
          UserCredentials(
            server: 'http://${server.address.host}:${server.port}',
            username: 'demo',
            password: 'secret',
          ),
        );

        expect(response.isAuthenticated, isTrue);
        expect(await service.getLiveCategories(), [
          const Category(id: '10', name: 'Live News'),
        ]);
        expect(requests.map((uri) => uri.path).toSet(), {
          '/player_api.php',
        });
        expect(requests.first.queryParameters['username'], 'demo');
        expect(requests.first.queryParameters['password'], 'secret');
        expect(requests.last.queryParameters['action'], 'get_live_categories');
      },
    );

    test(
      'default transport reports unauthorized HTTP failures without credentials',
      () async {
        final server = await io.HttpServer.bind(
          io.InternetAddress.loopbackIPv4,
          0,
        );
        unawaited(
          server.listen((request) {
            request.response.statusCode = io.HttpStatus.unauthorized;
            request.response.reasonPhrase = 'Unauthorized';
            request.response.headers.contentType = io.ContentType.json;
            request.response.write(
              jsonEncode(<String, Object?>{'error': 'Unauthorized'}),
            );
            unawaited(request.response.close());
          }).asFuture<void>(),
        );
        addTearDown(() => server.close(force: true));

        final service = XtreamService();

        await expectLater(
          service.authenticate(
            UserCredentials(
              server: 'http://${server.address.host}:${server.port}',
              username: 'demo-user',
              password: 'playlist-secret',
            ),
          ),
          throwsA(
            isA<XtreamHttpException>()
                .having(
                  (error) => error.statusCode,
                  'statusCode',
                  401,
                )
                .having(
                  (error) => '$error',
                  'message',
                  contains('player_api.php'),
                )
                .having(
                  (error) => '$error',
                  'message',
                  isNot(contains('demo-user')),
                )
                .having(
                  (error) => '$error',
                  'message',
                  isNot(contains('playlist-secret')),
                ),
          ),
        );
      },
    );

    test(
      'default transport reports plaintext server failures cleanly',
      () async {
        final server = await io.HttpServer.bind(
          io.InternetAddress.loopbackIPv4,
          0,
        );
        unawaited(
          server.listen((request) {
            request.response.headers.contentType = io.ContentType.text;
            request.response.write('no available server');
            unawaited(request.response.close());
          }).asFuture<void>(),
        );
        addTearDown(() => server.close(force: true));

        final service = XtreamService();

        await expectLater(
          service.authenticate(
            UserCredentials(
              server: 'http://${server.address.host}:${server.port}',
              username: 'demo-user',
              password: 'playlist-secret',
            ),
          ),
          throwsA(
            isA<XtreamResponseException>()
                .having(
                  (error) => '$error',
                  'message',
                  contains('no available server'),
                )
                .having(
                  (error) => '$error',
                  'message',
                  isNot(contains('FormatException')),
                )
                .having(
                  (error) => '$error',
                  'message',
                  isNot(contains('playlist-secret')),
                ),
          ),
        );
      },
    );

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
      expect(await service.getLiveCategories(), [
        const Category(id: '10', name: 'Live News'),
      ]);
      expect((await service.getVodCategories()).single.name, 'Movies');
      expect((await service.getSeriesCategories()).single.name, 'Series');
      expect((await service.getLiveStreams()).single.epgChannelId, 'bbc.one');
      expect((await service.getVodStreams()).single.containerExtension, 'mp4');
      expect((await service.getSeries()).single.id, 301);
      expect(transport.lastHeaders['X-M3UE-Client'], 'm3u-tv');
    });

    test('live streams parse Xtream catchup metadata', () async {
      final service = XtreamService(
        transport: FakeXtreamTransport({
          'auth': xtreamAuth(auth: 1),
          'get_live_streams': [
            {
              ...liveStream(101, 'BBC One', '10', 'bbc.one'),
              'tv_archive': 1,
              'tv_archive_duration': '7',
            },
            liveStream(102, 'BBC Two', '10', 'bbc.two'),
          ],
        }).call,
      );
      await service.authenticate(
        const UserCredentials(
          server: 'https://xtream.example',
          username: 'demo',
          password: 'secret',
        ),
      );

      final channels = await service.getLiveStreams();

      expect(channels.first.catchupSupported, isTrue);
      expect(channels.first.catchupDays, 7);
      expect(channels.last.catchupSupported, isFalse);
      expect(channels.last.catchupDays, isNull);
    });

    test('builds Xtream catchup timeshift URL from program window', () async {
      final service = XtreamService(
        transport: FakeXtreamTransport({'auth': xtreamAuth(auth: 1)}).call,
      );
      await service.authenticate(
        const UserCredentials(
          server: 'https://xtream.example/',
          username: 'demo',
          password: 'secret',
        ),
      );

      final url = service.getCatchupStreamUrl(
        101,
        DateTime.utc(2026, 1, 1, 12, 30),
        const Duration(minutes: 45),
      );

      expect(
        url,
        'https://xtream.example/timeshift/demo/secret/45/2026-01-01:12-30/101.ts',
      );
    });

    test(
      'expired credentials return typed auth error without cache corruption',
      () async {
        final cache = CacheService(memory: <String, Object?>{});
        await cache.set('categories', {'sentinel': true});
        final service = XtreamService(
          cache: cache,
          transport: FakeXtreamTransport({
            'auth': xtreamAuth(auth: 0, status: 'Expired'),
          }).call,
        );

        await expectLater(
          service.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'expired',
              password: 'bad',
            ),
          ),
          throwsA(
            isA<XtreamAuthException>().having(
              (e) => e.code,
              'code',
              AuthErrorCode.expired,
            ),
          ),
        );

        expect((await cache.get<Map<String, Object?>>('categories'))?.data, {
          'sentinel': true,
        });
        expect(service.isConfigured, isFalse);
      },
    );

    test(
      'series seasons and episodes are typed from Xtream response',
      () async {
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
        await service.authenticate(
          const UserCredentials(
            server: 'https://xtream.example',
            username: 'demo',
            password: 'secret',
          ),
        );

        final info = await service.getSeriesInfo(301);

        expect(info.seasons.single.number, 1);
        expect(info.episodesBySeason[1]!.single.title, 'Pilot');
        expect(info.episodesBySeason[1]!.single.containerExtension, 'mp4');
      },
    );

    test('VOD info parses m3u-editor get_vod_info metadata', () async {
      final transport = FakeXtreamTransport({
        'auth': xtreamAuth(auth: 1),
        'get_vod_info': {
          'info': {
            'plot': 'A rabbit faces a squad of tired butterflies.',
            'genre': 'Animation / Comedy',
            'director': 'Fixture Director',
            'actors': 'Bunny, Butterfly',
            'release_date': '2008-04-10',
            'duration_secs': 596,
            'rating_5based': '4.5',
            'rating': 4.5,
            'cover_big': 'https://img.example/bunny-big.jpg',
          },
          'movie_data': {
            'stream_id': 201,
            'name': 'Big Buck Bunny',
            'container_extension': 'mkv',
          },
        },
      });
      final service = XtreamService(transport: transport.call);
      await service.authenticate(
        const UserCredentials(
          server: 'https://xtream.example',
          username: 'demo',
          password: 'secret',
        ),
      );

      final info = await service.getVodInfo(201);

      expect(transport.requests.last.action, 'get_vod_info');
      expect(transport.requests.last.params, {'vod_id': '201'});
      expect(info.id, 201);
      expect(info.name, 'Big Buck Bunny');
      expect(info.plot, 'A rabbit faces a squad of tired butterflies.');
      expect(info.genre, 'Animation / Comedy');
      expect(info.director, 'Fixture Director');
      expect(info.cast, 'Bunny, Butterfly');
      expect(info.year, '2008');
      expect(info.duration, '9m');
      expect(info.rating, 4.5);
      expect(info.coverUrl, 'https://img.example/bunny-big.jpg');
      expect(info.containerExtension, 'mkv');
    });

    test('VOD info falls back to root-level Xtream variants', () async {
      final service = XtreamService(
        transport: FakeXtreamTransport({
          'auth': xtreamAuth(auth: 1),
          'get_vod_info': {
            'id': 202,
            'title': 'Root Movie',
            'description': 'Root description',
            'cast': 'Root Cast',
            'releasedate': '2024-02-03',
            'episode_run_time': '91',
            'rating': 7.2,
            'movie_image': 'https://img.example/root.jpg',
          },
        }).call,
      );
      await service.authenticate(
        const UserCredentials(
          server: 'https://xtream.example',
          username: 'demo',
          password: 'secret',
        ),
      );

      final info = await service.getVodInfo(202);

      expect(info.name, 'Root Movie');
      expect(info.plot, 'Root description');
      expect(info.cast, 'Root Cast');
      expect(info.year, '2024');
      expect(info.duration, '91');
      expect(info.rating, isNull);
      expect(info.coverUrl, 'https://img.example/root.jpg');
    });

    test('EPG batch parses m3u-editor and Xtream programme shapes', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final service = XtreamService(
        transport: FakeXtreamTransport({
          'auth': xtreamAuth(auth: 1),
          'get_epg_batch': {
            '101': [
              {
                'stream_id': 101,
                'title': base64Encode(utf8.encode('Midday News')),
                'description': base64Encode(utf8.encode('Fixture bulletin')),
                'start_timestamp':
                    now
                        .subtract(const Duration(minutes: 5))
                        .millisecondsSinceEpoch ~/
                    1000,
                'stop_timestamp':
                    now
                        .add(const Duration(minutes: 25))
                        .millisecondsSinceEpoch ~/
                    1000,
              },
              {
                'channel_id': 'bbc.one',
                'title': 'Afternoon News',
                'description': 'Next fixture',
                'start': '2026-01-01 12:25:00',
                'end': '2026-01-01 12:55:00',
              },
            ],
          },
        }).call,
      );
      await service.authenticate(
        const UserCredentials(
          server: 'https://xtream.example',
          username: 'demo',
          password: 'secret',
        ),
      );

      final programs = await service.getEpgBatch(const [
        Channel(
          id: 101,
          name: 'BBC One',
          streamUrl: 'https://example/live/101.m3u8',
          epgChannelId: 'bbc.one',
        ),
      ]);
      final midday = programs.singleWhere(
        (program) => program.title == 'Midday News',
      );
      final afternoon = programs.singleWhere(
        (program) => program.title == 'Afternoon News',
      );

      expect(programs, hasLength(2));
      expect(midday.channelId, 'bbc.one');
      expect(midday.description, 'Fixture bulletin');
      expect(afternoon.channelId, 'bbc.one');
    });

    test('EPG batch chunks requests to at most 100 stream ids', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final transport = FakeXtreamTransport({'auth': xtreamAuth(auth: 1)});
      transport.onRequest = (request) {
        if (request.action != 'get_epg_batch') {
          return transport.responses[request.action ?? 'auth'];
        }
        final streamIds = request.params['stream_ids']!.split(',');
        return <String, Object?>{
          for (final streamId in streamIds)
            streamId: <Map<String, Object?>>[
              <String, Object?>{
                'stream_id': int.parse(streamId),
                'channel_id': 'epg.$streamId',
                'title': 'Programme $streamId',
                'description': 'Plain m3u-editor listing',
                'start': now
                    .add(Duration(seconds: int.parse(streamId)))
                    .toIso8601String(),
                'end': now
                    .add(Duration(minutes: 30, seconds: int.parse(streamId)))
                    .toIso8601String(),
              },
            ],
        };
      };
      final service = XtreamService(transport: transport.call);
      await service.authenticate(
        const UserCredentials(
          server: 'https://xtream.example',
          username: 'demo',
          password: 'secret',
        ),
      );

      final programs = await service.getEpgBatch([
        for (var index = 1; index <= 205; index += 1)
          Channel(
            id: index,
            name: 'Channel $index',
            streamUrl: 'https://example/live/$index.m3u8',
            epgChannelId: 'epg.$index',
          ),
      ]);

      final epgRequests = transport.requests
          .where((request) => request.action == 'get_epg_batch')
          .toList(growable: false);
      expect(epgRequests, hasLength(3));
      expect(epgRequests[0].params['stream_ids']!.split(','), hasLength(100));
      expect(epgRequests[1].params['stream_ids']!.split(','), hasLength(100));
      expect(epgRequests[2].params['stream_ids']!.split(','), hasLength(5));
      expect(programs, hasLength(205));
      expect(programs.first.channelId, 'epg.1');
      expect(programs.first.title, 'Programme 1');
      expect(programs.first.description, 'Plain m3u-editor listing');
      expect(programs.last.channelId, 'epg.205');
    });

    test(
      'EPG batch uses listing channel_id when response key is stream id',
      () async {
        final now = DateTime.utc(2026, 1, 1, 12);
        final service = XtreamService(
          transport: FakeXtreamTransport({
            'auth': xtreamAuth(auth: 1),
            'get_epg_batch': <String, Object?>{
              '101': <Map<String, Object?>>[
                <String, Object?>{
                  'stream_id': 101,
                  'channel_id': 'm3u-editor-channel-key',
                  'title': 'Plain Short EPG Title',
                  'description': 'Plain short EPG description',
                  'start': now.toIso8601String(),
                  'end': now.add(const Duration(minutes: 30)).toIso8601String(),
                },
              ],
            },
          }).call,
        );
        await service.authenticate(
          const UserCredentials(
            server: 'https://xtream.example',
            username: 'demo',
            password: 'secret',
          ),
        );

        final programs = await service.getEpgBatch(const <Channel>[
          Channel(
            id: 101,
            name: 'Fallback Name',
            streamUrl: 'https://example/live/101.m3u8',
            epgChannelId: 'stale-channel-key',
          ),
        ]);

        expect(programs.single.channelId, 'stale-channel-key');
        expect(programs.single.title, 'Plain Short EPG Title');
        expect(programs.single.description, 'Plain short EPG description');
      },
    );
  });

  group('M3UParser contract', () {
    test(
      'parses valid direct M3U with metadata, headers, and groups',
      () async {
        final text = await io.File(
          'test/fixtures/direct_playlist.m3u',
        ).readAsString();

        final result = M3UParser().parse(text);

        expect(result.channels, hasLength(3));
        expect(result.channels.first, isA<Channel>());
        expect(result.channels.first.epgChannelId, 'bbc.one');
        expect(result.channels.first.name, 'BBC One HD');
        expect(result.channels.first.logoUrl, 'https://img.example/bbc.png');
        expect(result.channels.first.groupTitle, 'News');
        expect(
          result.channels.first.streamUrl,
          'https://streams.example/live/bbc-one.m3u8',
        );
        expect(
          result.channels.first.headers,
          containsPair('User-Agent', 'FixtureAgent/1.0'),
        );
        expect(
          result.channels.first.headers,
          containsPair('Authorization', 'Bearer fixture-token'),
        );
        expect(
          result.categories.map((c) => c.name),
          containsAll(['News', 'Movies', 'Ungrouped']),
        );
      },
    );

    test('parses M3U catchup attributes into channel metadata', () {
      final playlist = M3UParser().parse('''
#EXTM3U
#EXTINF:-1 tvg-id="bbc.one" tvg-name="BBC One" group-title="News" catchup="default" catchup-days="3" catchup-source="https://archive.example/{utc:Y-m-d:H-M}/{duration}/{channel-id}",BBC One
https://streams.example/live/bbc-one.m3u8
''');

      final channel = playlist.channels.single;

      expect(channel.catchupSupported, isTrue);
      expect(channel.catchupDays, 3);
      expect(
        channel.catchupSource,
        'https://archive.example/{utc:Y-m-d:H-M}/{duration}/{channel-id}',
      );
    });

    test('malformed playlist reports a typed parse error', () async {
      final text = await io.File(
        'test/fixtures/malformed_playlist.m3u',
      ).readAsString();

      expect(() => M3UParser().parse(text), throwsA(isA<M3UParseException>()));
    });

    test('maps tvg-id to EPG current/next programmes', () async {
      final playlist = M3UParser().parse(
        await io.File('test/fixtures/direct_playlist.m3u').readAsString(),
      );
      final now = DateTime.utc(2026, 1, 1, 12);
      final epg = EpgService(clock: () => now)
        ..loadPrograms([
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

    test(
      'huge playlist and EPG fixtures complete under timeout',
      () async {
        final buffer = StringBuffer('#EXTM3U\n');
        final now = DateTime.utc(2026, 1, 1, 12);
        final programs = <EpgProgram>[];
        for (var i = 0; i < 5000; i++) {
          buffer
            ..writeln(
              '#EXTINF:-1 tvg-id="ch.$i" group-title="Bulk",Channel $i',
            )
            ..writeln('https://streams.example/live/$i.m3u8');
          programs.add(
            EpgProgram(
              channelId: 'ch.$i',
              title: 'Current $i',
              description: 'Bulk fixture',
              start: now.subtract(const Duration(minutes: 1)),
              end: now.add(const Duration(minutes: 59)),
            ),
          );
        }

        final parser = M3UParser();
        final stopwatch = Stopwatch()..start();
        final playlist = parser.parse(buffer.toString());
        final epg = EpgService(clock: () => now)..loadPrograms(programs);

        expect(playlist.channels, hasLength(5000));
        expect(
          epg.lookupForChannel(playlist.channels[4999])?.current.title,
          'Current 4999',
        );
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      },
      timeout: const Timeout(Duration(seconds: 3)),
    );
  });

  group('Local state services', () {
    test('cache preserves channel catchup metadata', () async {
      final file = io.File(
        '${io.Directory.systemTemp.path}/m3u_tv_cache_catchup_${DateTime.now().microsecondsSinceEpoch}.json',
      );
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final store = PersistentJsonStore(file: file);
      final cache = CacheService(store: store);
      await cache.set('liveStreams', const <Channel>[
        Channel(
          id: 101,
          name: 'BBC One',
          streamUrl: 'https://streams.example/live/bbc-one.m3u8',
          catchupSupported: true,
          catchupDays: 7,
          catchupSource: 'https://archive.example/{utc}/{duration}',
        ),
      ]);

      final restored = await CacheService(
        store: PersistentJsonStore(file: file),
      ).get<List<Channel>>('liveStreams');

      expect(restored?.data.single.catchupSupported, isTrue);
      expect(restored?.data.single.catchupDays, 7);
      expect(
        restored?.data.single.catchupSource,
        'https://archive.example/{utc}/{duration}',
      );
    });

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

      expect(
        await service.load('viewer-admin', ContentType.vod, 201),
        progress,
      );
      expect(
        await service.shouldPromptResume('viewer-admin', ContentType.vod, 201),
        isTrue,
      );
    });
  });
}

Map<String, Object?> xtreamAuth({
  required int auth,
  String status = 'Active',
}) => {
  'user_info': {
    'username': 'demo',
    'password': 'secret',
    'auth': auth,
    'status': status,
    'message': status,
  },
  'server_info': {
    'url': 'xtream.example',
    'port': '443',
    'server_protocol': 'https',
  },
  'm3u_editor': {
    'version': '0.10.0',
    'features': <String>['progress'],
  },
};

Map<String, Object?> category(String id, String name) => {
  'category_id': id,
  'category_name': name,
  'parent_id': 0,
};

Map<String, Object?> liveStream(
  int id,
  String name,
  String categoryId,
  String epgId,
) => {
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
  final List<XtreamRequest> requests = <XtreamRequest>[];
  Map<String, String> lastHeaders = const {};
  FutureOr<Object?> Function(XtreamRequest request)? onRequest;

  Future<Object?> call(XtreamRequest request) async {
    requests.add(request);
    lastHeaders = request.headers;
    final handler = onRequest;
    if (handler != null) return handler(request);
    final action = request.action ?? 'auth';
    final response = responses[action];
    if (response == null) {
      throw StateError('No fixture for ${jsonEncode(request.toDebugMap())}');
    }
    return response;
  }
}
