import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _notificationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _accountA = UserCredentials(
  server: 'https://shared.example',
  username: 'account-a',
  password: 'secret-a',
);
const _accountB = UserCredentials(
  server: 'https://shared.example',
  username: 'account-b',
  password: 'secret-b',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'mark-all cannot pair account A IDs with account B credentials after its first await',
    () async {
      final auth = _MutableAuthNotifier(_accountA);
      final api = _RecordingNotificationService();
      final controller = AppStateController(
        authNotifier: auth,
        tvNotificationService: api,
        tvNotificationStore: _SwitchingAllStore(
          () => auth.current = _accountB,
        ),
      );
      addTearDown(controller.dispose);

      await controller.markAllNotificationsRead();
      await pumpEventQueue();

      expect(
        api.markCalls,
        isNot(contains(const _MarkCall(_accountB, _notificationId))),
      );
    },
  );

  final handoffs = <_Handoff>[
    _Handoff(
      name: 'account B',
      successorOwner: 'account-b',
      run: (controller) async {
        expect(await controller.connectXtream(_accountB), isTrue);
      },
    ),
    _Handoff(
      name: 'logged-out state',
      successorOwner: 'logged-out',
      run: (controller) => controller.disconnect(),
    ),
  ];

  for (final handoff in handoffs) {
    test(
      'mark-all started by account A stops after ${handoff.name} during its first await',
      () async {
        final fixture = await _connectedFixture();
        addTearDown(fixture.controller.dispose);
        fixture.store.delayNextAll();

        final staleMark = fixture.controller.markAllNotificationsRead();
        await fixture.store.allStarted.future;

        await handoff.run(fixture.controller);
        fixture.store.selectLocalOwner(handoff.successorOwner);
        fixture.store.releaseAll.complete();
        await staleMark;
        await pumpEventQueue();

        expect(fixture.store.isRead(handoff.successorOwner), isFalse);
        expect(fixture.controller.unreadNotificationCount, 0);
        expect(fixture.api.markCalls, isEmpty);
      },
    );

    test(
      'delayed local mark for account A cannot mark ${handoff.name} with the same UUID',
      () async {
        final fixture = await _connectedFixture();
        addTearDown(fixture.controller.dispose);
        fixture.store.delayNextMark();

        final staleMark = fixture.controller.markNotificationRead(
          _notificationId,
        );
        await fixture.store.markStarted.future;

        await handoff.run(fixture.controller);
        fixture.store.selectLocalOwner(handoff.successorOwner);
        fixture.store.releaseMark.complete();
        await staleMark;
        await pumpEventQueue();

        expect(fixture.store.isRead(handoff.successorOwner), isFalse);
        expect(fixture.api.markCalls, isEmpty);
      },
    );

    test(
      'delayed unread count for account A cannot publish into ${handoff.name}',
      () async {
        final fixture = await _connectedFixture();
        addTearDown(fixture.controller.dispose);
        fixture.store.delayNextUnreadCount(returning: 9);

        final staleMark = fixture.controller.markNotificationRead(
          _notificationId,
        );
        await fixture.store.unreadCountStarted.future;

        await handoff.run(fixture.controller);
        fixture.store.selectLocalOwner(handoff.successorOwner);
        fixture.store.releaseUnreadCount.complete();
        await staleMark;
        await pumpEventQueue();

        expect(fixture.controller.unreadNotificationCount, 0);
        expect(fixture.store.isRead(handoff.successorOwner), isFalse);
        expect(fixture.api.markCalls, isEmpty);
      },
    );
  }

  test(
    'delayed mark-all for account A cannot mark account B with the same UUID',
    () async {
      final fixture = await _connectedFixture();
      addTearDown(fixture.controller.dispose);
      fixture.store.delayNextMarkAll();

      final staleMark = fixture.controller.markAllNotificationsRead();
      await fixture.store.markAllStarted.future;

      expect(await fixture.controller.connectXtream(_accountB), isTrue);
      fixture.store.selectLocalOwner('account-b');
      fixture.store.releaseMarkAll.complete();
      await staleMark;
      await pumpEventQueue();

      expect(fixture.store.isRead('account-b'), isFalse);
      expect(fixture.controller.unreadNotificationCount, 0);
      expect(fixture.api.markCalls, isEmpty);
    },
  );

  test(
    'delayed mark-all unread count cannot publish or send after account B takes ownership',
    () async {
      final fixture = await _connectedFixture();
      addTearDown(fixture.controller.dispose);
      fixture.store.delayNextUnreadCount(returning: 9);

      final staleMark = fixture.controller.markAllNotificationsRead();
      await fixture.store.unreadCountStarted.future;

      expect(await fixture.controller.connectXtream(_accountB), isTrue);
      fixture.store.selectLocalOwner('account-b');
      fixture.store.releaseUnreadCount.complete();
      await staleMark;
      await pumpEventQueue();

      expect(fixture.store.isRead('account-b'), isFalse);
      expect(fixture.controller.unreadNotificationCount, 0);
      expect(fixture.api.markCalls, isEmpty);
    },
  );

  test(
    'delayed channel unread count cannot publish after account B takes ownership',
    () async {
      final fixture = await _connectedFixture();
      addTearDown(fixture.controller.dispose);
      fixture.store.delayNextUnreadCount(returning: 9);

      final staleUpdate = fixture.controller.setNotificationChannels({
        'general',
      });
      await fixture.store.unreadCountStarted.future;

      expect(await fixture.controller.connectXtream(_accountB), isTrue);
      fixture.store.selectLocalOwner('account-b');
      fixture.store.releaseUnreadCount.complete();
      await staleUpdate;

      expect(fixture.controller.unreadNotificationCount, 0);
    },
  );

  test(
    'current owner mark-all publishes and applies each effect once',
    () async {
      final fixture = await _connectedFixture();
      addTearDown(fixture.controller.dispose);
      fixture.store.resetEffectCounts();
      var publications = 0;
      void recordPublication() => publications += 1;
      fixture.controller.addListener(recordPublication);
      addTearDown(() => fixture.controller.removeListener(recordPublication));

      await fixture.controller.markAllNotificationsRead();
      await pumpEventQueue();

      expect(fixture.store.isRead('account-a'), isTrue);
      expect(fixture.store.allCalls, 1);
      expect(fixture.store.localMarkAllMutations, 1);
      expect(fixture.store.subscribedChannelsCalls, 1);
      expect(fixture.store.unreadCountCalls, 1);
      expect(publications, 1);
      expect(fixture.api.markCalls, <_MarkCall>[
        const _MarkCall(_accountA, _notificationId),
      ]);
    },
  );

  test(
    'current owner marks locally and sends the same account A credentials',
    () async {
      final fixture = await _connectedFixture();
      addTearDown(fixture.controller.dispose);
      fixture.store.delayNextMark();

      final mark = fixture.controller.markNotificationRead(_notificationId);
      await fixture.store.markStarted.future;
      fixture.store.releaseMark.complete();
      await mark;
      await pumpEventQueue();

      expect(fixture.store.isRead('account-a'), isTrue);
      expect(fixture.api.markCalls, <_MarkCall>[
        const _MarkCall(_accountA, _notificationId),
      ]);
    },
  );
}

