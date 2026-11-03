import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _sports = UserCredentials(
  server: 'https://editor.invalid',
  username: 'sports',
  password: 'sports-password',
);
const _movies = UserCredentials(
  server: 'https://editor.invalid',
  username: 'movies',
  password: 'movies-password',
);
const _otherEditor = UserCredentials(
  server: 'https://other.invalid',
  username: 'other',
  password: 'other-password',
);
const _rejected = UserCredentials(
  server: 'https://editor.invalid',
  username: 'rejected',
  password: 'wrong-password',
);

void main() {
  group('saved playlists', () {
    test('every successful connection is saved', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);

      expect(await fixture.controller.connectXtream(_sports), isTrue);
      expect(await fixture.controller.connectXtream(_movies), isTrue);

      final saved = fixture.controller.savedPlaylists;
      expect(saved.playlists.map((p) => p.credentials.username), <String>[
        'sports',
        'movies',
      ]);
      // Each one keeps its state under its own id, the first one included.
      expect(saved.playlists.where((p) => p.usesBaseKeys), isEmpty);
    });

    test(
      'a login saved before multiple playlists is adopted on boot',
      () async {
        final storage = InMemorySecureStorage();
        await storage.write(
          'm3ue_tv_credentials',
          jsonEncode(<String, String>{
            'server': _sports.server,
            'username': _sports.username,
            'password': _sports.password,
          }),
        );
        final fixture = _Fixture(storage: storage);
        addTearDown(fixture.dispose);
        // Its state from before multiple playlists, on the unscoped keys.
        fixture.memory['m3ue_favorites'] = <int>[101];
        fixture.memory['m3ue_tv_active_viewer_${_sports.server}|sports'] =
            'viewer-sports';

        await fixture.controller.boot();

        final saved = fixture.controller.savedPlaylists.playlists;
        expect(saved, hasLength(1));
        expect(saved.single.credentials.username, 'sports');
        // Moved to its own keys, so nothing is left for another login.
        expect(saved.single.usesBaseKeys, isFalse);
        final id = saved.single.id;
        expect(fixture.memory['m3ue_favorites_playlist_$id'], <int>[101]);
        expect(fixture.memory.containsKey('m3ue_favorites'), isFalse);
        expect(
          fixture.memory['m3ue_tv_active_viewer_playlist_$id'],
          'viewer-sports',
        );
        expect(await fixture.controller.favoritesService.all(), <int>{101});
      },
    );

    test(
      'favorites are kept per playlist and follow the shown one',
      () async {
        final fixture = _Fixture()
          ..transport.favoritesByViewer['viewer-sports'] = [
            <String, Object?>{'content_type': 'live', 'stream_id': 101},
          ]
          ..transport.favoritesByViewer['viewer-movies'] = [
            <String, Object?>{'content_type': 'live', 'stream_id': 202},
          ];
        addTearDown(fixture.dispose);
        final controller = fixture.controller;

        expect(await controller.connectXtream(_sports), isTrue);
        await pumpEventQueue();
        expect(await controller.favoritesService.all(), <int>{101});

        expect(await controller.switchToPlaylist(_movies), isNull);
        await pumpEventQueue();
        expect(await controller.favoritesService.all(), <int>{202});
        final sports = controller.savedPlaylists.find(_sports)!;
        final movies = controller.savedPlaylists.find(_movies)!;
        expect(fixture.memory['m3ue_favorites_playlist_${sports.id}'], <int>[
          101,
        ]);
        expect(fixture.memory['m3ue_favorites_playlist_${movies.id}'], <int>[
          202,
        ]);

        expect(await controller.switchToPlaylist(_sports), isNull);
        await pumpEventQueue();
        expect(await controller.favoritesService.all(), <int>{101});
      },
    );

    test(
      'a failed switch keeps the current playlist without an error',
      () async {
        final fixture = _Fixture()..transport.rejected.add('rejected');
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);

        final error = await controller.switchToPlaylist(_rejected);

        expect(error, contains('Invalid credentials'));
        expect(controller.isConfigured, isTrue);
        expect(controller.authNotifier.credentials?.username, 'sports');
        expect(controller.error, isNull);
        expect(controller.savedPlaylists.playlists, hasLength(1));
      },
    );

    test('switching to the active playlist does not reconnect', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      expect(await fixture.controller.connectXtream(_sports), isTrue);
      final authRequests = fixture.transport.authRequests;

      expect(await fixture.controller.switchToPlaylist(_sports), isNull);

      expect(fixture.transport.authRequests, authRequests);
    });

    test('disconnect removes only the active playlist', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      expect(await controller.connectXtream(_sports), isTrue);
      expect(await controller.connectXtream(_movies), isTrue);

      await controller.disconnect();

      expect(controller.isConfigured, isFalse);
      expect(
        controller.savedPlaylists.playlists.map((p) => p.credentials.username),
        <String>['sports'],
      );
    });

    test(
      'removing another playlist drops it and its local state only',
      () async {
        final fixture = _Fixture()
          ..transport.favoritesByViewer['viewer-sports'] = [
            <String, Object?>{'content_type': 'live', 'stream_id': 101},
          ]
          ..transport.favoritesByViewer['viewer-movies'] = [
            <String, Object?>{'content_type': 'live', 'stream_id': 202},
          ];
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        expect(await controller.switchToPlaylist(_sports), isNull);
        await pumpEventQueue();
        final movies = controller.savedPlaylists.find(_movies)!;
        expect(
          fixture.memory['m3ue_favorites_playlist_${movies.id}'],
          isNotNull,
        );

        await controller.removePlaylist(movies.id);

        expect(controller.isConfigured, isTrue);
        expect(controller.savedPlaylists.find(_movies), isNull);
        expect(
          fixture.memory.containsKey('m3ue_favorites_playlist_${movies.id}'),
          isFalse,
        );
        final sports = controller.savedPlaylists.find(_sports)!;
        expect(fixture.memory['m3ue_favorites_playlist_${sports.id}'], <int>[
          101,
        ]);
      },
    );

    test('removing the active playlist signs out of it', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      expect(await controller.connectXtream(_sports), isTrue);
      expect(await controller.connectXtream(_movies), isTrue);

      await controller.removePlaylist(
        controller.savedPlaylists.find(_movies)!.id,
      );

      expect(controller.isConfigured, isFalse);
      expect(controller.savedPlaylists.find(_movies), isNull);
      expect(controller.savedPlaylists.find(_sports), isNotNull);
    });

    test('signing the device out forgets every playlist', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      expect(await controller.connectXtream(_sports), isTrue);
      expect(await controller.connectXtream(_movies), isTrue);

      await controller.signOutDevice();

      expect(controller.isConfigured, isFalse);
      expect(controller.savedPlaylists.playlists, isEmpty);
      expect(
        await fixture.storage.read('m3ue_tv_saved_playlists'),
        isNull,
      );
    });

    test(
      'a revoke forgets only the playlists on the editor that sent it',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_otherEditor), isTrue);
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.connectXtream(_movies), isTrue);
        final movies = controller.savedPlaylists.find(_movies)!;
        await controller.favoritesService.add(202);

        await controller.signOutDevice();

        expect(controller.isConfigured, isFalse);
        expect(
          controller.savedPlaylists.playlists.map(
            (p) => p.credentials.username,
          ),
          <String>['other'],
        );
        expect(
          fixture.memory.containsKey('m3ue_favorites_playlist_${movies.id}'),
          isFalse,
        );
      },
    );

    test(
      'a failed favorites sync keeps the favorites a playlist stored',
      () async {
        final fixture = _Fixture()
          ..transport.favoritesByViewer['viewer-sports'] = [
            <String, Object?>{'content_type': 'live', 'stream_id': 101},
          ]
          ..transport.favoritesByViewer['viewer-movies'] = [
            <String, Object?>{'content_type': 'live', 'stream_id': 202},
          ];
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        await pumpEventQueue();
        expect(await controller.favoritesService.all(), <int>{101});
        expect(await controller.switchToPlaylist(_movies), isNull);
        await pumpEventQueue();

        fixture.transport.failingFavorites.add('viewer-sports');
        expect(await controller.switchToPlaylist(_sports), isNull);
        await pumpEventQueue();

        expect(await controller.favoritesService.all(), <int>{101});
      },
    );

    test('a failed connect clears what it staged for its playlist', () async {
      final fixture = _Fixture()..transport.failingContent.add('movies');
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      expect(await controller.connectXtream(_sports), isTrue);
      // Stands in for state written under the incoming playlist's id
      // before its load failed.
      final pending = controller.savedPlaylists.scopeFor(_movies)!;
      await controller.favoritesService.replaceAllIn(pending, <int>{202});
      final stagedKey = 'm3ue_favorites_playlist_$pending';
      expect(fixture.memory[stagedKey], isNotNull);

      expect(await controller.connectXtream(_movies), isFalse);

      expect(controller.authNotifier.credentials?.username, 'sports');
      expect(fixture.memory.containsKey(stagedKey), isFalse);
      expect(controller.savedPlaylists.find(_movies), isNull);
      expect(controller.savedPlaylists.scopeFor(_movies), isNot(pending));
    });

    test('continue watching follows the shown playlist', () async {
      final fixture = _Fixture()
        ..transport.recentlyWatchedByViewer['viewer-sports'] = [
          <String, Object?>{
            'content_type': 'vod',
            'stream_id': 301,
            'position_seconds': 91,
            'duration_seconds': 600,
            'title': 'Sports Movie',
          },
        ];
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      List<String?> titles() =>
          controller.progressList.map((p) => p.title).toList();

      expect(await controller.connectXtream(_sports), isTrue);
      await pumpEventQueue();
      expect(titles(), <String>['Sports Movie']);

      // The movies playlist's viewer has watched nothing.
      expect(await controller.switchToPlaylist(_movies), isNull);
      await pumpEventQueue();
      expect(controller.progressList, isEmpty);

      expect(await controller.switchToPlaylist(_sports), isNull);
      await pumpEventQueue();
      expect(titles(), <String>['Sports Movie']);
    });

    group('catalogs', () {
      Future<List<int>> shownChannelIds(AppStateController controller) async =>
          (await controller.catalogRepository.pageActiveItems<Channel>(
            kind: kCatalogKindLive,
            offset: 0,
            limit: 10,
          )).map((channel) => channel.id).toList();

      String sourceOf(AppStateController controller, UserCredentials login) =>
          controller.savedPlaylists.find(login)!.id;

      test('each playlist keeps its own, and the shown one is read', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();

        expect(await shownChannelIds(controller), <int>[202]);
        expect(await controller.cacheService.storedCatalogSources(), {
          sourceOf(controller, _sports),
          sourceOf(controller, _movies),
        });

        expect(await controller.switchToPlaylist(_sports), isNull);
        expect(await shownChannelIds(controller), <int>[101]);
      });

      test('only the most recently used ones are kept', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        await controller.setCachedPlaylistLimit(2);
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        expect(await controller.switchToPlaylist(_otherEditor), isNull);
        await controller.drainBackgroundPersistence();

        expect(await controller.cacheService.storedCatalogSources(), {
          sourceOf(controller, _movies),
          sourceOf(controller, _otherEditor),
        });

        await controller.setCachedPlaylistLimit(1);
        expect(await controller.cacheService.storedCatalogSources(), {
          sourceOf(controller, _otherEditor),
        });
      });

      test('removing a playlist drops its catalog', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();
        final sports = sourceOf(controller, _sports);

        await controller.removePlaylist(sports);

        expect(await controller.cacheService.storedCatalogSources(), {
          sourceOf(controller, _movies),
        });
      });

      test('clearing another playlist frees its catalog only', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();

        await controller.clearPlaylistCache(sourceOf(controller, _sports));

        expect(await controller.cacheService.storedCatalogSources(), {
          sourceOf(controller, _movies),
        });
        expect(await shownChannelIds(controller), <int>[202]);
        final usage = await controller.storageUsage();
        final byName = {
          for (final entry in usage.playlists)
            entry.playlist.credentials.username: entry,
        };
        expect(byName['sports']!.usage, isNull);
        expect(byName['movies']!.usage?.channels, 1);
        expect(byName['movies']!.isShown, isTrue);
      });

      test('a stored playlist is shown before its server answers', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();

        final signIn = Completer<void>();
        fixture.transport.authGate = signIn;
        expect(await controller.switchToPlaylist(_sports), isNull);

        expect(controller.authNotifier.credentials?.username, 'sports');
        expect(controller.authNotifier.isConfigured, isFalse);
        expect(controller.isConfigured, isTrue);
        expect(await shownChannelIds(controller), <int>[101]);
        expect(controller.activeViewer?.ulid, 'viewer-sports');
        final saved =
            jsonDecode(
                  (await fixture.storage.read(
                    'm3ue_tv_credentials',
                  ))!,
                )
                as Map<String, Object?>;
        expect(saved['username'], 'sports');

        signIn.complete();
        await controller.drainBackgroundPersistence();
        expect(controller.authNotifier.isConfigured, isTrue);
        expect(controller.error, isNull);
        expect(await shownChannelIds(controller), <int>[101]);
      });

      test('a stored playlist that fails to sign in stays shown', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();

        fixture.transport.rejected.add('sports');
        expect(await controller.switchToPlaylist(_sports), isNull);
        await controller.drainBackgroundPersistence();

        expect(controller.authNotifier.credentials?.username, 'sports');
        expect(controller.error, contains('Invalid credentials'));
        expect(await shownChannelIds(controller), <int>[101]);
      });

      test('the last of several quick switches wins', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();

        final signIn = Completer<void>();
        fixture.transport.authGate = signIn;
        expect(await controller.switchToPlaylist(_sports), isNull);
        expect(await controller.switchToPlaylist(_movies), isNull);
        signIn.complete();
        await controller.drainBackgroundPersistence();

        expect(controller.authNotifier.credentials?.username, 'movies');
        expect(controller.authNotifier.isConfigured, isTrue);
        expect(controller.activeViewer?.ulid, 'viewer-movies');
        expect(await shownChannelIds(controller), <int>[202]);
      });

      test('a stored playlist opens at once from the connect screen', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();
        // Signs out of movies; sports stays saved and stored.
        await controller.disconnect();
        expect(controller.isConfigured, isFalse);

        final signIn = Completer<void>();
        fixture.transport.authGate = signIn;
        expect(await controller.switchToPlaylist(_sports), isNull);

        expect(controller.isConfigured, isTrue);
        expect(await shownChannelIds(controller), <int>[101]);
        // The next start restores it.
        expect(await fixture.storage.read('m3ue_tv_source'), isNotNull);
        signIn.complete();
        await controller.drainBackgroundPersistence();
        expect(controller.authNotifier.isConfigured, isTrue);
      });

      test('reloading the shown playlist keeps the others', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();

        await controller.clearAndRefresh(scope: CacheClearScope.content);

        expect(await controller.cacheService.storedCatalogSources(), {
          sourceOf(controller, _sports),
          sourceOf(controller, _movies),
        });
        expect(await shownChannelIds(controller), <int>[202]);
      });

      test('signing out mid-connect forgets the shown playlist only', () async {
        final storage = _GatedSecureStorage();
        final fixture = _Fixture(storage: storage);
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();
        final sports = sourceOf(controller, _sports);

        // The new login's catalog is stored; its commit is held there.
        final held = storage.hold('m3ue_tv_source');
        final connecting = controller.connectXtream(_otherEditor);
        await held;
        await controller.disconnect();
        storage.release();
        expect(await connecting, isFalse);
        await controller.drainBackgroundPersistence();

        // Movies was on screen; the login being connected never was.
        expect(
          controller.savedPlaylists.playlists.map(
            (p) => p.credentials.username,
          ),
          <String>['sports'],
        );
        expect(await controller.cacheService.storedCatalogSources(), {sports});
      });

      test('a revoke mid-connect forgets the shown editor', () async {
        final storage = _GatedSecureStorage();
        final fixture = _Fixture(storage: storage);
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();

        final held = storage.hold('m3ue_tv_source');
        final connecting = controller.connectXtream(_otherEditor);
        await held;
        await controller.signOutDevice();
        storage.release();
        expect(await connecting, isFalse);
        await controller.drainBackgroundPersistence();

        expect(controller.savedPlaylists.playlists, isEmpty);
        expect(await controller.cacheService.storedCatalogSources(), isEmpty);
      });

      test("the catalog cached before playlists is the old login's", () async {
        final storage = InMemorySecureStorage();
        // The login from before multiple playlists, then one added since,
        // which is the one signed in now.
        await storage.write(
          'm3ue_tv_saved_playlists',
          jsonEncode([
            <String, Object?>{
              'id': 'legacy',
              'server': _sports.server,
              'username': _sports.username,
              'password': _sports.password,
              'base_keys': true,
            },
            <String, Object?>{
              'id': 'added',
              'server': _movies.server,
              'username': _movies.username,
              'password': _movies.password,
            },
          ]),
        );
        await storage.write(
          'm3ue_tv_credentials',
          jsonEncode(<String, String>{
            'server': _movies.server,
            'username': _movies.username,
            'password': _movies.password,
          }),
        );
        final fixture = _Fixture(storage: storage);
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        await controller.cacheService.replace(<String, Object?>{
          'liveStreams': const <Channel>[
            Channel(id: 101, name: 'Sports One', streamUrl: 'http://h/1.ts'),
          ],
        });

        await controller.boot();
        await controller.drainBackgroundPersistence();

        expect(
          await controller.cacheService.catalogUpdatedAt('legacy'),
          isNotNull,
        );
        expect(await shownChannelIds(controller), <int>[202]);
      });

      test('a playlist with nothing stored downloads before showing', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final controller = fixture.controller;
        expect(await controller.connectXtream(_sports), isTrue);
        expect(await controller.switchToPlaylist(_movies), isNull);
        await controller.drainBackgroundPersistence();
        await controller.clearPlaylistCache(sourceOf(controller, _sports));

        final signIn = Completer<void>();
        fixture.transport.authGate = signIn;
        var switched = false;
        final switching = controller.switchToPlaylist(_sports).then((error) {
          switched = true;
          return error;
        });
        await pumpEventQueue();
        expect(switched, isFalse);
        expect(await shownChannelIds(controller), <int>[202]);

        signIn.complete();
        expect(await switching, isNull);
        expect(await shownChannelIds(controller), <int>[101]);
      });
    });

    test('proxy preferences are kept per playlist', () async {
      final directory = await Directory.systemTemp.createTemp(
        'm3u-tv-playlist-proxy-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final fixture = _Fixture(
        persistentStore: PersistentJsonStore(
          file: File('${directory.path}/state.json'),
        ),
      );
      addTearDown(fixture.dispose);
      final controller = fixture.controller;
      final proxy = controller.proxyPlaybackSettings;

      expect(await controller.connectXtream(_sports), isTrue);
      await pumpEventQueue();
      await proxy.setEnabled(enabled: true);
      await proxy.setLiveProfileId(5);

      // In place as soon as the playlist is shown, before any stream starts.
      expect(await controller.switchToPlaylist(_movies), isNull);
      expect(proxy.enabled, isFalse);
      expect(proxy.liveProfileId, isNull);
      await proxy.setLiveProfileId(7);

      expect(await controller.switchToPlaylist(_sports), isNull);
      expect(proxy.enabled, isTrue);
      expect(proxy.liveProfileId, 5);

      expect(await controller.switchToPlaylist(_movies), isNull);
      expect(proxy.liveProfileId, 7);
    });
  });
}

