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
import 'package:m3u_tv/services/tv_notification_store.dart';
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

    for (final boundary in <String>['server channels', 'unread sync']) {
      for (final transition in <String>['viewer', 'source']) {
        test(
          'post-fetch $boundary cannot survive a $transition handoff',
          () async {
            final notificationPersistence = _BlockingNotificationStore();
            final notificationStore = TvNotificationStore(
              store: notificationPersistence,
            );
            final api = _UnreadReconciliationTvNotificationService(
              includeServerChannels: boundary == 'server channels',
            );
            final fixture = _Fixture(
              notificationApi: api,
              notificationStore: notificationStore,
            );
            addTearDown(fixture.controller.dispose);
            expect(
              await fixture.controller.connectXtream(_firstCredentials),
              isTrue,
            );
            await api.initialFetchCompleted.future;
            await fixture.controller.receiveTvNotification(
              _existingNotification,
            );
            final presented = <TvNotificationItem>[];
            final subscription = fixture.controller.tvNotifications.listen(
              presented.add,
            );
            addTearDown(subscription.cancel);
            var controllerNotifications = 0;
            fixture.controller.addListener(
              () => controllerNotifications += 1,
            );
            var persistenceCallbacks = 0;
            void onPersistenceCommit() => persistenceCallbacks += 1;
            notificationPersistence
              ..onCommit = onPersistenceCommit
              ..resetCommits();
            final write = notificationPersistence.blockNextWrite();

            final reconciliation = fixture.controller.reconcileNotifications();
            await write.started.future;
            if (transition == 'viewer') {
              await fixture.controller.switchViewer(
                const Viewer(
                  id: 2,
                  ulid: 'viewer-b',
                  name: 'Viewer B',
                  isAdmin: false,
                ),
              );
            } else {
              await fixture.controller.disconnect();
            }
            controllerNotifications = 0;
            notificationPersistence.resetCommits();
            write.release.complete();
            await reconciliation;
            await write.completed.future;
            await pumpEventQueue();

            expect(
              (await notificationStore.all()).map((stored) => stored.item.id),
              transition == 'viewer'
                  ? <String>[_existingNotification.id]
                  : <String>[],
            );
            expect(await notificationStore.serverChannels(), isEmpty);
            expect(
              fixture.controller.unreadNotificationCount,
              transition == 'viewer' ? 1 : 0,
            );
            expect(notificationPersistence.commits, 0);
            expect(persistenceCallbacks, 0);
            expect(controllerNotifications, 0);
            expect(presented, isEmpty);
          },
        );
      }
    }

    test(
      'current reconciliation owner persists and publishes exactly once',
      () async {
        final notificationPersistence = _BlockingNotificationStore();
        final notificationStore = TvNotificationStore(
          store: notificationPersistence,
        );
        final api = _UnreadReconciliationTvNotificationService(
          includeServerChannels: true,
        );
        final fixture = _Fixture(
          notificationApi: api,
          notificationStore: notificationStore,
        );
        addTearDown(fixture.controller.dispose);
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await api.initialFetchCompleted.future;
        await fixture.controller.receiveTvNotification(_existingNotification);
        final presented = <TvNotificationItem>[];
        final subscription = fixture.controller.tvNotifications.listen(
          presented.add,
        );
        addTearDown(subscription.cancel);
        var controllerNotifications = 0;
        fixture.controller.addListener(() => controllerNotifications += 1);
        var persistenceCallbacks = 0;
        void onPersistenceCommit() => persistenceCallbacks += 1;
        notificationPersistence
          ..onCommit = onPersistenceCommit
          ..resetCommits();

        await fixture.controller.reconcileNotifications();
        await pumpEventQueue();

        expect(
          (await notificationStore.all()).map((stored) => stored.item.id),
          <String>[_reconciledNotification.id],
        );
        expect(
          (await notificationStore.serverChannels()).map(
            (channel) => channel.name,
          ),
          <String>['general'],
        );
        expect(fixture.controller.unreadNotificationCount, 1);
        expect(notificationPersistence.commits, 2);
        expect(persistenceCallbacks, 2);
        expect(controllerNotifications, 1);
        expect(presented, <TvNotificationItem>[_reconciledNotification]);
      },
    );

    for (final transition in <String>['viewer', 'source']) {
      test(
        'delayed Reverb notification cannot survive a $transition handoff',
        () async {
          final notificationPersistence = _BlockingNotificationStore();
          final notificationStore = TvNotificationStore(
            store: notificationPersistence,
          );
          final reverb = _RecordingReverbService();
          final fixture = _Fixture(
            notificationApi: _SessionTvNotificationService(),
            notificationStore: notificationStore,
            reverbService: reverb,
          );
          addTearDown(fixture.controller.dispose);
          expect(
            await fixture.controller.connectXtream(_firstCredentials),
            isTrue,
          );
          await reverb.firstConnected.future;
          final presented = <TvNotificationItem>[];
          final subscription = fixture.controller.tvNotifications.listen(
            presented.add,
          );
          addTearDown(subscription.cancel);
          var controllerNotifications = 0;
          fixture.controller.addListener(() => controllerNotifications += 1);
          final write = notificationPersistence.blockNextWrite();

          reverb.emitNotification(
            'first',
            const TvNotificationItem(
              id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              channel: 'general',
              title: 'Source A notification',
              status: 'info',
            ),
          );
          await write.started.future;
          if (transition == 'viewer') {
            await fixture.controller.switchViewer(
              const Viewer(
                id: 2,
                ulid: 'viewer-b',
                name: 'Viewer B',
                isAdmin: false,
              ),
            );
          } else {
            await fixture.controller.disconnect();
          }
          controllerNotifications = 0;
          write.release.complete();
          await write.completed.future;
          await pumpEventQueue();

          expect(await notificationStore.all(), isEmpty);
          expect(fixture.controller.unreadNotificationCount, 0);
          expect(presented, isEmpty);
          expect(controllerNotifications, 0);
        },
      );
    }

    test(
      'current Reverb owner persists, refreshes, and presents once',
      () async {
        const item = TvNotificationItem(
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          channel: 'general',
          title: 'Current notification',
          status: 'info',
        );
        final notificationPersistence = _BlockingNotificationStore();
        final notificationStore = TvNotificationStore(
          store: notificationPersistence,
        );
        final reverb = _RecordingReverbService();
        final fixture = _Fixture(
          notificationApi: _SessionTvNotificationService(),
          notificationStore: notificationStore,
          reverbService: reverb,
        );
        addTearDown(fixture.controller.dispose);
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await reverb.firstConnected.future;
        final presented = <TvNotificationItem>[];
        final subscription = fixture.controller.tvNotifications.listen(
          presented.add,
        );
        addTearDown(subscription.cancel);
        final write = notificationPersistence.blockNextWrite();

        reverb.emitNotification('first', item);
        await write.started.future;
        expect(await notificationStore.all(), isEmpty);
        expect(fixture.controller.unreadNotificationCount, 0);
        expect(presented, isEmpty);
        write.release.complete();
        await write.completed.future;
        await pumpEventQueue();

        expect((await notificationStore.all()).single.item.id, item.id);
        expect(fixture.controller.unreadNotificationCount, 1);
        expect(presented, <TvNotificationItem>[item]);
      },
    );

    test(
      'account handoff isolates notification data and restores A on reload',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'm3u-tv-notification-owner-',
        );
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await directory.delete(recursive: true);
        });
        final stateFile = File('${directory.path}/state.json');
        final api = _AccountNotificationService(blockSecondAccount: true);
        addTearDown(api.releaseSecondAccount);
        final fixture = _Fixture(
          persistentStore: PersistentJsonStore(file: stateFile),
          notificationApi: api,
        );
        addTearDown(fixture.controller.dispose);
        final presented = <TvNotificationItem>[];
        final subscription = fixture.controller.tvNotifications.listen(
          presented.add,
        );
        addTearDown(subscription.cancel);

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForNotificationTitle(
          fixture.controller,
          'Account A private',
        );
        expect(
          (await fixture.controller.notificationStore.all())
              .single
              .item
              .adminOnly,
          isTrue,
        );
        await fixture.controller.markNotificationRead(_accountANotificationId);
        await fixture.controller.setNotificationChannels(<String>{'dvr'});
        expect(fixture.controller.unreadNotificationCount, 0);
        presented.clear();

        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isTrue,
        );
        await api.secondAccountFetchStarted.future;

        expect(await fixture.controller.notificationStore.all(), isEmpty);
        expect(
          await fixture.controller.notificationStore.subscribedChannels(),
          isEmpty,
        );
        expect(
          await fixture.controller.notificationStore.knownChannels(),
          isEmpty,
        );
        expect(fixture.controller.unreadNotificationCount, 0);
        expect(presented, isEmpty);

        api.releaseSecondAccount();
        await _waitForNotificationTitle(fixture.controller, 'Account B public');
        final accountBNotifications = await fixture.controller.notificationStore
            .all();
        expect(
          accountBNotifications.map((stored) => stored.item.title),
          <String>['Account B public'],
        );
        expect(
          accountBNotifications.any((stored) => stored.item.adminOnly),
          isFalse,
        );
        expect(fixture.controller.unreadNotificationCount, 1);
        expect(
          await fixture.controller.notificationStore.subscribedChannels(),
          isEmpty,
        );
        expect(
          (await fixture.controller.notificationStore.knownChannels()).map(
            (channel) => channel.name,
          ),
          <String>['general'],
        );
        expect(
          presented.map((notification) => notification.title),
          <String>['Account B public'],
        );

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForNotificationTitle(
          fixture.controller,
          'Account A private',
        );
        final restoredA =
            (await fixture.controller.notificationStore.all()).single;
        expect(restoredA.isRead, isTrue);
        expect(fixture.controller.unreadNotificationCount, 0);
        expect(
          await fixture.controller.notificationStore.subscribedChannels(),
          <String>{'dvr'},
        );
        final persisted = await PersistentJsonStore(file: stateFile).snapshot();
        final notificationKeys = persisted.keys
            .where(
              (key) =>
                  key.startsWith('m3ue_tv_notification') ||
                  key.startsWith('m3ue_tv_server_channels'),
            )
            .toList(growable: false);
        expect(notificationKeys, isNotEmpty);
        for (final key in notificationKeys) {
          expect(key, isNot(contains(_firstCredentials.username)));
          expect(key, isNot(contains(_secondCredentials.username)));
          expect(key, isNot(contains(_firstCredentials.password)));
          expect(key, isNot(contains(_secondCredentials.password)));
        }
        expect(persisted.containsKey('m3ue_tv_notifications'), isFalse);
        expect(
          persisted.containsKey('m3ue_tv_notification_channels'),
          isFalse,
        );

        final restartedApi = _AccountNotificationService();
        final restarted = _Fixture(
          persistentStore: PersistentJsonStore(file: stateFile),
          notificationApi: restartedApi,
        );
        addTearDown(restarted.controller.dispose);
        expect(
          await restarted.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForNotificationTitle(
          restarted.controller,
          'Account A private',
        );
        expect(
          (await restarted.controller.notificationStore.all()).single.isRead,
          isTrue,
        );
        expect(restarted.controller.unreadNotificationCount, 0);
      },
    );

    test('account B exposes no prior account notification data', () async {
      final api = _AccountNotificationService();
      final fixture = _Fixture(notificationApi: api);
      addTearDown(fixture.controller.dispose);
      expect(
        await fixture.controller.connectXtream(_firstCredentials),
        isTrue,
      );
      await _waitForNotificationTitle(fixture.controller, 'Account A private');
      await fixture.controller.setNotificationChannels(<String>{'dvr'});

      expect(
        await fixture.controller.connectXtream(_secondCredentials),
        isTrue,
      );

      expect(await fixture.controller.notificationStore.all(), isEmpty);
      expect(
        await fixture.controller.notificationStore.subscribedChannels(),
        isEmpty,
      );
      expect(
        (await fixture.controller.notificationStore.knownChannels()).map(
          (channel) => channel.name,
        ),
        <String>['general'],
      );
      expect(fixture.controller.unreadNotificationCount, 0);
    });

    test(
      'disconnected state exposes no prior account notification data',
      () async {
        final api = _AccountNotificationService();
        final fixture = _Fixture(notificationApi: api);
        addTearDown(fixture.controller.dispose);
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForNotificationTitle(
          fixture.controller,
          'Account A private',
        );
        await fixture.controller.setNotificationChannels(<String>{'dvr'});

        await fixture.controller.disconnect();

        expect(await fixture.controller.notificationStore.all(), isEmpty);
        expect(
          await fixture.controller.notificationStore.subscribedChannels(),
          isEmpty,
        );
        expect(
          await fixture.controller.notificationStore.knownChannels(),
          isEmpty,
        );
        expect(fixture.controller.unreadNotificationCount, 0);
      },
    );

    test('delayed dvr.status detail cannot survive A to account B', () async {
      final transport = _DvrOwnershipTransport();
      addTearDown(transport.releaseDetail);
      final reverb = _RecordingReverbService();
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

      reverb.emitDvrStatus('first', _dvrStatusPing);
      await transport.detailStarted.future;
      expect(
        await fixture.controller.connectXtream(_secondCredentials),
        isTrue,
      );
      await reverb.secondConnected.future;
      reverb.emitDvrStatus('first', _dvrStatusPing);
      transport.releaseDetail();
      await transport.detailReturned.future;
      await pumpEventQueue();

      expect(transport.detailUsers, <String>['first']);
      expect(fixture.controller.dvrRecordings, isEmpty);
      expect(fixture.controller.recordingChannelIds, isEmpty);
    });

    test(
      'delayed Reverb onConnected DVR refresh cannot survive A to account B',
      () async {
        final transport = _DvrOwnershipTransport();
        addTearDown(transport.releaseActiveRefresh);
        final reverb = _RecordingReverbService();
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

        reverb.emitConnected('first');
        await transport.activeRefreshStarted.future;
        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isTrue,
        );
        await reverb.secondConnected.future;
        reverb.emitConnected('first');
        transport.releaseActiveRefresh();
        await transport.activeRefreshReturned.future;
        await pumpEventQueue();

        expect(transport.activeRefreshUsers, <String>['first']);
        expect(fixture.controller.recordingChannelIds, isEmpty);
      },
    );

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

    test(
      'stale failed Xtream replacement preserves newer source error',
      () async {
        final failedCatalog = Completer<Object?>();
        final transport = _ThreeSourceXtreamTransport(
          secondVodCategories: failedCatalog.future,
          thirdHasViewer: false,
        );
        final reverb = _RecordingReverbService();
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

        final secondConnect = fixture.controller.connectXtream(
          _secondCredentials,
        );
        await transport.secondLiveCategoriesFetched.future;
        expect(
          await fixture.controller.connectXtream(_thirdCredentials),
          isTrue,
        );
        await reverb.thirdConnected.future;
        expect(fixture.controller.error, isNull);
        var notifications = 0;
        fixture.controller.addListener(() => notifications += 1);

        failedCatalog.completeError(StateError('stale catalog unavailable'));
        expect(await secondConnect, isFalse);
        await pumpEventQueue();

        expect(fixture.auth.credentials, _thirdCredentials);
        expect(fixture.controller.channels.single.name, 'Server C Channel');
        expect(fixture.controller.error, isNull);
        expect(notifications, 0);
      },
    );

    test(
      'disconnect clears loading while a catalog request is pending',
      () async {
        final transport = _RacingXtreamTransport();
        final fixture = _Fixture(transport: transport.call);
        addTearDown(fixture.controller.dispose);

        final connect = fixture.controller.connectXtream(_firstCredentials);
        await transport.firstCatalogStarted.future;
        expect(fixture.controller.isLoadingContent, isTrue);

        await fixture.controller.disconnect();
        final loadingAfterDisconnect = fixture.controller.isLoadingContent;
        transport.releaseFirstCatalog.complete();
        expect(await connect, isFalse);

        expect(loadingAfterDisconnect, isFalse);
        expect(fixture.controller.isLoadingContent, isFalse);
      },
    );

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
      await transport.secondLiveCategoriesFetched.future;
      failedCatalog.completeError(
        StateError(
          'catalog unavailable for ${_secondCredentials.username}: '
          '${_secondCredentials.password}',
        ),
      );

      expect(await secondConnect, isFalse);
      expect(
        fixture.controller.error,
        'Bad state: catalog unavailable for [redacted]: [redacted]',
      );
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
      'persistent cache failure rolls back the complete source transaction',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'm3u-tv-atomic-cache-',
        );
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await directory.delete(recursive: true);
        });
        final stateFile = File('${directory.path}/state.json');
        final store = _SourceMarkerFailingStore(file: stateFile);
        final transport = _TransactionalXtreamTransport(
          onSecondSourceStaged: store.arm,
          isSecondSourceCommitted: () => store.secondSourceCommitted,
        );
        final reverb = _RecordingReverbService();
        final fixture = _Fixture(
          persistentStore: store,
          secureStorage: FileSecureStorage(store: store),
          transport: transport.call,
          notificationApi: _SessionTvNotificationService(),
          reverbService: reverb,
        );
        addTearDown(fixture.controller.dispose);

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForGuide(fixture.controller, 'Server A guide');
        await reverb.firstConnected.future;
        final observedChannels = <String>[];
        fixture.controller.addListener(() {
          observedChannels.add(
            fixture.controller.channels.firstOrNull?.name ?? 'none',
          );
        });
        transport.secondSourcePostCommitEvents.clear();

        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isFalse,
        );
        await Future<void>.delayed(Duration.zero);

        expect(store.didFail, isTrue);
        expect(fixture.auth.credentials, _firstCredentials);
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
        expect(fixture.controller.viewers.single.name, 'Server A Viewer');
        expect(fixture.controller.activeViewer?.name, 'Server A Viewer');
        expect(
          fixture.controller.progressList.single.title,
          'Server A Progress',
        );
        expect(fixture.controller.dvrRecordings.single.title, 'Server A DVR');
        expect(
          fixture.controller.mediaRequests.single.title,
          'Server A Request',
        );
        expect(fixture.controller.isLoadingContent, isFalse);
        expect(fixture.controller.unreadNotificationCount, 0);
        expect(
          fixture.controller.epgService.lookup('server-a')?.current.title,
          'Server A guide',
        );
        expect(fixture.controller.epgService.lookup('server-b'), isNull);
        expect(observedChannels, isNot(contains('Server B Channel')));
        expect(transport.secondSourcePostCommitEvents, isEmpty);
        expect(reverb.activeUser, 'first');
        expect(reverb.connectedUsers, <String>['first', 'first']);

        final persisted = jsonEncode(
          await PersistentJsonStore(file: stateFile).snapshot(),
        );
        expect(persisted, isNot(contains('Server B')));
        expect(persisted, isNot(contains('/second/')));
        final persistedCredentials =
            jsonDecode(
                  (await fixture.storage.read('m3ue_tv_credentials'))!,
                )
                as Map<String, Object?>;
        final persistedSource =
            jsonDecode((await fixture.storage.read('m3ue_tv_source'))!)
                as Map<String, Object?>;
        expect(persistedCredentials['username'], 'first');
        expect(persistedSource['type'], 'xtream');

        final restarted = AppStateController(
          persistentStore: PersistentJsonStore(file: stateFile),
          xtreamService: XtreamService(transport: transport.call),
          tvNotificationService: _EmptyTvNotificationService(),
        );
        addTearDown(restarted.dispose);
        await restarted.boot();
        expect(
          restarted.authNotifier.credentials?.server,
          _firstCredentials.server,
        );
        expect(
          restarted.authNotifier.credentials?.username,
          _firstCredentials.username,
        );
        expect(restarted.sourceType, AppSourceType.xtream);
        expect(restarted.channels.single.name, 'Server A Channel');
        expect(restarted.viewers.single.name, 'Server A Viewer');
      },
    );

    test(
      'successful cache transaction publishes B before post-commit work',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'm3u-tv-atomic-cache-success-',
        );
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await directory.delete(recursive: true);
        });
        final stateFile = File('${directory.path}/state.json');
        final store = _SourceMarkerFailingStore(
          file: stateFile,
          failWhenArmed: false,
        );
        final transport = _TransactionalXtreamTransport(
          onSecondSourceStaged: store.arm,
          isSecondSourceCommitted: () => store.secondSourceCommitted,
        );
        final fixture = _Fixture(
          persistentStore: store,
          secureStorage: FileSecureStorage(store: store),
          transport: transport.call,
        );
        addTearDown(fixture.controller.dispose);
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForGuide(fixture.controller, 'Server A guide');
        transport.secondSourcePostCommitEvents.clear();
        var publishedSource = '';
        var sourceTransitions = 0;
        fixture.controller.addListener(() {
          final source = fixture.controller.channels.firstOrNull?.name ?? '';
          if (source == publishedSource) return;
          publishedSource = source;
          if (source == 'Server B Channel') sourceTransitions += 1;
        });

        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isTrue,
        );
        await _waitForGuide(fixture.controller, 'Server B guide');

        expect(sourceTransitions, 1);
        expect(fixture.controller.channels.single.name, 'Server B Channel');
        expect(
          (await fixture.cache.get<List<Channel>>(
            'liveStreams',
          ))?.data.single.name,
          'Server B Channel',
        );
        expect(transport.secondSourcePostCommitEvents, isNotEmpty);
        expect(
          transport.secondSourcePostCommitEvents.every((event) => event.$2),
          isTrue,
        );
        final persisted = jsonEncode(
          await PersistentJsonStore(file: stateFile).snapshot(),
        );
        expect(persisted, contains('Server B Channel'));
        expect(persisted, contains('/second/'));
      },
    );

    test(
      'stale cache replacement rolls back when the newer connection fails',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'm3u-tv-stale-cache-failure-',
        );
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await directory.delete(recursive: true);
        });
        final stateFile = File('${directory.path}/state.json');
        final store = _BlockingSourceCacheStore(file: stateFile);
        final transport = _ThreeSourceXtreamTransport(failThirdAuth: true);
        final fixture = _Fixture(
          persistentStore: store,
          secureStorage: FileSecureStorage(store: store),
          transport: transport.call,
        );
        addTearDown(fixture.controller.dispose);
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForGuide(fixture.controller, 'Server A guide');
        await fixture.controller.favoritesService.add(101);
        final observedChannels = <String>[];
        fixture.controller.addListener(() {
          observedChannels.add(
            fixture.controller.channels.firstOrNull?.name ?? 'none',
          );
        });

        final secondConnect = fixture.controller.connectXtream(
          _secondCredentials,
        );
        await store.secondCachePersisted.future;
        final thirdConnect = fixture.controller.connectXtream(
          _thirdCredentials,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        store.releaseSecondCache.complete();

        expect(await secondConnect, isFalse);
        expect(await thirdConnect, isFalse);
        expect(fixture.auth.credentials, _firstCredentials);
        expect(fixture.xtream.credentials?.username, 'first');
        expect(fixture.controller.sourceType, AppSourceType.xtream);
        expect(fixture.controller.channels.single.name, 'Server A Channel');
        expect(fixture.controller.activeViewer?.name, 'Server A Viewer');
        expect(
          fixture.controller.epgService.lookup('server-a')?.current.title,
          'Server A guide',
        );
        expect(fixture.controller.epgService.lookup('server-b'), isNull);
        expect(observedChannels, isNot(contains('Server B Channel')));
        expect(
          await fixture.controller.favoritesService.isFavorite(101),
          isTrue,
        );
        expect(
          (await fixture.cache.get<List<Channel>>(
            'liveStreams',
          ))?.data.single.name,
          'Server A Channel',
        );

        final persisted = await PersistentJsonStore(file: stateFile).snapshot();
        final persistedText = jsonEncode(persisted);
        expect(persistedText, contains('Server A Channel'));
        expect(persistedText, contains('viewer-server-a'));
        expect(persistedText, isNot(contains('Server B Channel')));
        expect(persistedText, isNot(contains('Server C Channel')));
        final persistedCredentials =
            jsonDecode(persisted['m3ue_tv_credentials']! as String)
                as Map<String, Object?>;
        final persistedSource =
            jsonDecode(persisted['m3ue_tv_source']! as String)
                as Map<String, Object?>;
        expect(persistedCredentials['username'], 'first');
        expect(persistedSource['type'], 'xtream');

        final restarted = AppStateController(
          persistentStore: PersistentJsonStore(file: stateFile),
          xtreamService: XtreamService(transport: transport.call),
          tvNotificationService: _EmptyTvNotificationService(),
        );
        addTearDown(restarted.dispose);
        await restarted.boot();
        expect(restarted.authNotifier.credentials?.username, 'first');
        expect(restarted.sourceType, AppSourceType.xtream);
        expect(restarted.channels.single.name, 'Server A Channel');
        expect(restarted.activeViewer?.name, 'Server A Viewer');
        expect(await restarted.favoritesService.isFavorite(101), isTrue);
      },
    );

    test(
      'disconnect remains authoritative after a stale cache replacement',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'm3u-tv-stale-cache-disconnect-',
        );
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await directory.delete(recursive: true);
        });
        final stateFile = File('${directory.path}/state.json');
        final store = _BlockingSourceCacheStore(file: stateFile);
        final transport = _ThreeSourceXtreamTransport();
        final reverb = _RecordingReverbService();
        final fixture = _Fixture(
          persistentStore: store,
          secureStorage: FileSecureStorage(store: store),
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

        final replacement = fixture.controller.connectXtream(
          _secondCredentials,
        );
        await store.secondCachePersisted.future;
        await fixture.controller.disconnect();
        expect(await fixture.storage.read('m3ue_tv_credentials'), isNull);
        expect(await fixture.storage.read('m3ue_tv_source'), isNull);

        store.releaseSecondCache.complete();
        final replacementResult = await replacement;
        await pumpEventQueue();
        final persisted = await PersistentJsonStore(file: stateFile).snapshot();

        final restarted = AppStateController(
          persistentStore: PersistentJsonStore(file: stateFile),
          xtreamService: XtreamService(transport: transport.call),
          tvNotificationService: _EmptyTvNotificationService(),
        );
        addTearDown(restarted.dispose);
        await restarted.boot();

        expect(
          <String, Object?>{
            'replacement': replacementResult,
            'auth': fixture.auth.credentials?.username,
            'source': fixture.controller.sourceType,
            'credentials persisted': persisted.containsKey(
              'm3ue_tv_credentials',
            ),
            'source persisted': persisted.containsKey('m3ue_tv_source'),
            'cache source': (await fixture.cache.get<String>(
              'sourceType',
            ))?.data,
            'channels': fixture.controller.channels.length,
            'active viewer': fixture.controller.activeViewer?.ulid,
            'push events': fixture.push.events,
            'reverb user': reverb.activeUser,
            'restart auth': restarted.authNotifier.credentials?.username,
            'restart source': restarted.sourceType,
          },
          <String, Object?>{
            'replacement': false,
            'auth': null,
            'source': AppSourceType.none,
            'credentials persisted': false,
            'source persisted': false,
            'cache source': null,
            'channels': 0,
            'active viewer': null,
            'push events': <String>[
              'unsubscribe:first:device-token:true',
            ],
            'reverb user': null,
            'restart auth': null,
            'restart source': AppSourceType.none,
          },
        );
        expect(jsonEncode(persisted), isNot(contains('Server B')));
      },
    );

    test(
      'stale cache cleanup cannot overwrite a newer successful connection',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'm3u-tv-stale-cache-success-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final stateFile = File('${directory.path}/state.json');
        final store = _BlockingSourceCacheStore(file: stateFile);
        final transport = _ThreeSourceXtreamTransport();
        final fixture = _Fixture(
          persistentStore: store,
          secureStorage: FileSecureStorage(store: store),
          transport: transport.call,
        );
        addTearDown(() async {
          fixture.controller.dispose();
          await fixture.controller.drainBackgroundPersistence();
        });
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForGuide(fixture.controller, 'Server A guide');
        final observedChannels = <String>[];
        fixture.controller.addListener(() {
          observedChannels.add(
            fixture.controller.channels.firstOrNull?.name ?? 'none',
          );
        });

        final secondConnect = fixture.controller.connectXtream(
          _secondCredentials,
        );
        await store.secondCachePersisted.future;
        final thirdConnect = fixture.controller.connectXtream(
          _thirdCredentials,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        store.releaseSecondCache.complete();

        expect(await secondConnect, isFalse);
        expect(await thirdConnect, isTrue);
        await _waitForGuide(fixture.controller, 'Server C guide');
        expect(fixture.auth.credentials, _thirdCredentials);
        expect(fixture.xtream.credentials?.username, 'third');
        expect(fixture.controller.sourceType, AppSourceType.xtream);
        expect(fixture.controller.channels.single.name, 'Server C Channel');
        expect(fixture.controller.activeViewer?.name, 'Server C Viewer');
        expect(
          fixture.controller.epgService.lookup('server-c')?.current.title,
          'Server C guide',
        );
        expect(observedChannels, isNot(contains('Server B Channel')));
        expect(
          (await fixture.cache.get<List<Channel>>(
            'liveStreams',
          ))?.data.single.name,
          'Server C Channel',
        );

        final persisted = await PersistentJsonStore(file: stateFile).snapshot();
        final persistedText = jsonEncode(persisted);
        expect(persistedText, contains('Server C Channel'));
        expect(persistedText, contains('viewer-server-c'));
        expect(persistedText, isNot(contains('Server B Channel')));
        final persistedCredentials =
            jsonDecode(persisted['m3ue_tv_credentials']! as String)
                as Map<String, Object?>;
        final persistedSource =
            jsonDecode(persisted['m3ue_tv_source']! as String)
                as Map<String, Object?>;
        expect(persistedCredentials['username'], 'third');
        expect(persistedSource['type'], 'xtream');

        await Future<void>.delayed(const Duration(milliseconds: 100));
        final restartedStore = _BlockingFavoritesStore(file: stateFile);
        final restarted = AppStateController(
          persistentStore: restartedStore,
          xtreamService: XtreamService(transport: transport.call),
          tvNotificationService: _EmptyTvNotificationService(),
        );
        addTearDown(() async {
          restarted.dispose();
          await restarted.drainBackgroundPersistence();
        });
        final restartedBoot = restarted.boot();
        await restartedStore.favoritesWriteStarted.future;
        var bootCompleted = false;
        unawaited(restartedBoot.then((_) => bootCompleted = true));
        await pumpEventQueue();
        expect(bootCompleted, isTrue);
        var persistenceDrained = false;
        final persistenceDrain = restarted.drainBackgroundPersistence();
        unawaited(persistenceDrain.then((_) => persistenceDrained = true));
        await pumpEventQueue();
        expect(persistenceDrained, isFalse);
        restartedStore.releaseFavoritesWrite.complete();
        await persistenceDrain;
        await restartedBoot;
        expect(restarted.authNotifier.credentials?.username, 'third');
        expect(restarted.sourceType, AppSourceType.xtream);
        expect(restarted.channels.single.name, 'Server C Channel');
        expect(restarted.activeViewer?.name, 'Server C Viewer');
      },
    );

    test(
      'cache rollback failure does not escape the source operation',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'm3u-tv-atomic-cache-rollback-',
        );
        addTearDown(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await directory.delete(recursive: true);
        });
        final store = _SourceMarkerFailingStore(
          file: File('${directory.path}/state.json'),
          failRollback: true,
        );
        final transport = _TransactionalXtreamTransport(
          onSecondSourceStaged: store.arm,
          isSecondSourceCommitted: () => store.secondSourceCommitted,
        );
        final fixture = _Fixture(
          persistentStore: store,
          secureStorage: FileSecureStorage(store: store),
          transport: transport.call,
        );
        addTearDown(fixture.controller.dispose);
        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForGuide(fixture.controller, 'Server A guide');

        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isFalse,
        );

        expect(fixture.auth.credentials, _firstCredentials);
        expect(fixture.controller.channels.single.name, 'Server A Channel');
        expect(fixture.controller.isLoadingContent, isFalse);
      },
    );

    test(
      'late post-commit progress cannot replace a newer source',
      () async {
        final transport = _PostCommitOwnershipTransport(
          blockSecondProgressRefresh: true,
        );
        final fixture = _Fixture(transport: transport.call);
        addTearDown(fixture.controller.dispose);

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await pumpEventQueue();
        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isTrue,
        );
        await transport.secondProgressRefreshStarted.future;

        expect(
          await fixture.controller.connectXtream(_thirdCredentials),
          isTrue,
        );
        await _waitForProgress(fixture.controller, 'Server C Progress');
        var stalePublications = 0;
        fixture.controller.addListener(() {
          if (fixture.controller.progressList.any(
            (progress) => progress.title == 'Server B delayed progress',
          )) {
            stalePublications += 1;
          }
        });

        transport.releaseSecondProgressRefresh.complete();
        await pumpEventQueue();

        expect(fixture.auth.credentials, _thirdCredentials);
        expect(fixture.controller.activeViewer?.ulid, 'viewer-server-c');
        expect(fixture.controller.channels.single.name, 'Server C Channel');
        expect(
          fixture.controller.progressList.single.title,
          'Server C Progress',
        );
        expect(stalePublications, 0);
        expect(
          jsonEncode(await fixture.store.snapshot()),
          isNot(contains('Server B delayed progress')),
        );
        expect(
          transport.requests.where(
            (request) =>
                request.action == 'update_progress' &&
                request.username == 'third' &&
                request.viewerId == 'viewer-server-b',
          ),
          isEmpty,
        );
      },
    );

    test(
      'resume persistence entered by a stale source cannot commit',
      () async {
        final store = _BlockingPostCommitStore();
        final transport = _PostCommitOwnershipTransport();
        final fixture = _Fixture(
          transport: transport.call,
          persistentStore: store,
        );
        addTearDown(fixture.controller.dispose);

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForProgress(fixture.controller, 'Server A Progress');
        store.blockResumeFor('viewer-server-b');

        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isTrue,
        );
        await store.blockedResumeWriteStarted.future;
        expect(
          await fixture.controller.connectXtream(_thirdCredentials),
          isTrue,
        );
        await _waitForProgress(fixture.controller, 'Server C Progress');
        await _waitForStoredProgress(
          fixture.controller,
          viewerId: 'viewer-server-c',
          streamId: 203,
        );

        store.releaseBlockedResumeWrite.complete();
        await store.blockedResumeWriteCompleted.future;
        await pumpEventQueue();

        expect(fixture.auth.credentials, _thirdCredentials);
        expect(fixture.controller.activeViewer?.ulid, 'viewer-server-c');
        expect(
          fixture.controller.progressList.single.title,
          'Server C Progress',
        );
        expect(
          await fixture.controller.resumeService.load(
            'viewer-server-b',
            ContentType.vod,
            202,
          ),
          isNull,
        );
        expect(
          (await fixture.controller.resumeService.load(
            'viewer-server-c',
            ContentType.vod,
            203,
          ))?.title,
          'Server C Progress',
        );
        final persisted = jsonEncode(await store.snapshot());
        expect(persisted, isNot(contains('Server B Progress')));
        expect(persisted, contains('Server C Progress'));
        expect(
          transport.requests.where(
            (request) =>
                request.action == 'update_progress' &&
                request.username == 'third' &&
                request.viewerId == 'viewer-server-b',
          ),
          isEmpty,
        );
      },
    );

    test(
      'resume persistence entered by a stale viewer cannot commit',
      () async {
        final store = _BlockingPostCommitStore();
        final transport = _PostCommitOwnershipTransport();
        final fixture = _Fixture(
          transport: transport.call,
          persistentStore: store,
        );
        addTearDown(fixture.controller.dispose);
        const secondViewer = Viewer(
          id: 20,
          ulid: 'viewer-local-b',
          name: 'Local Viewer B',
          isAdmin: false,
        );
        const thirdViewer = Viewer(
          id: 30,
          ulid: 'viewer-local-c',
          name: 'Local Viewer C',
          isAdmin: false,
        );

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForProgress(fixture.controller, 'Server A Progress');
        store.blockResumeFor(secondViewer.ulid);

        final secondSwitch = fixture.controller.switchViewer(secondViewer);
        await store.blockedResumeWriteStarted.future;
        await fixture.controller.switchViewer(thirdViewer);
        await _waitForStoredProgress(
          fixture.controller,
          viewerId: thirdViewer.ulid,
          streamId: 201,
        );

        store.releaseBlockedResumeWrite.complete();
        await store.blockedResumeWriteCompleted.future;
        await secondSwitch;
        await pumpEventQueue();

        expect(fixture.controller.activeViewer, thirdViewer);
        expect(
          fixture.controller.progressList.single.title,
          'Server A Progress',
        );
        expect(
          await fixture.controller.resumeService.load(
            secondViewer.ulid,
            ContentType.vod,
            201,
          ),
          isNull,
        );
        expect(
          (await fixture.controller.resumeService.load(
            thirdViewer.ulid,
            ContentType.vod,
            201,
          ))?.title,
          'Server A Progress',
        );
        expect(
          jsonEncode(await store.snapshot()),
          isNot(contains('m3ue_resume_${secondViewer.ulid}_')),
        );
        expect(
          transport.requests.where(
            (request) =>
                request.action == 'get_recently_watched' &&
                request.username == 'first' &&
                request.viewerId != 'viewer-server-a' &&
                request.viewerId != secondViewer.ulid &&
                request.viewerId != thirdViewer.ulid,
          ),
          isEmpty,
        );
      },
    );

    test(
      'late favorites pull cannot replace a newer source',
      () async {
        final storage = InMemorySecureStorage();
        final transport = _PostCommitOwnershipTransport(
          blockSecondFavoritesPull: true,
        );
        final fixture = _Fixture(
          transport: transport.call,
          secureStorage: storage,
        );
        addTearDown(fixture.controller.dispose);

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await pumpEventQueue();
        await storage.write(
          'm3ue_tv_favorites_migrated_viewers',
          jsonEncode(<String>['viewer-server-b']),
        );

        final secondConnect = fixture.controller.connectXtream(
          _secondCredentials,
        );
        await transport.secondFavoritesPullStarted.future;
        final thirdConnect = fixture.controller.connectXtream(
          _thirdCredentials,
        );

        transport.releaseSecondFavoritesPull.complete();
        expect(await secondConnect, isFalse);
        expect(await thirdConnect, isTrue);
        await _waitForFavorite(fixture.controller, 103);
        await pumpEventQueue();

        expect(await fixture.controller.favoritesService.all(), <int>{103});
        expect(
          transport.requests.where(
            (request) =>
                request.isFavorites &&
                request.viewerId !=
                    'viewer-server-${request.source.toLowerCase()}',
          ),
          isEmpty,
        );
      },
    );

    test(
      'favorites persistence entered by a stale source cannot commit',
      () async {
        final store = _BlockingPostCommitStore();
        final storage = InMemorySecureStorage();
        final transport = _PostCommitOwnershipTransport(
          blockThirdFavoritesPull: true,
        );
        final fixture = _Fixture(
          transport: transport.call,
          persistentStore: store,
          secureStorage: storage,
        );
        addTearDown(fixture.controller.dispose);
        await storage.write(
          'm3ue_tv_favorites_migrated_viewers',
          jsonEncode(<String>[
            'viewer-server-a',
            'viewer-server-b',
            'viewer-server-c',
          ]),
        );

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForFavorite(fixture.controller, 101);
        store.blockFavoritesFor(102);

        var staleNotifications = 0;
        var currentNotifications = 0;
        fixture.controller.favoritesService.addListener(() {
          final favorites = fixture.controller.favoritesService.all();
          unawaited(
            favorites.then((ids) {
              if (ids.contains(102)) staleNotifications += 1;
              if (ids.contains(103)) currentNotifications += 1;
            }),
          );
        });

        final secondConnect = fixture.controller.connectXtream(
          _secondCredentials,
        );
        await store.blockedFavoritesWriteStarted.future;
        final thirdConnect = fixture.controller.connectXtream(
          _thirdCredentials,
        );

        store.releaseBlockedFavoritesWrite.complete();
        await store.blockedFavoritesWriteCompleted.future;
        expect(await secondConnect, isFalse);
        await transport.thirdFavoritesPullStarted.future;
        await pumpEventQueue();

        expect(fixture.controller.activeViewer?.ulid, 'viewer-server-a');
        expect(await fixture.controller.favoritesService.all(), <int>{101});
        expect(await store.read('m3ue_favorites'), <int>[101]);
        expect(staleNotifications, 0);

        transport.releaseThirdFavoritesPull.complete();
        expect(await thirdConnect, isTrue);
        await _waitForFavorite(fixture.controller, 103);
        await pumpEventQueue();

        expect(await fixture.controller.favoritesService.all(), <int>{103});
        expect(await store.read('m3ue_favorites'), <int>[103]);
        expect(currentNotifications, 1);
        expect(
          transport.requests.where(
            (request) =>
                request.isFavorites &&
                request.viewerId !=
                    'viewer-server-${request.source.toLowerCase()}',
          ),
          isEmpty,
        );
      },
    );

    test(
      'stale first-time favorites migration cannot use newer credentials',
      () async {
        final storage = _BlockingFavoritesMigrationStorage();
        final transport = _PostCommitOwnershipTransport();
        final fixture = _Fixture(
          transport: transport.call,
          secureStorage: storage,
        );
        addTearDown(fixture.controller.dispose);

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await pumpEventQueue();
        storage.arm();

        final secondConnect = fixture.controller.connectXtream(
          _secondCredentials,
        );
        await storage.blockedReadStarted.future;
        final thirdConnect = fixture.controller.connectXtream(
          _thirdCredentials,
        );

        storage.releaseBlockedRead.complete();
        expect(await secondConnect, isFalse);
        expect(await thirdConnect, isTrue);
        await _waitForFavorite(fixture.controller, 103);
        await pumpEventQueue();

        final migrated =
            jsonDecode(
                  (await storage.read(
                    'm3ue_tv_favorites_migrated_viewers',
                  ))!,
                )
                as List<Object?>;
        expect(migrated, contains('viewer-server-c'));
        expect(migrated, isNot(contains('viewer-server-b')));
        expect(await fixture.controller.favoritesService.all(), <int>{103});
        expect(
          transport.requests.where(
            (request) =>
                request.isFavorites && request.viewerId == 'viewer-server-b',
          ),
          isEmpty,
        );
        expect(
          transport.requests.where(
            (request) =>
                request.isFavorites &&
                request.viewerId !=
                    'viewer-server-${request.source.toLowerCase()}',
          ),
          isEmpty,
        );
      },
    );

    test(
      'migration marker entered by a stale source cannot commit',
      () async {
        final storage = _BlockingFavoritesMigrationWriteStorage();
        final transport = _PostCommitOwnershipTransport();
        final fixture = _Fixture(
          transport: transport.call,
          secureStorage: storage,
        );
        addTearDown(fixture.controller.dispose);

        expect(
          await fixture.controller.connectXtream(_firstCredentials),
          isTrue,
        );
        await _waitForMigratedViewer(storage, 'viewer-server-a');
        storage.blockViewer('viewer-server-b');

        final secondConnect = fixture.controller.connectXtream(
          _secondCredentials,
        );
        await storage.blockedWriteStarted.future;
        final thirdConnect = fixture.controller.connectXtream(
          _thirdCredentials,
        );

        storage.releaseBlockedWrite.complete();
        await storage.blockedWriteCompleted.future;
        expect(await secondConnect, isFalse);
        expect(await thirdConnect, isTrue);
        await _waitForMigratedViewer(storage, 'viewer-server-c');
        await pumpEventQueue();

        final migratedAfterRelease = await _migratedViewers(storage);
        expect(migratedAfterRelease, contains('viewer-server-a'));
        expect(migratedAfterRelease, contains('viewer-server-c'));
        expect(migratedAfterRelease, isNot(contains('viewer-server-b')));

        expect(
          await fixture.controller.connectXtream(_secondCredentials),
          isTrue,
        );
        await _waitForMigratedViewer(storage, 'viewer-server-b');

        expect(
          transport.requests.where(
            (request) =>
                request.action == 'get_favorites' &&
                request.viewerId == 'viewer-server-b',
          ),
          hasLength(2),
        );
        expect(
          transport.requests.where(
            (request) =>
                request.isFavorites &&
                request.viewerId !=
                    'viewer-server-${request.source.toLowerCase()}',
          ),
          isEmpty,
        );
      },
    );

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
      await transport.secondLiveCategoriesFetched.future;
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
const _thirdCredentials = UserCredentials(
  server: 'https://fixture.invalid',
  username: 'third',
  password: 'third-private-value',
);
const _existingNotification = TvNotificationItem(
  id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  channel: 'general',
  title: 'Existing notification',
  status: 'info',
);
const _reconciledNotification = TvNotificationItem(
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  channel: 'general',
  title: 'Reconciled notification',
  status: 'info',
);
const _accountANotificationId = '11111111-1111-4111-8111-111111111111';
const _accountBNotificationId = '22222222-2222-4222-8222-222222222222';
const _accountBAdminNotificationId = '33333333-3333-4333-8333-333333333333';
const _dvrStatusPing = DvrRecording(
  uuid: 'recording-a',
  title: 'Account A recording status',
  status: DvrRecordingStatus.recording,
  channelId: 701,
);

