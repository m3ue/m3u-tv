import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/app/system_ui_policy.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

void main() {
  group('Route navigation', () {
    testWidgets('initial route shows Home content', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await _expandSidebar(tester);
      // Home text appears in both sidebar and content area
      expect(find.text('Home'), findsAtLeast(1));
      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets(
      'large desktop Home rows keep preview cards comfortably sized',
      (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final viewport in [
          const Size(1440, 900),
          const Size(1920, 1080),
          const Size(2560, 1440),
        ]) {
          tester.view.physicalSize = viewport;
          final appState = _testAppState(
            xtreamService: _NavigationXtreamService(
              liveChannels: List<Channel>.generate(
                16,
                (index) => Channel(
                  id: 100 + index,
                  name: 'Desktop Channel $index',
                  streamUrl: 'http://example.com/live/$index.m3u8',
                  categoryId: 'live',
                ),
              ),
              vodItems: List<VodItem>.generate(
                16,
                (index) => VodItem(
                  id: 200 + index,
                  name: 'Desktop Movie $index',
                  streamUrl: 'http://example.com/movie/$index.mp4',
                  containerExtension: 'mp4',
                  categoryId: 'vod',
                ),
              ),
              seriesList: List<Series>.generate(
                16,
                (index) => Series(
                  id: 300 + index,
                  name: 'Desktop Series $index',
                  categoryId: 'series',
                ),
              ),
            ),
          );
          addTearDown(appState.dispose);
          await appState.connectXtream(
            const UserCredentials(
              server: 'http://example.com',
              username: 'user',
              password: 'pass',
            ),
          );

          await tester.pumpWidget(
            _TestApp(deviceType: DeviceType.desktop, appState: appState),
          );
          await _pumpAppFrame(tester);

          expect(tester.takeException(), isNull);
          final firstMovieCard = find.byWidgetPredicate(
            (widget) =>
                widget is MediaPreviewCard &&
                widget.item.title == 'Desktop Movie 0',
          );
          final firstSeriesCard = find.byWidgetPredicate(
            (widget) =>
                widget is MediaPreviewCard &&
                widget.item.title == 'Desktop Series 0',
          );
          expect(firstMovieCard, findsOneWidget);
          expect(firstSeriesCard, findsOneWidget);
          expect(tester.getSize(firstMovieCard).width, lessThanOrEqualTo(190));
          expect(tester.getSize(firstSeriesCard).width, lessThanOrEqualTo(190));
        }
      },
    );

    testWidgets('Home shows favorite live channels before full Live TV', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(
          liveChannels: const <Channel>[
            Channel(
              id: 101,
              name: 'Favorite Route News',
              streamUrl: 'http://example.com/live/101.m3u8',
              categoryId: 'live',
            ),
            Channel(
              id: 102,
              name: 'Regular Route Sports',
              streamUrl: 'http://example.com/live/102.m3u8',
              categoryId: 'live',
            ),
          ],
        ),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );
      await appState.favoritesService.add(101);
      expect(await appState.favoritesService.all(), contains(101));

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);
      await _waitForText(tester, 'Favorite Channels');

      expect(find.text('Favorite Channels'), findsOneWidget);
      expect(find.text('Favorite Route News'), findsOneWidget);
      expect(find.text('Regular Route Sports'), findsNothing);
    });

    testWidgets('Home keeps full Live TV section when no favorites exist', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(
          liveChannels: const <Channel>[
            Channel(
              id: 101,
              name: 'Route News',
              streamUrl: 'http://example.com/live/101.m3u8',
              categoryId: 'live',
            ),
            Channel(
              id: 102,
              name: 'Route Sports',
              streamUrl: 'http://example.com/live/102.m3u8',
              categoryId: 'live',
            ),
          ],
        ),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);

      expect(find.text('Live TV'), findsAtLeast(1));
      expect(find.text('Route News'), findsOneWidget);
      expect(find.text('Route Sports'), findsOneWidget);
    });

    testWidgets('navigating to LiveTV shows Live TV screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      // Sidebar is expanded by default, so text is visible
      await tester.tap(_sidebarText('Live TV'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to VOD shows Movies screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(_sidebarText('Movies'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to Series shows Series screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(_sidebarText('Series'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to Search shows Search screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(_sidebarText('Search'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('navigating to Settings shows Settings screen', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(_sidebarText('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Server URL'), findsOneWidget);
    });

    testWidgets('hides DVR navigation when backend does not advertise DVR', (
      tester,
    ) async {
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);
      await _expandSidebar(tester);

      expect(_sidebarText('DVR'), findsNothing);
      expect(find.text('DVR Recordings'), findsNothing);
    });

    testWidgets('DVR appears in sidebar when backend advertises DVR', (
      tester,
    ) async {
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(
          features: const <String>['progress', 'dvr'],
          dvrRecordings: <DvrRecording>[_routeRecording()],
        ),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);
      await _expandSidebar(tester);

      await tester.tap(_sidebarText('DVR'));
      await _pumpAppFrame(tester);

      expect(find.text('Route Recording'), findsOneWidget);
    });

    testWidgets('hides Requests navigation when backend lacks requests', (
      tester,
    ) async {
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(
          features: const <String>['progress', 'dvr'],
        ),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);
      await _expandSidebar(tester);

      expect(_sidebarText('Requests'), findsNothing);
      expect(find.text('Request Content'), findsNothing);
    });

    testWidgets('Requests appears and opens when backend advertises requests', (
      tester,
    ) async {
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(
          features: const <String>['progress', 'requests'],
        ),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);
      await _expandSidebar(tester);

      await tester.tap(_sidebarText('Requests'));
      await _pumpAppFrame(tester);

      expect(find.text('Search'), findsOneWidget);
      expect(find.text('My Requests'), findsOneWidget);
      expect(find.text('Search...'), findsOneWidget);
    });

    testWidgets('sidebar labels remain visible after selecting a route', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.tap(_sidebarText('Settings'));
      await tester.pumpAndSettle();

      await _expandSidebar(tester);

      expect(
        find.descendant(
          of: find.byType(NavigationSidebar),
          matching: find.text('Home'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NavigationSidebar),
          matching: find.text('Settings'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'Player route pushes as modal via inner navigator',
      (tester) async {
        // Player is now a Stack overlay managed by AppShell, not a named route.
        // Covered by: "selecting live channel from app shell opens player route"
      },
      skip: true,
    );

    testWidgets(
      'Player route receives supplied EPG service',
      (tester) async {
        // This test used the old imperative RouteFactory (buildAppRouter).
        // Player is now an overlay managed by AppShell; EPG service is wired
        // through AppStateController. Test retained as a placeholder.
      },
      skip: true,
    );

    testWidgets(
      'Details route pushes via inner navigator',
      (tester) async {
        // VOD details now navigate via go_router (/vod/details/:id), not a
        // named imperative route. Covered by:
        // "selecting movie from app shell opens details then player route"
      },
      skip: true,
    );

    testWidgets(
      'SeriesDetails route pushes via inner navigator',
      (tester) async {
        // Series details now navigate via go_router (/series/details/:id), not
        // a named imperative route. Covered by:
        // "selecting series from app shell opens series details route"
      },
      skip: true,
    );

    testWidgets(
      'ViewerSelection route pushes via inner navigator',
      (tester) async {
        // Viewer selection is now a Stack overlay in AppShell, not a named
        // imperative route. Triggered via AppShell state, not Navigator.pushNamed.
      },
      skip: true,
    );
  });

  testWidgets('selecting live channel from app shell opens player route', (
    tester,
  ) async {
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(deviceType: DeviceType.tv, appState: appState),
    );
    await _pumpAppFrame(tester);

    await tester.tap(_sidebarText('Live TV'));
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route News').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Player route: Route News'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'active native plane suppresses browsing paint and restores it on release and close',
    (tester) async {
      final adapter = _NavigationPlayerAdapter();
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(
          deviceType: DeviceType.tv,
          appState: appState,
          useProductionPlayer: true,
          playbackOrchestratorBuilder: () => _testPlaybackOrchestrator(adapter),
        ),
      );
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route News').last);
      await _pumpAppFrame(tester);

      bool browsingPaintSuppressed() => tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byType(NavigationSidebar),
              matching: find.byType(Opacity),
            ),
          )
          .any((opacity) => opacity.opacity == 0);

      expect(browsingPaintSuppressed(), isFalse);

      adapter.setUsesNativePlane(value: true);
      await tester.pump();

      expect(browsingPaintSuppressed(), isTrue);

      adapter.setUsesNativePlane(value: false);
      await tester.pump();

      expect(browsingPaintSuppressed(), isFalse);

      adapter.setUsesNativePlane(value: true);
      await tester.pump();
      expect(browsingPaintSuppressed(), isTrue);

      expect(
        await tester
            .state<_TestAppState>(find.byType(_TestApp))
            .dispatchRouterBack(),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.byType(NavigationSidebar), findsOneWidget);
      expect(browsingPaintSuppressed(), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'native-plane playback failure restores browsing composition',
    (tester) async {
      final adapter = _NavigationPlayerAdapter();
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(
          deviceType: DeviceType.tv,
          appState: appState,
          useProductionPlayer: true,
          playbackOrchestratorBuilder: () => _testPlaybackOrchestrator(adapter),
        ),
      );
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route News').last);
      await _pumpAppFrame(tester);

      final sidebar = find.byType(NavigationSidebar);
      Iterable<T> browsingAncestors<T extends Widget>() => tester.widgetList<T>(
        find.ancestor(of: sidebar, matching: find.byType(T)),
      );

      adapter.setUsesNativePlane(value: true);
      await tester.pump();

      expect(browsingAncestors<Opacity>().any((w) => w.opacity == 0), isTrue);
      expect(browsingAncestors<IgnorePointer>().any((w) => w.ignoring), isTrue);
      expect(
        browsingAncestors<ExcludeSemantics>().any((w) => w.excluding),
        isTrue,
      );

      adapter.emitError(
        const PlaybackError(
          backend: PlaybackBackend.desktopLibmpv,
          message: 'Playback failed',
          code: 'playback_failed',
        ),
      );
      await tester.pump();

      expect(find.text('Playback error'), findsOneWidget);
      expect(browsingAncestors<Opacity>().any((w) => w.opacity == 0), isFalse);
      expect(
        browsingAncestors<IgnorePointer>().any((w) => w.ignoring),
        isFalse,
      );
      expect(
        browsingAncestors<ExcludeSemantics>().any((w) => w.excluding),
        isFalse,
      );
      expect(
        tester
            .widget<Scaffold>(
              find.ancestor(
                of: find.text('Playback error'),
                matching: find.byType(Scaffold),
              ),
            )
            .backgroundColor,
        Colors.black,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('player open and Android back apply route system UI policies', (
    tester,
  ) async {
    final modes = <SystemUiRouteMode>[];
    final policy = SystemUiPolicy(
      isAndroid: true,
      applySystemUiRouteMode: (mode) async => modes.add(mode),
    );
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.phone,
        appState: appState,
        systemUiPolicy: policy,
      ),
    );
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route News').last);
    await _pumpAppFrame(tester);

    expect(modes, <SystemUiRouteMode>[SystemUiRouteMode.player]);

    expect(
      await tester
          .state<_TestAppState>(find.byType(_TestApp))
          .dispatchRouterBack(),
      isTrue,
    );
    await _pumpAppFrame(tester);

    expect(modes, <SystemUiRouteMode>[
      SystemUiRouteMode.player,
      SystemUiRouteMode.browsing,
    ]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(modes.last, SystemUiRouteMode.browsing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('lifecycle resume reapplies browsing route system UI policy', (
    tester,
  ) async {
    final modes = <SystemUiRouteMode>[];
    final policy = SystemUiPolicy(
      isAndroid: true,
      applySystemUiRouteMode: (mode) async => modes.add(mode),
    );

    await tester.pumpWidget(
      _TestApp(deviceType: DeviceType.phone, systemUiPolicy: policy),
    );
    await _pumpAppFrame(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(modes, <SystemUiRouteMode>[SystemUiRouteMode.browsing]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('playback failure restores browsing system UI policy', (
    tester,
  ) async {
    final modes = <SystemUiRouteMode>[];
    final policy = SystemUiPolicy(
      isAndroid: true,
      applySystemUiRouteMode: (mode) async => modes.add(mode),
    );
    final adapter = _NavigationPlayerAdapter();
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.phone,
        appState: appState,
        systemUiPolicy: policy,
        useProductionPlayer: true,
        playbackOrchestratorBuilder: () => _testPlaybackOrchestrator(adapter),
      ),
    );
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route News').last);
    await _pumpAppFrame(tester);

    adapter.emitError(
      const PlaybackError(
        backend: PlaybackBackend.desktopLibmpv,
        message: 'Playback failed',
        code: 'playback_failed',
      ),
    );
    await _pumpAppFrame(tester);

    expect(find.text('Playback error'), findsOneWidget);
    expect(modes, <SystemUiRouteMode>[
      SystemUiRouteMode.player,
      SystemUiRouteMode.browsing,
    ]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(modes.last, SystemUiRouteMode.browsing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'live channel skip-next reuses the orchestrator instead of rebuilding it',
    (tester) async {
      // Regression test: the Android Media3 and Apple AVKit native plugins
      // each hold a single global player behind their MethodChannel. Building
      // a fresh PlaybackOrchestrator per channel switch (as skip-next used
      // to) let the previous orchestrator's deferred dispose tear down the
      // channel the user had just switched to, once its load already landed.
      // AppShell must now reuse the existing orchestrator across an
      // in-session channel switch instead of building a new one.
      var builderCallCount = 0;
      final adapter = _NavigationPlayerAdapter();
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(
          liveChannels: const <Channel>[
            Channel(
              id: 101,
              name: 'Route News',
              streamUrl: 'http://example.com/live/101.m3u8',
              categoryId: 'live',
            ),
            Channel(
              id: 102,
              name: 'Route Sports',
              streamUrl: 'http://example.com/live/102.m3u8',
              categoryId: 'live',
            ),
          ],
        ),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(
          deviceType: DeviceType.tv,
          appState: appState,
          useProductionPlayer: true,
          playbackOrchestratorBuilder: () {
            builderCallCount++;
            return _testPlaybackOrchestrator(adapter);
          },
        ),
      );
      await _pumpAppFrame(tester);

      await tester.tap(find.text('Route News').last);
      await _pumpAppFrame(tester);

      expect(builderCallCount, 1);
      expect(adapter.loadCallCount, 1);

      await tester.tap(find.byIcon(Icons.skip_next));
      await _pumpAppFrame(tester);

      expect(
        builderCallCount,
        1,
        reason: 'channel switch must reuse the existing orchestrator',
      );
      expect(
        adapter.disposeCallCount,
        0,
        reason: 'the just-opened channel must not be torn down mid-switch',
      );
      expect(adapter.loadCallCount, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('lifecycle resume keeps an active player immersive', (
    tester,
  ) async {
    final modes = <SystemUiRouteMode>[];
    final policy = SystemUiPolicy(
      isAndroid: true,
      applySystemUiRouteMode: (mode) async => modes.add(mode),
    );
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.phone,
        appState: appState,
        systemUiPolicy: policy,
      ),
    );
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route News').last);
    await _pumpAppFrame(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(modes, <SystemUiRouteMode>[
      SystemUiRouteMode.player,
      SystemUiRouteMode.player,
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('route replacement restores browsing system UI policy', (
    tester,
  ) async {
    final modes = <SystemUiRouteMode>[];
    final policy = SystemUiPolicy(
      isAndroid: true,
      applySystemUiRouteMode: (mode) async => modes.add(mode),
    );
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.phone,
        appState: appState,
        systemUiPolicy: policy,
      ),
    );
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route News').last);
    await _pumpAppFrame(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(modes, <SystemUiRouteMode>[
      SystemUiRouteMode.player,
      SystemUiRouteMode.browsing,
    ]);
  });

  testWidgets('selecting live channel passes name as EPG fallback', (
    tester,
  ) async {
    PlayerArgs? capturedArgs;
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.tv,
        appState: appState,
        playerRouteBuilder: (args) {
          capturedArgs = args;
          return _testPlayerRoute(args);
        },
      ),
    );
    await _pumpAppFrame(tester);

    await tester.tap(_sidebarText('Live TV'));
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route News').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(capturedArgs?.epgChannelId, 'Route News');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selecting Home continue watching movie resumes saved position', (
    tester,
  ) async {
    PlayerArgs? capturedArgs;
    final appState = _testAppState(
      xtreamService: _NavigationXtreamService(
        recentlyWatched: const <Progress>[
          Progress(
            viewerId: 'viewer-1',
            contentType: ContentType.vod,
            streamId: 201,
            positionSeconds: 91,
            durationSeconds: 600,
            title: 'Resume Route Movie',
          ),
        ],
      ),
    );
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.tv,
        appState: appState,
        playerRouteBuilder: (args) {
          capturedArgs = args;
          return _testPlayerRoute(args);
        },
      ),
    );
    await _pumpAppFrame(tester);

    // Continue Watching card uses enriched progress metadata when available.
    expect(find.text('Resume Route Movie'), findsAtLeast(1));

    await tester.tap(_mediaPreviewCardWithText('Resume Route Movie'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Resume modal lets the user choose to resume from saved position or restart.
    expect(find.text('Resume Watching'), findsOneWidget);
    await tester.tap(_dpadInkWellWithText('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Player route: Resume Route Movie'), findsOneWidget);
    expect(capturedArgs?.startPosition, 91.0);
    expect(
      capturedArgs?.toPlaybackSource().startPosition,
      const Duration(seconds: 91),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('start from beginning clears saved resume position', (
    tester,
  ) async {
    PlayerArgs? capturedArgs;
    final appState = _testAppState(
      xtreamService: _NavigationXtreamService(
        recentlyWatched: const <Progress>[
          Progress(
            viewerId: 'viewer-1',
            contentType: ContentType.vod,
            streamId: 201,
            positionSeconds: 91,
            durationSeconds: 600,
            title: 'Resume Route Movie',
          ),
        ],
      ),
    );
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.tv,
        appState: appState,
        playerRouteBuilder: (args) {
          capturedArgs = args;
          return _testPlayerRoute(args);
        },
      ),
    );
    await _pumpAppFrame(tester);
    await _waitForText(tester, 'Resume Route Movie');

    await tester.tap(_mediaPreviewCardWithText('Resume Route Movie'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Resume Watching'), findsOneWidget);
    await tester.tap(find.text('Start from Beginning'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Player route: Resume Route Movie'), findsOneWidget);
    expect(capturedArgs?.startPosition, isNull);
    expect(
      capturedArgs?.toPlaybackSource().startPosition,
      Duration.zero,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Home continue watching row caps at 4 items with a See All overflow tile',
    (tester) async {
      // The default test surface is too narrow to lay out 5 landscape cards
      // in the row without scrolling, which would leave the later ones
      // unbuilt (ListView.separated is lazy) and unfindable by find.text.
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final progressList = [
        for (var i = 0; i < 5; i += 1)
          Progress(
            viewerId: 'viewer-1',
            contentType: ContentType.vod,
            streamId: 300 + i,
            positionSeconds: 60,
            durationSeconds: 600,
            title: 'Overflow Movie $i',
          ),
      ];
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(recentlyWatched: progressList),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);
      await _waitForText(tester, 'Overflow Movie 0');

      // Only the first 4 items render as real cards on the Home row.
      for (var i = 0; i < 4; i += 1) {
        expect(_mediaPreviewCardWithText('Overflow Movie $i'), findsOneWidget);
      }
      expect(find.text('Overflow Movie 4'), findsNothing);

      // The overflow tile shows the remaining count.
      expect(find.text('See All'), findsOneWidget);
      expect(find.text('+1 more'), findsOneWidget);

      // Tapping it navigates to the full list, which shows every item.
      await tester.tap(_dpadInkWellWithText('See All'));
      await _pumpAppFrame(tester);
      await _waitForText(tester, 'Overflow Movie 4');

      for (var i = 0; i < 5; i += 1) {
        expect(_mediaPreviewCardWithText('Overflow Movie $i'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'selecting movie from app shell opens details then player route',
    (tester) async {
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);

      await tester.tap(_sidebarText('Movies'));
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route Movie').last);
      await _pumpAppFrame(tester);

      expect(find.text('Play movie'), findsOneWidget);
      await tester.tap(find.text('Play movie'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Player route: Route Movie'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Router back dispatch closes active live player', (
    tester,
  ) async {
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(deviceType: DeviceType.phone, appState: appState),
    );
    await _pumpAppFrame(tester);

    await tester.tap(find.text('Route News').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Player route: Route News'), findsOneWidget);

    final handled = await tester
        .state<_TestAppState>(find.byType(_TestApp))
        .dispatchRouterBack();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('Player route: Route News'), findsNothing);
    expect(find.text('Route News'), findsWidgets);
    expect(find.text('Press back again to exit'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Router back dispatch closes failed player', (tester) async {
    final adapter = _NavigationPlayerAdapter();
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.phone,
        appState: appState,
        useProductionPlayer: true,
        playbackOrchestratorBuilder: () => _testPlaybackOrchestrator(adapter),
      ),
    );
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route News').last);
    await _pumpAppFrame(tester);

    adapter.emitError(
      const PlaybackError(
        backend: PlaybackBackend.desktopLibmpv,
        message: 'Playback failed',
        code: 'playback_failed',
      ),
    );
    await _pumpAppFrame(tester);
    expect(find.text('Playback error'), findsOneWidget);

    final handled = await tester
        .state<_TestAppState>(find.byType(_TestApp))
        .dispatchRouterBack();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.text('Route News'), findsWidgets);
    expect(find.text('Press back again to exit'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Router back dispatch pops nested movie details', (tester) async {
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(deviceType: DeviceType.phone, appState: appState),
    );
    await _pumpAppFrame(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('Movies'),
      ),
    );
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route Movie').last);
    await _pumpAppFrame(tester);
    expect(find.text('Play movie'), findsOneWidget);

    final handled = await tester
        .state<_TestAppState>(find.byType(_TestApp))
        .dispatchRouterBack();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('Play movie'), findsNothing);
    expect(find.text('Route Movie'), findsWidgets);
  });

  testWidgets('Router back dispatch preserves root double-back exit', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp(deviceType: DeviceType.phone));
    await _pumpAppFrame(tester);
    final app = tester.state<_TestAppState>(find.byType(_TestApp));

    expect(await app.dispatchRouterBack(), isTrue);
    await tester.pump();
    expect(find.text('Press back again to exit'), findsOneWidget);

    expect(await app.dispatchRouterBack(), isFalse);
  });

  testWidgets('legacy Android platform back closes active player', (
    tester,
  ) async {
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(deviceType: DeviceType.phone, appState: appState),
    );
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route News').last);
    await _pumpAppFrame(tester);
    expect(find.text('Player route: Route News'), findsOneWidget);

    await _sendPlatformNavigationMethod(tester, const MethodCall('popRoute'));
    await _pumpAppFrame(tester);

    expect(find.text('Player route: Route News'), findsNothing);
    expect(find.text('Route News'), findsWidgets);
    expect(find.text('Press back again to exit'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'predictive back stays handled until the root exit window is armed',
    (tester) async {
      final frameworkHandlesBack = <bool>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (methodCall) async {
          if (methodCall.method == 'SystemNavigator.setFrameworkHandlesBack') {
            frameworkHandlesBack.add(methodCall.arguments as bool);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.phone));
      await _pumpAppFrame(tester);

      expect(frameworkHandlesBack, isNotEmpty);
      expect(frameworkHandlesBack.last, isTrue);

      final app = tester.state<_TestAppState>(find.byType(_TestApp));
      expect(await app.dispatchRouterBack(), isTrue);
      await tester.pump();

      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(frameworkHandlesBack.last, isFalse);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(frameworkHandlesBack.last, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'predictive Android back commit closes active player',
    (tester) async {
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.phone, appState: appState),
      );
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route News').last);
      await _pumpAppFrame(tester);
      expect(find.text('Player route: Route News'), findsOneWidget);

      await _sendPlatformBackGestureMethod(
        tester,
        const MethodCall('startBackGesture', <String, Object>{
          'touchOffset': <double>[5, 300],
          'progress': 0.0,
          'swipeEdge': 0,
        }),
      );
      await _sendPlatformBackGestureMethod(
        tester,
        const MethodCall('commitBackGesture'),
      );
      await _pumpAppFrame(tester);

      expect(find.text('Player route: Route News'), findsNothing);
      expect(find.text('Route News'), findsWidgets);
      expect(find.text('Press back again to exit'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('TV back dismisses audio selection before closing player', (
    tester,
  ) async {
    final adapter = _NavigationPlayerAdapter(
      audioTracks: const <PlaybackTrack>[
        PlaybackTrack(id: 'audio-en', label: 'English'),
      ],
    );
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.tv,
        appState: appState,
        playbackOrchestratorBuilder: () => _testPlaybackOrchestrator(adapter),
        useProductionPlayer: true,
      ),
    );
    await _pumpAppFrame(tester);

    await tester.tap(find.text('Route News').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.audiotrack));
    await tester.pumpAndSettle();

    expect(find.text('Audio Track'), findsOneWidget);

    await _sendPlatformNavigationMethod(tester, const MethodCall('popRoute'));
    await _pumpAppFrame(tester);

    expect(find.text('Audio Track'), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);

    await _sendPlatformNavigationMethod(tester, const MethodCall('popRoute'));
    await _pumpAppFrame(tester);
    expect(find.byType(PlayerScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Escape key dismisses audio selection before closing player',
    (tester) async {
      final adapter = _NavigationPlayerAdapter(
        audioTracks: const <PlaybackTrack>[
          PlaybackTrack(id: 'audio-en', label: 'English'),
        ],
      );
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(
          deviceType: DeviceType.tv,
          appState: appState,
          playbackOrchestratorBuilder: () => _testPlaybackOrchestrator(adapter),
          useProductionPlayer: true,
        ),
      );
      await _pumpAppFrame(tester);

      await tester.tap(find.text('Route News').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();

      expect(find.text('Audio Track'), findsOneWidget);

      // Escape/GoBack routes through PlayerScreen's own local Shortcuts
      // (_handleBack) while focus is inside the player - a separate path
      // from the popRoute/PopScope back handling covered above - and it
      // must also respect an open track dialog instead of falling through
      // to its "hide controls" / "close player" steps.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _pumpAppFrame(tester);

      expect(find.text('Audio Track'), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);

      // Next press hides the (still-visible) player controls, matching the
      // ordinary two-step back behavior once no dialog is in the way.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _pumpAppFrame(tester);
      expect(find.byType(PlaybackControls), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _pumpAppFrame(tester);
      expect(find.byType(PlayerScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('TV back dismisses player controls before closing player', (
    tester,
  ) async {
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(
        deviceType: DeviceType.tv,
        appState: appState,
        useProductionPlayer: true,
      ),
    );
    await _pumpAppFrame(tester);

    await tester.tap(find.text('Route News').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PlaybackControls), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpAppFrame(tester);

    expect(find.byType(PlaybackControls), findsNothing);
    expect(find.byType(PlayerScreen), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpAppFrame(tester);

    expect(find.byType(PlayerScreen), findsNothing);
    expect(find.text('Route News'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'open movie details updates to continue when progress changes behind route',
    (tester) async {
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);

      await tester.tap(_sidebarText('Movies'));
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route Movie').last);
      await _pumpAppFrame(tester);

      expect(find.text('Play movie'), findsOneWidget);
      expect(find.text('1h 5m left'), findsNothing);

      await appState.resumeService.save(
        Progress(
          viewerId: appState.activeViewer!.ulid,
          contentType: ContentType.vod,
          streamId: 201,
          positionSeconds: 43 * 60 + 13,
          durationSeconds: 6480,
          title: 'Route Movie',
        ),
      );
      await appState.refreshLocalState();
      await _pumpAppFrame(tester);

      // Remaining: 6480s - 2593s = 3887s, rounded up to 65 min = 1h 5m.
      expect(find.text('1h 5m left'), findsOneWidget);
      expect(find.text('Play movie'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'selecting started movie from app shell opens details with continue action',
    (tester) async {
      PlayerArgs? capturedArgs;
      final appState = _testAppState(
        xtreamService: _NavigationXtreamService(
          recentlyWatched: const <Progress>[
            Progress(
              viewerId: 'viewer-1',
              contentType: ContentType.vod,
              streamId: 201,
              positionSeconds: 91,
              durationSeconds: 600,
              title: 'Route Movie',
            ),
          ],
        ),
      );
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(
          deviceType: DeviceType.tv,
          appState: appState,
          playerRouteBuilder: (args) {
            capturedArgs = args;
            return _testPlayerRoute(args);
          },
        ),
      );
      await _pumpAppFrame(tester);

      await tester.tap(_sidebarText('Movies'));
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route Movie').last);
      await _pumpAppFrame(tester);

      // Remaining: 600s - 91s = 509s, rounded up to 9 min.
      expect(find.text('9 min left'), findsOneWidget);
      await tester.tap(find.text('9 min left'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Player route: Route Movie'), findsOneWidget);
      expect(capturedArgs?.startPosition, 91.0);
      expect(
        capturedArgs?.toPlaybackSource().startPosition,
        const Duration(seconds: 91),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('selecting series from app shell opens series details route', (
    tester,
  ) async {
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(deviceType: DeviceType.tv, appState: appState),
    );
    await _pumpAppFrame(tester);

    await tester.tap(_sidebarText('Series'));
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route Series').last);
    await _pumpAppFrame(tester);

    expect(find.text('Season 1'), findsWidgets);
    expect(find.textContaining('Pilot'), findsWidgets);
    expect(find.text('Route Series'), findsWidgets);
  });

  testWidgets('selecting series episode opens player route', (tester) async {
    final appState = _testAppState(xtreamService: _NavigationXtreamService());
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(deviceType: DeviceType.tv, appState: appState),
    );
    await _pumpAppFrame(tester);

    await tester.tap(_sidebarText('Series'));
    await _pumpAppFrame(tester);
    await tester.tap(find.text('Route Series').last);
    await _pumpAppFrame(tester);
    // The episode strip is bottom-aligned; bring it into view before tapping.
    await tester.ensureVisible(find.textContaining('Pilot').first);
    await _pumpAppFrame(tester);
    // The title renders over the thumbnail scrim; the card's tap handler still
    // receives the press at that point.
    await tester.tap(find.textContaining('Pilot').first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Player route: Pilot'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('TV layout does not overflow at tiny constraints', (
    tester,
  ) async {
    final previousOnError = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.binding.setSurfaceSize(const Size(1, 1));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
    await tester.pump();

    expect(
      errors.where(
        (details) =>
            details.exceptionAsString().contains('RenderFlex overflowed'),
      ),
      isEmpty,
    );
  });

  group('Adaptive layout', () {
    testWidgets('TV device shows sidebar navigation', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationSidebar), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('Desktop device shows sidebar navigation', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.desktop));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationSidebar), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('Phone device shows bottom navigation', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.phone));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationSidebar), findsNothing);
    });

    testWidgets('Tablet device shows bottom navigation', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tablet));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationSidebar), findsNothing);
    });
  });

  group('TV focus traversal', () {
    testWidgets('sidebar items are focusable', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      final sidebarItems = find.byType(SidebarDestinationItem);
      expect(sidebarItems, findsAtLeast(6));
    });

    testWidgets('D-pad down moves focus through sidebar items', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('D-pad right moves focus from sidebar to content', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('Menu key opens sidebar on TV', (tester) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();

      expect(find.byType(NavigationSidebar), findsOneWidget);
    });
  });

  group('Back behavior', () {
    testWidgets('back button closes player overlay and returns to content', (
      tester,
    ) async {
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);

      await tester.tap(_sidebarText('Live TV'));
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route News').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Player route: Route News'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Player route: Route News'), findsNothing);
      expect(find.text('Route News'), findsAtLeast(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('back on TV activates sidebar when content is focused', (
      tester,
    ) async {
      await tester.pumpWidget(const _TestApp(deviceType: DeviceType.tv));
      await tester.pumpAndSettle();

      // Move focus to content area first
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      // Press back/escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(find.byType(NavigationSidebar), findsOneWidget);
    });

    testWidgets('back on phone pops detail route', (tester) async {
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.phone, appState: appState),
      );
      await _pumpAppFrame(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text('Movies'),
        ),
      );
      await _pumpAppFrame(tester);

      await tester.tap(find.text('Route Movie').last);
      await _pumpAppFrame(tester);

      expect(find.text('Play movie'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Play movie'), findsNothing);
      expect(find.text('Route Movie'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('Home shows DVR recordings at the bottom when DVR is enabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final appState = _testAppState(
      xtreamService: _NavigationXtreamService(
        features: const <String>['progress', 'dvr'],
        dvrRecordings: <DvrRecording>[_routeRecording()],
      ),
    );
    addTearDown(appState.dispose);
    await appState.connectXtream(
      const UserCredentials(
        server: 'http://example.com',
        username: 'user',
        password: 'pass',
      ),
    );

    await tester.pumpWidget(
      _TestApp(deviceType: DeviceType.tv, appState: appState),
    );
    await _pumpAppFrame(tester);

    final liveTop = tester.getTopLeft(find.text('Live TV').last).dy;
    final moviesTop = tester.getTopLeft(find.text('Movies').last).dy;
    final seriesTop = tester.getTopLeft(find.text('Series').last).dy;
    final dvrTop = tester.getTopLeft(find.text('DVR').last).dy;

    expect(liveTop, lessThan(moviesTop));
    expect(moviesTop, lessThan(seriesTop));
    expect(seriesTop, lessThan(dvrTop));
  });

  group('Focus restoration', () {
    testWidgets('returning from player overlay preserves active tab content', (
      tester,
    ) async {
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);

      // Navigate to Live TV
      await tester.tap(_sidebarText('Live TV'));
      await _pumpAppFrame(tester);

      expect(find.text('Route News'), findsAtLeast(1));

      // Open player overlay by tapping a channel
      await tester.tap(find.text('Route News').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Player route: Route News'), findsOneWidget);

      // Close player overlay
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Should be back at Live TV (channel still visible, player gone)
      expect(find.text('Player route: Route News'), findsNothing);
      expect(find.text('Route News'), findsAtLeast(1));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('TV foreground reset to start page', () {
    Future<AppStateController> connectedAppState() async {
      final appState = _testAppState(xtreamService: _NavigationXtreamService());
      addTearDown(appState.dispose);
      await appState.connectXtream(
        const UserCredentials(
          server: 'http://example.com',
          username: 'user',
          password: 'pass',
        ),
      );
      return appState;
    }

    Future<void> backgroundAndResume(
      WidgetTester tester, {
      required Duration away,
    }) async {
      final base = DateTime(2026, 1, 1, 12);
      withClock(Clock.fixed(base), () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
      });
      withClock(Clock.fixed(base.add(away)), () {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });
      await _pumpAppFrame(tester);
    }

    testWidgets(
      'resuming after a real background returns to the configured start page',
      (tester) async {
        final appState = await connectedAppState();
        await appState.viewSettingsService.setDefaultStartPage(
          DefaultStartPage.liveTv,
        );

        await tester.pumpWidget(
          _TestApp(deviceType: DeviceType.tv, appState: appState),
        );
        await _pumpAppFrame(tester);

        // Wander off to a nested Movies detail screen.
        await tester.tap(_sidebarText('Movies'));
        await _pumpAppFrame(tester);
        await tester.tap(find.text('Route Movie').last);
        await _pumpAppFrame(tester);
        expect(find.text('Play movie'), findsOneWidget);

        await backgroundAndResume(tester, away: const Duration(seconds: 30));

        // Back on the Live TV start page; the Movies detail is no longer shown.
        expect(find.text('Play movie'), findsNothing);
        expect(find.text('Route News'), findsAtLeast(1));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('resuming after a real background closes an open player', (
      tester,
    ) async {
      final appState = await connectedAppState();

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);

      await tester.tap(_sidebarText('Live TV'));
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route News').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Player route: Route News'), findsOneWidget);

      await backgroundAndResume(tester, away: const Duration(seconds: 30));

      expect(find.text('Player route: Route News'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a brief background keeps the user where they were', (
      tester,
    ) async {
      final appState = await connectedAppState();
      await appState.viewSettingsService.setDefaultStartPage(
        DefaultStartPage.liveTv,
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.tv, appState: appState),
      );
      await _pumpAppFrame(tester);

      await tester.tap(_sidebarText('Movies'));
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route Movie').last);
      await _pumpAppFrame(tester);
      expect(find.text('Play movie'), findsOneWidget);

      await backgroundAndResume(tester, away: const Duration(seconds: 3));

      expect(find.text('Play movie'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('desktop never resets on resume', (tester) async {
      final appState = await connectedAppState();
      await appState.viewSettingsService.setDefaultStartPage(
        DefaultStartPage.liveTv,
      );

      await tester.pumpWidget(
        _TestApp(deviceType: DeviceType.desktop, appState: appState),
      );
      await _pumpAppFrame(tester);

      await tester.tap(_sidebarText('Movies'));
      await _pumpAppFrame(tester);
      await tester.tap(find.text('Route Movie').last);
      await _pumpAppFrame(tester);
      expect(find.text('Play movie'), findsOneWidget);

      await backgroundAndResume(tester, away: const Duration(minutes: 5));

      expect(find.text('Play movie'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

Finder _sidebarText(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is SidebarDestinationItem && widget.label == label,
  );
}

Finder _mediaPreviewCardWithText(String text) {
  return find.ancestor(
    of: find.text(text).first,
    matching: find.byType(MediaPreviewCard),
  );
}

Finder _dpadInkWellWithText(String text) {
  return find.ancestor(
    of: find.text(text).first,
    matching: find.byType(DpadInkWell),
  );
}

Future<void> _expandSidebar(WidgetTester tester) async {
  final finder = find.descendant(
    of: find.byType(NavigationSidebar),
    matching: find.byType(MouseRegion),
  );
  final mouseRegion = tester.widget<MouseRegion>(finder.first);
  mouseRegion.onEnter?.call(const PointerEnterEvent());
  await tester.pumpAndSettle();
}

Future<void> _pumpAppFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _sendPlatformNavigationMethod(
  WidgetTester tester,
  MethodCall methodCall,
) async {
  final message = const JSONMethodCodec().encodeMethodCall(methodCall);
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    message,
    (_) {},
  );
}

Future<void> _sendPlatformBackGestureMethod(
  WidgetTester tester,
  MethodCall methodCall,
) async {
  final message = const StandardMethodCodec().encodeMethodCall(methodCall);
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    message,
    (_) {},
  );
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  for (var i = 0; i < 60; i += 1) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsOneWidget);
}

/// Test app that wraps AppShell with a controlled device type.
class _TestApp extends StatefulWidget {
  const _TestApp({
    required this.deviceType,
    this.appState,
    this.playerRouteBuilder,
    this.systemUiPolicy,
    this.playbackOrchestratorBuilder,
    this.useProductionPlayer = false,
  });

  final DeviceType deviceType;
  final AppStateController? appState;
  final Widget Function(PlayerArgs args)? playerRouteBuilder;
  final SystemUiPolicy? systemUiPolicy;
  final PlaybackOrchestrator Function()? playbackOrchestratorBuilder;
  final bool useProductionPlayer;

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  late final AppStateController _appState =
      widget.appState ??
      _testAppState(xtreamService: _NavigationXtreamService());
  late final GoRouter _router = createGoRouter(
    appState: _appState,
    nativeTelevisionHint: false,
    deviceTypeOverride: widget.deviceType,
    playbackOrchestratorBuilder:
        widget.playbackOrchestratorBuilder ?? _testPlaybackOrchestrator,
    playerRouteBuilder: widget.useProductionPlayer
        ? null
        : widget.playerRouteBuilder ?? _testPlayerRoute,
    systemUiPolicy: widget.systemUiPolicy,
  );

  Future<bool> dispatchRouterBack() =>
      _router.backButtonDispatcher.invokeCallback(Future<bool>.value(false));

  @override
  void dispose() {
    // The proxy inside ProviderScope is disposed by Riverpod, but it does NOT
    // dispose _appState - the caller retains lifecycle ownership. Dispose here
    // only when _TestAppState itself created the controller (widget.appState
    // was null); external callers (which use addTearDown) own their own.
    if (widget.appState == null) _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [overrideAppState(_appState)],
      child: MaterialApp.router(
        title: 'M3U TV Test',
        theme: ThemeData.dark(useMaterial3: true),
        routerConfig: _router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}

AppStateController _testAppState({required XtreamService xtreamService}) {
  final memory = <String, Object?>{};
  return AppStateController(
    xtreamService: xtreamService,
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    favoritesService: FavoritesService(memory: memory),
    resumeService: ResumeService(memory: memory),
    viewerService: ViewerService(memory: memory),
    viewSettingsService: ViewSettingsService(memory: memory),
  );
}

Widget _testPlayerRoute(PlayerArgs args) {
  return Scaffold(body: Center(child: Text('Player route: ${args.title}')));
}

PlaybackOrchestrator _testPlaybackOrchestrator([
  _NavigationPlayerAdapter? adapter,
]) {
  return PlaybackOrchestrator(
    platform: PlaybackPlatform.desktop,
    adapters: <PlaybackBackend, PlayerAdapter>{
      PlaybackBackend.desktopLibmpv: adapter ?? _NavigationPlayerAdapter(),
    },
    transcodeGateway: _NavigationTranscodeGateway(),
    retryDelay: Duration.zero,
  );
}

class _NavigationPlayerAdapter implements PlayerAdapter, NativePlaneProvider {
  _NavigationPlayerAdapter({
    this.audioTracks = const <PlaybackTrack>[],
  });

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();
  final List<PlaybackTrack> audioTracks;

  int loadCallCount = 0;
  int disposeCallCount = 0;
  bool _usesNativePlane = false;

  @override
  bool get usesNativePlane => _usesNativePlane;

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.desktopLibmpv;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    loadCallCount++;
    _stateController.add(
      PlaybackState(
        backend: PlaybackBackend.desktopLibmpv,
        status: PlaybackStatus.playing,
        source: source,
        duration: source.isLive ? null : const Duration(hours: 2),
        audioTracks: audioTracks,
      ),
    );
  }

  void emitError(PlaybackError error) => _errorController.add(error);

  void setUsesNativePlane({required bool value}) {
    _usesNativePlane = value;
    _stateController.add(
      const PlaybackState(
        backend: PlaybackBackend.desktopLibmpv,
        status: PlaybackStatus.playing,
      ),
    );
  }

  @override
  void reportVideoRect(
    double x,
    double y,
    double width,
    double height,
    double devicePixelRatio,
  ) {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> setAudioTrack(String? trackId) async {}

  @override
  Future<void> setSubtitleTrack(String? trackId) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    await _stateController.close();
    await _errorController.close();
  }
}

class _NavigationTranscodeGateway implements PlaybackTranscodeGateway {
  @override
  Future<TranscodeResponse> startServerTranscode(StreamRequest request) {
    throw const TranscodeUnavailableException('Transcode disabled in tests');
  }

  @override
  Future<BroadcastSession?> startBroadcast(StreamRequest request) async => null;

  @override
  Future<void> stopBroadcast(String networkId) async {}

  @override
  Future<void> stopServerTranscode({
    required String streamId,
    required String? sessionId,
  }) async {}
}

DvrRecording _routeRecording() => const DvrRecording(
  uuid: 'route-rec-1',
  title: 'Route Recording',
  status: DvrRecordingStatus.completed,
  channelName: 'Route News',
  streamUrl: 'http://example.com/dvr/route-rec-1.mp4',
);

class _NavigationXtreamService extends XtreamService {
  _NavigationXtreamService({
    this.liveChannels = const <Channel>[
      Channel(
        id: 101,
        name: 'Route News',
        streamUrl: 'http://example.com/live/101.m3u8',
        categoryId: 'live',
      ),
    ],
    this.vodItems = const <VodItem>[
      VodItem(
        id: 201,
        name: 'Route Movie',
        streamUrl: 'http://example.com/movie/201.mp4',
        containerExtension: 'mp4',
        categoryId: 'vod',
      ),
    ],
    this.seriesList = const <Series>[
      Series(
        id: 301,
        name: 'Route Series',
        categoryId: 'series',
        plot: 'Route series plot',
      ),
    ],
    this.recentlyWatched = const <Progress>[],
    this.features = const <String>['progress'],
    this.dvrRecordings = const <DvrRecording>[],
  });

  final List<Channel> liveChannels;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final List<Progress> recentlyWatched;
  final List<String> features;
  final List<DvrRecording> dvrRecordings;

  @override
  Future<XtreamAuthResponse> authenticate(UserCredentials credentials) async {
    return XtreamAuthResponse(
      isAuthenticated: true,
      status: 'Active',
      m3uEditorVersion: 'test',
      features: features,
    );
  }

  @override
  Future<List<Category>> getLiveCategories() async => const <Category>[
    Category(id: 'live', name: 'Live'),
  ];

  @override
  Future<List<Category>> getVodCategories() async => const <Category>[
    Category(id: 'vod', name: 'VOD'),
  ];

  @override
  Future<List<Category>> getSeriesCategories() async => const <Category>[
    Category(id: 'series', name: 'Series'),
  ];

  @override
  Future<List<Channel>> getLiveStreams({String? categoryId}) async =>
      liveChannels;

  @override
  Future<List<VodItem>> getVodStreams({String? categoryId}) async => vodItems;

  @override
  Future<List<Series>> getSeries({String? categoryId}) async => seriesList;

  @override
  Future<VodInfo> getVodInfo(int vodId) async => const VodInfo(
    id: 201,
    name: 'Route Movie',
    plot: 'Route movie plot',
    genre: 'Adventure',
    duration: '90m',
    containerExtension: 'mp4',
  );

  @override
  Future<SeriesInfo> getSeriesInfo(int seriesId) async => const SeriesInfo(
    series: Series(
      id: 301,
      name: 'Route Series',
      categoryId: 'series',
      plot: 'Route series plot',
    ),
    seasons: <Season>[Season(number: 1, name: 'Season 1', episodeCount: 1)],
    episodesBySeason: <int, List<Episode>>{
      1: <Episode>[
        Episode(
          id: '9001',
          episodeNumber: 1,
          title: 'Pilot',
          containerExtension: 'mp4',
          seasonNumber: 1,
          plot: 'Route episode plot',
          streamUrl: 'http://example.com/series/9001.mp4',
        ),
      ],
    },
  );

  @override
  Future<List<Viewer>> getViewers() async => const <Viewer>[
    Viewer(id: 1, ulid: 'viewer-1', name: 'Viewer', isAdmin: true),
  ];

  @override
  Future<List<DvrRecording>> getDvrRecordings({
    DvrRecordingStatus? status,
    int? limit,
  }) async => dvrRecordings;

  @override
  Future<List<DvrRecording>> getDvrRecordingsFor(
    UserCredentials credentials, {
    DvrRecordingStatus? status,
    int? limit,
  }) async => dvrRecordings;

  @override
  Future<List<Progress>> getRecentlyWatched(
    String viewerId, {
    int limit = 20,
    ContentType? type,
  }) async => recentlyWatched
      .where((progress) => type == null || progress.contentType == type)
      .take(limit)
      .toList(growable: false);

  @override
  Future<List<Progress>> getSeriesProgress(
    String viewerId,
    int seriesId,
  ) async => const <Progress>[];
}