class _Fixture {
  _Fixture({
    InMemorySecureStorage? storage,
    PersistentJsonStore? persistentStore,
  }) : storage = storage ?? InMemorySecureStorage() {
    controller = persistentStore == null
        ? AppStateController(
            xtreamService: XtreamService(
              transport: transport.call,
              cache: CacheService(memory: <String, Object?>{}),
            ),
            secureStorage: this.storage,
            cacheService: CacheService(memory: <String, Object?>{}),
            favoritesService: FavoritesService(memory: memory),
            vodFavoritesService: FavoritesService(
              memory: memory,
              namespace: 'vod',
            ),
            seriesFavoritesService: FavoritesService(
              memory: memory,
              namespace: 'series',
            ),
            aioFavoritesService: AIOStreamsFavoritesService(),
            resumeService: ResumeService(memory: memory),
            viewerService: ViewerService(memory: memory),
            reverbService: ReverbService(),
            tvNotificationService: _EmptyTvNotificationService(),
          )
        : AppStateController(
            xtreamService: XtreamService(transport: transport.call),
            secureStorage: this.storage,
            persistentStore: persistentStore,
            reverbService: ReverbService(),
            tvNotificationService: _EmptyTvNotificationService(),
          );
  }

  final InMemorySecureStorage storage;
  final Map<String, Object?> memory = <String, Object?>{};
  final _PlaylistTransport transport = _PlaylistTransport();
  late final AppStateController controller;

