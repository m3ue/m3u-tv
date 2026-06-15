import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('app state boot', () {
    test('cached Xtream state is visible before remote refresh finishes', () async {
      final storage = InMemorySecureStorage();
      final cacheMemory = <String, Object?>{};
      final catalogGate = Completer<Object?>();
      await storage.write(
        'm3ue_tv_credentials',
        jsonEncode(<String, String>{
          'server': 'https://fixture.example',
          'username': 'fixture-user',
          'password': 'fixture-password',
        }),
      );
      await storage.write(
        'm3ue_tv_source',
        jsonEncode(<String, String>{'type': 'xtream'}),
      );

      final cache = CacheService(memory: cacheMemory);
      await cache.set('sourceType', 'xtream');
      await cache.set('liveCategories', const <Category>[
        Category(id: 'cached-live', name: 'Cached Live'),
      ]);
      await cache.set('vodCategories', const <Category>[
        Category(id: 'cached-vod', name: 'Cached Movies'),
      ]);
      await cache.set('seriesCategories', const <Category>[
        Category(id: 'cached-series', name: 'Cached Series'),
      ]);
      await cache.set('liveStreams', const <Channel>[
        Channel(id: 901, name: 'Cached BBC', streamUrl: 'cached-live-url'),
      ]);
      await cache.set('vodStreams', const <VodItem>[
        VodItem(
          id: 902,
          name: 'Cached Movie',
          streamUrl: 'cached-vod-url',
          containerExtension: 'mp4',
        ),
      ]);
      await cache.set('seriesStreams', const <Series>[
        Series(id: 903, name: 'Cached Show'),
      ]);

      final controller = _controller(
        storage: storage,
        cacheMemory: cacheMemory,
        transport: _FakeXtreamTransport.success()
            .withResponse('get_live_categories', catalogGate.future)
            .call,
      );

      final boot = controller.boot();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.sourceType, AppSourceType.xtream);
      expect(controller.isBootstrapping, isFalse);
      expect(controller.liveCategories.single.name, 'Cached Live');
      expect(controller.channels.single.name, 'Cached BBC');
      expect(controller.vodItems.single.name, 'Cached Movie');
      expect(controller.seriesList.single.name, 'Cached Show');
      await boot;

      catalogGate.complete(
        _FakeXtreamTransport.success().responses['get_live_categories'],
      );
      for (var pumpCount = 0; pumpCount < 5; pumpCount += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(controller.liveCategories.single.name, 'News');
      expect(controller.channels.single.name, 'BBC One');
    });

    testWidgets(
      'saved_source boots connected app state without constructor fixtures',
      (WidgetTester tester) async {
        final storage = InMemorySecureStorage();
        final localMemory = <String, Object?>{};
        await storage.write(
          'm3ue_tv_credentials',
          jsonEncode(<String, String>{
            'server': 'https://fixture.example',
            'username': 'fixture-user',
            'password': 'fixture-password',
          }),
        );
        await storage.write(
          'm3ue_tv_source',
          jsonEncode(<String, String>{'type': 'xtream'}),
        );
        final resumeService = ResumeService(memory: localMemory);
        await FavoritesService(memory: localMemory).add(101);
        await resumeService.save(
          const Progress(
            viewerId: 'viewer-admin',
            contentType: ContentType.vod,
            streamId: 201,
            positionSeconds: 91,
            durationSeconds: 600,
          ),
        );

        final controller = _controller(
          storage: storage,
          localMemory: localMemory,
          transport: _FakeXtreamTransport.success().call,
        );

        await tester.pumpWidget(_TestApp(controller: controller));
        await _pumpAppState(tester);

        expect(controller.sourceType, AppSourceType.xtream);
        expect(controller.isBootstrapping, isFalse);
        expect(_visibleText(tester), contains('Connected source: Xtream'));
        expect(controller.liveCategories.single.name, 'News');
        expect(controller.channels.single.name, 'BBC One');
        expect(controller.vodItems.single.name, 'Big Buck Bunny');
        expect(controller.seriesList.single.name, 'Fixture Show');
        expect(await controller.favoritesService.isFavorite(101), isTrue);

        await _tapSidebarDestination(tester, 'Live TV');
        await _pumpAppState(tester);
        expect(find.text('All Channels'), findsOneWidget);
        expect(find.text('BBC One'), findsWidgets);

        await _tapSidebarDestination(tester, 'Movies');
        await _pumpAppState(tester);
        expect(find.text('All Movies'), findsOneWidget);
        expect(find.text('Big Buck Bunny'), findsWidgets);

        await _tapSidebarDestination(tester, 'Series');
        await _pumpAppState(tester);
        expect(find.text('All Series'), findsOneWidget);
        expect(find.text('Fixture Show'), findsWidgets);

        await _tapSidebarDestination(tester, 'Settings');
        await _pumpAppState(tester);
        expect(find.text('Connection'), findsOneWidget);
        expect(find.text('Source'), findsOneWidget);
        expect(find.text('Xtream'), findsOneWidget);
        expect(_visibleText(tester), isNot(contains('fixture-password')));
        expect(_visibleText(tester), isNot(contains('fixture-user')));

        final restarted = _controller(
          storage: storage,
          localMemory: localMemory,
          transport: _FakeXtreamTransport.success().call,
        );
        await restarted.boot();
        await _waitForXtreamRefresh(restarted);

        expect(restarted.channels.single.name, 'BBC One');
        expect(restarted.channels.single.epgChannelId, 'bbc.one');
        expect(
          restarted.epgService
              .lookupForChannel(restarted.channels.single)
              ?.current
              .title,
          'News at Noon',
        );
        expect(
          restarted.epgService
              .lookupForChannel(restarted.channels.single)
              ?.next
              ?.title,
          'Afternoon News',
        );
        expect(await restarted.favoritesService.isFavorite(101), isTrue);
        expect(restarted.progressList.single.streamId, 201);
        expect(restarted.progressList.single.positionSeconds, 91);
        expect(restarted.error, isNot(contains('fixture-password')));
      },
    );

    testWidgets(
      'source switch failure path preserves prior cache and redacts credentials',
      (WidgetTester tester) async {
        final storage = InMemorySecureStorage();
        final cacheMemory = <String, Object?>{};
        final localMemory = <String, Object?>{};
        final controller = _controller(
          storage: storage,
          cacheMemory: cacheMemory,
          localMemory: localMemory,
          transport: _FakeXtreamTransport.success().call,
        );

        final connected = await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        );
        expect(connected, isTrue);
        expect(controller.channels.single.name, 'BBC One');

        final cachedXtreamChannels = await controller.cacheService
            .get<List<Channel>>('liveStreams');
        expect(cachedXtreamChannels?.data.single.name, 'BBC One');

        final switched = await controller.switchToM3u(
          playlistText:
              '#EXTM3U\n#EXTINF:-1 group-title="News",BBC One HD\nhttps://streams.example/live/bbc-one.m3u8',
        );
        expect(switched, isTrue);
        expect(controller.sourceType, AppSourceType.m3u);
        expect(controller.channels.single.name, 'BBC One HD');
        expect(
          (await controller.cacheService.get<List<Channel>>(
            'liveStreams',
          ))?.data.single.name,
          'BBC One HD',
        );

        final failed = await controller.switchToM3u(
          playlistText: 'fixture-password is not a playlist',
        );
        expect(failed, isFalse);
        expect(controller.error, contains('M3U parse error'));
        expect(controller.error, isNot(contains('fixture-password')));
        expect(controller.channels.single.name, 'BBC One HD');
        expect(
          (await controller.cacheService.get<List<Channel>>(
            'liveStreams',
          ))?.data.single.name,
          'BBC One HD',
        );

        await tester.pumpWidget(_TestApp(controller: controller));
        await _pumpAppState(tester);
        await _tapSidebarDestination(tester, 'Settings');
        await _pumpAppState(tester);

        expect(find.text('Last error'), findsOneWidget);
        expect(_visibleText(tester), contains('M3U parse error'));
        expect(_visibleText(tester), isNot(contains('fixture-password')));
        expect(_visibleText(tester), isNot(contains('fixture-user')));
      },
    );

    test(
      'production defaults persist state across controller instances',
      () async {
        final directory = await io.Directory.systemTemp.createTemp(
          'm3u-tv-state-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final stateFile = io.File('${directory.path}/state.json');
        final store = PersistentJsonStore(file: stateFile);

        final first = AppStateController(
          persistentStore: store,
          xtreamService: XtreamService(
            transport: _FakeXtreamTransport.success().call,
          ),
        );
        expect(
          await first.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        await first.favoritesService.add(101);
        await first.resumeService.save(
          const Progress(
            viewerId: 'viewer-admin',
            contentType: ContentType.vod,
            streamId: 201,
            positionSeconds: 91,
            durationSeconds: 600,
          ),
        );
        final cachedChannels = await first.cacheService.get<List<Channel>>(
          'liveStreams',
        );
        expect(cachedChannels?.data.single.name, 'BBC One');

        final restarted = AppStateController(
          persistentStore: PersistentJsonStore(file: stateFile),
          xtreamService: XtreamService(
            transport: _FakeXtreamTransport.success().call,
          ),
        );
        await restarted.boot();
        await _waitForXtreamRefresh(restarted);

        expect(restarted.sourceType, AppSourceType.xtream);
        expect(restarted.channels.single.name, 'BBC One');
        expect(
          restarted.epgService
              .lookupForChannel(restarted.channels.single)
              ?.current
              .title,
          'News at Noon',
        );
        expect(await restarted.favoritesService.isFavorite(101), isTrue);
        expect(restarted.activeViewer?.ulid, 'viewer-admin');
        expect(restarted.progressList.single.positionSeconds, 91);
        expect(
          (await restarted.cacheService.get<List<Channel>>(
            'liveStreams',
          ))?.data.single.name,
          'BBC One',
        );
      },
    );
  });
}

