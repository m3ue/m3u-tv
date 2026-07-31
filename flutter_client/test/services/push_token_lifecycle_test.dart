import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/push_notification_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('push token identity lifecycle', () {
    test('refresh unsubscribes the old token before registering new', () async {
      final fixture = _Fixture();
      addTearDown(fixture.controller.dispose);
      expect(await fixture.controller.connectXtream(_firstCredentials), isTrue);
      await fixture.controller.setPushToken('old-token');
      fixture.push.events.clear();

      await fixture.controller.setPushToken('new-token');

      expect(fixture.push.events, <String>[
        'unsubscribe:first:old-token:true',
        'register:first:new-token',
      ]);
    });

    test('logout unsubscribes before credentials are cleared', () async {
      final fixture = _Fixture();
      addTearDown(fixture.controller.dispose);
      expect(await fixture.controller.connectXtream(_firstCredentials), isTrue);
      await fixture.controller.setPushToken('device-token');
      fixture.push.events.clear();

      await fixture.controller.disconnect();

      expect(fixture.push.events, <String>[
        'unsubscribe:first:device-token:true',
      ]);
      expect(fixture.auth.credentials, isNull);
    });

    test(
      'logout rejects a direct token replacement queued behind unsubscribe',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.controller.dispose);
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await fixture.controller.setPushToken('old-token');
        fixture.push.events.clear();
        final unregisterStarted = fixture.push.delayNextUnregister();

        final disconnect = fixture.controller.disconnect();
        await unregisterStarted;
        final replacement = fixture.controller.setPushToken('new-token');
        fixture.push.releaseUnregister();
        await Future.wait<void>(<Future<void>>[disconnect, replacement]);

        expect(fixture.push.events, <String>[
          'unsubscribe:first:old-token:true',
        ]);
        expect(fixture.auth.credentials, isNull);
      },
    );

    test(
      'logout rejects a token refresh queued behind unsubscribe',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.controller.dispose);
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await fixture.controller.initPushNotifications();
        await fixture.controller.setPushToken('old-token');
        fixture.push.events.clear();
        final unregisterStarted = fixture.push.delayNextUnregister();

        final disconnect = fixture.controller.disconnect();
        await unregisterStarted;
        fixture.push.emitTokenRefresh('new-token');
        fixture.push.releaseUnregister();
        await disconnect;
        await fixture.controller.setPushToken('after-logout-token');

        expect(fixture.push.events, <String>[
          'unsubscribe:first:old-token:true',
        ]);
        expect(fixture.auth.credentials, isNull);
      },
    );

    test('credential replacement unsubscribes prior requester first', () async {
      final fixture = _Fixture();
      addTearDown(fixture.controller.dispose);
      expect(await fixture.controller.connectXtream(_firstCredentials), isTrue);
      await fixture.controller.setPushToken('device-token');
      fixture.push.events.clear();

      expect(
        await fixture.controller.connectXtream(_secondCredentials),
        isTrue,
      );

      expect(fixture.push.events, <String>[
        'unsubscribe:first:device-token:true',
        'register:second:device-token',
      ]);
    });

    test('switching to direct M3U unsubscribes the prior requester', () async {
      final fixture = _Fixture();
      addTearDown(fixture.controller.dispose);
      expect(await fixture.controller.connectXtream(_firstCredentials), isTrue);
      await fixture.controller.setPushToken('device-token');
      fixture.push.events.clear();

      expect(
        await fixture.controller.switchToM3u(
          playlistText:
              '#EXTM3U\n#EXTINF:-1,Fixture Channel\nhttps://media.invalid/live.m3u8',
        ),
        isTrue,
      );

      expect(fixture.push.events, <String>[
        'unsubscribe:first:device-token:true',
      ]);
      expect(fixture.auth.credentials, isNull);
    });

    test('credential replacement ignores stale notification setup', () async {
      final api = _DelayedTvNotificationService();
      final reverb = _RecordingReverbService();
      final fixture = _Fixture(notificationApi: api, reverbService: reverb);
      addTearDown(fixture.controller.dispose);

      expect(await fixture.controller.connectXtream(_firstCredentials), isTrue);
      await api.firstFetchStarted.future;

      expect(
        await fixture.controller.connectXtream(_secondCredentials),
        isTrue,
      );
      await reverb.secondConnected.future;
      api.releaseFirstFetch.complete();
      await api.firstFetchReturned.future;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(reverb.connectedUsers, <String>['second']);
    });

    test('late source operation cannot replace a newer connection', () async {
      final transport = _RacingXtreamTransport();
      final reverb = _RecordingReverbService();
      final fixture = _Fixture(
        transport: transport.call,
        notificationApi: _SessionTvNotificationService(),
        reverbService: reverb,
      );
      addTearDown(fixture.controller.dispose);
      await fixture.controller.setPushToken('device-token');

      final firstConnect = fixture.controller.connectXtream(_firstCredentials);
      await transport.firstCatalogStarted.future;

      expect(
        await fixture.controller.connectXtream(_secondCredentials),
        isTrue,
      );
      await reverb.secondConnected.future;
      await _waitForGuide(fixture.controller, 'Server B guide');

      transport.releaseFirstCatalog.complete();
      expect(await firstConnect, isFalse);
      await Future<void>.delayed(Duration.zero);

      final persistedCredentials =
          jsonDecode(
                (await fixture.storage.read('m3ue_tv_credentials'))!,
              )
              as Map<String, Object?>;
      final persistedSource =
          jsonDecode((await fixture.storage.read('m3ue_tv_source'))!)
              as Map<String, Object?>;
      expect(fixture.auth.credentials, _secondCredentials);
      expect(fixture.xtream.credentials?.server, _secondCredentials.server);
      expect(fixture.xtream.credentials?.username, _secondCredentials.username);
      expect(fixture.xtream.credentials?.password, _secondCredentials.password);
      expect(persistedCredentials, <String, Object?>{
        'server': _secondCredentials.server,
        'username': _secondCredentials.username,
        'password': _secondCredentials.password,
      });
      expect(persistedSource['type'], 'xtream');
      expect(fixture.controller.sourceType, AppSourceType.xtream);
      expect(fixture.controller.liveCategories.single.name, 'Server B Live');
      expect(fixture.controller.vodCategories.single.name, 'Server B Movies');
      expect(
        fixture.controller.seriesCategories.single.name,
        'Server B Series',
      );
      expect(fixture.controller.channels.single.name, 'Server B Channel');
      expect(fixture.controller.vodItems.single.name, 'Server B Movie');
      expect(fixture.controller.seriesList.single.name, 'Server B Show');
      expect(
        fixture.controller.epgService.lookup('server-b')?.current.title,
        'Server B guide',
      );
      expect(reverb.connectedUsers, <String>['second']);
      expect(fixture.push.events, <String>['register:second:device-token']);
      expect(
        (await fixture.cache.get<List<Category>>(
          'liveCategories',
        ))?.data.single.name,
        'Server B Live',
      );
      expect(
        (await fixture.cache.get<List<Channel>>(
          'liveStreams',
        ))?.data.single.name,
        'Server B Channel',
      );
    });

    test('failed catalog replacement restores the persistent cache', () async {
      final failedCatalog = Completer<Object?>();
      final transport = _RacingXtreamTransport(
        blockFirstCatalog: false,
        secondVodCategories: failedCatalog.future,
      );
      final fixture = _Fixture(transport: transport.call);
      addTearDown(fixture.controller.dispose);

      expect(await fixture.controller.connectXtream(_firstCredentials), isTrue);
      await _waitForGuide(fixture.controller, 'Server A guide');

      final secondConnect = fixture.controller.connectXtream(
        _secondCredentials,
      );
      await _waitForCachedLiveCategory(fixture.cache, 'Server B Live');
      failedCatalog.completeError(StateError('catalog unavailable'));

      expect(await secondConnect, isFalse);
      final persistedCredentials =
          jsonDecode(
                (await fixture.storage.read('m3ue_tv_credentials'))!,
              )
              as Map<String, Object?>;
      expect(fixture.auth.credentials, _firstCredentials);
      expect(persistedCredentials, <String, Object?>{
        'server': _firstCredentials.server,
        'username': _firstCredentials.username,
        'password': _firstCredentials.password,
      });
      expect(fixture.controller.sourceType, AppSourceType.xtream);
      expect(fixture.controller.liveCategories.single.name, 'Server A Live');
      expect(fixture.controller.vodCategories.single.name, 'Server A Movies');
      expect(
        fixture.controller.seriesCategories.single.name,
        'Server A Series',
      );
      expect(fixture.controller.channels.single.name, 'Server A Channel');
      expect(fixture.controller.vodItems.single.name, 'Server A Movie');
      expect(fixture.controller.seriesList.single.name, 'Server A Show');
      expect(
        fixture.controller.epgService.lookup('server-a')?.current.title,
        'Server A guide',
      );
      expect(
        (await fixture.cache.get<List<Category>>(
          'liveCategories',
        ))?.data.single.name,
        'Server A Live',
      );
      expect(
        (await fixture.cache.get<List<Category>>(
          'vodCategories',
        ))?.data.single.name,
        'Server A Movies',
      );
      expect(
        (await fixture.cache.get<List<Category>>(
          'seriesCategories',
        ))?.data.single.name,
        'Server A Series',
      );
      expect(
        (await fixture.cache.get<List<Channel>>(
          'liveStreams',
        ))?.data.single.name,
        'Server A Channel',
      );
      expect(
        (await fixture.cache.get<List<VodItem>>(
          'vodStreams',
        ))?.data.single.name,
        'Server A Movie',
      );
      expect(
        (await fixture.cache.get<List<Series>>(
          'seriesStreams',
        ))?.data.single.name,
        'Server A Show',
      );
    });

    test(
      'failed authentication restores the prior notification session',
      () async {
        final reverb = _RecordingReverbService();
        final transport = _RacingXtreamTransport(
          blockFirstCatalog: false,
          failSecondAuthentication: true,
        );
        final fixture = _Fixture(
          transport: transport.call,
          notificationApi: _SessionTvNotificationService(),
          reverbService: reverb,
        );
        addTearDown(fixture.controller.dispose);

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await reverb.firstConnected.future;
        await fixture.controller.setPushToken('device-token');
        fixture.push.events.clear();

        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isFalse,
        );
        await reverb.firstReconnected.future;

        expect(fixture.auth.credentials, _firstCredentials);
        expect(reverb.connectedUsers, <String>['first', 'first']);
        expect(reverb.activeUser, 'first');
        expect(fixture.push.events, <String>[
          'unsubscribe:first:device-token:true',
          'register:first:device-token',
        ]);

        fixture.push.events.clear();
        await fixture.controller.setPushToken('replacement-token');
        expect(fixture.push.events, <String>[
          'unsubscribe:first:device-token:true',
          'register:first:replacement-token',
        ]);
      },
    );

    test('failed catalog restores the prior notification session', () async {
      final failedCatalog = Completer<Object?>();
      final reverb = _RecordingReverbService();
      final transport = _RacingXtreamTransport(
        blockFirstCatalog: false,
        secondVodCategories: failedCatalog.future,
      );
      final fixture = _Fixture(
        transport: transport.call,
        notificationApi: _SessionTvNotificationService(),
        reverbService: reverb,
      );
      addTearDown(fixture.controller.dispose);

      expect(await fixture.controller.connectXtream(_firstCredentials), isTrue);
      await reverb.firstConnected.future;
      await fixture.controller.setPushToken('device-token');
      fixture.push.events.clear();

      final secondConnect = fixture.controller.connectXtream(
        _secondCredentials,
      );
      await _waitForCachedLiveCategory(fixture.cache, 'Server B Live');
      failedCatalog.completeError(StateError('catalog unavailable'));
      expect(await secondConnect, isFalse);
      await reverb.firstReconnected.future;

      expect(fixture.auth.credentials, _firstCredentials);
      expect(reverb.connectedUsers, <String>['first', 'first']);
      expect(reverb.activeUser, 'first');
      expect(fixture.push.events, <String>[
        'unsubscribe:first:device-token:true',
        'register:first:device-token',
      ]);
    });
  });
}

