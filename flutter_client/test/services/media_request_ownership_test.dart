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
    'delayed request refresh cannot publish account A into account B',
    () async {
      final transport = _RequestTransport();
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_accountA), isTrue);
      transport.delayNextHistory(<Map<String, Object?>>[
        _requestJson(401, 'Account A private request'),
      ]);

      final staleRefresh = controller.refreshMediaRequests();
      await transport.historyStarted.future;
      expect(await controller.connectXtream(_accountB), isTrue);

      transport.releaseHistory.complete();
      await staleRefresh;

      expect(
        controller.mediaRequests.map((request) => request.title),
        isNot(contains('Account A private request')),
      );
    },
  );

  test(
    'delayed request refresh cannot publish after switching to M3U',
    () async {
      final transport = _RequestTransport();
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_accountA), isTrue);
      transport.delayNextHistory(<Map<String, Object?>>[
        _requestJson(401, 'Account A private request'),
      ]);

      final staleRefresh = controller.refreshMediaRequests();
      await transport.historyStarted.future;
      expect(
        await controller.switchToM3u(
          playlistText:
              '#EXTM3U\n#EXTINF:-1,Local channel\nhttps://local.example/live',
        ),
        isTrue,
      );

      transport.releaseHistory.complete();
      await staleRefresh;

      expect(controller.sourceType, AppSourceType.m3u);
      expect(controller.mediaRequests, isEmpty);
    },
  );

  test(
    'delayed submit cannot publish account A request into account B',
    () async {
      final transport = _RequestTransport(
        historyByUsername: <String, List<Map<String, Object?>>>{
          _accountB.username: <Map<String, Object?>>[
            _requestJson(501, 'Account B request'),
          ],
        },
      );
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_accountA), isTrue);
      transport.delayNextSubmit(
        _requestJson(402, 'Account A submitted request'),
      );

      final staleSubmit = controller.submitContentRequest(
        type: 'movie',
        integrationId: 1,
        externalId: 'movie-a',
      );
      await transport.submitStarted.future;
      expect(await controller.connectXtream(_accountB), isTrue);

      transport.releaseSubmit.complete();
      await staleSubmit;

      expect(transport.submitCredentials?.username, _accountA.username);
      expect(
        controller.mediaRequests.map((request) => request.title),
        <String>['Account B request'],
      );
    },
  );

  test(
    'delayed dismiss cannot remove an account B request with the same ID',
    () async {
      final transport = _RequestTransport(
        historyByUsername: <String, List<Map<String, Object?>>>{
          _accountA.username: <Map<String, Object?>>[
            _requestJson(403, 'Account A request'),
          ],
          _accountB.username: <Map<String, Object?>>[
            _requestJson(403, 'Account B request'),
          ],
        },
      );
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_accountA), isTrue);
      transport.delayNextDismiss();

      final staleDismiss = controller.dismissMediaRequest(403);
      await transport.dismissStarted.future;
      expect(await controller.connectXtream(_accountB), isTrue);

      transport.releaseDismiss.complete();
      await staleDismiss;

      expect(transport.dismissCredentials?.username, _accountA.username);
      expect(controller.mediaRequests.single.title, 'Account B request');
    },
  );

  test(
    'request status callback from account A cannot publish into account B',
    () async {
      final transport = _RequestTransport();
      final reverb = _CapturingReverbService();
      final controller = _controller(transport, reverbService: reverb);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_accountA), isTrue);
      await reverb.firstConnection.future;
      final accountACallback = reverb.requestStatusCallbacks.single;

      expect(await controller.connectXtream(_accountB), isTrue);
      accountACallback(
        const MediaRequestSummary(
          id: 404,
          type: 'movie',
          title: 'Account A delayed status',
          status: MediaRequestStatus.approved,
        ),
      );

      expect(controller.mediaRequests, isEmpty);
    },
  );
}

AppStateController _controller(
  _RequestTransport transport, {
  ReverbService? reverbService,
}) {
  final localMemory = <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport.call,
      cache: CacheService(memory: <String, Object?>{}),
    ),
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    favoritesService: FavoritesService(memory: localMemory),
    vodFavoritesService: FavoritesService(
      memory: localMemory,
      namespace: 'vod',
    ),
    seriesFavoritesService: FavoritesService(
      memory: localMemory,
      namespace: 'series',
    ),
    resumeService: ResumeService(memory: localMemory),
    viewerService: ViewerService(memory: localMemory),
    tvNotificationService: _NotificationService(),
    tvNotificationStore: TvNotificationStore(memory: localMemory),
    reverbService: reverbService ?? _NoopReverbService(),
  );
}