class _Handoff {
  const _Handoff({
    required this.name,
    required this.successorOwner,
    required this.run,
  });

  final String name;
  final String successorOwner;
  final Future<void> Function(AppStateController controller) run;
}

Future<_Fixture> _connectedFixture() async {
  final memory = <String, Object?>{};
  final store = _DelayedNotificationStore();
  final api = _RecordingNotificationService();
  final controller = AppStateController(
    xtreamService: XtreamService(
      transport: _NotificationTransport().call,
      cache: CacheService(memory: <String, Object?>{}),
    ),
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    favoritesService: FavoritesService(memory: memory),
    vodFavoritesService: FavoritesService(memory: memory, namespace: 'vod'),
    seriesFavoritesService: FavoritesService(
      memory: memory,
      namespace: 'series',
    ),
    resumeService: ResumeService(memory: memory),
    viewerService: ViewerService(memory: memory),
    tvNotificationService: api,
    tvNotificationStore: store,
    reverbService: _NoopReverbService(),
  );
  expect(await controller.connectXtream(_accountA), isTrue);
  await pumpEventQueue();
  store.selectLocalOwner('account-a');
  return _Fixture(controller, store, api);
}

class _Fixture {
  const _Fixture(this.controller, this.store, this.api);

  final AppStateController controller;
  final _DelayedNotificationStore store;
  final _RecordingNotificationService api;
}