const _firstCredentials = UserCredentials(
  server: 'https://fixture.invalid',
  username: 'first',
  password: 'first-private-value',
);
const _secondCredentials = UserCredentials(
  server: 'https://fixture.invalid',
  username: 'second',
  password: 'second-private-value',
);

class _Fixture {
  _Fixture({
    TvNotificationService? notificationApi,
    ReverbService? reverbService,
    XtreamTransport? transport,
  }) {
    store = PersistentJsonStore(
      file: File(
        '${Directory.systemTemp.path}/m3u-tv-push-${identityHashCode(this)}.json',
      ),
    );
    cache = CacheService(memory: <String, Object?>{}, store: store);
    storage = InMemorySecureStorage();
    xtream = XtreamService(
      transport: transport ?? _FakeXtreamTransport().call,
      cache: cache,
    );
    auth = AuthNotifier(
      xtreamService: xtream,
      secureStorage: storage,
    );
    push = _FakePushNotificationService(
      credentialsArePresent: (credentials) =>
          identical(auth.credentials, credentials),
    );
    controller = AppStateController(
      authNotifier: auth,
      xtreamService: xtream,
      secureStorage: storage,
      cacheService: cache,
      persistentStore: store,
      pushNotificationService: push,
      tvNotificationService: notificationApi ?? _EmptyTvNotificationService(),
      reverbService: reverbService,
    );
  }

