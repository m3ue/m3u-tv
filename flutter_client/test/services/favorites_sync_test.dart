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
