import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
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

    test('toggling an AIOStreams favorite pushes its full metadata', () async {
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

      await controller.aioFavoritesService.add(
        const AIOStreamsFavoriteItem(
          id: 'tt0111161',
          type: 'movie',
          name: 'The Shawshank Redemption',
          integrationId: 7,
          poster: 'https://example.com/poster.jpg',
        ),
      );
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
    });
  });
}

AppStateController _controller({
  Map<String, Object?>? memory,
  required _FakeXtreamTransport transport,
}) {
  final sharedMemory = memory ?? <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport.call,
      cache: CacheService(memory: <String, Object?>{}),
    ),
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    favoritesService: FavoritesService(memory: sharedMemory),
    vodFavoritesService: FavoritesService(
      memory: sharedMemory,
      namespace: 'vod',
    ),
    seriesFavoritesService: FavoritesService(
      memory: sharedMemory,
      namespace: 'series',
    ),
    aioFavoritesService: AIOStreamsFavoritesService(),
    resumeService: ResumeService(memory: sharedMemory),
    viewerService: ViewerService(memory: sharedMemory),
  );
}

class _RecordedRequest {
  _RecordedRequest(this.action, this.body);
  final String action;
  final Map<String, Object?> body;
}

class _FakeXtreamTransport {
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

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
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_recently_watched':
        return const <Object?>[];
      case 'get_viewers':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'ulid': 'viewer-admin',
            'name': 'Admin',
            'is_admin': true,
          },
        ];
      case 'get_epg_batch':
        return <String, Object?>{};
      case 'get_favorites':
        return const <Object?>[];
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

Set<Object?> _persistedFavoriteIds(Map<String, Object?> snapshot) =>
    (snapshot['aio_favorites']! as Map<Object?, Object?>).keys.toSet();

Future<List<String>> _favoriteIds(AIOStreamsFavoritesService service) async =>
    (await service.all()).map((favorite) => favorite.id).toList();