class _DelayedNotificationStore extends TvNotificationStore {
  _DelayedNotificationStore() : super(memory: <String, Object?>{});

  final Map<String, bool> _readByOwner = <String, bool>{
    'account-a': false,
    'account-b': false,
    'm3u': false,
    'logged-out': false,
  };
  String _localOwner = 'account-a';
  bool _delayMark = false;
  bool _delayMarkAll = false;
  bool _delayAll = false;
  bool _delayUnreadCount = false;
  bool _unreadCountDelayClaimed = false;
  int _delayedUnreadCount = 0;
  Completer<void> markStarted = Completer<void>();
  Completer<void> releaseMark = Completer<void>();
  Completer<void> markAllStarted = Completer<void>();
  Completer<void> releaseMarkAll = Completer<void>();
  Completer<void> allStarted = Completer<void>();
  Completer<void> releaseAll = Completer<void>();
  Completer<void> unreadCountStarted = Completer<void>();
  Completer<void> releaseUnreadCount = Completer<void>();
  int allCalls = 0;
  int localMarkAllMutations = 0;
  int subscribedChannelsCalls = 0;
  int unreadCountCalls = 0;

  void selectLocalOwner(String owner) {
    _localOwner = owner;
  }

  bool isRead(String owner) => _readByOwner[owner]!;

  void delayNextMark() {
    _delayMark = true;
    markStarted = Completer<void>();
    releaseMark = Completer<void>();
  }

  void delayNextMarkAll() {
    _delayMarkAll = true;
    markAllStarted = Completer<void>();
    releaseMarkAll = Completer<void>();
  }

  void delayNextAll() {
    _delayAll = true;
    allStarted = Completer<void>();
    releaseAll = Completer<void>();
  }

  void resetEffectCounts() {
    allCalls = 0;
    localMarkAllMutations = 0;
    subscribedChannelsCalls = 0;
    unreadCountCalls = 0;
  }

  void delayNextUnreadCount({required int returning}) {
    _delayUnreadCount = true;
    _unreadCountDelayClaimed = false;
    _delayedUnreadCount = returning;
    unreadCountStarted = Completer<void>();
    releaseUnreadCount = Completer<void>();
  }

  @override
  Future<void> markReadIf(String id, bool Function() shouldCommit) async {
    if (_delayMark) {
      _delayMark = false;
      markStarted.complete();
      await releaseMark.future;
    }
    if (shouldCommit()) {
      _readByOwner[_localOwner] = true;
    }
  }

  @override
  Future<List<StoredTvNotification>> all({Set<String>? channelFilter}) async {
    allCalls += 1;
    if (_delayAll) {
      _delayAll = false;
      allStarted.complete();
      await releaseAll.future;
    }
    return <StoredTvNotification>[
      StoredTvNotification(
        item: const TvNotificationItem(
          id: _notificationId,
          channel: 'general',
          title: 'Same UUID',
          status: 'info',
        ),
        receivedAt: DateTime(2026),
        isRead: _readByOwner[_localOwner]!,
      ),
    ];
  }