AppStateController _controller({
  required InMemorySecureStorage storage,
  required XtreamTransport transport,
  Map<String, Object?>? cacheMemory,
  Map<String, Object?>? localMemory,
}) {
  final sharedLocalMemory = localMemory ?? <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport,
      cache: CacheService(memory: cacheMemory ?? <String, Object?>{}),
    ),
    secureStorage: storage,
    cacheService: CacheService(memory: cacheMemory ?? <String, Object?>{}),
    favoritesService: FavoritesService(memory: sharedLocalMemory),
    resumeService: ResumeService(memory: sharedLocalMemory),
    viewerService: ViewerService(memory: sharedLocalMemory),
  );
}

String _visibleText(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((Text text) => text.data ?? '')
      .join('\n');
}

Future<void> _pumpAppState(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _waitForXtreamRefresh(AppStateController controller) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final hasEpg = controller.channels.isNotEmpty &&
        controller.epgService.lookupForChannel(controller.channels.single) !=
            null;
    if (hasEpg &&
        controller.activeViewer != null &&
        controller.progressList.isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Finder _sidebarDestination(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is SidebarDestinationItem && widget.label == label,
  );
}

Future<void> _tapSidebarDestination(WidgetTester tester, String label) async {
  await tester.tap(_sidebarDestination(label));
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.controller});

  final AppStateController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: AppShell(deviceType: DeviceType.tv, appState: controller),
    );
  }
}

