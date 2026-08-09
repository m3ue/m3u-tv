import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('FavoritesService remote sync primitives', () {
    test('applyRemote adds/removes without invoking onChanged', () async {
      final service = FavoritesService(memory: <String, Object?>{});
      final pushed = <String>[];
      service.onChanged = (streamId, {required favorited}) =>
          pushed.add('$streamId:$favorited');

      await service.applyRemote(101, favorited: true);
      expect(await service.all(), <int>{101});
      expect(pushed, isEmpty);

      await service.applyRemote(101, favorited: false);
      expect(await service.all(), isEmpty);
      expect(pushed, isEmpty);
    });

    test(
      'replaceAll overwrites the local set without invoking onChanged',
      () async {
        final service = FavoritesService(memory: <String, Object?>{});
        final pushed = <String>[];
        service.onChanged = (streamId, {required favorited}) =>
            pushed.add('$streamId:$favorited');
        await service.add(1);

        await service.replaceAll(<int>{2, 3});

        expect(await service.all(), <int>{2, 3});
        expect(pushed, <String>['1:true']);
      },
    );

    test(
      'add/remove still invoke onChanged for local UI-driven toggles',
      () async {
        final service = FavoritesService(memory: <String, Object?>{});
        final pushed = <String>[];
        service.onChanged = (streamId, {required favorited}) =>
            pushed.add('$streamId:$favorited');

        await service.add(5);
        await service.remove(5);

        expect(pushed, <String>['5:true', '5:false']);
      },
    );

    test('listener ownership change suppresses the server callback', () async {
      var current = true;
      var notifications = 0;
      var serverCallbacks = 0;
      final service = FavoritesService(memory: <String, Object?>{})
        ..captureMutationOwnership = (() =>
            () => current)
        ..addListener(() {
          notifications += 1;
          current = false;
        })
        ..onChanged = (_, {required favorited}) => serverCallbacks += 1;

      await service.add(5);

      expect(notifications, 1);
      expect(serverCallbacks, 0);
    });
  });

  group('AIOStreamsFavoritesService remote sync primitives', () {
    const item = AIOStreamsFavoriteItem(
      id: 'tt0111161',
      type: 'movie',
      name: 'The Shawshank Redemption',
      integrationId: 7,
      poster: 'https://example.com/poster.jpg',
    );

    test('add/remove invoke onAdded/onRemoved', () async {
      final service = AIOStreamsFavoritesService();
      final added = <String>[];
      final removed = <String>[];
      service
        ..onAdded = (i) {
          added.add(i.id);
        }
        ..onRemoved = removed.add;

      await service.add(item);
      await service.remove(item.id);

      expect(added, <String>['tt0111161']);
      expect(removed, <String>['tt0111161']);
    });

    test(
      'applyRemote stores full metadata for a remote add without invoking onAdded',
      () async {
        final service = AIOStreamsFavoritesService();
        final added = <String>[];
        service.onAdded = (i) => added.add(i.id);

        await service.applyRemote(item.id, favorited: true, item: item);

        final all = await service.all();
        expect(all, hasLength(1));
        expect(all.single.name, 'The Shawshank Redemption');
        expect(added, isEmpty);
      },
    );

    test(
      'applyRemote drops a remote add with no metadata rather than storing a bare id',
      () async {
        final service = AIOStreamsFavoritesService();
        await service.applyRemote(item.id, favorited: true);
        expect(await service.all(), isEmpty);
      },
    );

    test(
      'replaceAll overwrites the full local set without invoking callbacks',
      () async {
        final service = AIOStreamsFavoritesService();
        final added = <String>[];
        service.onAdded = (i) => added.add(i.id);
        await service.add(item);

        const other = AIOStreamsFavoriteItem(
          id: 'tt9999999',
          type: 'series',
          name: 'Other Show',
          integrationId: 3,
        );
        await service.replaceAll(<AIOStreamsFavoriteItem>[other]);

        final all = await service.all();
        expect(all.map((i) => i.id), <String>['tt9999999']);
        expect(added, <String>['tt0111161']);
      },
    );

    test('local add failure keeps committed cache unpublished', () async {
      const prior = AIOStreamsFavoriteItem(
        id: 'tt9999999',
        type: 'series',
        name: 'Prior Show',
        integrationId: 3,
      );
      final store = _ControlledFavoritesStore();
      await store.write('aio_favorites', <String, Object?>{
        prior.id: prior.toJson(),
      });
      final service = AIOStreamsFavoritesService(store: store);
      expect((await service.all()).map((favorite) => favorite.id), <String>[
        prior.id,
      ]);
      var notifications = 0;
      var added = 0;
      service
        ..addListener(() => notifications += 1)
        ..onAdded = (_) => added += 1;
      final write = store.blockNextWrite(fail: true);

      final add = service.add(item);
      await write.started.future;
      final visibleWhileBlocked = (await service.all())
          .map((favorite) => favorite.id)
          .toSet();
      final persistedWhileBlocked = _persistedFavoriteIds(
        await store.snapshot(),
      );
      write.release.complete();
      await expectLater(add, throwsA(isA<StateError>()));

      expect(
        <String, Set<Object?>>{
          'visible while blocked': visibleWhileBlocked,
          'persisted while blocked': persistedWhileBlocked,
          'visible after failure': (await service.all())
              .map((favorite) => favorite.id)
              .toSet(),
          'persisted after failure': _persistedFavoriteIds(
            await store.snapshot(),
          ),
        },
        <String, Set<Object?>>{
          'visible while blocked': <String>{prior.id},
          'persisted while blocked': <String>{prior.id},
          'visible after failure': <String>{prior.id},
          'persisted after failure': <String>{prior.id},
        },
      );
      expect(notifications, 0);
      expect(added, 0);
    });

    test('local add publishes once after persistence succeeds', () async {
      const prior = AIOStreamsFavoriteItem(
        id: 'tt9999999',
        type: 'series',
        name: 'Prior Show',
        integrationId: 3,
      );
      final store = _ControlledFavoritesStore();
      await store.write('aio_favorites', <String, Object?>{
        prior.id: prior.toJson(),
      });
      final service = AIOStreamsFavoritesService(store: store);
      await service.all();
      final events = <String>[];
      service
        ..addListener(() => events.add('listener'))
        ..onAdded = (favorite) => events.add('added:${favorite.id}');
      final write = store.blockNextWrite(fail: false);

      final add = service.add(item);
      await write.started.future;
      expect(await service.isFavorite(item.id), isFalse);
      expect(await _favoriteIds(service), <String>[prior.id]);
      expect(_persistedFavoriteIds(await store.snapshot()), <String>{prior.id});
      expect(events, isEmpty);

      write.release.complete();
      await add;

      expect(
        (await service.all()).map((favorite) => favorite.id),
        <String>[item.id, prior.id],
      );
      expect(await service.isFavorite(item.id), isTrue);
      expect(
        (await store.snapshot())['aio_favorites'],
        <String, Object?>{prior.id: prior.toJson(), item.id: item.toJson()},
      );
      expect(events, <String>['listener', 'added:${item.id}']);
    });

    test('local remove failure keeps committed cache published', () async {
      const prior = AIOStreamsFavoriteItem(
        id: 'tt9999999',
        type: 'series',
        name: 'Prior Show',
        integrationId: 3,
      );
      final store = _ControlledFavoritesStore();
      await store.write('aio_favorites', <String, Object?>{
        prior.id: prior.toJson(),
        item.id: item.toJson(),
      });
      final service = AIOStreamsFavoritesService(store: store);
      await service.all();
      var notifications = 0;
      var removed = 0;
      service
        ..addListener(() => notifications += 1)
        ..onRemoved = (_) => removed += 1;
      final write = store.blockNextWrite(fail: true);

      final remove = service.remove(item.id);
      await write.started.future;
      expect(await service.isFavorite(item.id), isTrue);
      expect(_persistedFavoriteIds(await store.snapshot()), <String>{
        prior.id,
        item.id,
      });
      write.release.complete();
      await expectLater(remove, throwsA(isA<StateError>()));

      expect(await service.isFavorite(item.id), isTrue);
      expect(_persistedFavoriteIds(await store.snapshot()), <String>{
        prior.id,
        item.id,
      });
      expect(notifications, 0);
      expect(removed, 0);
    });

    test('local remove publishes once after persistence succeeds', () async {
      const prior = AIOStreamsFavoriteItem(
        id: 'tt9999999',
        type: 'series',
        name: 'Prior Show',
        integrationId: 3,
      );
      final store = _ControlledFavoritesStore();
      await store.write('aio_favorites', <String, Object?>{
        prior.id: prior.toJson(),
        item.id: item.toJson(),
      });
      final service = AIOStreamsFavoritesService(store: store);
      await service.all();
      final events = <String>[];
      service
        ..addListener(() => events.add('listener'))
        ..onRemoved = (itemId) => events.add('removed:$itemId');
      final write = store.blockNextWrite(fail: false);

      final remove = service.remove(item.id);
      await write.started.future;
      expect(await service.isFavorite(item.id), isTrue);
      expect(events, isEmpty);

      write.release.complete();
      await remove;

      expect(await _favoriteIds(service), <String>[prior.id]);
      expect(await service.isFavorite(item.id), isFalse);
      expect(_persistedFavoriteIds(await store.snapshot()), <String>{prior.id});
      expect(events, <String>['listener', 'removed:${item.id}']);
    });

    test(
      'toggle completes through one queued copy-on-write mutation',
      () async {
        final store = _ControlledFavoritesStore();
        await store.write('aio_favorites', <String, Object?>{});
        final service = AIOStreamsFavoritesService(store: store);
        await service.all();
        final events = <String>[];
        service
          ..onAdded = (favorite) {
            events.add('added:${favorite.id}');
          }
          ..onRemoved = (itemId) => events.add('removed:$itemId');
        final write = store.blockNextWrite(fail: false);

        final added = service.toggle(item);
        await write.started.future;
        expect(await service.isFavorite(item.id), isFalse);
        write.release.complete();
        expect(
          await added.timeout(const Duration(seconds: 1)),
          isTrue,
        );
        expect(await service.isFavorite(item.id), isTrue);

        expect(
          await service.toggle(item).timeout(const Duration(seconds: 1)),
          isFalse,
        );
        expect(await service.isFavorite(item.id), isFalse);
        expect(events, <String>['added:${item.id}', 'removed:${item.id}']);
      },
    );

    test(
      'remote changes publish after persistence without local callbacks',
      () async {
        const prior = AIOStreamsFavoriteItem(
          id: 'tt9999999',
          type: 'series',
          name: 'Prior Show',
          integrationId: 3,
        );
        final store = _ControlledFavoritesStore();
        await store.write('aio_favorites', <String, Object?>{
          prior.id: prior.toJson(),
        });
        final service = AIOStreamsFavoritesService(store: store);
        await service.all();
        var notifications = 0;
        var localCallbacks = 0;
        service
          ..addListener(() => notifications += 1)
          ..onAdded = (_) {
            localCallbacks += 1;
          }
          ..onRemoved = (_) => localCallbacks += 1;

        final addWrite = store.blockNextWrite(fail: false);
        final add = service.applyRemote(item.id, favorited: true, item: item);
        await addWrite.started.future;
        expect(await service.isFavorite(item.id), isFalse);
        expect(notifications, 0);
        addWrite.release.complete();
        await add;
        expect(await service.isFavorite(item.id), isTrue);
        expect(notifications, 1);

        final removeWrite = store.blockNextWrite(fail: false);
        final remove = service.applyRemote(item.id, favorited: false);
        await removeWrite.started.future;
        expect(await service.isFavorite(item.id), isTrue);
        expect(notifications, 1);
        removeWrite.release.complete();
        await remove;

        expect(await _favoriteIds(service), <String>[prior.id]);
        expect(_persistedFavoriteIds(await store.snapshot()), <String>{
          prior.id,
        });
        expect(notifications, 2);
        expect(localCallbacks, 0);
      },
    );

    test('remote add failure leaves committed state unchanged', () async {
      const prior = AIOStreamsFavoriteItem(
        id: 'tt9999999',
        type: 'series',
        name: 'Prior Show',
        integrationId: 3,
      );
      final store = _ControlledFavoritesStore();
      await store.write('aio_favorites', <String, Object?>{
        prior.id: prior.toJson(),
      });
      final service = AIOStreamsFavoritesService(store: store);
      await service.all();
      var notifications = 0;
      service.addListener(() => notifications += 1);
      final write = store.blockNextWrite(fail: true);

      final add = service.applyRemote(item.id, favorited: true, item: item);
      await write.started.future;
      expect(await service.isFavorite(item.id), isFalse);
      write.release.complete();
      await expectLater(add, throwsA(isA<StateError>()));

      expect(await _favoriteIds(service), <String>[prior.id]);
      expect(_persistedFavoriteIds(await store.snapshot()), <String>{prior.id});
      expect(notifications, 0);
    });

    test(
      'unconditional replacement publishes only after persistence',
      () async {
        const prior = AIOStreamsFavoriteItem(
          id: 'tt9999999',
          type: 'series',
          name: 'Prior Show',
          integrationId: 3,
        );
        final store = _ControlledFavoritesStore();
        await store.write('aio_favorites', <String, Object?>{
          prior.id: prior.toJson(),
        });
        final service = AIOStreamsFavoritesService(store: store);
        await service.all();
        var notifications = 0;
        var localCallbacks = 0;
        service
          ..addListener(() => notifications += 1)
          ..onAdded = (_) {
            localCallbacks += 1;
          }
          ..onRemoved = (_) => localCallbacks += 1;

        final failedWrite = store.blockNextWrite(fail: true);
        final failedReplacement = service.replaceAll(<AIOStreamsFavoriteItem>[
          item,
        ]);
        await failedWrite.started.future;
        expect(await _favoriteIds(service), <String>[prior.id]);
        failedWrite.release.complete();
        await expectLater(failedReplacement, throwsA(isA<StateError>()));
        expect(await _favoriteIds(service), <String>[prior.id]);
        expect(notifications, 0);

        final successfulWrite = store.blockNextWrite(fail: false);
        final successfulReplacement = service.replaceAll(
          <AIOStreamsFavoriteItem>[item],
        );
        await successfulWrite.started.future;
        expect(await _favoriteIds(service), <String>[prior.id]);
        expect(notifications, 0);
        successfulWrite.release.complete();
        expect(await successfulReplacement, isTrue);

        expect(await _favoriteIds(service), <String>[item.id]);
        expect(
          (await store.snapshot())['aio_favorites'],
          <String, Object?>{item.id: item.toJson()},
        );
        expect(notifications, 1);
        expect(localCallbacks, 0);
      },
    );

    test('conditional replacement checks ownership before writing', () async {
      final store = _ControlledFavoritesStore();
      await store.write('aio_favorites', <String, Object?>{
        item.id: item.toJson(),
      });
      final service = AIOStreamsFavoritesService(store: store);
      await service.all();
      var checks = 0;
      var notifications = 0;
      service.addListener(() => notifications += 1);

      expect(
        await service.replaceAll(
          const <AIOStreamsFavoriteItem>[],
          shouldCommit: () {
            checks += 1;
            return false;
          },
        ),
        isFalse,
      );

      expect(checks, 1);
      expect(await _favoriteIds(service), <String>[item.id]);
      expect(_persistedFavoriteIds(await store.snapshot()), <String>{item.id});
      expect(notifications, 0);
    });

    test('conditional replacement rolls back stale persisted work', () async {
      const remote = AIOStreamsFavoriteItem(
        id: 'tt9999999',
        type: 'series',
        name: 'Remote Show',
        integrationId: 3,
      );
      final store = _ControlledFavoritesStore();
      await store.write('aio_favorites', <String, Object?>{
        item.id: item.toJson(),
      });
      final service = AIOStreamsFavoritesService(store: store);
      await service.all();
      var current = true;
      var checks = 0;
      var notifications = 0;
      service.addListener(() => notifications += 1);

      final replacement = service.replaceAll(
        const <AIOStreamsFavoriteItem>[remote],
        shouldCommit: () {
          checks += 1;
          return current;
        },
      );
      await store.conditionalWriteStarted.future;
      current = false;
      store.releaseConditionalWrite.complete();

      expect(await replacement, isFalse);
      expect(checks, 2);
      expect(await _favoriteIds(service), <String>[item.id]);
      expect(_persistedFavoriteIds(await store.snapshot()), <String>{item.id});
      expect(notifications, 0);
    });

    test(
      'local add survives a pending conditional replacement',
      () async {
        const remote = AIOStreamsFavoriteItem(
          id: 'tt9999999',
          type: 'series',
          name: 'Remote Show',
          integrationId: 3,
        );
        final store = _ControlledFavoritesStore();
        final service = AIOStreamsFavoritesService(store: store);
        await service.all();

        final replacement = service.replaceAll(
          const <AIOStreamsFavoriteItem>[remote],
          shouldCommit: () => true,
        );
        await store.conditionalWriteStarted.future;

        final localAdd = service.add(item);
        await pumpEventQueue();
        store.releaseConditionalWrite.complete();
        await replacement;
        await localAdd;

        final visibleIds = (await service.all())
            .map((favorite) => favorite.id)
            .toSet();
        final persisted = await store.snapshot();
        final persistedIds =
            (persisted['aio_favorites']! as Map<Object?, Object?>).keys.toSet();
        expect(
          <String, Set<Object?>>{
            'visible': visibleIds,
            'persisted': persistedIds,
          },
          <String, Set<Object?>>{
            'visible': <String>{remote.id, item.id},
            'persisted': <String>{remote.id, item.id},
          },
        );
      },
    );
  });

  group('AppStateController favorites server sync', () {
    test(
      'connecting as admin with pre-existing local favorites syncs them to the server',
      () async {
        final memory = <String, Object?>{};
        final transport = _FakeXtreamTransport();
        final controller = _controller(memory: memory, transport: transport);
        addTearDown(controller.dispose);

        await controller.favoritesService.add(101);
        await controller.vodFavoritesService.add(201);
        await controller.seriesFavoritesService.add(301);
        await controller.aioFavoritesService.add(
          const AIOStreamsFavoriteItem(
            id: 'tt0111161',
            type: 'movie',
            name: 'The Shawshank Redemption',
            integrationId: 7,
            poster: 'https://example.com/poster.jpg',
          ),
        );
        // The adds above happened before any server connection, so no push
        // was attempted yet — connecting now should sync_favorites once.
        transport.requests.clear();

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
        await pumpEventQueue();

        final syncRequest = transport.requests.singleWhere(
          (r) => r.action == 'sync_favorites',
        );
        final favorites =
            syncRequest.body['favorites']! as List<Map<String, Object?>>;
        expect(favorites, hasLength(4));
        expect(
          favorites.map((f) => f['content_type']),
          containsAll(<String>['live', 'vod', 'series', 'aiostreams']),
        );

        // Server response (fixture) is authoritative from here on.
        expect(await controller.favoritesService.all(), <int>{101, 999});
        expect(await controller.aioFavoritesService.all(), hasLength(1));
        expect(
          (await controller.aioFavoritesService.all()).single.name,
          'Server Title',
        );
      },
    );

    test(
      'connecting a second source does not upload favorites cached from the first source',
      () async {
        final memory = <String, Object?>{};
        final transport = _FakeXtreamTransport();
        final controller = _controller(memory: memory, transport: transport);
        addTearDown(controller.dispose);
        await controller.favoritesService.add(101);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://source-a.example',
              username: 'source-a',
              password: 'source-a-password',
            ),
          ),
          isTrue,
        );
        await pumpEventQueue();
        expect(
          transport.requests.where((r) => r.action == 'sync_favorites'),
          hasLength(1),
        );
        transport.requests.clear();

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://source-b.example',
              username: 'source-b',
              password: 'source-b-password',
            ),
          ),
          isTrue,
        );
        await pumpEventQueue();

        expect(
          transport.requests.where((r) => r.action == 'sync_favorites'),
          isEmpty,
        );
        expect(await controller.favoritesService.all(), isEmpty);
      },
    );

    test(
      'publishing a second source never exposes the first source favorites',
      () async {
        const sourceBFavorites = <Map<String, Object?>>[
          <String, Object?>{'content_type': 'live', 'stream_id': 202},
          <String, Object?>{'content_type': 'vod', 'stream_id': 302},
          <String, Object?>{'content_type': 'series', 'stream_id': 402},
          <String, Object?>{
            'content_type': 'aiostreams',
            'aio_item_id': 'tt2222222',
            'title': 'Source B Title',
            'thumbnail_url': 'https://source-b.example/poster.jpg',
            'item_type': 'movie',
            'aio_integration_id': 22,
          },
        ];
        final transport = _FakeXtreamTransport()
          ..liveStreamsByUsername['source-a'] = const <Map<String, Object?>>[
            <String, Object?>{'stream_id': 101, 'name': 'Source A Channel'},
          ]
          ..liveStreamsByUsername['source-b'] = const <Map<String, Object?>>[
            <String, Object?>{'stream_id': 202, 'name': 'Source B Channel'},
          ]
          ..favoritesByViewer['viewer-source-b'] = sourceBFavorites
          ..blockFavoritesFor('viewer-source-b');
        addTearDown(() {
          if (!transport.releaseBlockedFavorites.isCompleted) {
            transport.releaseBlockedFavorites.complete();
          }
        });
        final controller = _controller(transport: transport);
        addTearDown(controller.dispose);
        await controller.favoritesService.add(101);
        await controller.vodFavoritesService.add(201);
        await controller.seriesFavoritesService.add(301);
        await controller.aioFavoritesService.add(
          const AIOStreamsFavoriteItem(
            id: 'tt1111111',
            type: 'series',
            name: 'Source A Title',
            integrationId: 11,
            poster: 'https://source-a.example/poster.jpg',
          ),
        );

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://source-a.example',
              username: 'source-a',
              password: 'source-a-password',
            ),
          ),
          isTrue,
        );
        await pumpEventQueue();
        expect(await controller.favoritesService.all(), contains(101));
        expect(await controller.vodFavoritesService.all(), contains(201));
        expect(await controller.seriesFavoritesService.all(), contains(301));
        expect(
          (await controller.aioFavoritesService.all()).map((item) => item.id),
          contains('tt0111161'),
        );
        transport.requests.clear();

        final sourceBPublished = Completer<Map<String, Object?>>();
        var sourceBPublishCaptured = false;
        controller.addListener(() {
          if (controller.activeViewer?.ulid != 'viewer-source-b' ||
              sourceBPublishCaptured) {
            return;
          }
          sourceBPublishCaptured = true;
          final sourceType = controller.sourceType;
          final channelIds = controller.channels
              .map((channel) => channel.id)
              .toList();
          unawaited(
            Future.wait<Object>(<Future<Object>>[
              controller.favoritesService.all(),
              controller.vodFavoritesService.all(),
              controller.seriesFavoritesService.all(),
              controller.aioFavoritesService.all(),
            ]).then((favorites) {
              sourceBPublished.complete(<String, Object?>{
                'sourceType': sourceType,
                'channelIds': channelIds,
                'viewerId': controller.activeViewer?.ulid,
                'live': favorites[0],
                'vod': favorites[1],
                'series': favorites[2],
                'aio': (favorites[3] as List<AIOStreamsFavoriteItem>)
                    .map((item) => item.toJson())
                    .toList(),
              });
            }),
          );
        });

        final sourceBConnect = controller.connectXtream(
          const UserCredentials(
            server: 'https://source-b.example',
            username: 'source-b',
            password: 'source-b-password',
          ),
        );
        await transport.blockedFavoritesStarted.future;
        await pumpEventQueue();
        expect(controller.activeViewer?.ulid, 'viewer-source-a');
        expect(controller.channels.map((channel) => channel.id), <int>[101]);
        expect(await controller.favoritesService.all(), contains(101));
        expect(sourceBPublishCaptured, isFalse);
        expect(
          transport.requests.where(
            (request) => request.action == 'sync_favorites',
          ),
          isEmpty,
        );

        expect(sourceBPublished.isCompleted, isFalse);

        transport.releaseBlockedFavorites.complete();
        expect(await sourceBConnect, isTrue);
        expect(await sourceBPublished.future, <String, Object?>{
          'sourceType': AppSourceType.xtream,
          'channelIds': <int>[202],
          'viewerId': 'viewer-source-b',
          'live': <int>{202},
          'vod': <int>{302},
          'series': <int>{402},
          'aio': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'tt2222222',
              'type': 'movie',
              'name': 'Source B Title',
              'integrationId': 22,
              'poster': 'https://source-b.example/poster.jpg',
            },
          ],
        });
        expect(await controller.favoritesService.all(), <int>{202});
        expect(await controller.vodFavoritesService.all(), <int>{302});
        expect(await controller.seriesFavoritesService.all(), <int>{402});
        expect(
          (await controller.aioFavoritesService.all()).map(
            (item) => item.toJson(),
          ),
          <Map<String, Object?>>[
            <String, Object?>{
              'id': 'tt2222222',
              'type': 'movie',
              'name': 'Source B Title',
              'integrationId': 22,
              'poster': 'https://source-b.example/poster.jpg',
            },
          ],
        );
      },
    );

    test(
      'a current replacement publishes empty favorites when its pull fails',
      () async {
        final transport = _FakeXtreamTransport()
          ..liveStreamsByUsername['source-a'] = const <Map<String, Object?>>[
            <String, Object?>{'stream_id': 101, 'name': 'Source A Channel'},
          ]
          ..liveStreamsByUsername['source-b'] = const <Map<String, Object?>>[
            <String, Object?>{'stream_id': 202, 'name': 'Source B Channel'},
          ]
          ..failingFavoriteViewers.add('viewer-source-b');
        final controller = _controller(transport: transport);
        addTearDown(controller.dispose);
        await controller.favoritesService.add(101);
        await controller.vodFavoritesService.add(201);
        await controller.seriesFavoritesService.add(301);
        await controller.aioFavoritesService.add(
          const AIOStreamsFavoriteItem(
            id: 'tt1111111',
            type: 'series',
            name: 'Source A Title',
            integrationId: 11,
          ),
        );

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://source-a.example',
              username: 'source-a',
              password: 'source-a-password',
            ),
          ),
          isTrue,
        );
        await pumpEventQueue();
        transport.requests.clear();

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://source-b.example',
              username: 'source-b',
              password: 'source-b-password',
            ),
          ),
          isTrue,
        );

        expect(controller.activeViewer?.ulid, 'viewer-source-b');
        expect(controller.channels.map((channel) => channel.id), <int>[202]);
        expect(await controller.favoritesService.all(), isEmpty);
        expect(await controller.vodFavoritesService.all(), isEmpty);
        expect(await controller.seriesFavoritesService.all(), isEmpty);
        expect(await controller.aioFavoritesService.all(), isEmpty);
        expect(
          transport.requests.where(
            (request) => request.action == 'sync_favorites',
          ),
          isEmpty,
        );
      },
    );

    test(
      'toggling a live favorite pushes toggle_favorite to the server',
      () async {
        final transport = _FakeXtreamTransport();
        final controller = _controller(transport: transport);
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
        transport.requests.clear();

        await controller.favoritesService.add(555);
        await pumpEventQueue();

        final request = transport.requests.singleWhere(
          (r) => r.action == 'toggle_favorite',
        );
        expect(request.body['content_type'], 'live');
        expect(request.body['stream_id'], '555');
        expect(request.body['favorited'], 'true');
      },
    );

    for (final contentType in <String>['live', 'vod', 'series']) {
      test(
        'stale remote $contentType mutation cannot persist for a newer viewer',
        () async {
          const staleId = 777;
          const viewerB = Viewer(
            id: 2,
            ulid: 'viewer-b',
            name: 'Viewer B',
            isAdmin: false,
          );
          final transport = _FakeXtreamTransport();
          final store = _BlockingNumericMutationStore();
          final live = FavoritesService(store: store);
          final vod = FavoritesService(store: store, namespace: 'vod');
          final series = FavoritesService(store: store, namespace: 'series');
          final reverb = _RecordingFavoriteReverbService();
          final controller = _controller(
            transport: transport,
            favoritesService: live,
            vodFavoritesService: vod,
            seriesFavoritesService: series,
            reverbService: reverb,
            tvNotificationService: _FavoriteSessionNotificationService(),
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
          await reverb.connected.future;
          await pumpEventQueue();
          transport.blockFavoritesFor(viewerB.ulid);
          final service = switch (contentType) {
            'live' => live,
            'vod' => vod,
            _ => series,
          };
          var notifications = 0;
          service.addListener(() => notifications += 1);
          final write = store.blockNextWrite();

          reverb.emitFavorite(
            FavoriteToggleEvent(
              viewerId: controller.activeViewer!.ulid,
              contentType: contentType,
              streamId: staleId,
              favorited: true,
            ),
          );
          await write.started.future;
          await controller.switchViewer(viewerB);
          await transport.blockedFavoritesStarted.future;
          write.release.complete();
          await write.completed.future;
          await pumpEventQueue();

          expect(controller.activeViewer, viewerB);
          expect(await service.all(), isNot(contains(staleId)));
          expect(
            _persistedNumericFavoriteIds(
              await store.snapshot(),
              contentType,
            ),
            isNot(contains(staleId)),
          );
          expect(notifications, 0);

          transport.releaseBlockedFavorites.complete();
          await pumpEventQueue();
        },
      );

      test(
        'stale local $contentType add cannot target a newer viewer',
        () async {
          await _verifyStaleLocalNumericMutation(
            contentType: contentType,
            mutation: _NumericMutation.add,
          );
        },
      );
      test(
        'stale local $contentType remove cannot target a newer viewer',
        () async {
          await _verifyStaleLocalNumericMutation(
            contentType: contentType,
            mutation: _NumericMutation.remove,
          );
        },
      );
      test(
        'stale local $contentType toggle captures ownership before reading',
        () async {
          await _verifyStaleLocalNumericMutation(
            contentType: contentType,
            mutation: _NumericMutation.toggle,
          );
        },
      );
      test(
        'current owner publishes local and remote $contentType mutations',
        () async {
          const localId = 778;
          const remoteId = 779;
          final transport = _FakeXtreamTransport();
          final store = _BlockingNumericMutationStore();
          final live = FavoritesService(store: store);
          final vod = FavoritesService(store: store, namespace: 'vod');
          final series = FavoritesService(store: store, namespace: 'series');
          final reverb = _RecordingFavoriteReverbService();
          final controller = _controller(
            transport: transport,
            favoritesService: live,
            vodFavoritesService: vod,
            seriesFavoritesService: series,
            reverbService: reverb,
            tvNotificationService: _FavoriteSessionNotificationService(),
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
          await reverb.connected.future;
          await pumpEventQueue();
          final service = switch (contentType) {
            'live' => live,
            'vod' => vod,
            _ => series,
          };
          transport.requests.clear();
          var notifications = 0;
          service.addListener(() => notifications += 1);

          final localWrite = store.blockNextWrite();
          final localMutation = service.add(localId);
          await localWrite.started.future;
          expect(await service.all(), isNot(contains(localId)));
          localWrite.release.complete();
          await localMutation;
          await localWrite.completed.future;
          await pumpEventQueue();

          final remoteWrite = store.blockNextWrite();
          reverb.emitFavorite(
            FavoriteToggleEvent(
              viewerId: controller.activeViewer!.ulid,
              contentType: contentType,
              streamId: remoteId,
              favorited: true,
            ),
          );
          await remoteWrite.started.future;
          remoteWrite.release.complete();
          await remoteWrite.completed.future;
          await pumpEventQueue();

          expect(await service.all(), containsAll(<int>[localId, remoteId]));
          expect(
            _persistedNumericFavoriteIds(
              await store.snapshot(),
              contentType,
            ),
            containsAll(<int>[localId, remoteId]),
          );
          expect(notifications, 2);
          final requests = transport.requests
              .where(
                (request) =>
                    request.action == 'toggle_favorite' &&
                    request.body['stream_id'] == '$localId',
              )
              .toList();
          expect(requests, hasLength(1));
          expect(requests.single.body['viewer_id'], 'viewer-admin');
          expect(
            transport.requests.where(
              (request) => request.body['stream_id'] == '$remoteId',
            ),
            isEmpty,
          );
        },
      );
    }

    test('toggling an AIOStreams favorite pushes its full metadata', () async {
      final transport = _FakeXtreamTransport();
      final store = _BlockingAioMutationStore();
      final aioFavorites = AIOStreamsFavoritesService(store: store);
      final controller = _controller(
        transport: transport,
        aioFavoritesService: aioFavorites,
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
      await pumpEventQueue();
      await aioFavorites.replaceAll(const <AIOStreamsFavoriteItem>[]);
      transport.requests.clear();
      var notifications = 0;
      aioFavorites.addListener(() => notifications += 1);

      const item = AIOStreamsFavoriteItem(
        id: 'tt0111161',
        type: 'movie',
        name: 'The Shawshank Redemption',
        integrationId: 7,
        poster: 'https://example.com/poster.jpg',
      );
      await controller.aioFavoritesService.add(item);
      await pumpEventQueue();

      final request = transport.requests.singleWhere(
        (r) => r.action == 'toggle_favorite',
      );
      expect(request.body['content_type'], 'aiostreams');
      expect(request.body['aio_item_id'], 'tt0111161');
      expect(request.body['title'], 'The Shawshank Redemption');
      expect(request.body['thumbnail_url'], 'https://example.com/poster.jpg');
      expect(request.body['item_type'], 'movie');
      expect(request.body['aio_integration_id'], '7');
      expect(notifications, 1);
      expect(await _favoriteIds(aioFavorites), <String>[item.id]);
      expect(
        _persistedFavoriteIds(await store.snapshot()),
        <String>{item.id},
      );
    });

    for (final remove in <bool>[false, true]) {
      test(
        'stale local AIOStreams ${remove ? 'remove' : 'add'} cannot target a newer viewer',
        () async {
          const prior = AIOStreamsFavoriteItem(
            id: 'tt9999999',
            type: 'series',
            name: 'Prior Show',
            integrationId: 3,
          );
          const item = AIOStreamsFavoriteItem(
            id: 'tt0111161',
            type: 'movie',
            name: 'The Shawshank Redemption',
            integrationId: 7,
            poster: 'https://example.com/poster.jpg',
          );
          const viewerB = Viewer(
            id: 2,
            ulid: 'viewer-b',
            name: 'Viewer B',
            isAdmin: false,
          );
          final transport = _FakeXtreamTransport();
          final store = _BlockingAioMutationStore();
          final aioFavorites = AIOStreamsFavoritesService(store: store);
          final controller = _controller(
            transport: transport,
            aioFavoritesService: aioFavorites,
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
          await pumpEventQueue();
          await aioFavorites.replaceAll(<AIOStreamsFavoriteItem>[
            prior,
            if (remove) item,
          ]);
          final committedIds = <String>{prior.id, if (remove) item.id};
          transport
            ..requests.clear()
            ..blockFavoritesFor(viewerB.ulid);
          var notifications = 0;
          aioFavorites.addListener(() => notifications += 1);
          final write = store.blockNextWrite();

          final mutation = remove
              ? aioFavorites.remove(item.id)
              : aioFavorites.add(item);
          await write.started.future;
          final switchViewer = controller.switchViewer(viewerB);
          await transport.blockedFavoritesStarted.future;
          await switchViewer;
          write.release.complete();
          await mutation;
          await pumpEventQueue();

          final toggleRequests = transport.requests.where(
            (request) => request.action == 'toggle_favorite',
          );
          expect(
            toggleRequests.map((request) => request.body['viewer_id']).toList(),
            isEmpty,
          );
          expect(notifications, 0);
          expect(
            (await aioFavorites.all()).map((favorite) => favorite.id).toSet(),
            committedIds,
          );
          expect(
            _persistedFavoriteIds(await store.snapshot()),
            committedIds,
          );

          transport.releaseBlockedFavorites.complete();
          await pumpEventQueue();
        },
      );
    }
  });
}

enum _NumericMutation { add, remove, toggle }

Future<void> _verifyStaleLocalNumericMutation({
  required String contentType,
  required _NumericMutation mutation,
}) async {
  const staleId = 777;
  const viewerB = Viewer(
    id: 2,
    ulid: 'viewer-b',
    name: 'Viewer B',
    isAdmin: false,
  );
  final transport = _FakeXtreamTransport();
  final store = _BlockingNumericMutationStore();
  final live = FavoritesService(store: store);
  final vod = FavoritesService(store: store, namespace: 'vod');
  final series = FavoritesService(store: store, namespace: 'series');
  final controller = _controller(
    transport: transport,
    favoritesService: live,
    vodFavoritesService: vod,
    seriesFavoritesService: series,
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
  await pumpEventQueue();
  final service = switch (contentType) {
    'live' => live,
    'vod' => vod,
    _ => series,
  };
  if (mutation == _NumericMutation.remove) {
    await service.add(staleId);
    await pumpEventQueue();
  }
  transport
    ..requests.clear()
    ..blockFavoritesFor(viewerB.ulid);
  var notifications = 0;
  service.addListener(() => notifications += 1);
  final write = mutation == _NumericMutation.toggle
      ? null
      : store.blockNextWrite();
  final read = mutation == _NumericMutation.toggle
      ? store.blockNextRead()
      : null;

  final pendingMutation = switch (mutation) {
    _NumericMutation.add => service.add(staleId),
    _NumericMutation.remove => service.remove(staleId),
    _NumericMutation.toggle => service.toggle(staleId),
  };
  await (write?.started.future ?? read!.started.future);
  await controller.switchViewer(viewerB);
  await transport.blockedFavoritesStarted.future;
  write?.release.complete();
  read?.release.complete();
  await pendingMutation;
  if (write != null) await write.completed.future;
  await pumpEventQueue();

  final shouldContain = mutation == _NumericMutation.remove;
  expect((await service.all()).contains(staleId), shouldContain);
  expect(
    _persistedNumericFavoriteIds(
      await store.snapshot(),
      contentType,
    ).contains(staleId),
    shouldContain,
  );
  expect(notifications, 0);
  expect(
    transport.requests.where(
      (request) =>
          request.action == 'toggle_favorite' &&
          request.body['stream_id'] == '$staleId',
    ),
    isEmpty,
  );

  transport.releaseBlockedFavorites.complete();
  await pumpEventQueue();
}

AppStateController _controller({
  Map<String, Object?>? memory,
  required _FakeXtreamTransport transport,
  AIOStreamsFavoritesService? aioFavoritesService,
  FavoritesService? favoritesService,
  FavoritesService? vodFavoritesService,
  FavoritesService? seriesFavoritesService,
  ReverbService? reverbService,
  TvNotificationService? tvNotificationService,
}) {
  final sharedMemory = memory ?? <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport.call,
      cache: CacheService(memory: <String, Object?>{}),
    ),
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    favoritesService:
        favoritesService ?? FavoritesService(memory: sharedMemory),
    vodFavoritesService:
        vodFavoritesService ??
        FavoritesService(memory: sharedMemory, namespace: 'vod'),
    seriesFavoritesService:
        seriesFavoritesService ??
        FavoritesService(memory: sharedMemory, namespace: 'series'),
    aioFavoritesService: aioFavoritesService ?? AIOStreamsFavoritesService(),
    resumeService: ResumeService(memory: sharedMemory),
    viewerService: ViewerService(memory: sharedMemory),
    reverbService: reverbService,
    tvNotificationService: tvNotificationService,
  );
}