  late final PersistentJsonStore store;
  late final CacheService cache;
  late final InMemorySecureStorage storage;
  late final XtreamService xtream;
  late final AuthNotifier auth;
  late final _FakePushNotificationService push;
  late final AppStateController controller;
}

class _FakePushNotificationService extends PushNotificationService {
  _FakePushNotificationService({required this.credentialsArePresent});

  final bool Function(UserCredentials credentials) credentialsArePresent;
  final List<String> events = <String>[];
  final StreamController<String> _tokenRefreshes =
      StreamController<String>.broadcast(sync: true);
  Completer<void>? _unregisterStarted;
  Completer<void>? _releaseUnregister;

  Future<void> delayNextUnregister() {
    _unregisterStarted = Completer<void>();
    _releaseUnregister = Completer<void>();
    return _unregisterStarted!.future;
  }

  void releaseUnregister() => _releaseUnregister!.complete();

  void emitTokenRefresh(String token) => _tokenRefreshes.add(token);

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshes.stream;

  @override
  Future<String?> init({
    required PushMessageHandler onForegroundMessage,
    required PushMessageHandler onMessageOpenedApp,
  }) async => null;

  @override
  Future<void> registerToken(
    UserCredentials creds, {
    required String token,
    required String platform,
  }) async {
    events.add('register:${creds.username}:$token');
  }

