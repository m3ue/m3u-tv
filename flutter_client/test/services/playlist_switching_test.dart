import 'dart:convert';
import 'dart:io';

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
      expect(saved.find(_sports)?.usesBaseKeys, isTrue);
      expect(saved.find(_movies)?.usesBaseKeys, isFalse);
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

        await fixture.controller.boot();

        final saved = fixture.controller.savedPlaylists.playlists;
        expect(saved, hasLength(1));
        expect(saved.single.credentials.username, 'sports');
        // Its existing favorites and viewer keys stay where they were.
        expect(saved.single.usesBaseKeys, isTrue);
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
        final movies = controller.savedPlaylists.find(_movies)!;
        expect(fixture.memory['m3ue_favorites'], <int>[101]);
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
        expect(fixture.memory['m3ue_favorites'], <int>[101]);
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

      expect(await controller.switchToPlaylist(_movies), isNull);
      await pumpEventQueue();
      expect(proxy.enabled, isFalse);
      expect(proxy.liveProfileId, isNull);
      await proxy.setLiveProfileId(7);

      expect(await controller.switchToPlaylist(_sports), isNull);
      await pumpEventQueue();
      expect(proxy.enabled, isTrue);
      expect(proxy.liveProfileId, 5);

      expect(await controller.switchToPlaylist(_movies), isNull);
      await pumpEventQueue();
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

class _PlaylistTransport {
  final Map<String, List<Map<String, Object?>>> favoritesByViewer =
      <String, List<Map<String, Object?>>>{};
  final Set<String> rejected = <String>{};
  int authRequests = 0;

  Future<Object?> call(XtreamRequest request) async {
    final action = request.action ?? 'auth';
    final username = request.credentials.username;
    switch (action) {
      case 'auth':
        authRequests += 1;
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
      case 'get_recently_watched':
        return const <Object?>[];
      case 'get_live_streams':
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
        return favoritesByViewer['${request.params['viewer_id']}'] ??
            const <Object?>[];
      case 'sync_favorites':
        return favoritesByViewer['${request.body['viewer_id']}'] ??
            const <Object?>[];
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