class _RecordedRequest {
  _RecordedRequest(this.action, this.body);
  final String action;
  final Map<String, Object?> body;
}

class _FakeXtreamTransport {
  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  final Map<String, List<Map<String, Object?>>> liveStreamsByUsername =
      <String, List<Map<String, Object?>>>{};
  final Map<String, List<Map<String, Object?>>> favoritesByViewer =
      <String, List<Map<String, Object?>>>{};
  final Set<String> failingFavoriteViewers = <String>{};
  final blockedFavoritesStarted = Completer<void>();
  final releaseBlockedFavorites = Completer<void>();
  String? _blockedFavoritesViewer;

  void blockFavoritesFor(String viewerUlid) {
    _blockedFavoritesViewer = viewerUlid;
  }

  Future<Object?> call(XtreamRequest request) async {
    final action = request.action ?? 'auth';
    if (request.method == 'POST') {
      requests.add(_RecordedRequest(action, request.body));
    }
    switch (action) {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{'version': '0.10.0'},
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_recently_watched':
        return const <Object?>[];
      case 'get_live_streams':
        return liveStreamsByUsername[request.credentials.username] ??
            const <Object?>[];
      case 'get_viewers':
        final viewerSuffix = request.credentials.username == 'fixture-user'
            ? 'admin'
            : request.credentials.username;
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'ulid': 'viewer-$viewerSuffix',
            'name': 'Admin',
            'is_admin': true,
          },
        ];
      case 'get_epg_batch':
        return <String, Object?>{};
      case 'get_favorites':
        final viewerId = '${request.params['viewer_id']}';
        if (failingFavoriteViewers.contains(viewerId)) {
          throw StateError('controlled favorites fetch failure');
        }
        if (viewerId == _blockedFavoritesViewer) {
          blockedFavoritesStarted.complete();
          await releaseBlockedFavorites.future;
        }
        return favoritesByViewer[viewerId] ?? const <Object?>[];
      case 'toggle_favorite':
        return <String, Object?>{'favorited': request.body['favorited']};
      case 'sync_favorites':
        return <Map<String, Object?>>[
          <String, Object?>{'content_type': 'live', 'stream_id': 101},
          <String, Object?>{'content_type': 'live', 'stream_id': 999},
          <String, Object?>{'content_type': 'vod', 'stream_id': 201},
          <String, Object?>{'content_type': 'series', 'stream_id': 301},
          <String, Object?>{
            'content_type': 'aiostreams',
            'aio_item_id': 'tt0111161',
            'title': 'Server Title',
            'thumbnail_url': 'https://example.com/server-poster.jpg',
            'item_type': 'movie',
            'aio_integration_id': 7,
          },
        ];
      default:
        throw StateError('No fixture for $action');
    }
  }
}