class _Fixture {
  _Fixture({
    TvNotificationService? notificationApi,
    ReverbService? reverbService,
    XtreamTransport? transport,
    PersistentJsonStore? persistentStore,
    SecureStorage? secureStorage,
    TvNotificationStore? notificationStore,
  }) {
    store =
        persistentStore ??
        PersistentJsonStore(
          file: File(
            '${Directory.systemTemp.path}/m3u-tv-push-${identityHashCode(this)}.json',
          ),
        );
    cache = CacheService(memory: <String, Object?>{}, store: store);
    storage = secureStorage ?? InMemorySecureStorage();
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
      tvNotificationStore: notificationStore,
      reverbService: reverbService,
    );
  }

  late final PersistentJsonStore store;
  late final CacheService cache;
  late final SecureStorage storage;
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

class _UnreadReconciliationTvNotificationService extends TvNotificationService {
  _UnreadReconciliationTvNotificationService({
    required this.includeServerChannels,
  });

  final bool includeServerChannels;
  final Completer<void> initialFetchCompleted = Completer<void>();
  int _fetches = 0;

  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async {
    _fetches += 1;
    final initialFetch = _fetches == 1;
    if (initialFetch) initialFetchCompleted.complete();
    return (
      TvPlaylistSession(
        notifiableId: 1,
        notifiableType: 'playlist',
        isAdmin: false,
        channelName: '',
        reverb: const ReverbConfig(
          host: 'fixture.invalid',
          port: 443,
          scheme: 'wss',
          appKey: '',
        ),
        availableChannels: !initialFetch && includeServerChannels
            ? const <TvNotificationChannel>[
                TvNotificationChannel(name: 'general', label: 'General'),
              ]
            : const <TvNotificationChannel>[],
      ),
      initialFetch
          ? const <TvNotificationItem>[]
          : const <TvNotificationItem>[_reconciledNotification],
    );
  }
}

