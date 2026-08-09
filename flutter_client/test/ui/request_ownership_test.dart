import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/features/requests/request_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/providers/app_providers.dart';
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
const _accountAResult = ContentRequestSearchResult(
  type: 'movie',
  externalId: 'shared-external-id',
  integrationId: 7,
  integrationName: 'Account A private Radarr',
  title: 'Account A private title',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('account handoff hides an already-visible account A detail', (
    tester,
  ) async {
    final transport = _RequestDetailTransport();
    final fixture = _fixture(transport);
    addTearDown(fixture.controller.dispose);
    expect(await fixture.controller.connectXtream(_accountA), isTrue);

    final router = await _pumpDetail(tester, fixture.controller);
    addTearDown(router.dispose);
    expect(find.text(_accountAResult.title), findsWidgets);

    await fixture.xtreamService.authenticate(_accountB);
    fixture.auth.overrideCredentials = _accountB;
    fixture.controller.notifyListeners();
    await tester.pump();

    expect(find.text(_accountAResult.title), findsNothing);
    expect(find.text(_accountAResult.integrationName), findsNothing);
  });

  testWidgets('stale account A detail cannot submit during handoff to B', (
    tester,
  ) async {
    final transport = _RequestDetailTransport();
    final fixture = _fixture(transport);
    addTearDown(fixture.controller.dispose);
    expect(await fixture.controller.connectXtream(_accountA), isTrue);

    final router = await _pumpDetail(tester, fixture.controller);
    addTearDown(router.dispose);
    final detailContext = tester.element(find.byType(RequestDetailScreen));
    final requestLabel = AppLocalizations.of(
      detailContext,
    ).requestsRequestButton;
    final requestButton = find.text(requestLabel);
    expect(requestButton, findsOneWidget);

    await fixture.xtreamService.authenticate(_accountB);
    fixture.auth.overrideCredentials = _accountB;
    fixture.controller.notifyListeners();
    await tester.tap(requestButton);
    await tester.pump();
    await tester.pump();

    expect(transport.submitUsers, isEmpty);
  });
}

Future<GoRouter> _pumpDetail(
  WidgetTester tester,
  AppStateController controller,
) async {
  final router = createGoRouter(
    appState: controller,
    nativeTelevisionHint: false,
    deviceTypeOverride: DeviceType.phone,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [overrideAppState(controller)],
      child: MaterialApp.router(
        theme: ThemeData.dark(useMaterial3: true),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  router.go(
    RouteNames.requestsDetailsFor(
      _accountAResult.integrationId,
      _accountAResult.type,
      _accountAResult.externalId,
    ),
    extra: _accountAResult,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return router;
}

_ControllerFixture _fixture(_RequestDetailTransport transport) {
  final memory = <String, Object?>{};
  final xtreamService = XtreamService(
    transport: transport.call,
    cache: CacheService(memory: <String, Object?>{}),
  );
  final auth = _MutableAuthNotifier(xtreamService);
  final controller = AppStateController(
    authNotifier: auth,
    xtreamService: xtreamService,
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
  return _ControllerFixture(controller, auth, xtreamService);
}

class _ControllerFixture {
  const _ControllerFixture(this.controller, this.auth, this.xtreamService);

  final AppStateController controller;
  final _MutableAuthNotifier auth;
  final XtreamService xtreamService;
}

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(XtreamService xtreamService)
    : super(
        xtreamService: xtreamService,
        secureStorage: InMemorySecureStorage(),
      );

  UserCredentials? overrideCredentials;

  @override
  UserCredentials? get credentials => overrideCredentials ?? super.credentials;
}

class _RequestDetailTransport {
  final submitUsers = <String>[];

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
        return <String, Object?>{
          'api_version': '1',
          'data': <String, Object?>{'requests': const <Object?>[]},
        };
      case 'request_submit':
        submitUsers.add(request.credentials.username);
        return <String, Object?>{
          'api_version': '1',
          'data': <String, Object?>{
            'request': <String, Object?>{
              'id': 1,
              'type': 'movie',
              'title': _accountAResult.title,
              'status': 'pending',
            },
          },
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