class _ControlledFavoritesStore extends PersistentJsonStore {
  final conditionalWriteStarted = Completer<void>();
  final releaseConditionalWrite = Completer<void>();
  final _conditionalWriteCompleted = Completer<void>();
  final _data = <String, Object?>{};
  _ControlledWrite? _ordinaryWrite;

  _ControlledWrite blockNextWrite({required bool fail}) {
    final write = _ControlledWrite(fail: fail);
    _ordinaryWrite = write;
    return write;
  }

  @override
  Future<Object?> read(String key) async {
    if (conditionalWriteStarted.isCompleted &&
        !_conditionalWriteCompleted.isCompleted) {
      await _conditionalWriteCompleted.future;
    }
    return _data[key];
  }

  @override
  Future<void> write(String key, Object? value) async {
    if (conditionalWriteStarted.isCompleted &&
        !_conditionalWriteCompleted.isCompleted) {
      await _conditionalWriteCompleted.future;
    }
    final write = _ordinaryWrite;
    if (write != null) {
      write.started.complete();
      await write.release.future;
      _ordinaryWrite = null;
      if (write.fail) throw StateError('controlled write failure');
    }
    _data[key] = value;
  }

  @override
  Future<bool> writeIf(
    String key,
    Object? value,
    bool Function() shouldCommit,
  ) async {
    conditionalWriteStarted.complete();
    try {
      if (!shouldCommit()) return false;
      final previous = _data[key];
      await releaseConditionalWrite.future;
      _data[key] = value;
      if (shouldCommit()) return true;
      _data[key] = previous;
      return false;
    } finally {
      _conditionalWriteCompleted.complete();
    }
  }

