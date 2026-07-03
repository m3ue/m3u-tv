import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
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

      expect(find.text('DVR Recordings'), findsOneWidget);
      expect(find.text('Route Recording'), findsOneWidget);
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
      expect(find.text('Continue movie'), findsNothing);

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

      expect(find.text('Continue movie'), findsOneWidget);
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

      expect(find.text('Continue movie'), findsOneWidget);
      await tester.tap(find.text('Continue movie'));
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

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.textContaining('Pilot'), findsOneWidget);
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
    await tester.tap(find.textContaining('Pilot'));
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
  });

  final DeviceType deviceType;
  final AppStateController? appState;
  final Widget Function(PlayerArgs args)? playerRouteBuilder;

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
    playbackOrchestratorBuilder: _testPlaybackOrchestrator,
    playerRouteBuilder: widget.playerRouteBuilder ?? _testPlayerRoute,
  );

  @override
  void dispose() {
    if (widget.appState == null) _appState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'M3U TV Test',
      theme: ThemeData.dark(useMaterial3: true),
      routerConfig: _router,
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
  );
}

Widget _testPlayerRoute(PlayerArgs args) {
  return Scaffold(body: Center(child: Text('Player route: ${args.title}')));
}

PlaybackOrchestrator _testPlaybackOrchestrator() {
  return PlaybackOrchestrator(
    platform: PlaybackPlatform.desktop,
    adapters: <PlaybackBackend, PlayerAdapter>{
      PlaybackBackend.desktopLibmpv: _NavigationPlayerAdapter(),
    },
    transcodeGateway: _NavigationTranscodeGateway(),
    retryDelay: Duration.zero,
  );
}

class _NavigationPlayerAdapter implements PlayerAdapter {
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.desktopLibmpv;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    _stateController.add(
      PlaybackState(
        backend: PlaybackBackend.desktopLibmpv,
        status: PlaybackStatus.playing,
        source: source,
        duration: source.isLive ? null : const Duration(hours: 2),
      ),
    );
  }

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
  Future<List<DvrRecording>> getDvrRecordings() async => dvrRecordings;

  @override
  Future<List<Progress>> getRecentlyWatched(
    String viewerId, {
    int limit = 20,
    ContentType? type,
  }) async => recentlyWatched
      .where((progress) => type == null || progress.contentType == type)
      .take(limit)
      .toList(growable: false);
}