class _AccountNotificationService extends TvNotificationService {
  _AccountNotificationService({this.blockSecondAccount = false});

  final bool blockSecondAccount;
  final Completer<void> secondAccountFetchStarted = Completer<void>();
  final Completer<void> _releaseSecondAccount = Completer<void>();

  void releaseSecondAccount() {
    if (!_releaseSecondAccount.isCompleted) _releaseSecondAccount.complete();
  }

  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async {
    final isFirst = creds.username == _firstCredentials.username;
    if (!isFirst) {
      if (!secondAccountFetchStarted.isCompleted) {
        secondAccountFetchStarted.complete();
      }
      if (blockSecondAccount) await _releaseSecondAccount.future;
    }
    return (
      TvPlaylistSession(
        notifiableId: isFirst ? 101 : 202,
        notifiableType: 'playlist',
        isAdmin: isFirst,
        channelName: '',
        reverb: const ReverbConfig(
          host: 'fixture.invalid',
          port: 443,
          scheme: 'wss',
          appKey: '',
        ),
        availableChannels: <TvNotificationChannel>[
          TvNotificationChannel(
            name: isFirst ? 'dvr' : 'general',
            label: isFirst ? 'DVR' : 'General',
          ),
        ],
      ),
      isFirst
          ? const <TvNotificationItem>[
              TvNotificationItem(
                id: _accountANotificationId,
                channel: 'dvr',
                title: 'Account A private',
                body: 'Account A private body',
                status: 'warning',
                adminOnly: true,
              ),
            ]
          : const <TvNotificationItem>[
              TvNotificationItem(
                id: _accountBNotificationId,
                channel: 'general',
                title: 'Account B public',
                body: 'Account B public body',
                status: 'info',
              ),
              TvNotificationItem(
                id: _accountBAdminNotificationId,
                channel: 'general',
                title: 'Account B admin only',
                status: 'warning',
                adminOnly: true,
              ),
            ],
    );
  }