  @override
  Future<Map<String, Object?>> snapshot() async {
    if (conditionalWriteStarted.isCompleted &&
        !_conditionalWriteCompleted.isCompleted) {
      await _conditionalWriteCompleted.future;
    }
    return Map<String, Object?>.from(_data);
  }
}

class _ControlledWrite {
  _ControlledWrite({required this.fail});

  final bool fail;
  final started = Completer<void>();
  final release = Completer<void>();
}

class _BlockingAioMutationStore extends PersistentJsonStore {
  final _data = <String, Object?>{};
  _ControlledWrite? _blockedWrite;

  _ControlledWrite blockNextWrite() {
    final write = _ControlledWrite(fail: false);
    _blockedWrite = write;
    return write;
  }

  @override
  Future<Object?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Object? value) async {
    final previous = _data[key];
    _data[key] = value;
    final write = _blockedWrite;
    if (write == null) return;
    _blockedWrite = null;
    write.started.complete();
    await write.release.future;
    if (write.fail) _data[key] = previous;
  }

  @override
  Future<bool> writeIf(
    String key,
    Object? value,
    bool Function() shouldCommit,
  ) async {
    if (!shouldCommit()) return false;
    final previous = _data[key];
    _data[key] = value;
    final write = _blockedWrite;
    if (write != null) {
      _blockedWrite = null;
      write.started.complete();
      await write.release.future;
    }
    if (shouldCommit()) return true;
    if (previous == null) {
      _data.remove(key);
    } else {
      _data[key] = previous;
    }
    return false;
  }

  @override
  Future<Map<String, Object?>> snapshot() async =>
      Map<String, Object?>.from(_data);
}

