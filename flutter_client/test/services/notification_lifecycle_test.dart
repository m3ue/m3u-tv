import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/push_notification_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('notification reconciliation', () {
    test('rejects a missing or malformed canonical notification UUID', () {
      expect(
        TvNotificationItem.tryFromJson(<String, Object?>{
          'channel': 'general',
          'title': 'Missing identity',
        }),
        isNull,
      );
      expect(
        TvNotificationItem.tryFromJson(<String, Object?>{
          'id': 'aaaaaaaa-aaaa-0aaa-0aaa-aaaaaaaaaaaa',
          'channel': 'general',
          'title': 'Invalid UUID version and variant',
        }),
        isNull,
      );
      expect(
        TvNotificationItem.tryFromJson(<String, Object?>{
          'id': 'not-a-uuid',
          'channel': 'general',
          'title': 'Malformed identity',
        }),
        isNull,
      );
    });

    test(
      'REST then Reverb then repeated foreground FCM stores and presents once',
      () async {
        final item = TvNotificationItem.tryFromJson(<String, Object?>{
          'id': _notificationId,
          'channel': 'general',
          'title': 'Authoritative title',
          'body': 'Authoritative body',
          'status': 'info',
        })!;
        final api = _FakeTvNotificationService(<TvNotificationItem>[item]);
        final store = TvNotificationStore(memory: <String, Object?>{});
        final controller = AppStateController(
          authNotifier: _FixedAuthNotifier(_credentials),
          tvNotificationService: api,
          tvNotificationStore: store,
        );
        addTearDown(controller.dispose);
        final presented = <TvNotificationItem>[];
        final subscription = controller.tvNotifications.listen(presented.add);
        addTearDown(subscription.cancel);

        await controller.reconcileNotifications();
        await controller.receiveTvNotification(item);
        await controller.handleForegroundPush(
          const PushMessage(
            data: <String, String>{'notification_id': _notificationId},
          ),
        );
        await controller.handleForegroundPush(
          const PushMessage(
            data: <String, String>{'notification_id': _notificationId},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect((await store.all()).map((stored) => stored.item.id), [
          _notificationId,
        ]);
        expect(presented.map((notification) => notification.id), [
          _notificationId,
        ]);
        expect(api.fetchCalls, 3);
      },
    );

    test('concurrent duplicate receipts report one insertion', () async {
      final store = TvNotificationStore(memory: <String, Object?>{});
      final item = _item(id: _notificationId, channel: 'general');

      final inserted = await Future.wait<bool>(<Future<bool>>[
        store.add(item),
        store.add(item),
      ]);

      expect(inserted.where((value) => value), hasLength(1));
      expect(await store.all(), hasLength(1));
    });

    test('restores the admin-only flag from persisted notifications', () async {
      final memory = <String, Object?>{};
      final store = TvNotificationStore(memory: memory);
      await store.add(
        const TvNotificationItem(
          id: _notificationId,
          channel: 'general',
          title: 'Admin only',
          status: 'warning',
          adminOnly: true,
        ),
      );

      final restored = await TvNotificationStore(memory: memory).all();

      expect(restored.single.item.adminOnly, isTrue);
    });
  });

  group('notification activation', () {
    for (final entry in <String, TvNotificationDestination>{
      'general': TvNotificationDestination.notifications,
      'dvr': TvNotificationDestination.dvr,
      'requests': TvNotificationDestination.requests,
    }.entries) {
      test(
        'opened-app ${entry.key} activates its safe destination once',
        () async {
          final item = _item(id: _notificationId, channel: entry.key);
          final api = _FakeTvNotificationService(<TvNotificationItem>[item]);
          final controller = _controller(api);
          addTearDown(controller.dispose);
          final destinations = <TvNotificationDestination>[];
          final subscription = controller.notificationActivations.listen(
            destinations.add,
          );
          addTearDown(subscription.cancel);
          const message = PushMessage(
            data: <String, String>{
              'notification_id': _notificationId,
              'route': 'https://attacker.invalid/private',
              'url': '/arbitrary-route',
            },
          );

          await controller.handlePushActivation(message);
          await controller.handlePushActivation(message);
          await Future<void>.delayed(Duration.zero);

          expect(destinations, <TvNotificationDestination>[entry.value]);
        },
      );
    }

    test('unknown category and arbitrary routes fail closed', () async {
      final api = _FakeTvNotificationService(<TvNotificationItem>[
        _item(id: _notificationId, channel: 'untrusted-category'),
      ]);
      final controller = _controller(api);
      addTearDown(controller.dispose);
      final destinations = <TvNotificationDestination>[];
      final subscription = controller.notificationActivations.listen(
        destinations.add,
      );
      addTearDown(subscription.cancel);

      await controller.handlePushActivation(
        const PushMessage(
          data: <String, String>{
            'notification_id': _notificationId,
            'route': '/arbitrary-route',
            'url': 'https://attacker.invalid/private',
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(destinations, isEmpty);
    });

    test(
      'missing and malformed UUIDs fail closed before REST lookup',
      () async {
        final api = _FakeTvNotificationService(<TvNotificationItem>[]);
        final controller = _controller(api);
        addTearDown(controller.dispose);
        final destinations = <TvNotificationDestination>[];
        final subscription = controller.notificationActivations.listen(
          destinations.add,
        );
        addTearDown(subscription.cancel);

        await controller.handlePushActivation(
          const PushMessage(data: <String, String>{}),
        );
        await controller.handlePushActivation(
          const PushMessage(
            data: <String, String>{'notification_id': 'malformed'},
          ),
        );

        expect(api.fetchCalls, 0);
        expect(destinations, isEmpty);
      },
    );

    test('ID-only activation uses authoritative unread state', () async {
      final item = _item(id: _notificationId, channel: 'dvr');
      final api = _FakeTvNotificationService(<TvNotificationItem>[item]);
      final controller = _controller(api);
      addTearDown(controller.dispose);
      final destinations = <TvNotificationDestination>[];
      final subscription = controller.notificationActivations.listen(
        destinations.add,
      );
      addTearDown(subscription.cancel);

      await controller.handleNotificationActivation(_notificationId);
      await controller.handleNotificationActivation('malformed');
      await Future<void>.delayed(Duration.zero);

      expect(api.fetchCalls, 1);
      expect(destinations, <TvNotificationDestination>[
        TvNotificationDestination.dvr,
      ]);
    });

    test('admin-only content fails closed for standard credentials', () async {
      final api = _FakeTvNotificationService(<TvNotificationItem>[
        const TvNotificationItem(
          id: _notificationId,
          channel: 'general',
          title: 'Admin only',
          status: 'warning',
          adminOnly: true,
        ),
      ]);
      final store = TvNotificationStore(memory: <String, Object?>{});
      final controller = _controller(api, store: store);
      addTearDown(controller.dispose);
      final destinations = <TvNotificationDestination>[];
      final subscription = controller.notificationActivations.listen(
        destinations.add,
      );
      addTearDown(subscription.cancel);

      await controller.handlePushActivation(
        const PushMessage(
          data: <String, String>{'notification_id': _notificationId},
        ),
      );

      expect(destinations, isEmpty);
      expect(await store.all(), isEmpty);
    });

    test(
      'unauthorized requester payload is not authorized client-side',
      () async {
        final api = _FakeTvNotificationService(<TvNotificationItem>[]);
        final store = TvNotificationStore(memory: <String, Object?>{});
        final controller = _controller(api, store: store);
        addTearDown(controller.dispose);
        final destinations = <TvNotificationDestination>[];
        final subscription = controller.notificationActivations.listen(
          destinations.add,
        );
        addTearDown(subscription.cancel);

        await controller.handlePushActivation(
          const PushMessage(
            data: <String, String>{
              'notification_id': _notificationId,
              'channel': 'requests',
              'request_id': '123',
            },
          ),
        );

        expect(destinations, isEmpty);
        expect(await store.all(), isEmpty);
      },
    );

    test(
      'background OS tap reconciles without a second in-app toast',
      () async {
        final item = _item(id: _notificationId, channel: 'general');
        final api = _FakeTvNotificationService(<TvNotificationItem>[item]);
        final controller = _controller(api);
        addTearDown(controller.dispose);
        final presented = <TvNotificationItem>[];
        final presentationSubscription = controller.tvNotifications.listen(
          presented.add,
        );
        addTearDown(presentationSubscription.cancel);

        await controller.handlePushActivation(
          const PushMessage(
            data: <String, String>{'notification_id': _notificationId},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(presented, isEmpty);
        expect(
          (await controller.notificationStore.all()).single.item.id,
          item.id,
        );
      },
    );

    for (final entry in <String, TvNotificationDestination>{
      'general': TvNotificationDestination.notifications,
      'dvr': TvNotificationDestination.dvr,
      'requests': TvNotificationDestination.requests,
    }.entries) {
      test('cold-start ${entry.key} waits for restored credentials', () async {
        final item = _item(id: _notificationId, channel: entry.key);
        final api = _FakeTvNotificationService(<TvNotificationItem>[item]);
        final auth = _MutableAuthNotifier();
        final controller = AppStateController(
          authNotifier: auth,
          tvNotificationService: api,
          tvNotificationStore: TvNotificationStore(memory: <String, Object?>{}),
        );
        addTearDown(controller.dispose);
        final presented = <TvNotificationItem>[];
        final destinations = <TvNotificationDestination>[];
        final presentationSubscription = controller.tvNotifications.listen(
          presented.add,
        );
        final activationSubscription = controller.notificationActivations
            .listen(
              destinations.add,
            );
        addTearDown(presentationSubscription.cancel);
        addTearDown(activationSubscription.cancel);

        await controller.handlePushActivation(
          const PushMessage(
            data: <String, String>{'notification_id': _notificationId},
          ),
        );
        expect(api.fetchCalls, 0);

        auth.fixedCredentials = _credentials;
        await controller.resumeNotifications();
        await Future<void>.delayed(Duration.zero);

        expect(presented, isEmpty);
        expect(destinations, <TvNotificationDestination>[entry.value]);
      });
    }

    test('requester-scoped REST fixture isolates two credentials', () async {
      final requesterItem = _item(
        id: _notificationId,
        channel: 'requests',
      );
      final requesterApi = _FakeTvNotificationService(<TvNotificationItem>[
        requesterItem,
      ]);
      final otherApi = _FakeTvNotificationService(const <TvNotificationItem>[]);
      final requester = _controller(requesterApi);
      final other = _controller(otherApi, credentials: _otherCredentials);
      addTearDown(requester.dispose);
      addTearDown(other.dispose);
      final requesterDestinations = <TvNotificationDestination>[];
      final otherDestinations = <TvNotificationDestination>[];
      final requesterSubscription = requester.notificationActivations.listen(
        requesterDestinations.add,
      );
      final otherSubscription = other.notificationActivations.listen(
        otherDestinations.add,
      );
      addTearDown(requesterSubscription.cancel);
      addTearDown(otherSubscription.cancel);
      const message = PushMessage(
        data: <String, String>{'notification_id': _notificationId},
      );

      await requester.handlePushActivation(message);
      await other.handlePushActivation(message);
      await Future<void>.delayed(Duration.zero);

      expect(requesterDestinations, <TvNotificationDestination>[
        TvNotificationDestination.requests,
      ]);
      expect(otherDestinations, isEmpty);
      expect(await requester.notificationStore.all(), hasLength(1));
      expect(await other.notificationStore.all(), isEmpty);
    });
  });
}

const _notificationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _credentials = UserCredentials(
  server: 'https://fixture.invalid',
  username: 'requester-one',
  password: 'private-value',
);
const _otherCredentials = UserCredentials(
  server: 'https://fixture.invalid',
  username: 'requester-two',
  password: 'other-private-value',
);

TvNotificationItem _item({required String id, required String channel}) =>
    TvNotificationItem(
      id: id,
      channel: channel,
      title: 'Authoritative title',
      body: 'Authoritative body',
      status: 'info',
    );

AppStateController _controller(
  _FakeTvNotificationService api, {
  TvNotificationStore? store,
  UserCredentials credentials = _credentials,
}) => AppStateController(
  authNotifier: _FixedAuthNotifier(credentials),
  tvNotificationService: api,
  tvNotificationStore:
      store ?? TvNotificationStore(memory: <String, Object?>{}),
);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this.fixedCredentials)
    : super(
        xtreamService: XtreamService(),
        secureStorage: InMemorySecureStorage(),
      );

  final UserCredentials fixedCredentials;

  @override
  UserCredentials? get credentials => fixedCredentials;
}

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier()
    : super(
        xtreamService: XtreamService(),
        secureStorage: InMemorySecureStorage(),
      );

  UserCredentials? fixedCredentials;

  @override
  UserCredentials? get credentials => fixedCredentials;
}

class _FakeTvNotificationService extends TvNotificationService {
  _FakeTvNotificationService(this.unread);

  final List<TvNotificationItem> unread;
  int fetchCalls = 0;

  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async {
    fetchCalls += 1;
    return (
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
      unread,
    );
  }
}