  @override
  Future<void> unregisterToken(
    UserCredentials creds, {
    required String token,
  }) async {
    events.add(
      'unsubscribe:${creds.username}:$token:${credentialsArePresent(creds)}',
    );
    final unregisterStarted = _unregisterStarted;
    final releaseUnregister = _releaseUnregister;
    if (unregisterStarted != null && releaseUnregister != null) {
      unregisterStarted.complete();
      await releaseUnregister.future;
      _unregisterStarted = null;
      _releaseUnregister = null;
    }
  }

  @override
  Future<void> dispose() async {
    await _tokenRefreshes.close();
    await super.dispose();
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

class _SessionTvNotificationService extends TvNotificationService {
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

class _DelayedTvNotificationService extends TvNotificationService {
  final Completer<void> firstFetchStarted = Completer<void>();
  final Completer<void> releaseFirstFetch = Completer<void>();
  final Completer<void> firstFetchReturned = Completer<void>();

  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async {
    if (creds.username == 'first') {
      firstFetchStarted.complete();
      await releaseFirstFetch.future;
      firstFetchReturned.complete();
    }
    return (
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
}

class _RecordingReverbService extends ReverbService {
  final List<String> connectedUsers = <String>[];
  final Completer<void> firstConnected = Completer<void>();
  final Completer<void> firstReconnected = Completer<void>();
  final Completer<void> secondConnected = Completer<void>();
  String? activeUser;

  @override
  Future<void> disconnect() async {
    activeUser = null;
  }

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
    connectedUsers.add(credentials.username);
    activeUser = credentials.username;
    if (credentials.username == 'first') {
      if (!firstConnected.isCompleted) {
        firstConnected.complete();
      } else if (!firstReconnected.isCompleted) {
        firstReconnected.complete();
      }
    }
    if (credentials.username == 'second') secondConnected.complete();
  }
}

class _FakeXtreamTransport {
  Future<Object?> call(XtreamRequest request) async =>
      switch (request.action ?? 'auth') {
        'auth' => <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{'version': '0.10.0'},
        },
        'get_live_categories' ||
        'get_vod_categories' ||
        'get_series_categories' ||
        'get_live_streams' ||
        'get_vod_streams' ||
        'get_series' ||
        'get_viewers' => <Object?>[],
        _ => throw StateError('Unexpected fixture action'),
      };
}

class _RacingXtreamTransport {
  _RacingXtreamTransport({
    this.blockFirstCatalog = true,
    this.secondVodCategories,
    this.failSecondAuthentication = false,
  });

  final bool blockFirstCatalog;
  final Future<Object?>? secondVodCategories;
  final bool failSecondAuthentication;
  final Completer<void> firstCatalogStarted = Completer<void>();
  final Completer<void> releaseFirstCatalog = Completer<void>();

  Future<Object?> call(XtreamRequest request) async {
    final isFirst = request.credentials.username == 'first';
    final source = isFirst ? 'A' : 'B';
    final slug = isFirst ? 'server-a' : 'server-b';
    switch (request.action ?? 'auth') {
      case 'auth':
        if (!isFirst && failSecondAuthentication) {
          return <String, Object?>{
            'user_info': <String, Object?>{
              'auth': 0,
              'status': 'Invalid credentials',
            },
            'm3u_editor': <String, Object?>{'version': '0.10.0'},
          };
        }
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{'version': '0.10.0'},
        };
      case 'get_live_categories':
        if (isFirst && blockFirstCatalog) {
          firstCatalogStarted.complete();
          await releaseFirstCatalog.future;
        }
        return <Map<String, Object?>>[
          <String, Object?>{
            'category_id': 'live-$slug',
            'category_name': 'Server $source Live',
          },
        ];
      case 'get_vod_categories':
        if (!isFirst && secondVodCategories != null) {
          return secondVodCategories;
        }
        return <Map<String, Object?>>[
          <String, Object?>{
            'category_id': 'vod-$slug',
            'category_name': 'Server $source Movies',
          },
        ];
      case 'get_series_categories':
        return <Map<String, Object?>>[
          <String, Object?>{
            'category_id': 'series-$slug',
            'category_name': 'Server $source Series',
          },
        ];
      case 'get_live_streams':
        return <Map<String, Object?>>[
          <String, Object?>{
            'stream_id': isFirst ? 101 : 102,
            'name': 'Server $source Channel',
            'category_id': 'live-$slug',
            'epg_channel_id': slug,
          },
        ];
      case 'get_vod_streams':
        return <Map<String, Object?>>[
          <String, Object?>{
            'stream_id': isFirst ? 201 : 202,
            'name': 'Server $source Movie',
            'category_id': 'vod-$slug',
            'container_extension': 'mp4',
          },
        ];
      case 'get_series':
        return <Map<String, Object?>>[
          <String, Object?>{
            'series_id': isFirst ? 301 : 302,
            'name': 'Server $source Show',
            'category_id': 'series-$slug',
          },
        ];
      case 'get_viewers':
        return <Object?>[];
      case 'get_epg_batch':
        final now = DateTime.now();
        return <String, Object?>{
          '${isFirst ? 101 : 102}': <Map<String, Object?>>[
            <String, Object?>{
              'stream_id': isFirst ? 101 : 102,
              'title': base64Encode(utf8.encode('Server $source guide')),
              'description': '',
              'start_timestamp':
                  now
                      .subtract(const Duration(minutes: 10))
                      .millisecondsSinceEpoch ~/
                  1000,
              'stop_timestamp':
                  now.add(const Duration(minutes: 20)).millisecondsSinceEpoch ~/
                  1000,
            },
          ],
        };
      default:
        throw StateError('Unexpected fixture action: ${request.action}');
    }
  }
}

Future<void> _waitForGuide(AppStateController controller, String title) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final channelId = title.contains('A') ? 'server-a' : 'server-b';
    if (controller.epgService.lookup(channelId)?.current.title == title) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for guide');
}

Future<void> _waitForCachedLiveCategory(
  CacheService cache,
  String name,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final categories = await cache.get<List<Category>>('liveCategories');
    if (categories?.data.singleOrNull?.name == name) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for cached live category');
}