class _BlockingNumericMutationStore extends PersistentJsonStore {
  final _data = <String, Object?>{};
  _ControlledNumericWrite? _blockedWrite;
  _ControlledNumericRead? _blockedRead;

  _ControlledNumericWrite blockNextWrite() {
    final write = _ControlledNumericWrite();
    _blockedWrite = write;
    return write;
  }

  _ControlledNumericRead blockNextRead() {
    final read = _ControlledNumericRead();
    _blockedRead = read;
    return read;
  }

  @override
  Future<Object?> read(String key) async {
    final read = _blockedRead;
    if (read != null) {
      _blockedRead = null;
      read.started.complete();
      await read.release.future;
    }
    return _data[key];
  }

  @override
  Future<void> write(String key, Object? value) async {
    final write = _blockedWrite;
    if (write != null) {
      _blockedWrite = null;
      write.started.complete();
      await write.release.future;
    }
    _data[key] = value;
    write?.completed.complete();
  }

  @override
  Future<bool> writeIf(
    String key,
    Object? value,
    bool Function() shouldCommit,
  ) async {
    if (!shouldCommit()) return false;
    final previous = _data[key];
    final write = _blockedWrite;
    if (write != null) {
      _blockedWrite = null;
      write.started.complete();
      await write.release.future;
    }
    _data[key] = value;
    if (shouldCommit()) {
      write?.completed.complete();
      return true;
    }
    if (previous == null) {
      _data.remove(key);
    } else {
      _data[key] = previous;
    }
    write?.completed.complete();
    return false;
  }

