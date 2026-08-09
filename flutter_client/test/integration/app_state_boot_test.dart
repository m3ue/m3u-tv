import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('app state boot', () {
    test('runtime EPG interval changes update EPG freshness', () async {
      var now = DateTime.utc(2026, 7, 30, 12);
      final epgService = EpgService(clock: () => now);
      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: _FakeXtreamTransport.success().call,
        epgService: epgService,
      );
      addTearDown(controller.dispose);
      const channel = Channel(
        id: 101,
        name: 'BBC One',
        streamUrl: 'https://fixture.example/live/101',
        epgChannelId: 'bbc.one',
      );

      for (final interval in AppStateController.epgRefreshOptions) {
        await controller.setEpgRefreshInterval(interval);
        expect(controller.epgService.cacheTtl, interval);

        epgService.markFetched(const <String>['bbc.one']);
        now = now.add(interval - const Duration(microseconds: 1));
        expect(epgService.hasFreshDataForChannel(channel), isTrue);
        now = now.add(const Duration(microseconds: 1));
        expect(epgService.hasFreshDataForChannel(channel), isFalse);
      }
    });

    test('boot restores the EPG freshness interval', () async {
      final storage = InMemorySecureStorage();
      await storage.write('m3ue_tv_epg_interval_minutes', '360');
      final controller = _controller(
        storage: storage,
        transport: _FakeXtreamTransport.success().call,
      );
      addTearDown(controller.dispose);

      await controller.boot();

      expect(controller.epgService.cacheTtl, const Duration(hours: 6));
    });

    test(
      'failed EPG batches preserve guide data and retry after backoff',
      () async {
        var now = DateTime.utc(2026, 7, 30, 12);
        final epgService = EpgService(clock: () => now)
          ..loadPrograms(<EpgProgram>[
            EpgProgram(
              channelId: 'bbc.one',
              title: 'Loaded guide',
              description: '',
              start: now.subtract(const Duration(hours: 1)),
              end: now.add(const Duration(hours: 3)),
            ),
          ]);
        now = now.add(const Duration(hours: 2));
        var epgRequests = 0;
        final fixtures = _FakeXtreamTransport.success();
        Future<Object?> transport(XtreamRequest request) {
          if (request.action == 'get_epg_batch') {
            epgRequests += 1;
            return Future<Object?>.error(StateError('temporary EPG outage'));
          }
          return fixtures.call(request);
        }

        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: transport,
          epgService: epgService,
        );
        addTearDown(controller.dispose);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);

        expect(epgRequests, 1);
        expect(epgService.lookup('bbc.one')?.current.title, 'Loaded guide');
        controller
          ..ensureEpgForChannels(controller.channels)
          ..ensureEpgForChannels(controller.channels);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(epgRequests, 1);

        now = now.add(EpgService.retryBackoff);
        controller.ensureEpgForChannels(controller.channels);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(epgRequests, 2);
        expect(epgService.lookup('bbc.one')?.current.title, 'Loaded guide');
        expect(
          epgService.hasFreshDataForChannel(controller.channels.single),
          isFalse,
        );
      },
    );

    test(
      'successful EPG batches clear stale channels with no programs',
      () async {
        var now = DateTime.utc(2026, 7, 30, 12);
        final epgService = EpgService(clock: () => now)
          ..loadPrograms(<EpgProgram>[
            EpgProgram(
              channelId: 'bbc.one',
              title: 'Stale BBC guide',
              description: '',
              start: now.subtract(const Duration(minutes: 10)),
              end: now.add(const Duration(hours: 2)),
            ),
            EpgProgram(
              channelId: 'cnn',
              title: 'Stale CNN guide',
              description: '',
              start: now.subtract(const Duration(minutes: 10)),
              end: now.add(const Duration(hours: 2)),
            ),
          ]);
        now = now.add(const Duration(hours: 1));
        var epgRequests = 0;
        final fixtures = _FakeXtreamTransport.success()
            .withResponse('get_live_streams', <Map<String, Object?>>[
              <String, Object?>{
                'stream_id': 101,
                'name': 'BBC One',
                'category_id': '10',
                'epg_channel_id': 'bbc.one',
              },
              <String, Object?>{
                'stream_id': 102,
                'name': 'CNN',
                'category_id': '10',
                'epg_channel_id': 'cnn',
              },
            ])
            .withResponse('get_epg_batch', <String, Object?>{
              '101': <Map<String, Object?>>[
                <String, Object?>{
                  'stream_id': 101,
                  'title': base64Encode(utf8.encode('Fresh BBC guide')),
                  'description': '',
                  'start_timestamp':
                      now
                          .subtract(const Duration(minutes: 10))
                          .millisecondsSinceEpoch ~/
                      1000,
                  'stop_timestamp':
                      now
                          .add(const Duration(minutes: 20))
                          .millisecondsSinceEpoch ~/
                      1000,
                },
              ],
            });
        Future<Object?> transport(XtreamRequest request) {
          if (request.action == 'get_epg_batch') epgRequests += 1;
          return fixtures.call(request);
        }

        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: transport,
          epgService: epgService,
        );
        addTearDown(controller.dispose);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);

        expect(epgRequests, 1);
        expect(epgService.lookup('bbc.one')?.current.title, 'Fresh BBC guide');
        expect(epgService.lookup('cnn'), isNull);
        expect(
          controller.channels.every(epgService.hasFreshDataForChannel),
          isTrue,
        );
        controller.ensureEpgForChannels(controller.channels);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(epgRequests, 1);
      },
    );

    test('lazy EPG refresh does not duplicate an in-flight prime', () async {
      final epgGate = Completer<Object?>();
      var epgRequests = 0;
      final fixtures = _FakeXtreamTransport.success();
      Future<Object?> transport(XtreamRequest request) {
        if (request.action == 'get_epg_batch') {
          epgRequests += 1;
          return epgGate.future;
        }
        return fixtures.call(request);
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );
      expect(epgRequests, 1);

      controller
        ..ensureEpgForChannels(controller.channels)
        ..ensureEpgForChannels(controller.channels);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(epgRequests, 1);
      epgGate.complete(<String, Object?>{});
      await Future<void>.delayed(Duration.zero);
    });

    test('source switch refreshes EPG with shared channel IDs', () async {
      final fixtures = _FakeXtreamTransport.success();
      var serverBEpgRequests = 0;
      Future<Object?> transport(XtreamRequest request) {
        if (request.action == 'get_epg_batch' &&
            request.credentials.server == 'https://server-b.example') {
          serverBEpgRequests += 1;
          return Future<Object?>.value(<String, Object?>{
            '101': <Map<String, Object?>>[
              <String, Object?>{
                'stream_id': 101,
                'title': base64Encode(utf8.encode('Server B guide')),
                'description': '',
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
            ],
          });
        }
        return fixtures.call(request);
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://server-a.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.epgService.lookup('bbc.one'), isNotNull);

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://server-b.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);

      expect(serverBEpgRequests, 1);
      expect(
        controller.epgService.lookup('bbc.one')?.current.title,
        'Server B guide',
      );
    });

    test(
      'failed authentication preserves the active source and guide',
      () async {
        final fixtures = _FakeXtreamTransport.success();
        Future<Object?> transport(XtreamRequest request) {
          if (request.action == null &&
              request.credentials.server == 'https://server-b.example') {
            return Future<Object?>.value(<String, Object?>{
              'user_info': <String, Object?>{
                'auth': 0,
                'status': 'Invalid credentials',
              },
              'm3u_editor': <String, Object?>{'version': '0.10.0'},
            });
          }
          return fixtures.call(request);
        }

        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: transport,
        );
        addTearDown(controller.dispose);
        const serverACredentials = UserCredentials(
          server: 'https://server-a.example',
          username: 'fixture-user',
          password: 'fixture-password',
        );

        expect(await controller.connectXtream(serverACredentials), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.epgService.lookup('bbc.one')?.current.title,
          'News at Noon',
        );

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://server-b.example',
              username: 'fixture-user',
              password: 'wrong-password',
            ),
          ),
          isFalse,
        );

        expect(controller.sourceType, AppSourceType.xtream);
        expect(controller.authNotifier.credentials, serverACredentials);
        expect(controller.channels.single.name, 'BBC One');
        expect(
          controller.epgService.lookup('bbc.one')?.current.title,
          'News at Noon',
        );
        expect(
          controller.epgService.hasFreshDataForChannel(
            controller.channels.single,
          ),
          isTrue,
        );
      },
    );

    test(
      'failed catalog replacement restores the active Xtream session',
      () async {
        var now = DateTime.now();
        var serverAEpgRequests = 0;
        var serverBEpgRequests = 0;
        final storage = InMemorySecureStorage();
        final fixtures = _FakeXtreamTransport.success();
        Future<Object?> transport(XtreamRequest request) {
          if (request.action == 'get_live_categories' &&
              request.credentials.server == 'https://server-b.example') {
            return Future<Object?>.error(StateError('catalog unavailable'));
          }
          if (request.action == 'get_epg_batch') {
            if (request.credentials.server == 'https://server-a.example') {
              serverAEpgRequests += 1;
              return Future<Object?>.value(_epgBatch('Server A guide', now));
            }
            if (request.credentials.server == 'https://server-b.example') {
              serverBEpgRequests += 1;
              return Future<Object?>.value(_epgBatch('Server B guide', now));
            }
          }
          return fixtures.call(request);
        }

        final controller = _controller(
          storage: storage,
          transport: transport,
          epgService: EpgService(clock: () => now),
        );
        addTearDown(controller.dispose);
        const serverACredentials = UserCredentials(
          server: 'https://server-a.example',
          username: 'fixture-user',
          password: 'fixture-password',
        );

        expect(await controller.connectXtream(serverACredentials), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(serverAEpgRequests, 1);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://server-b.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isFalse,
        );

        now = now.add(controller.epgService.cacheTtl);
        controller.ensureEpgForChannels(controller.channels);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final persistedCredentials =
            jsonDecode(
                  (await storage.read('m3ue_tv_credentials'))!,
                )
                as Map<String, Object?>;
        expect(serverBEpgRequests, 0);
        expect(serverAEpgRequests, 2);
        expect(controller.authNotifier.credentials, serverACredentials);
        expect(persistedCredentials, <String, Object?>{
          'server': serverACredentials.server,
          'username': serverACredentials.username,
          'password': serverACredentials.password,
        });
        expect(controller.sourceType, AppSourceType.xtream);
        expect(controller.channels.single.name, 'BBC One');
        expect(
          controller.epgService.lookup('bbc.one')?.current.title,
          'Server A guide',
        );
      },
    );

    test(
      'failed EPG after a source switch clears old guide and retries',
      () async {
        var now = DateTime.now();
        var serverBEpgRequests = 0;
        final fixtures = _FakeXtreamTransport.success();
        Future<Object?> transport(XtreamRequest request) {
          if (request.action == 'get_epg_batch' &&
              request.credentials.server == 'https://server-b.example') {
            serverBEpgRequests += 1;
            if (serverBEpgRequests == 1) {
              return Future<Object?>.error(StateError('temporary EPG outage'));
            }
            return Future<Object?>.value(_epgBatch('Server B guide', now));
          }
          return fixtures.call(request);
        }

        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: transport,
          epgService: EpgService(clock: () => now),
        );
        addTearDown(controller.dispose);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://server-a.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://server-b.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);

        expect(serverBEpgRequests, 1);
        expect(controller.epgService.lookup('bbc.one'), isNull);
        controller
          ..ensureEpgForChannels(controller.channels)
          ..ensureEpgForChannels(controller.channels);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(serverBEpgRequests, 1);

        now = now.add(EpgService.retryBackoff);
        controller.ensureEpgForChannels(controller.channels);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(serverBEpgRequests, 2);
        expect(
          controller.epgService.lookup('bbc.one')?.current.title,
          'Server B guide',
        );
      },
    );

    test('late EPG response from the previous source is ignored', () async {
      final now = DateTime.now();
      final serverAEpg = Completer<Object?>();
      var serverAEpgRequests = 0;
      var serverBEpgRequests = 0;
      final fixtures = _FakeXtreamTransport.success();
      Future<Object?> transport(XtreamRequest request) {
        if (request.action == 'get_epg_batch') {
          if (request.credentials.server == 'https://server-a.example') {
            serverAEpgRequests += 1;
            return serverAEpg.future;
          }
          if (request.credentials.server == 'https://server-b.example') {
            serverBEpgRequests += 1;
            return Future<Object?>.value(_epgBatch('Server B guide', now));
          }
        }
        return fixtures.call(request);
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://server-a.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );
      expect(serverAEpgRequests, 1);

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://server-b.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect(serverBEpgRequests, 1);
      expect(
        controller.epgService.lookup('bbc.one')?.current.title,
        'Server B guide',
      );

      serverAEpg.complete(_epgBatch('Late server A guide', now));
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.epgService.lookup('bbc.one')?.current.title,
        'Server B guide',
      );
    });

    test('same-source refresh rejects a delayed pre-refresh EPG', () async {
      final now = DateTime.now();
      final oldEpg = Completer<Object?>();
      final freshEpg = Completer<Object?>();
      var epgRequests = 0;
      final fixtures = _FakeXtreamTransport.success();
      Future<Object?> transport(XtreamRequest request) {
        if (request.action == 'get_epg_batch') {
          epgRequests += 1;
          return epgRequests == 1 ? oldEpg.future : freshEpg.future;
        }
        return fixtures.call(request);
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://server-a.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );
      expect(epgRequests, 1);

      await controller.clearAndRefresh();
      expect(controller.channels.single.epgChannelId, 'bbc.one');

      oldEpg.complete(_epgBatch('Old guide', now));
      await Future<void>.delayed(Duration.zero);
      expect(controller.epgService.lookup('bbc.one'), isNull);

      expect(epgRequests, 2);
      freshEpg.complete(_epgBatch('Fresh guide', now));
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.epgService.lookup('bbc.one')?.current.title,
        'Fresh guide',
      );
    });

    test('late Xtream EPG response is ignored after M3U switch', () async {
      final now = DateTime.now();
      final xtreamEpg = Completer<Object?>();
      final fixtures = _FakeXtreamTransport.success();
      Future<Object?> transport(XtreamRequest request) {
        if (request.action == 'get_epg_batch') return xtreamEpg.future;
        return fixtures.call(request);
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://server-a.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );
      expect(
        await controller.switchToM3u(
          playlistText:
              '#EXTM3U\n'
              '#EXTINF:-1 tvg-id="bbc.one" group-title="News",Local BBC\n'
              'https://streams.example/live/bbc-one.m3u8',
        ),
        isTrue,
      );

      xtreamEpg.complete(_epgBatch('Late server A guide', now));
      await Future<void>.delayed(Duration.zero);

      expect(controller.sourceType, AppSourceType.m3u);
      expect(controller.channels.single.epgChannelId, 'bbc.one');
      expect(controller.epgService.lookup('bbc.one'), isNull);
    });

    test(
      'cached Xtream state is visible before remote refresh finishes',
      () async {
        final storage = InMemorySecureStorage();
        final cacheMemory = <String, Object?>{};
        final localMemory = <String, Object?>{};
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
        await cache.set('viewers', const <Viewer>[
          Viewer(id: 1, ulid: 'viewer-admin', name: 'Admin', isAdmin: true),
        ]);
        await ResumeService(memory: localMemory).save(
          const Progress(
            viewerId: 'viewer-admin',
            contentType: ContentType.vod,
            streamId: 902,
            positionSeconds: 91,
            durationSeconds: 600,
            title: 'Cached Movie',
          ),
        );

        final controller = _controller(
          storage: storage,
          cacheMemory: cacheMemory,
          localMemory: localMemory,
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
        expect(controller.activeViewer?.ulid, 'viewer-admin');
        expect(controller.progressList.single.streamId, 902);
        expect(controller.progressList.single.title, 'Cached Movie');
        await boot;

        catalogGate.complete(
          _FakeXtreamTransport.success().responses['get_live_categories'],
        );
        for (var pumpCount = 0; pumpCount < 5; pumpCount += 1) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(controller.liveCategories.single.name, 'News');
        expect(controller.channels.single.name, 'BBC One');
      },
    );

    test(
      'cached Xtream boot refreshes remote progress before catalog refresh finishes',
      () async {
        final storage = InMemorySecureStorage();
        final cacheMemory = <String, Object?>{};
        final catalogGate = Completer<Object?>();
        final recentlyWatchedGate = Completer<Object?>();
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
        await cache.set('viewers', const <Viewer>[
          Viewer(id: 1, ulid: 'viewer-admin', name: 'Admin', isAdmin: true),
        ]);

        final controller = _controller(
          storage: storage,
          cacheMemory: cacheMemory,
          transport: _FakeXtreamTransport.success()
              .withResponse('get_live_categories', catalogGate.future)
              .withResponse('get_recently_watched', recentlyWatchedGate.future)
              .call,
        );

        final boot = controller.boot();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.channels.single.name, 'Cached BBC');
        expect(controller.progressList, isEmpty);

        recentlyWatchedGate.complete(<Map<String, Object?>>[
          <String, Object?>{
            'content_type': 'vod',
            'stream_id': 902,
            'position_seconds': 121,
            'duration_seconds': 600,
            'title': 'Remote Cached Movie',
          },
        ]);
        for (var pumpCount = 0; pumpCount < 5; pumpCount += 1) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(controller.progressList.single.streamId, 902);
        expect(controller.progressList.single.title, 'Remote Cached Movie');
        expect(controller.channels.single.name, 'Cached BBC');

        await boot;
        catalogGate.complete(
          _FakeXtreamTransport.success().responses['get_live_categories'],
        );
      },
    );

    test('Xtream progress is visible before EPG refresh finishes', () async {
      final storage = InMemorySecureStorage();
      final epgGate = Completer<Object?>();
      final controller = _controller(
        storage: storage,
        transport: _FakeXtreamTransport.success()
            .withResponse('get_recently_watched', <Map<String, Object?>>[
              <String, Object?>{
                'content_type': 'vod',
                'stream_id': 201,
                'position_seconds': 91,
                'duration_seconds': 600,
                'title': 'Big Buck Bunny',
              },
            ])
            .withResponse('get_epg_batch', epgGate.future)
            .call,
      );
      addTearDown(controller.dispose);

      final connect = controller.connectXtream(
        const UserCredentials(
          server: 'https://fixture.example',
          username: 'fixture-user',
          password: 'fixture-password',
        ),
      );
      for (var pumpCount = 0; pumpCount < 10; pumpCount += 1) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(controller.vodItems.single.name, 'Big Buck Bunny');
      expect(controller.activeViewer?.ulid, 'viewer-admin');
      expect(controller.progressList.single.positionSeconds, 91);

      epgGate.complete(
        _FakeXtreamTransport.success().responses['get_epg_batch'],
      );
      expect(await connect, isTrue);
    });

    testWidgets(
      'saved_source offline boot keeps configured shell and outage actions',
      (tester) async {
        final storage = InMemorySecureStorage();
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

        final controller = _controller(
          storage: storage,
          transport: (request) async {
            throw XtreamHttpException(
              statusCode: 503,
              method: request.method,
              uri: Uri.parse('${request.credentials.server}/player_api.php'),
              reasonPhrase: 'Service Unavailable',
            );
          },
        );

        await tester.pumpWidget(_TestApp(controller: controller));
        await _pumpAppState(tester);

        expect(controller.sourceType, AppSourceType.xtream);
        expect(controller.isConfigured, isTrue);
        expect(
          _visibleText(tester),
          contains('Server is currently unavailable.'),
        );
        expect(
          _visibleText(tester),
          isNot(contains('Please connect to your service in Settings')),
        );
        expect(_sidebarDestination('Settings'), findsOneWidget);

        await _tapSidebarDestination(tester, 'Settings');
        await _pumpAppState(tester);

        expect(find.text('Server is currently unavailable.'), findsWidgets);
        expect(find.text('Retry connection'), findsOneWidget);
        expect(find.text('Edit server settings'), findsOneWidget);
        expect(find.text('Server URL'), findsNothing);
      },
    );

    testWidgets(
      'saved_source boots connected app state without constructor fixtures',
      (tester) async {
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
          transport: _FakeXtreamTransport.success().withResponse(
            'get_recently_watched',
            <Map<String, Object?>>[
              <String, Object?>{
                'content_type': 'vod',
                'stream_id': 201,
                'position_seconds': 91,
                'duration_seconds': 600,
                'title': 'Big Buck Bunny',
              },
            ],
          ).call,
        );
        await restarted.boot();
        await _waitForXtreamRefresh(
          restarted,
          wait: () => tester.pump(const Duration(milliseconds: 10)),
        );

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
      (tester) async {
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
        addTearDown(() => _deleteDirectoryRetrying(directory));
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
            transport: _FakeXtreamTransport.success().withResponse(
              'get_recently_watched',
              <Map<String, Object?>>[
                <String, Object?>{
                  'content_type': 'vod',
                  'stream_id': 201,
                  'position_seconds': 91,
                  'duration_seconds': 600,
                },
              ],
            ).call,
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

    test('newer EPG range wins when an older request completes last', () async {
      final oldRange = Completer<Object?>();
      final newRange = Completer<Object?>();
      final fixture = _FakeXtreamTransport.success();
      Future<Object?> transport(XtreamRequest request) async {
        if (request.action != 'get_epg_batch') return fixture.call(request);
        return switch (request.params['date']) {
          '2026-01-01' => oldRange.future,
          '2026-01-02' => newRange.future,
          _ => <String, Object?>{},
        };
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );

      controller.ensureEpgForChannels(
        controller.channels,
        startDate: DateTime.utc(2026),
        endDate: DateTime.utc(2026),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.ensureEpgForChannels(
        controller.channels,
        startDate: DateTime.utc(2026, 1, 2),
        endDate: DateTime.utc(2026, 1, 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      newRange.complete(_epgResponse('Newer day', DateTime.utc(2026, 1, 2)));
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.epgService.programsForChannel(controller.channels.single),
        hasLength(1),
      );
      expect(
        controller.epgService
            .programsForChannel(controller.channels.single)
            .single
            .title,
        'Newer day',
      );

      oldRange.complete(_epgResponse('Older day', DateTime.utc(2026)));
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.epgService
            .programsForChannel(controller.channels.single)
            .single
            .title,
        'Newer day',
      );
    });

    test(
      'dated browsing preserves current guide when returning to the list',
      () async {
        final now = DateTime.utc(2026, 7, 31, 12);
        final fixture = _FakeXtreamTransport.success();
        var currentGuideRequests = 0;
        Future<Object?> transport(XtreamRequest request) async {
          if (request.action != 'get_epg_batch') return fixture.call(request);
          if (request.params['date'] == null) {
            currentGuideRequests += 1;
            return _epgResponse('Current guide', now);
          }
          return _epgResponse(
            'Yesterday guide',
            now.subtract(const Duration(days: 1)),
          );
        }

        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: transport,
          epgService: EpgService(clock: () => now),
        );
        addTearDown(controller.dispose);
        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        expect(
          controller.epgService
              .lookupForChannel(controller.channels.single)
              ?.current
              .title,
          'Current guide',
        );

        controller.ensureEpgForChannels(
          controller.channels,
          startDate: now.subtract(const Duration(days: 1)),
          endDate: now.subtract(const Duration(days: 1)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        controller.ensureEpgForChannels(controller.channels);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(currentGuideRequests, 1);
        expect(
          controller.epgService
              .lookupForChannel(controller.channels.single)
              ?.current
              .title,
          'Current guide',
        );
      },
    );

    test('failed EPG range is backed off independently', () async {
      final fixture = _FakeXtreamTransport.success();
      var rangedRequests = 0;
      var currentGuideRequests = 0;
      Future<Object?> transport(XtreamRequest request) async {
        if (request.action != 'get_epg_batch') {
          return fixture.call(request);
        }
        if (request.params['date'] == null) {
          currentGuideRequests += 1;
          return <String, Object?>{};
        }
        rangedRequests += 1;
        throw StateError('dated EPG unavailable');
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);
      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );

      final date = DateTime.utc(2026, 7, 30);
      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(rangedRequests, 1);
      controller.ensureEpgForChannels(controller.channels);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(currentGuideRequests, 2);
      expect(
        controller.epgService.hasFreshDataForChannel(
          controller.channels.single,
        ),
        isTrue,
      );
    });

    test(
      'dated EPG range is not fresh after clock rollback and a failed fetch',
      () async {
        var now = DateTime.utc(2026, 7, 30, 12);
        final fixture = _FakeXtreamTransport.success();
        var rangedRequests = 0;
        final secondRangedRequest = Completer<void>();
        Future<Object?> transport(XtreamRequest request) async {
          if (request.action != 'get_epg_batch') return fixture.call(request);
          if (request.params['date'] == null) return <String, Object?>{};
          rangedRequests += 1;
          if (rangedRequests == 2) secondRangedRequest.complete();
          return _epgResponse('Dated guide', now);
        }

        final epgService = EpgService(clock: () => now);
        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: transport,
          epgService: epgService,
        );
        addTearDown(controller.dispose);
        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );

        final firstRangePublished = Completer<void>();
        void onEpgChanged() {
          final channel = controller.channels.single;
          if (!firstRangePublished.isCompleted &&
              epgService
                  .programsForChannel(channel)
                  .any((program) => program.title == 'Dated guide')) {
            firstRangePublished.complete();
          }
        }

        epgService.addListener(onEpgChanged);
        addTearDown(() => epgService.removeListener(onEpgChanged));
        final date = DateTime.utc(2026, 7, 30);
        controller.ensureEpgForChannels(
          controller.channels,
          startDate: date,
          endDate: date,
        );
        await firstRangePublished.future.timeout(const Duration(seconds: 5));
        expect(rangedRequests, 1);

        epgService.markFetchFailed(<String>['bbc.one:2026-07-30:2026-07-30']);
        now = now.subtract(const Duration(minutes: 1));
        controller.ensureEpgForChannels(
          controller.channels,
          startDate: date,
          endDate: date,
        );
        await secondRangedRequest.future.timeout(const Duration(seconds: 5));

        expect(rangedRequests, 2);
      },
    );

    test('dated EPG range uses the configured freshness TTL', () async {
      var now = DateTime.utc(2026, 7, 30, 12);
      final fixture = _FakeXtreamTransport.success();
      var rangedRequests = 0;
      final secondRangedRequest = Completer<void>();
      Future<Object?> transport(XtreamRequest request) async {
        if (request.action != 'get_epg_batch') return fixture.call(request);
        if (request.params['date'] == null) return <String, Object?>{};
        rangedRequests += 1;
        if (rangedRequests == 2) secondRangedRequest.complete();
        return _epgResponse('Dated guide', now);
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
        epgService: EpgService(clock: () => now),
      );
      addTearDown(controller.dispose);
      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'fixture-user',
            password: 'fixture-password',
          ),
        ),
        isTrue,
      );
      await controller.setEpgRefreshInterval(const Duration(minutes: 1));

      final firstRangePublished = Completer<void>();
      void onEpgChanged() {
        final channel = controller.channels.single;
        if (!firstRangePublished.isCompleted &&
            controller.epgService
                .programsForChannel(channel)
                .any((program) => program.title == 'Dated guide')) {
          firstRangePublished.complete();
        }
      }

      controller.epgService.addListener(onEpgChanged);
      addTearDown(
        () => controller.epgService.removeListener(onEpgChanged),
      );
      final date = DateTime.utc(2026, 7, 30);
      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await firstRangePublished.future.timeout(const Duration(seconds: 5));
      now = now.add(const Duration(minutes: 1));
      expect(
        controller.epgService.shouldFetchData(
          'bbc.one:2026-07-30:2026-07-30',
        ),
        isTrue,
      );

      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await secondRangedRequest.future.timeout(const Duration(seconds: 5));

      expect(rangedRequests, 2);
    });

    test(
      'adjacent EPG ranges deduplicate only the overlapping program',
      () async {
        final fixture = _FakeXtreamTransport.success();
        final overlapStart = DateTime.utc(2026, 7, 31);
        Map<String, Object?> response(List<DateTime> starts) => {
          '101': [
            for (final start in starts)
              <String, Object?>{
                'stream_id': 101,
                'title': 'Daily News',
                'description': 'Fixture',
                'start': start.toIso8601String(),
                'end': start.add(const Duration(hours: 1)).toIso8601String(),
              },
          ],
        };
        Future<Object?> transport(XtreamRequest request) async {
          if (request.action != 'get_epg_batch') return fixture.call(request);
          return switch (request.params['date']) {
            '2026-07-30' => response([
              DateTime.utc(2026, 7, 30, 10),
              overlapStart,
            ]),
            '2026-07-31' => response([
              overlapStart,
              DateTime.utc(2026, 7, 31, 10),
            ]),
            _ => <String, Object?>{},
          };
        }

        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: transport,
        );
        addTearDown(controller.dispose);
        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );

        for (final date in [
          DateTime.utc(2026, 7, 30),
          DateTime.utc(2026, 7, 31),
        ]) {
          controller.ensureEpgForChannels(
            controller.channels,
            startDate: date,
            endDate: date,
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }

        final programs = controller.epgService.programsForChannel(
          controller.channels.single,
        );
        expect(programs, hasLength(3));
        expect(
          programs.where((program) => program.title == 'Daily News'),
          hasLength(3),
        );
        expect(
          programs.where((program) => program.start == overlapStart),
          hasLength(1),
        );
      },
    );

    test('ranged EPG freshness is isolated between Xtream sessions', () async {
      final fixture = _FakeXtreamTransport.success();
      final rangedRequestUsers = <String>[];
      Future<Object?> transport(XtreamRequest request) async {
        if (request.action != 'get_epg_batch') return fixture.call(request);
        if (request.params['date'] == null) return <String, Object?>{};
        rangedRequestUsers.add(request.credentials.username);
        return _epgResponse(
          '${request.credentials.username} guide',
          DateTime.utc(2026, 7, 30, 12),
        );
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);
      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'provider-a',
            password: 'provider-a-password',
          ),
        ),
        isTrue,
      );

      final date = DateTime.utc(2026, 7, 30);
      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        controller.epgService
            .programsForChannel(controller.channels.single)
            .single
            .title,
        'provider-a guide',
      );

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'provider-b',
            password: 'provider-b-password',
          ),
        ),
        isTrue,
      );
      expect(
        controller.epgService.programsForChannel(controller.channels.single),
        isEmpty,
      );

      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(rangedRequestUsers, <String>['provider-a', 'provider-b']);
      expect(
        controller.epgService
            .programsForChannel(controller.channels.single)
            .single
            .title,
        'provider-b guide',
      );
    });

    test('old Xtream range completion cannot update a new session', () async {
      final fixture = _FakeXtreamTransport.success();
      final oldRange = Completer<Object?>();
      final newRange = Completer<Object?>();
      Future<Object?> transport(XtreamRequest request) async {
        if (request.action != 'get_epg_batch') return fixture.call(request);
        if (request.params['date'] == null) return <String, Object?>{};
        return request.credentials.username == 'provider-a'
            ? oldRange.future
            : newRange.future;
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);
      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'provider-a',
            password: 'provider-a-password',
          ),
        ),
        isTrue,
      );

      final date = DateTime.utc(2026, 7, 30);
      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'provider-b',
            password: 'provider-b-password',
          ),
        ),
        isTrue,
      );
      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      newRange.complete(
        _epgResponse('Provider B guide', DateTime.utc(2026, 7, 30, 12)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.epgService
            .programsForChannel(controller.channels.single)
            .single
            .title,
        'Provider B guide',
      );

      oldRange.complete(
        _epgResponse('Provider A guide', DateTime.utc(2026, 7, 30, 12)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        controller.epgService
            .programsForChannel(controller.channels.single)
            .single
            .title,
        'Provider B guide',
      );
    });

    test('old Xtream range failure cannot back off a new session', () async {
      final fixture = _FakeXtreamTransport.success();
      final oldRange = Completer<Object?>();
      var newSessionRequests = 0;
      Future<Object?> transport(XtreamRequest request) async {
        if (request.action != 'get_epg_batch') return fixture.call(request);
        if (request.params['date'] == null) return <String, Object?>{};
        if (request.credentials.username == 'provider-a') {
          return oldRange.future;
        }
        newSessionRequests += 1;
        return _epgResponse('Provider B guide', DateTime.utc(2026, 7, 30, 12));
      }

      final controller = _controller(
        storage: InMemorySecureStorage(),
        transport: transport,
      );
      addTearDown(controller.dispose);
      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'provider-a',
            password: 'provider-a-password',
          ),
        ),
        isTrue,
      );

      final date = DateTime.utc(2026, 7, 30);
      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        await controller.connectXtream(
          const UserCredentials(
            server: 'https://fixture.example',
            username: 'provider-b',
            password: 'provider-b-password',
          ),
        ),
        isTrue,
      );
      oldRange.completeError(StateError('Provider A guide failed'));
      await Future<void>.delayed(Duration.zero);

      controller.ensureEpgForChannels(
        controller.channels,
        startDate: date,
        endDate: date,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(newSessionRequests, 1);
      expect(
        controller.epgService
            .programsForChannel(controller.channels.single)
            .single
            .title,
        'Provider B guide',
      );
    });
  });

  group('DVR storage refresh', () {
    const credentials = UserCredentials(
      server: 'https://fixture.example',
      username: 'fixture-user',
      password: 'fixture-password',
    );

    _FakeXtreamTransport withDvrFeature(_FakeXtreamTransport base) {
      return base.withResponse('auth', <String, Object?>{
        'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
        'm3u_editor': <String, Object?>{
          'version': '0.10.0',
          'features': <String>['dvr'],
        },
      });
    }

    test(
      'populates dvrStorageInfo from a server that supports get_dvr_storage',
      () async {
        final fixture =
            withDvrFeature(
              _FakeXtreamTransport.success(),
            ).withResponse('get_dvr_storage', <String, Object?>{
              'used_bytes': 2147483648,
              'quota_bytes': 4294967296,
              'percent_used': 50.0,
              'recording_count': 4,
              'scope': 'account',
            });
        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: fixture.call,
        );

        expect(await controller.connectXtream(credentials), isTrue);
        expect(controller.hasDvrFeature, isTrue);

        await controller.refreshDvrStorage();

        expect(controller.dvrStorageInfo?.usedBytes, 2147483648);
        expect(controller.dvrStorageInfo?.quotaBytes, 4294967296);
        expect(controller.dvrStorageInfo?.recordingCount, 4);
      },
    );

    test(
      'clears dvrStorageInfo when an older server has no get_dvr_storage action',
      () async {
        // No `get_dvr_storage` stub, so the fixture throws StateError for it
        // — mirroring an older m3u-editor server that 404s the action.
        final fixture = withDvrFeature(_FakeXtreamTransport.success());
        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: fixture.call,
        );

        expect(await controller.connectXtream(credentials), isTrue);
        expect(controller.hasDvrFeature, isTrue);

        await controller.refreshDvrStorage();

        expect(controller.dvrStorageInfo, isNull);
      },
    );

    test(
      'does not call get_dvr_storage when the dvr feature is not advertised',
      () async {
        final base = _FakeXtreamTransport.success();
        final calledActions = <String>[];
        Future<Object?> spyingTransport(XtreamRequest request) async {
          calledActions.add(request.action ?? 'auth');
          return base.call(request);
        }

        final controller = _controller(
          storage: InMemorySecureStorage(),
          transport: spyingTransport,
        );

        expect(await controller.connectXtream(credentials), isTrue);
        expect(controller.hasDvrFeature, isFalse);
        calledActions.clear();

        await controller.refreshDvrStorage();

        expect(calledActions, isEmpty);
        expect(controller.dvrStorageInfo, isNull);
      },
    );
  });
}