class _FakeXtreamTransport {
  _FakeXtreamTransport(this.responses);

  factory _FakeXtreamTransport.success() =>
      _FakeXtreamTransport(<String, Object?>{
        'auth': <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{'version': '0.10.0'},
        },
        'get_live_categories': <Map<String, Object?>>[
          <String, Object?>{'category_id': '10', 'category_name': 'News'},
        ],
        'get_vod_categories': <Map<String, Object?>>[
          <String, Object?>{'category_id': '20', 'category_name': 'Movies'},
        ],
        'get_series_categories': <Map<String, Object?>>[
          <String, Object?>{'category_id': '30', 'category_name': 'Series'},
        ],
        'get_live_streams': <Map<String, Object?>>[
          <String, Object?>{
            'stream_id': 101,
            'name': 'BBC One',
            'category_id': '10',
            'epg_channel_id': 'bbc.one',
          },
        ],
        'get_vod_streams': <Map<String, Object?>>[
          <String, Object?>{
            'stream_id': 201,
            'name': 'Big Buck Bunny',
            'category_id': '20',
            'container_extension': 'mp4',
          },
        ],
        'get_series': <Map<String, Object?>>[
          <String, Object?>{
            'series_id': 301,
            'name': 'Fixture Show',
            'category_id': '30',
          },
        ],
        'get_viewers': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'ulid': 'viewer-admin',
            'name': 'Admin',
            'is_admin': true,
          },
        ],
        'get_recently_watched': <Map<String, Object?>>[],
        'get_epg_batch': <String, Object?>{
          '101': <Map<String, Object?>>[
            <String, Object?>{
              'stream_id': 101,
              'title': base64Encode(utf8.encode('News at Noon')),
              'description': base64Encode(utf8.encode('Fixture bulletin')),
              'start_timestamp':
                  DateTime.now()
                      .subtract(const Duration(minutes: 10))
                      .millisecondsSinceEpoch ~/
                  1000,
              'stop_timestamp':
                  DateTime.now()
                      .add(const Duration(minutes: 20))
                      .millisecondsSinceEpoch ~/
                  1000,
            },
            <String, Object?>{
              'stream_id': 101,
              'title': base64Encode(utf8.encode('Afternoon News')),
              'description': 'Next fixture',
              'start': DateTime.now()
                  .add(const Duration(minutes: 20))
                  .toUtc()
                  .toIso8601String(),
              'end': DateTime.now()
                  .add(const Duration(minutes: 50))
                  .toUtc()
                  .toIso8601String(),
            },
          ],
        },
      });

  final Map<String, Object?> responses;

  _FakeXtreamTransport withResponse(String action, Object? response) {
    return _FakeXtreamTransport(<String, Object?>{
      ...responses,
      action: response,
    });
  }

  Future<Object?> call(XtreamRequest request) async {
    final action = request.action ?? 'auth';
    final response = responses[action];
    if (response == null) {
      throw StateError('No fixture for ${jsonEncode(request.toDebugMap())}');
    }
    if (response is Future<Object?>) return response;
    return response;
  }
}