  @override
  Future<Map<String, Object?>> snapshot() async =>
      Map<String, Object?>.from(_data);
}

class _ControlledNumericWrite {
  final started = Completer<void>();
  final release = Completer<void>();
  final completed = Completer<void>();
}

class _ControlledNumericRead {
  final started = Completer<void>();
  final release = Completer<void>();
}

class _RecordingFavoriteReverbService extends ReverbService {
  final connected = Completer<void>();
  void Function(FavoriteToggleEvent)? _onFavoriteToggled;

  void emitFavorite(FavoriteToggleEvent event) => _onFavoriteToggled!(event);

  @override
  Future<void> connect({
    required TvPlaylistSession session,
    required UserCredentials credentials,
    Set<String> subscribedChannels = const <String>{},
    required void Function(TvNotificationItem) onNotification,
    void Function(DvrRecording)? onDvrStatus,
    void Function(MediaRequestSummary)? onRequestStatus,
    void Function(FavoriteToggleEvent)? onFavoriteToggled,
    void Function()? onConnected,
  }) async {
    _onFavoriteToggled = onFavoriteToggled;
    if (!connected.isCompleted) connected.complete();
  }

  @override
  Future<void> disconnect() async {}
}

class _FavoriteSessionNotificationService extends TvNotificationService {
  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async => (
    const TvPlaylistSession(
      notifiableId: 1,
      notifiableType: 'playlist',
      isAdmin: false,
      channelName: 'private-tv.playlist.fixture',
      reverb: ReverbConfig(
        host: 'fixture.invalid',
        port: 443,
        scheme: 'wss',
        appKey: 'fixture-key',
      ),
    ),
    const <TvNotificationItem>[],
  );
}

Set<int> _persistedNumericFavoriteIds(
  Map<String, Object?> snapshot,
  String contentType,
) {
  final key = switch (contentType) {
    'vod' => 'm3ue_favorites_vod',
    'series' => 'm3ue_favorites_series',
    _ => 'm3ue_favorites',
  };
  final raw = snapshot[key];
  return raw is Iterable
      ? raw.map((value) => int.parse('$value')).toSet()
      : <int>{};
}

Set<Object?> _persistedFavoriteIds(Map<String, Object?> snapshot) =>
    (snapshot['aio_favorites']! as Map<Object?, Object?>).keys.toSet();

Future<List<String>> _favoriteIds(AIOStreamsFavoritesService service) async =>
    (await service.all()).map((favorite) => favorite.id).toList();