Map<String, Object?> _epgResponse(String title, DateTime start) => {
  '101': <Map<String, Object?>>[
    <String, Object?>{
      'stream_id': 101,
      'title': title,
      'description': 'Fixture',
      'start': start.toIso8601String(),
      'end': start.add(const Duration(minutes: 30)).toIso8601String(),
    },
  ],
};

AppStateController _controller({
  required InMemorySecureStorage storage,
  required XtreamTransport transport,
  Map<String, Object?>? cacheMemory,
  Map<String, Object?>? localMemory,
  EpgService? epgService,
}) {
  final sharedLocalMemory = localMemory ?? <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport,
      cache: CacheService(memory: cacheMemory ?? <String, Object?>{}),
    ),
    secureStorage: storage,
    cacheService: CacheService(memory: cacheMemory ?? <String, Object?>{}),
    epgService: epgService,
    favoritesService: FavoritesService(memory: sharedLocalMemory),
    resumeService: ResumeService(memory: sharedLocalMemory),
    viewerService: ViewerService(memory: sharedLocalMemory),
  );
}

// PersistentJsonStore serializes writes onto its own internal queue rather
// than requiring every caller to await them (several services share one
// store and fire-and-forget on construction, e.g. ProxyPlaybackSettings.load
// in AppStateController). One of those can still be mid-write (temp file ->
// delete -> rename) when this teardown runs, so a plain recursive delete can
// hit ENOTEMPTY if a file reappears between listing and removal. Retry a few
// times rather than making every service await its store writes just for
// test cleanup.
Future<void> _deleteDirectoryRetrying(io.Directory directory) async {
  for (var attempt = 0; attempt < 5; attempt += 1) {
    try {
      await directory.delete(recursive: true);
      return;
    } on io.FileSystemException {
      if (attempt == 4) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

String _visibleText(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .join('\n');
}

Future<void> _pumpAppState(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _waitForXtreamRefresh(
  AppStateController controller, {
  Future<void> Function()? wait,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final hasEpg =
        controller.channels.isNotEmpty &&
        controller.epgService.lookupForChannel(controller.channels.single) !=
            null;
    if (hasEpg &&
        controller.activeViewer != null &&
        controller.progressList.isNotEmpty) {
      return;
    }
    await (wait?.call() ??
        Future<void>.delayed(const Duration(milliseconds: 10)));
  }
}

Map<String, Object?> _epgBatch(String title, DateTime now) => <String, Object?>{
  '101': <Map<String, Object?>>[
    <String, Object?>{
      'stream_id': 101,
      'title': base64Encode(utf8.encode(title)),
      'description': '',
      'start_timestamp':
          now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/
          1000,
      'stop_timestamp':
          now.add(const Duration(minutes: 20)).millisecondsSinceEpoch ~/ 1000,
    },
  ],
};

Finder _sidebarDestination(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is SidebarDestinationItem && widget.label == label,
  );
}

Future<void> _tapSidebarDestination(WidgetTester tester, String label) async {
  await tester.tap(_sidebarDestination(label));
}

class _TestApp extends StatefulWidget {
  const _TestApp({required this.controller});

  final AppStateController controller;

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  late final GoRouter _router = createGoRouter(
    appState: widget.controller,
    nativeTelevisionHint: false,
    deviceTypeOverride: DeviceType.tv,
  );

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [overrideAppState(widget.controller)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: ThemeData.dark(useMaterial3: true),
        routerConfig: _router,
      ),
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