  @override
  Future<void> markAllRead() => _markAllRead();

  @override
  Future<void> markAllReadIf(bool Function() shouldCommit) =>
      _markAllRead(shouldCommit: shouldCommit);

  Future<void> _markAllRead({bool Function()? shouldCommit}) async {
    if (_delayMarkAll) {
      _delayMarkAll = false;
      markAllStarted.complete();
      await releaseMarkAll.future;
    }
    if (shouldCommit?.call() ?? true) {
      _readByOwner[_localOwner] = true;
      localMarkAllMutations += 1;
    }
  }

  @override
  Future<Set<String>> subscribedChannels() async {
    subscribedChannelsCalls += 1;
    return <String>{};
  }

  @override
  Future<int> unreadCount({Set<String>? channelFilter}) async {
    unreadCountCalls += 1;
    if (_delayUnreadCount && !_unreadCountDelayClaimed) {
      _unreadCountDelayClaimed = true;
      unreadCountStarted.complete();
      await releaseUnreadCount.future;
      return _delayedUnreadCount;
    }
    return _readByOwner[_localOwner]! ? 0 : 1;
  }

  @override
  Future<List<TvNotificationItem>> syncUnreadWithServer(
    List<TvNotificationItem> serverUnread, {
    bool Function()? shouldCommit,
  }) async => const <TvNotificationItem>[];
}

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this.current)
    : super(
        xtreamService: XtreamService(),
        secureStorage: InMemorySecureStorage(),
      );

  UserCredentials? current;

  @override
  UserCredentials? get credentials => current;
}

class _SwitchingAllStore extends TvNotificationStore {
  _SwitchingAllStore(this.onAll) : super(memory: <String, Object?>{});

  final void Function() onAll;

  @override
  Future<List<StoredTvNotification>> all({Set<String>? channelFilter}) async {
    onAll();
    return <StoredTvNotification>[
      StoredTvNotification(
        item: const TvNotificationItem(
          id: _notificationId,
          channel: 'general',
          title: 'Account A private notification',
          status: 'info',
        ),
        receivedAt: DateTime(2026),
        isRead: false,
      ),
    ];
  }
}

class _NotificationTransport {
  Future<Object?> call(XtreamRequest request) async {
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'server_info': <String, Object?>{'timezone': 'UTC'},
          'm3u_editor': <String, Object?>{
            'version': '0.10.0',
            'features': const <String>[],
          },
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_viewers':
        return const <Object?>[];
      default:
        throw StateError('No fixture for ${request.action}');
    }
  }
}

class _RecordingNotificationService extends TvNotificationService {
  final List<_MarkCall> markCalls = <_MarkCall>[];
  final Completer<void> _accountBFetch = Completer<void>();

  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async {
    if (creds.username == _accountB.username) {
      await _accountBFetch.future;
    }
    return const (
      TvPlaylistSession(
        notifiableId: 17,
        notifiableType: 'playlist',
        isAdmin: false,
        channelName: '',
        reverb: ReverbConfig(host: '', port: 0, scheme: 'wss', appKey: ''),
      ),
      <TvNotificationItem>[
        TvNotificationItem(
          id: _notificationId,
          channel: 'general',
          title: 'Same UUID',
          status: 'info',
        ),
      ],
    );
  }

  @override
  Future<void> markRead(UserCredentials creds, String id) async {
    markCalls.add(_MarkCall(creds, id));
  }
}

class _MarkCall {
  const _MarkCall(this.credentials, this.id);

  final UserCredentials credentials;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is _MarkCall &&
      other.credentials.server == credentials.server &&
      other.credentials.username == credentials.username &&
      other.credentials.password == credentials.password &&
      other.id == id;

  @override
  int get hashCode => Object.hash(
    credentials.server,
    credentials.username,
    credentials.password,
    id,
  );
}

class _NoopReverbService extends ReverbService {
  @override
  Future<void> disconnect() async {}
}
