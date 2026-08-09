import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';

const _notificationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _secondNotificationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _accountA = UserCredentials(
  server: 'HTTPS://Shared.Example:443/api/',
  username: 'Account-A',
  password: 'account-a-password-sentinel',
);
const _accountB = UserCredentials(
  server: 'https://shared.example/api',
  username: 'account-b',
  password: 'account-b-password-sentinel',
);
const _session = TvPlaylistSession(
  notifiableId: 17,
  notifiableType: 'playlist',
  isAdmin: false,
  channelName: '',
  reverb: ReverbConfig(
    host: 'shared.example',
    port: 443,
    scheme: 'wss',
    appKey: '',
  ),
);

void main() {
  test(
    'current owner add read mark-all and channel behavior is preserved',
    () async {
      final store = TvNotificationStore(memory: <String, Object?>{});
      _selectOwner(store, _accountA);

      expect(await store.add(_item(_notificationId, 'general')), isTrue);
      expect(await store.add(_item(_secondNotificationId, 'requests')), isTrue);
      await store.setSubscribedChannels(<String>{'general'});
      await store.setServerChannels(const <TvNotificationChannel>[
        TvNotificationChannel(name: 'general', label: 'General'),
      ]);

      expect(await store.subscribedChannels(), <String>{'general'});
      expect(
        (await store.knownChannels()).map((channel) => channel.name),
        <String>['general', 'requests'],
      );
      expect(await store.unreadCount(), 2);

      await store.markReadIf(_notificationId, () => true);
      expect(
        (await store.all())
            .firstWhere((n) => n.item.id == _notificationId)
            .isRead,
        isTrue,
      );
      await store.markAllReadIf(() => true);
      expect(
        (await store.all()).every((notification) => notification.isRead),
        isTrue,
      );
    },
  );

  test(
    'account principals are case-sensitive and password rotation keeps state',
    () async {
      final memory = <String, Object?>{};
      final store = TvNotificationStore(memory: memory);
      _selectOwner(store, _accountA);
      await store.add(_item(_notificationId, 'account-a'));
      await store.setSubscribedChannels(<String>{'account-a'});

      _selectOwner(
        store,
        const UserCredentials(
          server: 'https://shared.example/api',
          username: 'account-a',
          password: 'case-distinct-password-sentinel',
        ),
      );

      expect(await store.all(), isEmpty);
      expect(await store.subscribedChannels(), isEmpty);
      expect(await store.knownChannels(), isEmpty);

      _selectOwner(
        store,
        const UserCredentials(
          server: 'https://shared.example/api',
          username: 'Account-A',
          password: 'rotated-password-sentinel',
        ),
      );

      expect((await store.all()).single.item.channel, 'account-a');
      expect(await store.subscribedChannels(), <String>{'account-a'});
      final persisted = memory.toString();
      expect(persisted, isNot(contains(_accountA.password)));
      expect(persisted, isNot(contains('case-distinct-password-sentinel')));
      expect(persisted, isNot(contains('rotated-password-sentinel')));
    },
  );

  test('legacy account-unqualified v2 keys fail closed', () async {
    final legacyOwner = sha256
        .convert(
          utf8.encode(
            'https://shared.example/api|playlist|${_session.notifiableId}',
          ),
        )
        .toString();
    final memory = <String, Object?>{
      'm3ue_tv_notifications_v2_$legacyOwner': <Map<String, Object?>>[
        _stored(_item(_notificationId, 'legacy-private')),
      ],
      'm3ue_tv_notification_channels_v2_$legacyOwner': <String>[
        'legacy-private',
      ],
      'm3ue_tv_server_channels_v2_$legacyOwner': <Map<String, Object?>>[
        <String, Object?>{'name': 'legacy-private', 'label': 'Legacy private'},
      ],
    };
    final store = TvNotificationStore(memory: memory);

    _selectOwner(store, _accountA);

    expect(await store.all(), isEmpty);
    expect(await store.subscribedChannels(), isEmpty);
    expect(await store.knownChannels(), isEmpty);
  });

  test('cleared owner fails closed for Direct M3U and logout state', () async {
    final store = TvNotificationStore(memory: <String, Object?>{});
    _selectOwner(store, _accountA);
    await store.add(_item(_notificationId, 'private'));
    await store.setSubscribedChannels(<String>{'private'});
    await store.setServerChannels(const <TvNotificationChannel>[
      TvNotificationChannel(name: 'private', label: 'Private'),
    ]);

    store.clearOwner();
    await store.markReadIf(_notificationId, () => true);
    await store.markAllReadIf(() => true);
    await store.setSubscribedChannels(<String>{'other'});
    await store.setServerChannels(const <TvNotificationChannel>[
      TvNotificationChannel(name: 'other', label: 'Other'),
    ]);

    expect(await store.all(), isEmpty);
    expect(await store.subscribedChannels(), isEmpty);
    expect(await store.knownChannels(), isEmpty);
  });

  test(
    'account change rejects an in-flight write before queued mutation',
    () async {
      final persistentStore = _BlockingPersistentStore();
      final store = TvNotificationStore(store: persistentStore);
      _selectOwner(store, _accountA);

      final accountAWrite = store.add(
        _item(_notificationId, 'account-a', title: 'Account A private'),
      );
      await persistentStore.writeStarted.future;
      _selectOwner(store, _accountB);
      final accountBWrite = store.add(
        _item(_notificationId, 'account-b', title: 'Account B private'),
      );
      persistentStore.releaseWrite.complete();

      expect(await accountAWrite, isFalse);
      expect(await accountBWrite, isTrue);
      expect((await store.all()).single.item.title, 'Account B private');

      _selectOwner(store, _accountA);
      expect(await store.all(), isEmpty);
    },
  );
}

void _selectOwner(TvNotificationStore store, UserCredentials credentials) {
  expect(
    store.selectOwner(
      server: credentials.server,
      accountPrincipal: credentials.username,
      session: _session,
    ),
    isTrue,
  );
}

TvNotificationItem _item(String id, String channel, {String? title}) =>
    TvNotificationItem(
      id: id,
      channel: channel,
      title: title ?? channel,
      status: 'info',
    );

Map<String, Object?> _stored(TvNotificationItem item) => StoredTvNotification(
  item: item,
  receivedAt: DateTime.utc(2026),
  isRead: false,
).toJson();

class _BlockingPersistentStore extends PersistentJsonStore {
  final Map<String, Object?> _values = <String, Object?>{};
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();
  bool _blockNextWrite = true;

  @override
  Future<Object?> read(String key) async => _values[key];

  @override
  Future<bool> writeIf(
    String key,
    Object? value,
    bool Function() shouldCommit,
  ) async {
    if (_blockNextWrite) {
      _blockNextWrite = false;
      writeStarted.complete();
      await releaseWrite.future;
    }
    if (!shouldCommit()) return false;
    _values[key] = value;
    return true;
  }
}