Map<String, Object?> _requestJson(int id, String title) => <String, Object?>{
  'id': id,
  'type': 'movie',
  'title': title,
  'status': 'pending',
};

class _RequestTransport {
  _RequestTransport({this.historyByUsername = const {}});

  final Map<String, List<Map<String, Object?>>> historyByUsername;
  final historyStarted = Completer<void>();
  final releaseHistory = Completer<void>();
  final submitStarted = Completer<void>();
  final releaseSubmit = Completer<void>();
  final dismissStarted = Completer<void>();
  final releaseDismiss = Completer<void>();
  List<Map<String, Object?>>? _delayedHistory;
  Map<String, Object?>? _delayedSubmit;
  bool _delayDismiss = false;
  UserCredentials? submitCredentials;
  UserCredentials? dismissCredentials;

  void delayNextHistory(List<Map<String, Object?>> requests) {
    _delayedHistory = requests;
  }

  void delayNextSubmit(Map<String, Object?> request) {
    _delayedSubmit = request;
  }

  void delayNextDismiss() {
    _delayDismiss = true;
  }

  Future<Object?> call(XtreamRequest request) async {
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
        final delayed = _delayedHistory;
        if (delayed != null &&
            request.credentials.username == _accountA.username) {
          _delayedHistory = null;
          historyStarted.complete();
          await releaseHistory.future;
          return _history(delayed);
        }
        return _history(
          historyByUsername[request.credentials.username] ??
              const <Map<String, Object?>>[],
        );
      case 'request_submit':
        submitCredentials = request.credentials;
        final delayed = _delayedSubmit;
        if (delayed == null) throw StateError('No delayed submit configured');
        _delayedSubmit = null;
        submitStarted.complete();
        await releaseSubmit.future;
        return <String, Object?>{
          'api_version': '1',
          'data': <String, Object?>{'request': delayed},
        };
      case 'request_dismiss':
        dismissCredentials = request.credentials;
        if (!_delayDismiss) throw StateError('No delayed dismiss configured');
        _delayDismiss = false;
        dismissStarted.complete();
        await releaseDismiss.future;
        return <String, Object?>{
          'api_version': '1',
          'data': const <String, Object?>{},
        };
      default:
        throw StateError('No fixture for ${request.action}');
    }
  }

  Map<String, Object?> _history(List<Map<String, Object?>> requests) =>
      <String, Object?>{
        'api_version': '1',
        'data': <String, Object?>{'requests': requests},
      };
}

class _NotificationService extends TvNotificationService {
  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async => (
    const TvPlaylistSession(
      notifiableId: 1,
      notifiableType: 'playlist',
      isAdmin: false,
      channelName: 'private-playlist.1',
      reverb: ReverbConfig(
        appKey: 'fixture',
        host: 'reverb.example',
        port: 443,
        scheme: 'wss',
      ),
    ),
    const <TvNotificationItem>[],
  );
}

class _NoopReverbService extends ReverbService {
  @override
  Future<void> connect({
    required TvPlaylistSession session,
    required UserCredentials credentials,
    Set<String> subscribedChannels = const {},
    required void Function(TvNotificationItem) onNotification,
    void Function(DvrRecording)? onDvrStatus,
    void Function(MediaRequestSummary)? onRequestStatus,
    void Function(FavoriteToggleEvent)? onFavoriteToggled,
    void Function()? onConnected,
  }) async {}

  @override
  Future<void> disconnect() async {}
}

class _CapturingReverbService extends _NoopReverbService {
  final firstConnection = Completer<void>();
  final requestStatusCallbacks = <void Function(MediaRequestSummary)>[];

  @override
  Future<void> connect({
    required TvPlaylistSession session,
    required UserCredentials credentials,
    Set<String> subscribedChannels = const {},
    required void Function(TvNotificationItem) onNotification,
    void Function(DvrRecording)? onDvrStatus,
    void Function(MediaRequestSummary)? onRequestStatus,
    void Function(FavoriteToggleEvent)? onFavoriteToggled,
    void Function()? onConnected,
  }) async {
    if (onRequestStatus != null) requestStatusCallbacks.add(onRequestStatus);
    if (!firstConnection.isCompleted) firstConnection.complete();
  }
}
