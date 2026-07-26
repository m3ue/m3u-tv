import 'dart:async';
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
  }) {
    final store = PersistentJsonStore(
      file: File(
        '${Directory.systemTemp.path}/m3u-tv-push-${identityHashCode(this)}.json',
      ),
    );
    xtream = XtreamService(
      transport: _FakeXtreamTransport().call,
      cache: CacheService(memory: <String, Object?>{}),
    );
    auth = AuthNotifier(
      xtreamService: xtream,
      secureStorage: InMemorySecureStorage(),
    );
    push = _FakePushNotificationService(
      credentialsArePresent: (credentials) =>
          identical(auth.credentials, credentials),
    );
    controller = AppStateController(
      authNotifier: auth,
      xtreamService: xtream,
      secureStorage: auth.secureStorage,
      persistentStore: store,
      pushNotificationService: push,
      tvNotificationService: notificationApi ?? _EmptyTvNotificationService(),
      reverbService: reverbService,
    );
  }

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
  final Completer<void> secondConnected = Completer<void>();

  @override
  Future<void> connect({
    required TvPlaylistSession session,
    required UserCredentials credentials,
    Set<String> subscribedChannels = const <String>{},
    required void Function(TvNotificationItem) onNotification,
    void Function(DvrRecording)? onDvrStatus,
    void Function(MediaRequestSummary)? onRequestStatus,
    void Function()? onConnected,
  }) async {
    connectedUsers.add(credentials.username);
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