  @override
  Future<void> markRead(UserCredentials creds, String id) async {}
}

class _DvrOwnershipTransport {
  final Completer<void> detailStarted = Completer<void>();
  final Completer<void> detailReturned = Completer<void>();
  final Completer<void> _releaseDetail = Completer<void>();
  final Completer<void> activeRefreshStarted = Completer<void>();
  final Completer<void> activeRefreshReturned = Completer<void>();
  final Completer<void> _releaseActiveRefresh = Completer<void>();
  final List<String> detailUsers = <String>[];
  final List<String> activeRefreshUsers = <String>[];

  void releaseDetail() {
    if (!_releaseDetail.isCompleted) _releaseDetail.complete();
  }

  void releaseActiveRefresh() {
    if (!_releaseActiveRefresh.isCompleted) _releaseActiveRefresh.complete();
  }

  Future<Object?> call(XtreamRequest request) async {
    final username = request.credentials.username;
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{
            'version': '0.10.0',
            'features': <String>['dvr'],
          },
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_viewers':
        return <Object?>[];
      case 'get_dvr_recordings':
        if (request.params['status'] != DvrRecordingStatus.recording.name) {
          return <Object?>[];
        }
        activeRefreshUsers.add(username);
        if (username == _firstCredentials.username &&
            !activeRefreshStarted.isCompleted) {
          activeRefreshStarted.complete();
          await _releaseActiveRefresh.future;
          if (!activeRefreshReturned.isCompleted) {
            activeRefreshReturned.complete();
          }
        }
        return <Map<String, Object?>>[
          _dvrDetail(
            username: username,
            channelId: username == _firstCredentials.username ? 701 : 802,
          ),
        ];
      case 'get_dvr_recording':
        detailUsers.add(username);
        if (username == _firstCredentials.username &&
            !detailStarted.isCompleted) {
          detailStarted.complete();
          await _releaseDetail.future;
          if (!detailReturned.isCompleted) detailReturned.complete();
        }
        return _dvrDetail(
          username: username,
          channelId: username == _firstCredentials.username ? 701 : 802,
        );
      default:
        throw StateError('Unexpected DVR fixture action: ${request.action}');
    }
  }

  static Map<String, Object?> _dvrDetail({
    required String username,
    required int channelId,
  }) => <String, Object?>{
    'uuid': 'recording-a',
    'title': '$username private recording',
    'status': 'recording',
    'channel_id': channelId,
    'stream_url': 'https://media.invalid/$username/recording.ts',
    'live_url': 'https://media.invalid/$username/live.ts',
    'edl_url': 'https://media.invalid/$username/recording.edl',
    'metadata': <String, Object?>{'owner': username},
  };
}