  Future<void> dispose() async {
    controller.dispose();
    await controller.drainBackgroundPersistence();
  }
}

/// Holds the next write of one key until [release], to land another
/// operation in the middle of the one writing it.
class _GatedSecureStorage extends InMemorySecureStorage {
  String? _key;
  Completer<void>? _reached;
  final Completer<void> _released = Completer<void>();

  /// Completes once the next write of [key] has started.
  Future<void> hold(String key) {
    _key = key;
    return (_reached = Completer<void>()).future;
  }

  void release() => _released.complete();

  @override
  Future<void> write(String key, String value) async {
    final reached = _reached;
    if (key == _key && reached != null && !reached.isCompleted) {
      reached.complete();
      await _released.future;
    }
    await super.write(key, value);
  }
}

class _PlaylistTransport {
  final Map<String, List<Map<String, Object?>>> favoritesByViewer =
      <String, List<Map<String, Object?>>>{};
  final Map<String, List<Map<String, Object?>>> recentlyWatchedByViewer =
      <String, List<Map<String, Object?>>>{};
  final Set<String> rejected = <String>{};

  /// Viewer ulids whose favorites can't be read or synced.
  final Set<String> failingFavorites = <String>{};

  /// Usernames whose catalog can't be downloaded.
  final Set<String> failingContent = <String>{};
  int authRequests = 0;

