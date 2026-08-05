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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'delayed viewer creation cannot publish or persist account A into account B',
    () async {
      final transport = _ViewerTransport();
      final memory = <String, Object?>{};
      final controller = _controller(transport, memory);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_accountA), isTrue);
      final staleCreation = controller.createViewer('Account A child');
      await transport.creationStarted.future;

      expect(await controller.connectXtream(_accountB), isTrue);
      await pumpEventQueue();
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      transport.releaseCreation.complete();

      expect(await staleCreation, isNull);
      await pumpEventQueue();
      expect(transport.creationCredentials?.username, _accountA.username);
      expect(controller.viewers.map((viewer) => viewer.ulid), <String>[
        'viewer-b',
      ]);
      expect(controller.activeViewer?.ulid, 'viewer-b');
      expect(
        memory['m3ue_tv_active_viewer_${_accountB.server}|${_accountB.username}'],
        'viewer-b',
      );
      expect(notifications, 0);
    },
  );
}

AppStateController _controller(
  _ViewerTransport transport,
  Map<String, Object?> memory,
) => AppStateController(
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

class _ViewerTransport {
  final creationStarted = Completer<void>();
  final releaseCreation = Completer<void>();
  UserCredentials? creationCredentials;

  Future<Object?> call(XtreamRequest request) async {
    final username = request.credentials.username;
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'server_info': <String, Object?>{'timezone': 'UTC'},
          'm3u_editor': <String, Object?>{
            'version': '0.10.0',
            'features': <String>[],
          },
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_recently_watched':
      case 'get_favorites':
      case 'sync_favorites':
        return const <Object?>[];
      case 'get_viewers':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': username == _accountA.username ? 1 : 2,
            'ulid': username == _accountA.username ? 'viewer-a' : 'viewer-b',
            'name': username == _accountA.username
                ? 'Account A viewer'
                : 'Account B viewer',
            'is_admin': true,
          },
        ];
      case 'create_viewer':
        creationCredentials = request.credentials;
        creationStarted.complete();
        await releaseCreation.future;
        return <String, Object?>{
          'id': 3,
          'ulid': 'viewer-a-child',
          'name': 'Account A child',
          'is_admin': false,
        };
      default:
        throw StateError('No fixture for ${request.action}');
    }
  }
}

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