class _RecordingReverbService extends ReverbService {
  final List<String> connectedUsers = <String>[];
  final Completer<void> firstConnected = Completer<void>();
  final Completer<void> firstReconnected = Completer<void>();
  final Completer<void> secondConnected = Completer<void>();
  final Completer<void> thirdConnected = Completer<void>();
  String? activeUser;
  final Map<String, void Function(TvNotificationItem)> _notificationCallbacks =
      <String, void Function(TvNotificationItem)>{};
  final Map<String, void Function(DvrRecording)> _dvrCallbacks =
      <String, void Function(DvrRecording)>{};
  final Map<String, void Function()> _connectedCallbacks =
      <String, void Function()>{};

  void emitNotification(String username, TvNotificationItem item) =>
      _notificationCallbacks[username]!(item);

  void emitDvrStatus(String username, DvrRecording recording) =>
      _dvrCallbacks[username]!(recording);

  void emitConnected(String username) => _connectedCallbacks[username]!();

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
    _notificationCallbacks[credentials.username] = onNotification;
    if (onDvrStatus != null) {
      _dvrCallbacks[credentials.username] = onDvrStatus;
    }
    if (onConnected != null) {
      _connectedCallbacks[credentials.username] = onConnected;
    }
    if (credentials.username == 'first') {
      if (!firstConnected.isCompleted) {
        firstConnected.complete();
      } else if (!firstReconnected.isCompleted) {
        firstReconnected.complete();
      }
    }
    if (credentials.username == 'second') secondConnected.complete();
    if (credentials.username == 'third') thirdConnected.complete();
  }
}