  /// Holds every sign-in until it completes.
  Completer<void>? authGate;

  Future<Object?> call(XtreamRequest request) async {
    final action = request.action ?? 'auth';
    final username = request.credentials.username;
    switch (action) {
      case 'auth':
        authRequests += 1;
        await authGate?.future;
        if (rejected.contains(username)) {
          return <String, Object?>{
            'user_info': <String, Object?>{
              'auth': 0,
              'status': 'Invalid credentials',
            },
          };
        }
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{'version': '0.14.0'},
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_vod_streams':
      case 'get_series':
        return const <Object?>[];
      case 'get_recently_watched':
        return recentlyWatchedByViewer['${request.params['viewer_id']}'] ??
            const <Object?>[];
      case 'get_live_streams':
        if (failingContent.contains(username)) {
          throw StateError('catalog unavailable');
        }
        return <Map<String, Object?>>[
          <String, Object?>{
            'stream_id': username == 'sports' ? 101 : 202,
            'name': '$username channel',
          },
        ];
      case 'get_viewers':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'ulid': 'viewer-$username',
            'name': 'Admin',
            'is_admin': true,
          },
        ];
      case 'get_epg_batch':
        return <String, Object?>{};
      case 'get_favorites':
      case 'sync_favorites':
        final viewerId =
            '${request.params['viewer_id'] ?? request.body['viewer_id']}';
        if (failingFavorites.contains(viewerId)) {
          throw StateError('favorites unavailable');
        }
        return favoritesByViewer[viewerId] ?? const <Object?>[];
      case 'toggle_favorite':
        return <String, Object?>{'favorited': request.body['favorited']};
      default:
        throw StateError('No fixture for $action');
    }
  }
}

class _EmptyTvNotificationService extends TvNotificationService {
  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async => (
    const TvPlaylistSession(
      notifiableId: 1,
      notifiableType: 'playlist',
      isAdmin: false,
      channelName: '',
      reverb: ReverbConfig(
        host: 'fixture.invalid',
        port: 443,
        scheme: 'wss',
        appKey: '',
      ),
    ),
    const <TvNotificationItem>[],
  );
}
