import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
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

const _accountA = UserCredentials(
  server: 'https://account-a.example',
  username: 'account-a',
  password: 'secret-a',
);
const _accountB = UserCredentials(
  server: 'https://account-b.example',
  username: 'account-b',
  password: 'secret-b',
);
const _channel = Channel(
  id: 101,
  name: 'News',
  streamUrl: 'https://media.example/news',
);
final _program = EpgProgram(
  channelId: 'news',
  title: 'Evening News',
  description: '',
  start: DateTime.utc(2026, 8, 4, 20),
  end: DateTime.utc(2026, 8, 4, 21),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('delayed account A schedule cannot notify M3U state', () async {
    final transport = _DvrMutationTransport();
    final controller = _controller(transport);
    addTearDown(controller.dispose);

    expect(await controller.connectXtream(_accountA), isTrue);
    final staleSchedule = controller.scheduleDvr(_channel, _program);
    await transport.scheduleStarted.future;

    expect(
      await controller.switchToM3u(
        playlistText:
            '#EXTM3U\n#EXTINF:-1,Local channel\nhttps://local.example/live',
      ),
      isTrue,
    );
    await pumpEventQueue();
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    transport.releaseSchedule.complete();
    expect(await staleSchedule, isNull);
    await pumpEventQueue();

    expect(transport.scheduleUsers, <String>[_accountA.username]);
    expect(controller.sourceType, AppSourceType.m3u);
    expect(controller.dvrRecordings, isEmpty);
    expect(notifications, 0);
  });

  test('delayed account A cancel detail cannot publish after logout', () async {
    final transport = _DvrMutationTransport();
    final controller = _controller(transport);
    addTearDown(controller.dispose);

    expect(await controller.connectXtream(_accountA), isTrue);
    final staleCancel = controller.cancelDvrRecording('shared-recording');
    await transport.cancelDetailStarted.future;

    await controller.disconnect();
    await pumpEventQueue();
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    transport.releaseCancelDetail.complete();
    await staleCancel;
    await pumpEventQueue();

    expect(transport.cancelUsers, <String>[_accountA.username]);
    expect(transport.cancelDetailUsers, <String>[_accountA.username]);
    expect(controller.sourceType, AppSourceType.none);
    expect(controller.dvrRecordings, isEmpty);
    expect(controller.recordingChannelIds, isEmpty);
    expect(notifications, 0);
  });

  test(
    'delayed account A delete cannot remove account B row with the same ID',
    () async {
      final transport = _DvrMutationTransport();
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_accountA), isTrue);
      final staleDelete = controller.deleteDvrRecording('shared-recording');
      await transport.deleteStarted.future;

      expect(await controller.connectXtream(_accountB), isTrue);
      await pumpEventQueue();
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      transport.releaseDelete.complete();
      await staleDelete;
      await pumpEventQueue();

      expect(transport.deleteUsers, <String>[_accountA.username]);
      expect(controller.dvrRecordings.single.title, 'Account B recording');
      expect(controller.recordingChannelIds, <int>{202});
      expect(notifications, 0);
    },
  );
}

AppStateController _controller(_DvrMutationTransport transport) {
  final memory = <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport.call,
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
    aioFavoritesService: AIOStreamsFavoritesService(),
    resumeService: ResumeService(memory: memory),
    viewerService: ViewerService(memory: memory),
    tvNotificationService: _NotificationService(),
    tvNotificationStore: TvNotificationStore(memory: memory),
    reverbService: _NoopReverbService(),
  );
}

class _DvrMutationTransport {
  final scheduleStarted = Completer<void>();
  final releaseSchedule = Completer<void>();
  final cancelDetailStarted = Completer<void>();
  final releaseCancelDetail = Completer<void>();
  final deleteStarted = Completer<void>();
  final releaseDelete = Completer<void>();
  final scheduleUsers = <String>[];
  final cancelUsers = <String>[];
  final cancelDetailUsers = <String>[];
  final deleteUsers = <String>[];

  Future<Object?> call(XtreamRequest request) async {
    final username = request.credentials.username;
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'server_info': <String, Object?>{'timezone': 'UTC'},
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
        return const <Object?>[];
      case 'get_dvr_recordings':
        return <Map<String, Object?>>[
          _recording(
            title: username == _accountA.username
                ? 'Account A recording'
                : 'Account B recording',
            channelId: username == _accountA.username ? 101 : 202,
          ),
        ];
      case 'schedule_dvr':
        scheduleUsers.add(username);
        scheduleStarted.complete();
        await releaseSchedule.future;
        return <String, Object?>{'success': true, 'rule_id': 1};
      case 'cancel_dvr_recording':
        cancelUsers.add(username);
        return <String, Object?>{'success': true};
      case 'get_dvr_recording':
        cancelDetailUsers.add(username);
        cancelDetailStarted.complete();
        await releaseCancelDetail.future;
        return _recording(
          title: 'Account A cancelled recording',
          channelId: 101,
          status: 'cancelled',
        );
      case 'delete_dvr_recording':
        deleteUsers.add(username);
        deleteStarted.complete();
        await releaseDelete.future;
        return <String, Object?>{'success': true};
      default:
        throw StateError('No fixture for ${request.action}');
    }
  }
}

Map<String, Object?> _recording({
  required String title,
  required int channelId,
  String status = 'recording',
}) => <String, Object?>{
  'uuid': 'shared-recording',
  'title': title,
  'status': status,
  'channel_id': channelId,
  'scheduled_start': _program.start.toIso8601String(),
  'scheduled_end': _program.end.toIso8601String(),
};

class _NotificationService extends TvNotificationService {
  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async => const (
    TvPlaylistSession(
      notifiableId: 1,
      notifiableType: 'playlist',
      isAdmin: false,
      channelName: '',
      reverb: ReverbConfig(host: '', port: 0, scheme: 'wss', appKey: ''),
    ),
    <TvNotificationItem>[],
  );
}

class _NoopReverbService extends ReverbService {
  @override
  Future<void> disconnect() async {}
}