class _BlockingNotificationStore extends PersistentJsonStore {
  final _data = <String, Object?>{};
  _BlockedNotificationWrite? _blockedWrite;
  int commits = 0;
  void Function()? onCommit;

  void resetCommits() => commits = 0;

  _BlockedNotificationWrite blockNextWrite() {
    final write = _BlockedNotificationWrite();
    _blockedWrite = write;
    return write;
  }

  @override
  Future<Object?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, Object? value) async {
    final write = _blockedWrite;
    if (write != null) {
      _blockedWrite = null;
      write.started.complete();
      await write.release.future;
    }
    _data[key] = value;
    commits += 1;
    onCommit?.call();
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
      commits += 1;
      onCommit?.call();
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
}

class _BlockedNotificationWrite {
  final started = Completer<void>();
  final release = Completer<void>();
  final completed = Completer<void>();
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
        'get_viewers' ||
        'get_recently_watched' ||
        'get_favorites' => <Object?>[],
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
  final Completer<void> secondLiveCategoriesFetched = Completer<void>();

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
        if (!isFirst && !secondLiveCategoriesFetched.isCompleted) {
          secondLiveCategoriesFetched.complete();
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

class _SourceMarkerFailingStore extends PersistentJsonStore {
  _SourceMarkerFailingStore({
    required super.file,
    this.failWhenArmed = true,
    this.failRollback = false,
  });

  final bool failWhenArmed;
  final bool failRollback;
  bool _armed = false;
  bool didFail = false;
  bool secondSourceCommitted = false;

  void arm() => _armed = true;

  @override
  Future<void> write(String key, Object? value) async {
    if (_armed && key == 'm3ue_tv_source') {
      if (failWhenArmed && !didFail) {
        didFail = true;
        throw const FileSystemException('controlled cache transaction failure');
      }
      await super.write(key, value);
      secondSourceCommitted = true;
      return;
    }
    await super.write(key, value);
  }

  @override
  Future<void> replaceWhere(
    bool Function(String key) test,
    Map<String, Object?> replacement,
  ) {
    if (failRollback && didFail) {
      throw const FileSystemException('controlled cache rollback failure');
    }
    return super.replaceWhere(test, replacement);
  }
}

class _BlockingSourceCacheStore extends PersistentJsonStore {
  _BlockingSourceCacheStore({required super.file});

  final Completer<void> secondCachePersisted = Completer<void>();
  final Completer<void> releaseSecondCache = Completer<void>();

  @override
  Future<void> replaceWhere(
    bool Function(String key) test,
    Map<String, Object?> replacement,
  ) async {
    await super.replaceWhere(test, replacement);
    if (jsonEncode(replacement).contains('Server B Channel') &&
        !secondCachePersisted.isCompleted) {
      secondCachePersisted.complete();
      await releaseSecondCache.future;
    }
  }
}

class _BlockingFavoritesStore extends PersistentJsonStore {
  _BlockingFavoritesStore({required super.file});

  final Completer<void> favoritesWriteStarted = Completer<void>();
  final Completer<void> releaseFavoritesWrite = Completer<void>();

  @override
  Future<bool> writeIf(
    String key,
    Object? value,
    bool Function() shouldCommit,
  ) async {
    if (key == 'm3ue_favorites' && !favoritesWriteStarted.isCompleted) {
      favoritesWriteStarted.complete();
      await releaseFavoritesWrite.future;
    }
    return super.writeIf(key, value, shouldCommit);
  }
}

class _BlockingPostCommitStore extends PersistentJsonStore {
  _BlockingPostCommitStore()
    : super(
        file: File(
          '${Directory.systemTemp.path}/m3u-tv-post-commit-${DateTime.now().microsecondsSinceEpoch}.json',
        ),
      );

  final Completer<void> blockedFavoritesWriteStarted = Completer<void>();
  final Completer<void> releaseBlockedFavoritesWrite = Completer<void>();
  final Completer<void> blockedFavoritesWriteCompleted = Completer<void>();
  final Completer<void> blockedResumeWriteStarted = Completer<void>();
  final Completer<void> releaseBlockedResumeWrite = Completer<void>();
  final Completer<void> blockedResumeWriteCompleted = Completer<void>();
  int? _blockedFavorite;
  String? _blockedResumeViewer;

  void blockFavoritesFor(int streamId) => _blockedFavorite = streamId;

  void blockResumeFor(String viewerId) => _blockedResumeViewer = viewerId;

  Future<void> _blockWrite(String key, Object? value) async {
    if (key == 'm3ue_favorites' &&
        value is List<Object?> &&
        value.contains(_blockedFavorite) &&
        !blockedFavoritesWriteStarted.isCompleted) {
      blockedFavoritesWriteStarted.complete();
      await releaseBlockedFavoritesWrite.future;
    }
    final resumeViewer = _blockedResumeViewer;
    if (resumeViewer != null &&
        key.startsWith('m3ue_resume_${resumeViewer}_') &&
        !blockedResumeWriteStarted.isCompleted) {
      blockedResumeWriteStarted.complete();
      await releaseBlockedResumeWrite.future;
    }
  }

  @override
  Future<void> write(String key, Object? value) async {
    await _blockWrite(key, value);
    await super.write(key, value);
    if (key == 'm3ue_favorites' &&
        value is List<Object?> &&
        value.contains(_blockedFavorite) &&
        !blockedFavoritesWriteCompleted.isCompleted) {
      blockedFavoritesWriteCompleted.complete();
    }
    if (key.startsWith('m3ue_resume_${_blockedResumeViewer}_') &&
        !blockedResumeWriteCompleted.isCompleted) {
      blockedResumeWriteCompleted.complete();
    }
  }

  @override
  Future<bool> writeIf(
    String key,
    Object? value,
    bool Function() shouldCommit,
  ) async {
    await _blockWrite(key, value);
    final committed = await super.writeIf(key, value, shouldCommit);
    if (key == 'm3ue_favorites' &&
        value is List<Object?> &&
        value.contains(_blockedFavorite) &&
        !blockedFavoritesWriteCompleted.isCompleted) {
      blockedFavoritesWriteCompleted.complete();
    }
    if (key.startsWith('m3ue_resume_${_blockedResumeViewer}_') &&
        !blockedResumeWriteCompleted.isCompleted) {
      blockedResumeWriteCompleted.complete();
    }
    return committed;
  }
}

class _ThreeSourceXtreamTransport {
  _ThreeSourceXtreamTransport({
    this.failThirdAuth = false,
    this.secondVodCategories,
    this.thirdHasViewer = true,
  });

  final bool failThirdAuth;
  final Future<Object?>? secondVodCategories;
  final bool thirdHasViewer;
  final Completer<void> secondLiveCategoriesFetched = Completer<void>();

  Future<Object?> call(XtreamRequest request) async {
    final username = request.credentials.username;
    final source = switch (username) {
      'first' => 'A',
      'second' => 'B',
      'third' => 'C',
      _ => throw StateError('Unexpected source user: $username'),
    };
    final slug = 'server-${source.toLowerCase()}';
    final offset = source.codeUnitAt(0) - 'A'.codeUnitAt(0);
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{
            'auth': username == 'third' && failThirdAuth ? 0 : 1,
            'status': username == 'third' && failThirdAuth
                ? 'Invalid credentials'
                : 'Active',
          },
          'm3u_editor': <String, Object?>{'version': '0.10.0'},
        };
      case 'get_live_categories':
        if (username == 'second' && !secondLiveCategoriesFetched.isCompleted) {
          secondLiveCategoriesFetched.complete();
        }
        return <Map<String, Object?>>[
          <String, Object?>{
            'category_id': 'live-$slug',
            'category_name': 'Server $source Live',
          },
        ];
      case 'get_vod_categories':
        if (username == 'second' && secondVodCategories != null) {
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
            'stream_id': 101 + offset,
            'name': 'Server $source Channel',
            'category_id': 'live-$slug',
            'epg_channel_id': slug,
          },
        ];
      case 'get_vod_streams':
        return <Map<String, Object?>>[
          <String, Object?>{
            'stream_id': 201 + offset,
            'name': 'Server $source Movie',
            'category_id': 'vod-$slug',
            'container_extension': 'mp4',
          },
        ];
      case 'get_series':
        return <Map<String, Object?>>[
          <String, Object?>{
            'series_id': 301 + offset,
            'name': 'Server $source Show',
            'category_id': 'series-$slug',
          },
        ];
      case 'get_viewers':
        if (username == 'third' && !thirdHasViewer) return <Object?>[];
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 1 + offset,
            'ulid': 'viewer-$slug',
            'name': 'Server $source Viewer',
            'is_admin': true,
          },
        ];
      case 'get_recently_watched':
        return <Object?>[];
      case 'get_favorites':
      case 'sync_favorites':
        return <Map<String, Object?>>[
          <String, Object?>{
            'content_type': 'live',
            'stream_id': 101 + offset,
          },
        ];
      case 'toggle_favorite':
        return <String, Object?>{'favorited': request.body['favorited']};
      case 'get_epg_batch':
        final now = DateTime.now();
        return <String, Object?>{
          '${101 + offset}': <Map<String, Object?>>[
            <String, Object?>{
              'stream_id': 101 + offset,
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

class _SourceRequest {
  const _SourceRequest({
    required this.action,
    required this.username,
    required this.viewerId,
  });

  final String action;
  final String username;
  final String? viewerId;

  String get source => switch (username) {
    'first' => 'A',
    'second' => 'B',
    'third' => 'C',
    _ => throw StateError('Unexpected source user: $username'),
  };

  bool get isFavorites =>
      action == 'get_favorites' || action == 'sync_favorites';
}

class _PostCommitOwnershipTransport {
  _PostCommitOwnershipTransport({
    this.blockSecondProgressRefresh = false,
    this.blockSecondFavoritesPull = false,
    this.blockThirdFavoritesPull = false,
  });

  final bool blockSecondProgressRefresh;
  final bool blockSecondFavoritesPull;
  final bool blockThirdFavoritesPull;
  final List<_SourceRequest> requests = <_SourceRequest>[];
  final Completer<void> secondProgressRefreshStarted = Completer<void>();
  final Completer<void> releaseSecondProgressRefresh = Completer<void>();
  final Completer<void> secondFavoritesPullStarted = Completer<void>();
  final Completer<void> releaseSecondFavoritesPull = Completer<void>();
  final Completer<void> thirdFavoritesPullStarted = Completer<void>();
  final Completer<void> releaseThirdFavoritesPull = Completer<void>();
  final Map<String, int> _recentlyWatchedCalls = <String, int>{};

  Future<Object?> call(XtreamRequest request) async {
    final username = request.credentials.username;
    final source = switch (username) {
      'first' => 'A',
      'second' => 'B',
      'third' => 'C',
      _ => throw StateError('Unexpected source user: $username'),
    };
    final slug = 'server-${source.toLowerCase()}';
    final offset = source.codeUnitAt(0) - 'A'.codeUnitAt(0);
    final action = request.action ?? 'auth';
    final viewerId =
        request.body['viewer_id']?.toString() ?? request.params['viewer_id'];
    requests.add(
      _SourceRequest(
        action: action,
        username: username,
        viewerId: viewerId,
      ),
    );
    switch (action) {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{'version': '0.10.0'},
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
        return <Map<String, Object?>>[
          <String, Object?>{
            'category_id': '$action-$slug',
            'category_name': 'Server $source Category',
          },
        ];
      case 'get_live_streams':
        return <Map<String, Object?>>[
          <String, Object?>{
            'stream_id': 101 + offset,
            'name': 'Server $source Channel',
            'category_id': 'get_live_categories-$slug',
            'epg_channel_id': slug,
          },
        ];
      case 'get_vod_streams':
        return <Map<String, Object?>>[
          <String, Object?>{
            'stream_id': 201 + offset,
            'name': 'Server $source Movie',
            'category_id': 'get_vod_categories-$slug',
            'container_extension': 'mp4',
          },
        ];
      case 'get_series':
        return <Map<String, Object?>>[
          <String, Object?>{
            'series_id': 301 + offset,
            'name': 'Server $source Show',
            'category_id': 'get_series_categories-$slug',
          },
        ];
      case 'get_viewers':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 1 + offset,
            'ulid': 'viewer-$slug',
            'name': 'Server $source Viewer',
            'is_admin': true,
          },
        ];
      case 'get_recently_watched':
        final callCount = (_recentlyWatchedCalls[username] ?? 0) + 1;
        _recentlyWatchedCalls[username] = callCount;
        if (username == 'second' &&
            callCount == 2 &&
            blockSecondProgressRefresh) {
          secondProgressRefreshStarted.complete();
          await releaseSecondProgressRefresh.future;
          return <Map<String, Object?>>[
            <String, Object?>{
              'content_type': 'vod',
              'stream_id': 902,
              'position_seconds': 92,
              'title': 'Server B delayed progress',
            },
          ];
        }
        return <Map<String, Object?>>[
          <String, Object?>{
            'content_type': 'vod',
            'stream_id': 201 + offset,
            'position_seconds': 10 + offset,
            'title': 'Server $source Progress',
          },
        ];
      case 'get_favorites':
        if (username == 'second' && blockSecondFavoritesPull) {
          secondFavoritesPullStarted.complete();
          await releaseSecondFavoritesPull.future;
        }
        if (username == 'third' && blockThirdFavoritesPull) {
          thirdFavoritesPullStarted.complete();
          await releaseThirdFavoritesPull.future;
        }
        return <Map<String, Object?>>[
          <String, Object?>{
            'content_type': 'live',
            'stream_id': 101 + offset,
          },
        ];
      case 'sync_favorites':
        final requestedViewer = request.body['viewer_id']?.toString() ?? '';
        final requestedSource = requestedViewer.endsWith('server-b')
            ? 'B'
            : source;
        final requestedOffset =
            requestedSource.codeUnitAt(0) - 'A'.codeUnitAt(0);
        return <Map<String, Object?>>[
          <String, Object?>{
            'content_type': 'live',
            'stream_id': 101 + requestedOffset,
          },
        ];
      case 'get_epg_batch':
        return <String, Object?>{};
      case 'update_progress':
        return <String, Object?>{};
      default:
        throw StateError('Unexpected fixture action: $action');
    }
  }
}

class _BlockingFavoritesMigrationStorage extends InMemorySecureStorage {
  static const _migrationKey = 'm3ue_tv_favorites_migrated_viewers';

  final Completer<void> blockedReadStarted = Completer<void>();
  final Completer<void> releaseBlockedRead = Completer<void>();
  bool _armed = false;
  bool _blocked = false;

  void arm() => _armed = true;

  @override
  Future<String?> read(String key) async {
    if (_armed && !_blocked && key == _migrationKey) {
      _blocked = true;
      blockedReadStarted.complete();
      await releaseBlockedRead.future;
    }
    return super.read(key);
  }
}

class _BlockingFavoritesMigrationWriteStorage extends InMemorySecureStorage {
  static const _migrationKey = 'm3ue_tv_favorites_migrated_viewers';

  final Completer<void> blockedWriteStarted = Completer<void>();
  final Completer<void> releaseBlockedWrite = Completer<void>();
  final Completer<void> blockedWriteCompleted = Completer<void>();
  String? _blockedViewer;

  void blockViewer(String viewerUlid) => _blockedViewer = viewerUlid;

  Future<void> _blockWrite(String key, String value) async {
    if (_blockedViewer == null ||
        key != _migrationKey ||
        !value.contains(_blockedViewer!) ||
        blockedWriteStarted.isCompleted) {
      return;
    }
    blockedWriteStarted.complete();
    await releaseBlockedWrite.future;
  }

  @override
  Future<void> write(String key, String value) async {
    await _blockWrite(key, value);
    await super.write(key, value);
    if (key == _migrationKey &&
        value.contains(_blockedViewer ?? '') &&
        !blockedWriteCompleted.isCompleted) {
      blockedWriteCompleted.complete();
    }
  }

  @override
  Future<bool> writeIf(
    String key,
    String value,
    bool Function() shouldCommit,
  ) async {
    await _blockWrite(key, value);
    final committed = await super.writeIf(key, value, shouldCommit);
    if (key == _migrationKey &&
        value.contains(_blockedViewer ?? '') &&
        !blockedWriteCompleted.isCompleted) {
      blockedWriteCompleted.complete();
    }
    return committed;
  }
}

class _TransactionalXtreamTransport {
  _TransactionalXtreamTransport({
    required this.onSecondSourceStaged,
    required this.isSecondSourceCommitted,
  });

  final void Function() onSecondSourceStaged;
  final bool Function() isSecondSourceCommitted;
  final List<(String, bool)> secondSourcePostCommitEvents = <(String, bool)>[];

  Future<Object?> call(XtreamRequest request) async {
    final isFirst = request.credentials.username == 'first';
    final source = isFirst ? 'A' : 'B';
    final slug = isFirst ? 'server-a' : 'server-b';
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{
            'version': '0.10.0',
            'features': <String>['dvr', 'requests'],
            'requests': <String, Object?>{
              'content_types': <String>['movie'],
              'approval_behavior': 'manual',
            },
          },
        };
      case 'get_live_categories':
        return <Map<String, Object?>>[
          <String, Object?>{
            'category_id': 'live-$slug',
            'category_name': 'Server $source Live',
          },
        ];
      case 'get_vod_categories':
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
      case 'get_dvr_recordings':
        return <Map<String, Object?>>[
          <String, Object?>{
            'uuid': 'dvr-$slug',
            'title': 'Server $source DVR',
            'status': 'recording',
            'channel_id': isFirst ? 101 : 102,
          },
        ];
      case 'request_history':
        return <String, Object?>{
          'api_version': '1',
          'data': <String, Object?>{
            'requests': <Map<String, Object?>>[
              <String, Object?>{
                'id': isFirst ? 401 : 402,
                'type': 'movie',
                'title': 'Server $source Request',
                'status': 'pending',
              },
            ],
          },
        };
      case 'get_viewers':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': isFirst ? 1 : 2,
            'ulid': 'viewer-$slug',
            'name': 'Server $source Viewer',
            'is_admin': true,
          },
        ];
      case 'get_recently_watched':
        if (!isFirst) onSecondSourceStaged();
        return <Map<String, Object?>>[
          <String, Object?>{
            'content_type': 'vod',
            'stream_id': isFirst ? 201 : 202,
            'position_seconds': isFirst ? 11 : 22,
            'title': 'Server $source Progress',
          },
        ];
      case 'sync_favorites':
      case 'get_favorites':
        if (!isFirst) {
          secondSourcePostCommitEvents.add((
            request.action!,
            isSecondSourceCommitted(),
          ));
        }
        return <Object?>[];
      case 'get_epg_batch':
        if (!isFirst) {
          secondSourcePostCommitEvents.add((
            request.action!,
            isSecondSourceCommitted(),
          ));
        }
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
    final channelId = switch (title) {
      _ when title.contains('A') => 'server-a',
      _ when title.contains('B') => 'server-b',
      _ => 'server-c',
    };
    if (controller.epgService.lookup(channelId)?.current.title == title) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for guide');
}

Future<void> _waitForNotificationTitle(
  AppStateController controller,
  String title,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if ((await controller.notificationStore.all()).any(
      (stored) => stored.item.title == title,
    )) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for notification: $title');
}

Future<void> _waitForProgress(
  AppStateController controller,
  String title,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (controller.progressList.any((progress) => progress.title == title)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for progress');
}

Future<void> _waitForStoredProgress(
  AppStateController controller, {
  required String viewerId,
  required int streamId,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (await controller.resumeService.load(
          viewerId,
          ContentType.vod,
          streamId,
        ) !=
        null) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for stored progress');
}

Future<void> _waitForFavorite(
  AppStateController controller,
  int streamId,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (await controller.favoritesService.isFavorite(streamId)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for favorite');
}

Future<Set<String>> _migratedViewers(SecureStorage storage) async {
  final raw = await storage.read('m3ue_tv_favorites_migrated_viewers');
  if (raw == null) return <String>{};
  return (jsonDecode(raw) as List<Object?>).map((value) => '$value').toSet();
}

Future<void> _waitForMigratedViewer(
  SecureStorage storage,
  String viewerUlid,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if ((await _migratedViewers(storage)).contains(viewerUlid)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for migrated viewer');
}
