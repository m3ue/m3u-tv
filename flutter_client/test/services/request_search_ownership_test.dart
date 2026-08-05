import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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

  for (final handoff in <_Handoff>[
    _Handoff(
      name: 'account B with a colliding integration ID',
      run: (controller) async {
        expect(await controller.connectXtream(_accountB), isTrue);
      },
    ),
    _Handoff(
      name: 'Direct M3U',
      run: (controller) async {
        expect(
          await controller.switchToM3u(
            playlistText:
                '#EXTM3U\n#EXTINF:-1,Local channel\nhttps://local.example/live',
          ),
          isTrue,
        );
      },
    ),
    _Handoff(
      name: 'logged-out state',
      run: (controller) => controller.disconnect(),
    ),
  ]) {
    test(
      'delayed account A search is discarded after handoff to ${handoff.name}',
      () async {
        final transport = _RequestSearchTransport();
        final controller = _controller(transport);
        addTearDown(controller.dispose);

        expect(await controller.connectXtream(_accountA), isTrue);
        final staleSearch = controller.searchContentRequests('private title');
        await transport.searchStarted.future;

        await handoff.run(controller);
        transport.releaseSearch.complete();

        expect(await staleSearch, isEmpty);
        expect(transport.searchUsers, <String>[_accountA.username]);

        if (handoff.name.startsWith('account B')) {
          final currentResults = await controller.searchContentRequests(
            'current title',
          );
          expect(transport.searchUsers, <String>[
            _accountA.username,
            _accountB.username,
          ]);
          expect(currentResults.single.integrationId, 7);
          expect(currentResults.single.integrationName, 'Account B Radarr');
          expect(currentResults.single.externalId, 'account-b-title');
          expect(currentResults.single.alreadyAvailable, isFalse);
        }
      },
    );
  }
}

class _Handoff {
  const _Handoff({required this.name, required this.run});

  final String name;
  final Future<void> Function(AppStateController controller) run;
}

AppStateController _controller(_RequestSearchTransport transport) {
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
    resumeService: ResumeService(memory: memory),
    viewerService: ViewerService(memory: memory),
    tvNotificationService: _NotificationService(),
    tvNotificationStore: TvNotificationStore(memory: memory),
    reverbService: _NoopReverbService(),
  );
}

class _RequestSearchTransport {
  final searchStarted = Completer<void>();
  final releaseSearch = Completer<void>();
  final searchUsers = <String>[];
  bool _delayAccountASearch = true;

  Future<Object?> call(XtreamRequest request) async {
    final username = request.credentials.username;
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'server_info': <String, Object?>{'timezone': 'UTC'},
          'm3u_editor': <String, Object?>{
            'version': '0.10.0',
            'features': <String>['requests'],
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
      case 'request_history':
        return _requestEnvelope('requests', const <Object?>[]);
      case 'request_search':
        searchUsers.add(username);
        if (username == _accountA.username && _delayAccountASearch) {
          _delayAccountASearch = false;
          searchStarted.complete();
          await releaseSearch.future;
        }
        return _requestEnvelope('results', <Map<String, Object?>>[
          <String, Object?>{
            'type': 'movie',
            'external_id': username == _accountA.username
                ? 'account-a-title'
                : 'account-b-title',
            'integration_id': 7,
            'integration_name': username == _accountA.username
                ? 'Account A private Radarr'
                : 'Account B Radarr',
            'title': username == _accountA.username
                ? 'Account A private title'
                : 'Account B title',
            'already_available': username == _accountA.username,
          },
        ]);
      default:
        throw StateError('No fixture for ${request.action}');
    }
  }

  Map<String, Object?> _requestEnvelope(String key, Object? value) =>
      <String, Object?>{
        'api_version': '1',
        'data': <String, Object?>{key: value},
      };
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
